# Prueba Mosquitero en Microsoft Edge sin ventana (--headless=new).
#
# Usa perfiles temporales dentro de pruebas-locales\edge\ (--user-data-dir): no abre ni cambia los
# perfiles de Edge o de Chrome de la persona, y no instala nada. Necesita internet, porque la página de
# prueba intenta cargar recursos reales de anuncios, de rastreadores y normales.
#
# Qué hace:
#   1. Abre la página de prueba sin la extensión y con ella (publicar\chrome), y compara qué cargó.
#   2. Revisa qué elementos se ocultan: los generales, los de un sitio con «sitio.*» y los de un dominio.
#   3. Con una copia de prueba de la extensión, apaga un sitio y los rastreadores como lo haría la
#      ventanita, y comprueba que en ese sitio todo carga y que los rastreadores ya no se bloquean.
#   4. Cuenta cuántos grupos de genericos.css acepta Edge y qué selectores no entiende.
#
# Uso: primero armar.ps1; después
#      powershell -ExecutionPolicy Bypass -File pruebas\probar-en-edge.ps1
param(
    [string]$Raiz = (Split-Path $PSScriptRoot -Parent),
    [int]$Puerto = 8765
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1

$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'No encuentro Microsoft Edge.' }
$versionEdge = (Get-Item $edge).VersionInfo.ProductVersion

$extension = Join-Path (Join-Path $Raiz 'publicar') 'chrome'
if (-not (Test-Path (Join-Path $extension 'manifest.json'))) { throw 'Falta publicar\chrome. Corre armar.ps1 primero.' }
$trabajo = Join-Path (Join-Path $Raiz 'pruebas-locales') 'edge'
if (Test-Path $trabajo) { Remove-Item $trabajo -Recurse -Force }
New-Item -ItemType Directory -Force $trabajo | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# --- Lo que va a servir el servidor ---------------------------------------------------------------
$sitio = Join-Path $trabajo 'sitio'
New-Item -ItemType Directory -Force $sitio | Out-Null
Copy-Item (Join-Path (Join-Path $PSScriptRoot 'sitio') '*') $sitio -Force
Copy-Item (Join-Path (Join-Path $extension 'cosmetico') 'genericos.css') $sitio -Force

# Elementos para ocultar, sacados de lo generado (así la prueba sigue sirviendo con listas nuevas)
$reSimple = '^([.#])([A-Za-z_][A-Za-z0-9_-]*)$'
function Elemento([string]$nombre, [string]$tipo, [string]$selector) {
    $m = [regex]::Match($selector, $reSimple)
    $e = [ordered]@{ nombre = $nombre; tipo = $tipo; selector = $selector }
    if ($m.Groups[1].Value -eq '#') { $e.id = $m.Groups[2].Value } else { $e.clase = $m.Groups[2].Value }
    return $e
}
$css = [System.IO.File]::ReadAllLines((Join-Path $sitio 'genericos.css'), [System.Text.Encoding]::UTF8)
$generales = New-Object 'System.Collections.Generic.List[string]'
foreach ($l in $css) {
    $m = [regex]::Match($l, '^& ([.#][A-Za-z_][A-Za-z0-9_-]*)(,| \{)')
    if ($m.Success) { $generales.Add($m.Groups[1].Value) }
}
$elegidos = @(@($generales | Where-Object { $_.StartsWith('#') } | Select-Object -First 2) + @($generales | Where-Object { $_.StartsWith('.') } | Select-Object -First 2))
$elementos = New-Object 'System.Collections.Generic.List[object]'
$n = 0
foreach ($s in $elegidos) { $n++; $elementos.Add((Elemento "general $n" 'general' $s)) }

# JSON igual en Windows PowerShell 5.1 y en PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Add-Type -AssemblyName System.Web.Extensions
    $serializador = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializador.MaxJsonLength = [int]::MaxValue
    function DeJson([string]$texto) { return , $serializador.DeserializeObject($texto) }
    function AJson($objeto) { return $serializador.Serialize($objeto) }
}
else {
    function DeJson([string]$texto) { return , ($texto | ConvertFrom-Json -AsHashtable -Depth 100) }
    function AJson($objeto) { return ($objeto | ConvertTo-Json -Depth 20 -Compress) }
}
$datos = DeJson ([System.IO.File]::ReadAllText((Join-Path (Join-Path $extension 'cosmetico') 'por-sitio.json'), [System.Text.Encoding]::UTF8))
$tabla = $datos['selectores']
foreach ($i in $datos['conExcepcion']) {
    if ($tabla[$i] -match $reSimple) { $elementos.Add((Elemento 'general con excepción' 'conExcepcion' $tabla[$i])); break }
}
$hostComodin = ''; $hostExacto = ''
# softonic.* primero, si está; si no, el primer «sitio.*» que sirva
$claves = @($datos['ocultar'].Keys)
$claves = @($claves | Where-Object { $_ -eq 'softonic.*' }) + @($claves | Where-Object { $_ -ne 'softonic.*' })
foreach ($clave in $claves) {
    if ($hostComodin -and $hostExacto) { break }
    $simple = $null
    foreach ($i in $datos['ocultar'][$clave]) { if ($tabla[$i] -match $reSimple -and -not $generales.Contains($tabla[$i])) { $simple = $tabla[$i]; break } }
    if (-not $simple) { continue }
    if (-not $hostComodin -and $clave -match '^[a-z0-9-]+\.\*$') {
        $hostComodin = $clave.Replace('.*', '.test')
        $elementos.Add((Elemento "de $clave" 'comodin' $simple))
    }
    elseif (-not $hostExacto -and $clave -match '^[a-z0-9-]+\.(com|net|org)$') {
        $hostExacto = $clave
        $elementos.Add((Elemento "de $clave" 'exacto' $simple))
    }
}
$elementos.Add([ordered]@{ nombre = 'contenido normal'; tipo = 'normal'; selector = '.contenido-normal'; clase = 'contenido-normal' })

$recursos = @(
    [ordered]@{ nombre = 'Google AdSense (adsbygoogle.js)'; grupo = 'anuncio'; como = 'script'; url = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' },
    [ordered]@{ nombre = 'Google Ad Manager (gpt.js)'; grupo = 'anuncio'; como = 'script'; url = 'https://securepubads.g.doubleclick.net/tag/js/gpt.js' },
    [ordered]@{ nombre = 'googletagservices.com (gpt.js)'; grupo = 'anuncio'; como = 'script'; url = 'https://www.googletagservices.com/tag/js/gpt.js' },
    [ordered]@{ nombre = 'DoubleClick (ad_status.js)'; grupo = 'anuncio'; como = 'fetch'; url = 'https://static.doubleclick.net/instream/ad_status.js' },
    [ordered]@{ nombre = 'Amazon (apstag.js)'; grupo = 'anuncio'; como = 'fetch'; url = 'https://c.amazon-adsystem.com/aax2/apstag.js' },
    [ordered]@{ nombre = 'Google Analytics (analytics.js)'; grupo = 'rastreador'; como = 'script'; url = 'https://www.google-analytics.com/analytics.js' },
    [ordered]@{ nombre = 'Google Tag Manager (gtag.js)'; grupo = 'rastreador'; como = 'fetch'; url = 'https://www.googletagmanager.com/gtag/js?id=G-PRUEBA' },
    [ordered]@{ nombre = 'Hotjar'; grupo = 'rastreador'; como = 'fetch'; url = 'https://static.hotjar.com/c/hotjar-1.js?sv=6' },
    [ordered]@{ nombre = 'jQuery en cdnjs'; grupo = 'normal'; como = 'script'; url = 'https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js' },
    [ordered]@{ nombre = 'Ícono de Wikipedia'; grupo = 'normal'; como = 'imagen'; url = 'https://www.wikipedia.org/static/favicon/wikipedia.ico' },
    [ordered]@{ nombre = 'Página de Brizna Soft'; grupo = 'normal'; como = 'fetch'; url = 'https://brizna-soft.github.io/' },
    [ordered]@{ nombre = 'Script de la misma página'; grupo = 'normal'; como = 'script'; url = '/normal.js' }
)
$config = [ordered]@{ esperaInicial = 2000; recursos = $recursos; elementos = $elementos.ToArray() }
[System.IO.File]::WriteAllText((Join-Path $sitio 'config.js'), 'window.CONFIG_PRUEBA = ' + (AJson $config) + ";`n", $utf8)

# --- Copia de prueba de la extensión (con los ganchos de pruebas\extension-prueba) ----------------
$extPrueba = Join-Path $trabajo 'extension-prueba'
Copy-Item $extension $extPrueba -Recurse -Force
Copy-Item (Join-Path (Join-Path $PSScriptRoot 'extension-prueba') '*') $extPrueba -Force
$manifiesto = DeJson ([System.IO.File]::ReadAllText((Join-Path $extPrueba 'manifest.json'), [System.Text.Encoding]::UTF8))
$manifiesto['background']['service_worker'] = 'prueba-sw.js'
$manifiesto['content_scripts'] = @($manifiesto['content_scripts']) + @(@{ matches = @('http://*/*'); js = @('prueba-control.js'); run_at = 'document_start' })
[System.IO.File]::WriteAllText((Join-Path $extPrueba 'manifest.json'), (AJson $manifiesto), $utf8)

# --- Servidor -------------------------------------------------------------------------------------
$libre = $false
for ($intento = 0; $intento -lt 20 -and -not $libre; $intento++) {
    try { $t = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Puerto); $t.Start(); $t.Stop(); $libre = $true }
    catch { $Puerto++ }
}
$shell = (Get-Process -Id $PID).Path
$servidor = Start-Process -FilePath $shell -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'servidor.ps1') + '"'),
    '-Raiz', ('"' + $sitio + '"'), '-Puerto', $Puerto)
$listo = $false
for ($intento = 0; $intento -lt 30 -and -not $listo; $intento++) {
    Start-Sleep -Milliseconds 500
    try { Invoke-WebRequest -Uri "http://127.0.0.1:$Puerto/normal.js" -UseBasicParsing -TimeoutSec 3 | Out-Null; $listo = $true } catch { }
}
if (-not $listo) { Stop-Process -Id $servidor.Id -Force -ErrorAction SilentlyContinue; throw 'El servidor de prueba no arrancó.' }

$mapas = @('pagina.test', 'apagado.test')
if ($hostComodin) { $mapas += $hostComodin }
if ($hostExacto) { $mapas += $hostExacto }
$reglasHost = '"--host-resolver-rules=' + (($mapas | ForEach-Object { "MAP $_ 127.0.0.1" }) -join ',') + '"'

function Abrir([string]$nombre, [string]$url, [string]$perfil, [string]$ext) {
    $salida = Join-Path $trabajo "dom-$nombre.html"
    $registro = Join-Path $trabajo "edge-$nombre.log"
    $opciones = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-sync',
        "--user-data-dir=$(Join-Path $trabajo $perfil)", '--virtual-time-budget=30000', $reglasHost, '--dump-dom')
    if ($ext) { $opciones += @("--load-extension=$ext", "--disable-extensions-except=$ext") }
    $opciones += $url
    $p = Start-Process -FilePath $edge -ArgumentList $opciones -PassThru -WindowStyle Hidden -RedirectStandardOutput $salida -RedirectStandardError $registro
    if (-not $p.WaitForExit(150000)) { Stop-Process -Id $p.Id -Force; throw "Edge no terminó a tiempo en «$nombre»." }
    # Los procesos hijos de Edge pueden tardar un poco en soltar el archivo
    for ($intento = 0; $intento -lt 60; $intento++) {
        try { return [System.IO.File]::ReadAllText($salida, [System.Text.Encoding]::UTF8) }
        catch [System.IO.IOException] { Start-Sleep -Milliseconds 500 }
    }
    throw "No pude leer lo que dejó Edge en «$nombre»."
}

# Edge le da a una extensión cargada desde una carpeta un id sacado de la ruta (SHA-256 de la ruta en
# UTF-16, primeros 16 bytes, con las cifras 0-f cambiadas por las letras a-p).
function IdDeRuta([string]$ruta) {
    $ruta = (Resolve-Path -LiteralPath $ruta).Path
    if ($ruta -match '^[a-z]:') { $ruta = $ruta.Substring(0, 1).ToUpperInvariant() + $ruta.Substring(1) }
    $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::Unicode.GetBytes($ruta))
    $id = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt 16; $i++) {
        [void]$id.Append([char]([int][char]'a' + ($h[$i] -shr 4))).Append([char]([int][char]'a' + ($h[$i] -band 15)))
    }
    return $id.ToString()
}

function Resultado([string]$dom, [string]$nombre) {
    $m = [regex]::Match($dom, '<pre id="resultado">([^<]*)</pre>')
    if (-not $m.Success -or $m.Groups[1].Value -eq 'esperando') { throw "La página de prueba no terminó en «$nombre» (ver pruebas-locales\edge\dom-$nombre.html)." }
    return DeJson ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value))
}

$base = "http://pagina.test:$Puerto"
# Cada sesión con la extensión usa un perfil nuevo: Edge carga --load-extension solo la primera vez
# que se abre un perfil (en las siguientes la deja apagada).
try {
    Write-Host "Edge $versionEdge sin ventana, servidor de prueba en $base"
    Write-Host '  - sin extensión...'
    $sin = Resultado (Abrir 'sin-extension' "$base/prueba.html" 'perfil-sin' '') 'sin-extension'
    Write-Host '  - con Mosquitero...'
    $con = Resultado (Abrir 'con-mosquitero' "$base/prueba.html" 'perfil-con' $extension) 'con-mosquitero'
    Write-Host '  - con Mosquitero en 127.0.0.1 (EasyList pide no ocultar ahí lo general)...'
    $local = Resultado (Abrir 'local' "http://127.0.0.1:$Puerto/prueba.html" 'perfil-local' $extension) 'local'
    $comodin = $null; $exacto = $null
    if ($hostComodin) {
        Write-Host "  - con Mosquitero en $hostComodin..."
        $comodin = Resultado (Abrir 'sitio-comodin' "http://${hostComodin}:$Puerto/prueba.html" 'perfil-comodin' $extension) 'sitio-comodin'
    }
    if ($hostExacto) {
        Write-Host "  - con Mosquitero en $hostExacto..."
        try { $exacto = Resultado (Abrir 'sitio-exacto' "http://${hostExacto}:$Puerto/prueba.html" 'perfil-exacto' $extension) 'sitio-exacto' }
        catch { Write-Host "      (no se pudo abrir $hostExacto por http: $($_.Exception.Message))" }
    }
    # Copia de prueba: cambia el ajuste como la ventanita y vuelve a abrir la página en la misma sesión
    Write-Host '  - «Activo en este sitio» apagado en apagado.test...'
    $apagado = Resultado (Abrir 'sitio-apagado' "http://apagado.test:$Puerto/prueba.html?preparar=apagar-sitio" 'perfil-apagado' $extPrueba) 'sitio-apagado'
    Write-Host '  - «Bloquear rastreadores» apagado...'
    $sinRastreo = Resultado (Abrir 'sin-rastreadores' "$base/prueba.html?preparar=sin-rastreadores" 'perfil-rastreadores' $extPrueba) 'sin-rastreadores'
    $control = $apagado['previos']['control']
    $controlRastreo = $sinRastreo['previos']['control']
    # La ventanita de verdad (popup.html), dentro de una página de la copia de prueba
    Write-Host '  - la ventanita...'
    $idPrueba = IdDeRuta $extPrueba
    $ventanita = Resultado (Abrir 'ventanita' "chrome-extension://$idPrueba/prueba-ventanita.html?puerto=$Puerto" 'perfil-ventanita' $extPrueba) 'ventanita'
    Write-Host '  - validar genericos.css...'
    $domCss = Abrir 'validar-css' "$base/validar-css.html" 'perfil-sin' ''
    $mv = [regex]::Match($domCss, '<pre id="resultado">([^<]*)</pre>')
    $validacion = $(if ($mv.Success -and $mv.Groups[1].Value -ne 'esperando') { DeJson ([System.Net.WebUtility]::HtmlDecode($mv.Groups[1].Value)) } else { $null })
}
finally {
    try { Invoke-WebRequest -Uri "http://127.0.0.1:$Puerto/salir" -UseBasicParsing -TimeoutSec 5 | Out-Null } catch { }
    if (-not $servidor.HasExited) { Stop-Process -Id $servidor.Id -Force -ErrorAction SilentlyContinue }
}

# --- Informe --------------------------------------------------------------------------------------
$fallos = New-Object 'System.Collections.Generic.List[string]'
$inf = New-Object System.Text.StringBuilder
function L([string]$t = '') { [void]$inf.Append($t).Append("`n") }
function Estado($resultado, [string]$nombre) { foreach ($r in $resultado['red']) { if ($r['nombre'] -eq $nombre) { return $r['estado'] } }; return '?' }
function Oculto($resultado, [string]$nombre) { foreach ($r in $resultado['ocultar']) { if ($r['nombre'] -eq $nombre) { return [bool]$r['oculto'] } }; return $null }
function Visto($b) { if ($b) { 'oculto' } else { 'visible' } }

L "Prueba de Mosquitero en Microsoft Edge $versionEdge sin ventana ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
L ''
L 'Red: sin extensión -> con Mosquitero'
foreach ($r in $recursos) {
    $a = Estado $sin $r.nombre
    $b = Estado $con $r.nombre
    $veredicto = ''
    if ($r.grupo -eq 'normal') {
        $veredicto = $(if ($b -eq 'cargó') { 'bien: no se bloquea' } else { 'MAL: se bloqueó algo normal' })
        if ($b -ne 'cargó' -and $a -eq 'cargó') { $fallos.Add("Se bloqueó un recurso normal: $($r.nombre)") }
    }
    elseif ($a -ne 'cargó') { $veredicto = 'no se puede saber: tampoco cargó sin la extensión' }
    elseif ($b -ne 'cargó') { $veredicto = 'bien: bloqueado' }
    else { $veredicto = 'MAL: no se bloqueó'; $fallos.Add("No se bloqueó: $($r.nombre)") }
    L ('  {0,-11} {1,-34} {2,-9} -> {3,-9} {4}' -f $r.grupo, $r.nombre, $a, $b, $veredicto)
}
L ''
L 'Ocultar huecos'
foreach ($e in $elementos) {
    $a = Oculto $sin $e.nombre
    $b = Oculto $con $e.nombre
    $linea = '  {0,-26} {1,-40} sin extensión: {2,-8} con Mosquitero en pagina.test: {3}' -f $e.nombre, $e.selector, (Visto $a), (Visto $b)
    if ($e.tipo -eq 'comodin' -and $comodin) { $c = Oculto $comodin $e.nombre; $linea += "; en ${hostComodin}: $(Visto $c)"; if (-not $c) { $fallos.Add("No se ocultó $($e.selector) en $hostComodin") } }
    if ($e.tipo -eq 'exacto' -and $exacto) { $c = Oculto $exacto $e.nombre; $linea += "; en ${hostExacto}: $(Visto $c)"; if (-not $c) { $fallos.Add("No se ocultó $($e.selector) en $hostExacto") } }
    L $linea
    if ($a) { $fallos.Add("Sin la extensión ya estaba oculto: $($e.selector)") }
    if (($e.tipo -eq 'general' -or $e.tipo -eq 'conExcepcion') -and -not $b) { $fallos.Add("No se ocultó el general $($e.selector)") }
    if (($e.tipo -eq 'comodin' -or $e.tipo -eq 'exacto' -or $e.tipo -eq 'normal') -and $b) { $fallos.Add("Se ocultó en pagina.test algo que no tocaba: $($e.selector)") }
}
$anunciosLocal = @($recursos | Where-Object { $_.grupo -eq 'anuncio' } | ForEach-Object { Estado $local $_.nombre })
$generalesLocal = @(@($local['ocultar']) | Where-Object { ($_['tipo'] -eq 'general' -or $_['tipo'] -eq 'conExcepcion') -and $_['oculto'] })
L ('  En 127.0.0.1 (EasyList trae «@@://127.0.0.1$generichide»): anuncios bloqueados {0} de {1}; generales ocultos: {2} (deben ser 0); marca de pausa: {3}' -f @($anunciosLocal | Where-Object { $_ -ne 'cargó' }).Count, $anunciosLocal.Count, $generalesLocal.Count, $local['pausa'])
if ($generalesLocal.Count -or -not $local['pausa']) { $fallos.Add('En 127.0.0.1 se ocultó lo general, y EasyList pide no hacerlo') }
if (@($anunciosLocal | Where-Object { $_ -eq 'cargó' }).Count) { $fallos.Add('En 127.0.0.1 cargó algún anuncio') }
L ''
L 'Interruptores (copia de prueba que hace lo mismo que la ventanita)'
if ($control -and -not $control['error']) {
    $dinamicas = @($control['dinamicas'])
    L ('  Reglas dinámicas creadas: {0} (allowAllRequests para {1})' -f $dinamicas.Count, (($dinamicas | ForEach-Object { $_['condition']['requestDomains'] -join ',' }) -join '; '))
    L ('  Reglas estáticas que todavía caben en Edge: {0}' -f $control['disponibles'])
    foreach ($x in $control['antes']) {
        $txt = $(if ($x['error']) { 'error: ' + $x['error'] } elseif (@($x['reglas']).Count) { 'la cazan ' + (@($x['reglas']) -join ', ') } else { 'ninguna regla la caza' })
        L ('  testMatchOutcome {0}: {1}' -f $x['url'], $txt)
    }
}
else { L '  No se pudo leer la respuesta del control.'; $fallos.Add('El control de la copia de prueba no respondió') }
$anunciosApagado = @($recursos | Where-Object { $_.grupo -eq 'anuncio' } | ForEach-Object { Estado $apagado $_.nombre })
$todosCargan = -not ($anunciosApagado | Where-Object { $_ -ne 'cargó' })
$nadaOculto = -not (@($apagado['ocultar']) | Where-Object { $_['oculto'] })
L ('  Sitio apagado (apagado.test): anuncios que cargan {0} de {1}; elementos ocultos: {2}; marca de pausa: {3}' -f @($anunciosApagado | Where-Object { $_ -eq 'cargó' }).Count, $anunciosApagado.Count, $(if ($nadaOculto) { 'ninguno' } else { 'alguno' }), $apagado['pausa'])
if (-not $todosCargan) { $fallos.Add('En el sitio apagado no cargaron todos los anuncios') }
if (-not $nadaOculto) { $fallos.Add('En el sitio apagado se ocultó algo') }
$rastreo = @($recursos | Where-Object { $_.grupo -eq 'rastreador' } | ForEach-Object { Estado $sinRastreo $_.nombre })
$anuncios = @($recursos | Where-Object { $_.grupo -eq 'anuncio' } | ForEach-Object { Estado $sinRastreo $_.nombre })
L ('  Sin «Bloquear rastreadores» (pagina.test): rastreadores que cargan {0} de {1}; anuncios bloqueados {2} de {3}' -f @($rastreo | Where-Object { $_ -eq 'cargó' }).Count, $rastreo.Count, @($anuncios | Where-Object { $_ -ne 'cargó' }).Count, $anuncios.Count)
if ($controlRastreo -and -not $controlRastreo['error']) {
    L ('  Conjuntos de reglas activos después de apagar los rastreadores: {0}' -f (@($controlRastreo['activos']) -join ', '))
    if (@($controlRastreo['activos']) -contains 'rastreadores') { $fallos.Add('El conjunto «rastreadores» siguió activo') }
}
else { $fallos.Add('El control de «Bloquear rastreadores» no respondió') }
if (@($rastreo | Where-Object { $_ -ne 'cargó' }).Count) { $fallos.Add('Con los rastreadores apagados, alguno no cargó') }
if (@($anuncios | Where-Object { $_ -eq 'cargó' }).Count) { $fallos.Add('Con los rastreadores apagados, algún anuncio cargó') }
L ''
L 'Ventanita (popup.html de verdad, abierta dentro de una página de la copia de prueba)'
$versionEsperada = ([System.IO.File]::ReadAllText((Join-Path $Raiz 'version.txt'))).Trim()
L ('  Versión: {0}; sitio: «{1}»; interruptor desactivado (es una página del navegador): {2}' -f $ventanita['version'], $ventanita['sitio'], $ventanita['interruptorDesactivado'])
L ('  Aviso: {0}' -f $ventanita['aviso'])
L ('  Nota del contador visible: {0}; «Bloquear rastreadores» marcada: {1}' -f $ventanita['notaContador'], $ventanita['rastreadores'])
L ('  Al desmarcarla: conjuntos activos {0} -> {1}' -f (@($ventanita['activosAntes']) -join ', '), (@($ventanita['activosDespues']) -join ', '))
L ('  Aviso: {0}' -f $ventanita['avisoRastreadores'])
if ($ventanita['version'] -ne $versionEsperada) { $fallos.Add('La ventanita no muestra la versión') }
if (-not $ventanita['rastreadores'] -or -not $ventanita['notaContador'] -or -not $ventanita['interruptorDesactivado']) { $fallos.Add('La ventanita no mostró el estado esperado') }
if (@($ventanita['activosDespues']) -contains 'rastreadores' -or -not $ventanita['avisoRastreadores']) { $fallos.Add('La casilla «Bloquear rastreadores» de la ventanita no apagó los rastreadores') }
L ''
L 'genericos.css en Edge'
if ($validacion) {
    L ('  Grupos: {0} en el archivo, {1} aceptados por Edge; selectores: {2}, que Edge no entiende: {3}' -f $validacion['esperados'], $validacion['aceptados'], $validacion['selectores'], @($validacion['invalidos']).Count)
    foreach ($s in @($validacion['invalidos'] | Select-Object -First 15)) { L "    $s" }
}
else { L '  No se pudo validar.'; $fallos.Add('No se pudo validar genericos.css') }
L ''
if ($fallos.Count) { L "RESULTADO: $($fallos.Count) problema(s)"; foreach ($f in $fallos) { L "  - $f" } }
else { L 'RESULTADO: todo bien.' }

$texto = $inf.ToString()
[System.IO.File]::WriteAllText((Join-Path $trabajo 'resultado.txt'), $texto, $utf8)
Write-Host ''
Write-Host $texto
if ($fallos.Count) { exit 1 }
