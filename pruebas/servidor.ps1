# Servidor web mínimo para las pruebas: sirve los archivos de una carpeta solo en 127.0.0.1.
#   /esperar?ms=N  responde después de N milisegundos (para dar tiempo a la extensión)
#   /salir         apaga el servidor
# Se apaga solo después de -MaxSegundos. No necesita permisos de administrador.
param(
    [Parameter(Mandatory = $true)][string]$Raiz,
    [int]$Puerto = 8765,
    [int]$MaxSegundos = 900
)
$ErrorActionPreference = 'Stop'
$tipos = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'; '.png' = 'image/png'; '.txt' = 'text/plain; charset=utf-8'
}

function Responder($flujo, [int]$codigo, [string]$tipo, [byte[]]$cuerpo) {
    $estado = $(if ($codigo -eq 200) { 'OK' } else { 'Not Found' })
    $cabecera = "HTTP/1.1 $codigo $estado`r`nContent-Type: $tipo`r`nContent-Length: $($cuerpo.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
    $b = [System.Text.Encoding]::ASCII.GetBytes($cabecera)
    $flujo.Write($b, 0, $b.Length)
    if ($cuerpo.Length) { $flujo.Write($cuerpo, 0, $cuerpo.Length) }
    $flujo.Flush()
}

$escucha = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Puerto)
$escucha.Start()
$fin = (Get-Date).AddSeconds($MaxSegundos)
$seguir = $true
try {
    while ($seguir -and (Get-Date) -lt $fin) {
        if (-not $escucha.Pending()) { Start-Sleep -Milliseconds 15; continue }
        $cliente = $escucha.AcceptTcpClient()
        try {
            $cliente.ReceiveTimeout = 1500
            $cliente.SendTimeout = 5000
            $flujo = $cliente.GetStream()
            $buf = New-Object byte[] 16384
            $leido = 0
            $texto = ''
            while ($texto.IndexOf("`r`n`r`n") -lt 0 -and $leido -lt $buf.Length) {
                $n = $flujo.Read($buf, $leido, $buf.Length - $leido)
                if ($n -le 0) { break }
                $leido += $n
                $texto = [System.Text.Encoding]::ASCII.GetString($buf, 0, $leido)
            }
            $partes = ($texto -split "`r`n")[0] -split ' '
            if ($partes.Count -lt 2) { continue }
            $ruta = $partes[1]
            $consulta = ''
            $i = $ruta.IndexOf('?')
            if ($i -ge 0) { $consulta = $ruta.Substring($i + 1); $ruta = $ruta.Substring(0, $i) }
            if ($ruta -eq '/') { $ruta = '/prueba.html' }

            if ($ruta -eq '/salir') {
                Responder $flujo 200 'text/plain' ([System.Text.Encoding]::ASCII.GetBytes('adios'))
                $seguir = $false
            }
            elseif ($ruta -eq '/esperar') {
                $ms = 1000
                if ($consulta -match '(?:^|&)ms=(\d+)') { $ms = [Math]::Min([int]$Matches[1], 20000) }
                Start-Sleep -Milliseconds $ms
                Responder $flujo 200 'text/javascript' ([System.Text.Encoding]::ASCII.GetBytes('/* listo */'))
            }
            elseif ($ruta -match '^/([A-Za-z0-9_.-]+)$' -and $Matches[1] -notmatch '^\.') {
                $archivo = Join-Path $Raiz $Matches[1]
                if (Test-Path -LiteralPath $archivo -PathType Leaf) {
                    $ext = [System.IO.Path]::GetExtension($archivo).ToLowerInvariant()
                    $tipo = $(if ($tipos.ContainsKey($ext)) { $tipos[$ext] } else { 'application/octet-stream' })
                    Responder $flujo 200 $tipo ([System.IO.File]::ReadAllBytes($archivo))
                }
                else { Responder $flujo 404 'text/plain' ([System.Text.Encoding]::ASCII.GetBytes('no existe')) }
            }
            else { Responder $flujo 404 'text/plain' ([System.Text.Encoding]::ASCII.GetBytes('no existe')) }
        }
        catch {
            # Conexión que no mandó nada a tiempo, o que se cerró: se sigue con la próxima
        }
        finally {
            $cliente.Close()
        }
    }
}
finally {
    $escucha.Stop()
}
