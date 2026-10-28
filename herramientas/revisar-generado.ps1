# Revisa una carpeta de extensión ya armada (por ejemplo publicar\chrome) antes de comprimirla:
#   - que el manifiesto y las reglas sean JSON válido;
#   - que cada regla tenga la forma que piden Chrome y Firefox (ids únicos, tipos conocidos,
#     dominios en minúsculas y ASCII, urlFilter en ASCII y sin «||*» al principio, etc.);
#   - que el total no pase del límite seguro de Chrome (30 000 reglas estáticas);
#   - que el JSON por sitio y el CSS general estén bien formados.
# Si algo falla, termina con error y dice qué.
#
# Uso: powershell -ExecutionPolicy Bypass -File herramientas\revisar-generado.ps1 -Carpeta publicar\chrome
param(
    [Parameter(Mandatory = $true)][string]$Carpeta,
    [int]$Limite = 30000
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1

$esPs5 = $PSVersionTable.PSVersion.Major -lt 6
if ($esPs5) {
    Add-Type -AssemblyName System.Web.Extensions
    $serializador = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializador.MaxJsonLength = [int]::MaxValue
    $serializador.RecursionLimit = 100
}

function LeerJson([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { throw "Falta $ruta" }
    $texto = [System.IO.File]::ReadAllText($ruta, [System.Text.Encoding]::UTF8)
    try {
        if ($esPs5) { return , $serializador.DeserializeObject($texto) }
        return , ($texto | ConvertFrom-Json -AsHashtable -Depth 100)
    }
    catch { throw "$ruta no es JSON válido: $($_.Exception.Message)" }
}

$problemas = New-Object 'System.Collections.Generic.List[string]'
function Problema([string]$texto) { if ($problemas.Count -lt 50) { $problemas.Add($texto) } }
# PowerShell 5.1 lee los números como Int32 y PowerShell 7 como Int64
function EsEntero($x) { return ($x -is [int] -or $x -is [long]) }

$tiposValidos = @('main_frame', 'sub_frame', 'stylesheet', 'script', 'image', 'font', 'object', 'xmlhttprequest',
    'ping', 'csp_report', 'media', 'websocket', 'webtransport', 'webbundle', 'other')
$accionesValidas = @('block', 'allow', 'allowAllRequests', 'upgradeScheme')
$clavesCondicion = @('urlFilter', 'isUrlFilterCaseSensitive', 'requestDomains', 'initiatorDomains',
    'excludedInitiatorDomains', 'domainType', 'resourceTypes', 'excludedResourceTypes')
$reDominio = New-Object System.Text.RegularExpressions.Regex('^[a-z0-9_-]+(?:\.[a-z0-9_-]+)*$')
$reNoAscii = New-Object System.Text.RegularExpressions.Regex('[^\x20-\x7E]')

function RevisarDominios($valor, [string]$donde) {
    $n = 0
    foreach ($d in $valor) {
        $n++
        if (-not ($d -is [string]) -or -not $reDominio.IsMatch($d)) { Problema "$donde tiene un dominio no válido: «$d»" }
    }
    if ($n -eq 0) { Problema "$donde es una lista vacía" }
}

# --- Manifiesto ---
$manifiesto = LeerJson (Join-Path $Carpeta 'manifest.json')
foreach ($ruta in @('background.js', 'contenido.js', 'popup.html', 'popup.js', 'popup.css', 'cosmetico/genericos.css',
        'cosmetico/por-sitio.json', 'iconos/icono-16.png', 'iconos/icono-32.png', 'iconos/icono-48.png', 'iconos/icono-128.png',
        'LICENSE', 'AVISOS-DE-TERCEROS.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Carpeta $ruta))) { Problema "Falta $ruta" }
}

# --- Reglas de red ---
$total = 0
foreach ($recurso in $manifiesto['declarative_net_request']['rule_resources']) {
    $nombre = $recurso['id']
    $reglas = LeerJson (Join-Path $Carpeta $recurso['path'])
    $ids = New-Object 'System.Collections.Generic.HashSet[long]'
    $cuenta = 0
    foreach ($r in $reglas) {
        $cuenta++
        $id = $r['id']
        $donde = "$nombre, regla $id"
        if (-not (EsEntero $id) -or $id -lt 1 -or -not $ids.Add([long]$id)) { Problema "$donde`: id repetido o no válido" }
        if (-not (EsEntero $r['priority']) -or $r['priority'] -lt 1) { Problema "$donde`: prioridad no válida" }
        $accion = $r['action']['type']
        if ($accionesValidas -notcontains $accion) { Problema "$donde`: acción desconocida «$accion»" }
        $c = $r['condition']
        if ($null -eq $c -or $c.Count -eq 0) { Problema "$donde`: sin condición"; continue }
        foreach ($k in $c.Keys) { if ($clavesCondicion -cnotcontains $k) { Problema "$donde`: clave inesperada «$k»" } }
        if ($c.ContainsKey('urlFilter')) {
            $f = $c['urlFilter']
            if (-not ($f -is [string]) -or $f.Length -eq 0) { Problema "$donde`: urlFilter vacío" }
            elseif ($reNoAscii.IsMatch($f)) { Problema "$donde`: urlFilter con caracteres no ASCII" }
            elseif ($f.StartsWith('||*')) { Problema "$donde`: urlFilter empieza con ||*" }
        }
        foreach ($k in 'requestDomains', 'initiatorDomains', 'excludedInitiatorDomains') {
            if ($c.ContainsKey($k)) { RevisarDominios $c[$k] "$donde ($k)" }
        }
        if ($c.ContainsKey('domainType') -and @('firstParty', 'thirdParty') -cnotcontains $c['domainType']) { Problema "$donde`: domainType no válido" }
        if ($c.ContainsKey('resourceTypes') -and $c.ContainsKey('excludedResourceTypes')) { Problema "$donde`: resourceTypes y excludedResourceTypes a la vez" }
        foreach ($k in 'resourceTypes', 'excludedResourceTypes') {
            if ($c.ContainsKey($k)) {
                $n = 0
                foreach ($t in $c[$k]) { $n++; if ($tiposValidos -cnotcontains $t) { Problema "$donde`: tipo desconocido «$t»" } }
                if ($n -eq 0) { Problema "$donde`: $k vacío" }
            }
        }
        if ($accion -eq 'allowAllRequests') {
            if (-not $c.ContainsKey('resourceTypes')) { Problema "$donde`: allowAllRequests sin resourceTypes" }
            else { foreach ($t in $c['resourceTypes']) { if (@('main_frame', 'sub_frame') -cnotcontains $t) { Problema "$donde`: allowAllRequests solo admite main_frame y sub_frame" } } }
        }
    }
    Write-Host ("  {0}: {1} reglas" -f $nombre, $cuenta)
    $total += $cuenta
}
Write-Host ("  total: {0} reglas (límite seguro {1})" -f $total, $Limite)
if ($total -gt $Limite) { Problema "Hay $total reglas: pasa del límite de $Limite" }

# --- Ocultar huecos ---
$sitios = LeerJson (Join-Path (Join-Path $Carpeta 'cosmetico') 'por-sitio.json')
$cuantos = 0
foreach ($s in $sitios['selectores']) { $cuantos++ }
function RevisarIndices($lista, [string]$donde) {
    foreach ($i in $lista) { if (-not (EsEntero $i) -or $i -lt 0 -or $i -ge $cuantos) { Problema "$donde`: índice fuera de rango ($i)"; return } }
}
RevisarIndices $sitios['conExcepcion'] 'por-sitio.json, conExcepcion'
foreach ($parte in 'ocultar', 'excepciones') {
    foreach ($k in $sitios[$parte].Keys) {
        if (-not $reDominio.IsMatch(($k -replace '\.\*$', ''))) { Problema "por-sitio.json, $parte`: clave no válida «$k»" }
        RevisarIndices $sitios[$parte][$k] "por-sitio.json, $parte, $k"
    }
}
Write-Host ("  por-sitio.json: {0} selectores, {1} sitios" -f $cuantos, $sitios['ocultar'].Count)

$css = [System.IO.File]::ReadAllText((Join-Path (Join-Path $Carpeta 'cosmetico') 'genericos.css'), [System.Text.Encoding]::UTF8)
$abre = ([regex]::Matches($css, '\{')).Count
$cierra = ([regex]::Matches($css, '\}')).Count
if ($abre -ne $cierra) { Problema "genericos.css: llaves sin cerrar ($abre abren, $cierra cierran)" }
Write-Host ("  genericos.css: {0} grupos" -f ($abre - 1))

if ($problemas.Count) {
    foreach ($p in $problemas) { Write-Host "  PROBLEMA: $p" }
    throw "La revisión encontró $($problemas.Count) problema(s) en $Carpeta."
}
Write-Host '  Todo en orden.'
