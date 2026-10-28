# Hace publicar\captura.png (1000 x 620): la ventanita de Mosquitero sobre un fondo neutro, para la
# página de Brizna Soft. La ventanita es la de verdad (popup.html y popup.css), con datos de ejemplo
# (example.com) y sin su script.
#
# Usa Edge sin ventana con un perfil temporal en pruebas-locales\captura: no toca el Edge de la persona.
# Uso: powershell -ExecutionPolicy Bypass -File herramientas\hacer-captura.ps1
param(
    [string]$Raiz = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'No encuentro Microsoft Edge.' }

$comun = Join-Path (Join-Path $Raiz 'extension') 'comun'
$trabajo = Join-Path (Join-Path $Raiz 'pruebas-locales') 'captura'
if (Test-Path $trabajo) { Remove-Item $trabajo -Recurse -Force }
New-Item -ItemType Directory -Force $trabajo | Out-Null
Copy-Item (Join-Path $comun 'popup.css') $trabajo
Copy-Item (Join-Path $comun 'iconos') (Join-Path $trabajo 'iconos') -Recurse
Copy-Item (Join-Path $PSScriptRoot 'captura.html') $trabajo

$version = ([System.IO.File]::ReadAllText((Join-Path $Raiz 'version.txt'))).Trim()
$utf8 = New-Object System.Text.UTF8Encoding($false)
$popup = [System.IO.File]::ReadAllText((Join-Path $comun 'popup.html'), [System.Text.Encoding]::UTF8)
$popup = $popup -replace '\s*<script[^>]*></script>', ''
$popup = $popup -replace '(<p class="sitio" id="sitio">)[^<]*(</p>)', '${1}example.com${2}'
$popup = $popup -replace '(<span id="version">)(</span>)', ('${1}' + $version + '${2}')
[System.IO.File]::WriteAllText((Join-Path $trabajo 'ventanita.html'), $popup, $utf8)

$publicar = Join-Path $Raiz 'publicar'
New-Item -ItemType Directory -Force $publicar | Out-Null
$png = Join-Path $publicar 'captura.png'
if (Test-Path $png) { Remove-Item $png -Force }
$url = 'file:///' + ((Join-Path $trabajo 'captura.html') -replace '\\', '/')
$opciones = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check',
    "--user-data-dir=$(Join-Path $trabajo 'perfil')", '--window-size=1000,620', '--virtual-time-budget=4000',
    '--blink-settings=preferredColorScheme=1', "--screenshot=$png", $url)
$p = Start-Process -FilePath $edge -ArgumentList $opciones -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(90000)) { Stop-Process -Id $p.Id -Force; throw 'Edge no terminó a tiempo.' }
for ($i = 0; $i -lt 20 -and -not (Test-Path $png); $i++) { Start-Sleep -Milliseconds 500 }
if (-not (Test-Path $png)) { throw 'Edge no hizo la captura.' }
$img = [System.Drawing.Image]::FromFile($png)
Write-Host ("Captura lista: publicar\captura.png ({0} x {1})" -f $img.Width, $img.Height)
$img.Dispose()
