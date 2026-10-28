# Baja las listas de EasyList a la carpeta listas\, con la fecha de descarga en el nombre, y anota en
# listas\descargas.txt de dónde salió cada una, su versión y su huella SHA256.
#
# Solo se usa al preparar una versión nueva de Mosquitero. La extensión nunca baja nada de internet:
# las listas viajan dentro de ella, ya convertidas.
#
# Uso: powershell -ExecutionPolicy Bypass -File herramientas\actualizar-listas.ps1
# Está hecho para Windows PowerShell 5.1 y para PowerShell 7 (pwsh).
param(
    [string]$Raiz = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

$listas = @(
    [pscustomobject]@{ Nombre = 'easylist';        Url = 'https://easylist.to/easylist/easylist.txt' },
    [pscustomobject]@{ Nombre = 'easyprivacy';     Url = 'https://easylist.to/easylist/easyprivacy.txt' },
    [pscustomobject]@{ Nombre = 'easylistspanish'; Url = 'https://easylist-downloads.adblockplus.org/easylistspanish.txt' }
)

$carpeta = Join-Path $Raiz 'listas'
New-Item -ItemType Directory -Force $carpeta | Out-Null
$ahora = (Get-Date).ToUniversalTime()
$fecha = $ahora.ToString('yyyy-MM-dd')
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Encabezado([string[]]$lineas, [string]$clave) {
    foreach ($l in $lineas) {
        if ($l -match ('^!\s*' + [regex]::Escape($clave) + '\s*:\s*(.+)$')) { return $Matches[1].Trim() }
        if ($l -notmatch '^(!|\[)') { break }
    }
    return ''
}

$registro = New-Object System.Text.StringBuilder
[void]$registro.AppendLine('Listas originales usadas por Mosquitero')
[void]$registro.AppendLine('=======================================')
[void]$registro.AppendLine('')
[void]$registro.AppendLine('Son copias exactas, sin cambios, tal como se bajaron. Las hacen «The EasyList authors»')
[void]$registro.AppendLine('(https://easylist.to/). Licencia: GPLv3 o CC BY-SA 3.0, a elección; los detalles están en')
[void]$registro.AppendLine('AVISOS-DE-TERCEROS.txt.')
[void]$registro.AppendLine('')

foreach ($l in $listas) {
    $temporal = Join-Path $carpeta ($l.Nombre + '.descargando')
    Write-Host "Bajando $($l.Url) ..."
    Invoke-WebRequest -Uri $l.Url -OutFile $temporal -UseBasicParsing -TimeoutSec 120
    $lineas = [System.IO.File]::ReadAllLines($temporal, [System.Text.Encoding]::UTF8)
    if ($lineas.Count -lt 100 -or $lineas[0] -notmatch '^\[Adblock Plus') {
        Remove-Item $temporal -Force
        throw "Lo que llegó de $($l.Url) no parece una lista de filtros."
    }
    Get-ChildItem $carpeta -Filter ($l.Nombre + '-*.txt') | Remove-Item -Force
    $final = Join-Path $carpeta ('{0}-{1}.txt' -f $l.Nombre, $fecha)
    Move-Item $temporal $final -Force

    $huella = (Get-FileHash $final -Algorithm SHA256).Hash.ToLowerInvariant()
    $licencia = Encabezado $lineas 'License'
    if (-not $licencia) { $licencia = Encabezado $lineas 'Licence' }
    [void]$registro.AppendLine(('Archivo:          {0}' -f (Split-Path $final -Leaf)))
    [void]$registro.AppendLine(('Título:           {0}' -f (Encabezado $lineas 'Title')))
    [void]$registro.AppendLine(('Bajada de:        {0}' -f $l.Url))
    [void]$registro.AppendLine(('Fecha de bajada:  {0} UTC' -f $ahora.ToString('yyyy-MM-dd HH:mm')))
    [void]$registro.AppendLine(('Versión:          {0}' -f (Encabezado $lineas 'Version')))
    [void]$registro.AppendLine(('Última revisión:  {0}' -f (Encabezado $lineas 'Last modified')))
    [void]$registro.AppendLine(('Licencia (dice):  {0}' -f $licencia))
    [void]$registro.AppendLine(('Líneas:           {0}' -f $lineas.Count))
    [void]$registro.AppendLine(('SHA256:           {0}' -f $huella))
    [void]$registro.AppendLine('')
    Write-Host ("  {0}: {1} líneas" -f (Split-Path $final -Leaf), $lineas.Count)
}

[System.IO.File]::WriteAllText((Join-Path $carpeta 'descargas.txt'), $registro.ToString().Replace("`r`n", "`n"), $utf8)
Write-Host 'Listas al día. Ahora corre armar.ps1 para convertirlas.'
