# Arma Mosquitero para Chrome, Edge y Brave, y para Firefox:
#   1. convierte las listas de listas\ en reglas (herramientas\convertir-listas.ps1);
#   2. junta extension\comun, lo convertido y el manifiesto de cada navegador en publicar\chrome y
#      publicar\firefox (esas carpetas sirven para «Cargar descomprimida»);
#   3. revisa lo armado (herramientas\revisar-generado.ps1);
#   4. comprime cada carpeta en publicar\Mosquitero-<versión>-chrome.zip y -firefox.zip, escribe la
#      huella SHA256 de cada uno (.sha256) y las notas de la versión (publicar\notas.md).
#
# No usa internet. Está hecho para Windows PowerShell 5.1 y para PowerShell 7 (pwsh).
# Uso: powershell -ExecutionPolicy Bypass -File armar.ps1 [-SinConvertir]
param(
    [switch]$SinConvertir
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$raiz = $PSScriptRoot
$herramientas = Join-Path $raiz 'herramientas'
$extension = Join-Path $raiz 'extension'
$generado = Join-Path $extension 'generado'
$publicar = Join-Path $raiz 'publicar'
$utf8 = New-Object System.Text.UTF8Encoding($false)

$version = ([System.IO.File]::ReadAllText((Join-Path $raiz 'version.txt'))).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "version.txt no tiene una versión válida: «$version»" }
foreach ($navegador in 'chrome', 'firefox') {
    $m = [System.IO.File]::ReadAllText((Join-Path (Join-Path $extension $navegador) 'manifest.json'))
    if ($m -notmatch ('"version"\s*:\s*"' + [regex]::Escape($version) + '"')) {
        throw "El manifiesto de $navegador no dice la versión $version de version.txt."
    }
}
Write-Host "Mosquitero $version"

# 1. Convertir las listas
if (-not $SinConvertir) {
    & (Join-Path $herramientas 'convertir-listas.ps1') -Raiz $raiz -Salida $generado
}
foreach ($f in 'reglas\anuncios.json', 'reglas\rastreadores.json', 'cosmetico\genericos.css', 'cosmetico\por-sitio.json') {
    if (-not (Test-Path -LiteralPath (Join-Path $generado $f))) { throw "Falta $f en extension\generado. Corre armar.ps1 sin -SinConvertir." }
}

# Fecha fija para lo que va dentro de los zip: la de las listas. Así, con las mismas listas, salen
# los mismos zip.
$fechaListas = Get-ChildItem -LiteralPath (Join-Path $raiz 'listas') -File |
    ForEach-Object { if ($_.Name -match '^easylist-(\d{4}-\d{2}-\d{2})\.txt$') { $Matches[1] } } |
    Sort-Object -Descending | Select-Object -First 1
if (-not $fechaListas) { throw 'No encuentro listas\easylist-AAAA-MM-DD.txt.' }
$fechaZip = New-Object System.DateTimeOffset([datetime]::ParseExact($fechaListas, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture), [TimeSpan]::Zero)

function Copiar([string]$desde, [string]$hacia) {
    New-Item -ItemType Directory -Force -Path $hacia | Out-Null
    Copy-Item -Path (Join-Path $desde '*') -Destination $hacia -Recurse -Force
}

function Comprimir([string]$carpeta, [string]$zip) {
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    $base = (Resolve-Path -LiteralPath $carpeta).Path.TrimEnd('\', '/')
    $nombres = New-Object 'System.Collections.Generic.List[string]'
    foreach ($a in Get-ChildItem -LiteralPath $base -Recurse -File) {
        $nombres.Add($a.FullName.Substring($base.Length + 1).Replace('\', '/'))
    }
    $orden = $nombres.ToArray()
    [System.Array]::Sort($orden, [System.StringComparer]::Ordinal)
    $flujo = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
    $archivo = New-Object System.IO.Compression.ZipArchive($flujo, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($nombre in $orden) {
            # Barras normales dentro del zip: Firefox y las tiendas rechazan las «\»
            $entrada = $archivo.CreateEntry($nombre, [System.IO.Compression.CompressionLevel]::Optimal)
            $entrada.LastWriteTime = $fechaZip
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $base $nombre))
            $s = $entrada.Open()
            $s.Write($bytes, 0, $bytes.Length)
            $s.Dispose()
        }
    }
    finally {
        $archivo.Dispose()
        $flujo.Dispose()
    }
}

# 2 a 4. Armar, revisar y comprimir cada versión
New-Item -ItemType Directory -Force -Path $publicar | Out-Null
$huellas = [ordered]@{}
foreach ($navegador in 'chrome', 'firefox') {
    $destino = Join-Path $publicar $navegador
    if (Test-Path -LiteralPath $destino) { Remove-Item -LiteralPath $destino -Recurse -Force }
    Copiar (Join-Path $extension 'comun') $destino
    Copiar (Join-Path $generado 'reglas') (Join-Path $destino 'reglas')
    Copiar (Join-Path $generado 'cosmetico') (Join-Path $destino 'cosmetico')
    Copy-Item -LiteralPath (Join-Path (Join-Path $extension $navegador) 'manifest.json') -Destination $destino -Force
    Copy-Item -LiteralPath (Join-Path $raiz 'LICENSE') -Destination $destino -Force
    # Con BOM, para que el navegador muestre bien los acentos al abrirlo desde la ventanita
    $avisos = [System.IO.File]::ReadAllText((Join-Path $raiz 'AVISOS-DE-TERCEROS.txt'), [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $destino 'AVISOS-DE-TERCEROS.txt'), $avisos, (New-Object System.Text.UTF8Encoding($true)))

    Write-Host "Revisando publicar\$navegador ..."
    & (Join-Path $herramientas 'revisar-generado.ps1') -Carpeta $destino

    $nombreZip = "Mosquitero-$version-$navegador.zip"
    $zip = Join-Path $publicar $nombreZip
    Comprimir $destino $zip
    $huella = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText("$zip.sha256", "$huella  $nombreZip`n", $utf8)
    $huellas[$nombreZip] = $huella
}

# Notas para la página de la versión en GitHub
$resumen = [System.IO.File]::ReadAllText((Join-Path $generado 'resumen.txt'), [System.Text.Encoding]::UTF8)
$totales = ($resumen -split "`n" | Where-Object { $_ -match '^\s+(anuncios|rastreadores|total):' }) -join "`n"
$n = New-Object System.Text.StringBuilder
[void]$n.Append("Mosquitero ${version}: deja afuera los anuncios y los rastreadores.`n`n")
[void]$n.Append("Extensión gratis, sin publicidad y sin recoger datos, hecha por Brizna Soft.`n`n")
[void]$n.Append("## Qué bajar`n`n")
[void]$n.Append("- **Mosquitero-$version-chrome.zip**: para Chrome, Edge y Brave.`n")
[void]$n.Append("- **Mosquitero-$version-firefox.zip**: para Firefox. Firefox solo la instala para siempre cuando Mozilla la firma; mientras tanto se puede probar como complemento temporal.`n`n")
[void]$n.Append("Mientras no esté en las tiendas, se instala con «Cargar descomprimida» en el modo de desarrollador. Los pasos están en el README.`n`n")
[void]$n.Append("## Listas`n`n")
[void]$n.Append("EasyList, EasyList Spanish y EasyPrivacy del $fechaListas (The EasyList authors, licencia CC BY-SA 3.0).`n`n")
[void]$n.Append("``````text`n$totales`n```````n`n")
[void]$n.Append("## Huellas SHA256`n`n``````text`n")
foreach ($k in $huellas.Keys) { [void]$n.Append("$($huellas[$k])  $k`n") }
[void]$n.Append("```````n")
[System.IO.File]::WriteAllText((Join-Path $publicar 'notas.md'), $n.ToString(), $utf8)

Write-Host ''
Write-Host 'Listo:'
foreach ($k in $huellas.Keys) { Write-Host "  publicar\$k" ; Write-Host "    SHA256 $($huellas[$k])" }
