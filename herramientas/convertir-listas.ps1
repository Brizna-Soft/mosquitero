# Convierte las listas de EasyList (formato de Adblock Plus) en lo que usa Mosquitero:
#   - el bloqueo de red, como reglas de declarativeNetRequest (DNR), el sistema de Chrome, Edge, Brave
#     y Firefox para bloquear sin leer lo que visitas;
#   - el ocultar los huecos de los anuncios (cosmético), como una hoja CSS general y un JSON por sitio.
#
# Entradas (en -Listas): easylist-AAAA-MM-DD.txt, easylistspanish-AAAA-MM-DD.txt y easyprivacy-AAAA-MM-DD.txt.
# Salidas (en -Salida):
#   reglas\anuncios.json        EasyList + EasyList Spanish
#   reglas\rastreadores.json    EasyPrivacy
#   cosmetico\genericos.css     los «##selector» que valen en todas las páginas
#   cosmetico\por-sitio.json    los «dominio##selector», las excepciones «#@#» y los sitios con $generichide
#   resumen.txt                 cuántas reglas quedaron, cuántas se omitieron y por qué
#
# No usa internet. Está hecho para Windows PowerShell 5.1 y para PowerShell 7 (pwsh): el JSON se escribe
# a mano, en un orden fijo, para que los dos den el mismo resultado (el flujo de GitHub lo comprueba).
#
# Uso: powershell -ExecutionPolicy Bypass -File herramientas\convertir-listas.ps1
param(
    [string]$Raiz = (Split-Path $PSScriptRoot -Parent),
    [string]$Listas = '',
    [string]$Salida = '',
    # Chrome garantiza 30 000 reglas estáticas por extensión; lo que pase de ahí puede no activarse.
    [int]$Limite = 30000,
    # Selectores por grupo en el CSS: si uno es inválido, el navegador descarta solo su grupo.
    [int]$Grupo = 10
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1
if (-not $Listas) { $Listas = Join-Path $Raiz 'listas' }
if (-not $Salida) { $Salida = Join-Path (Join-Path $Raiz 'extension') 'generado' }

$fuentes = @(
    [pscustomobject]@{ Clave = 'easylist';        Nombre = 'EasyList';         Conjunto = 'anuncios' },
    [pscustomobject]@{ Clave = 'easylistspanish'; Nombre = 'EasyList Spanish'; Conjunto = 'anuncios' },
    [pscustomobject]@{ Clave = 'easyprivacy';     Nombre = 'EasyPrivacy';      Conjunto = 'rastreadores' }
)
$conjuntos = @('anuncios', 'rastreadores')

# --- Expresiones y tablas ------------------------------------------------------------------------
$opcRe = [System.Text.RegularExpressions.RegexOptions]'Compiled, CultureInvariant'
$opcReI = [System.Text.RegularExpressions.RegexOptions]'Compiled, CultureInvariant, IgnoreCase'
# Las opciones van después del primer «$» desde el que el resto es una lista de opciones válida (igual que Adblock Plus)
$reOpciones = New-Object System.Text.RegularExpressions.Regex('\$(~?[\w-]+(?:=[^,]*)?(?:,~?[\w-]+(?:=[^,]*)?)*)$', $opcRe)
$reCosmetico = New-Object System.Text.RegularExpressions.Regex('^([^/|@"!]*?)#([@?$%]{0,2})#(.+)$', $opcRe)
$reNoAscii = New-Object System.Text.RegularExpressions.Regex('[^\x00-\x7F]', $opcRe)
$reControl = New-Object System.Text.RegularExpressions.Regex('[\x00-\x1F\x7F]', $opcRe)
$reDominio = New-Object System.Text.RegularExpressions.Regex('^[a-z0-9_-]+(?:\.[a-z0-9_-]+)*$', $opcRe)
# «||dominio^» sin nada más: se agrupa con los demás en una sola regla con requestDomains
$reDominioSolo = New-Object System.Text.RegularExpressions.Regex('^\|\|([a-z0-9_-]+(?:\.[a-z0-9_-]+)+)\^$', $opcReI)
# El sitio de un patrón como «||sitio.com^», «||www.google.*/search?» o «://localhost/», para las
# excepciones $generichide, $elemhide y $document (que en el ocultar valen para todo ese sitio)
$reSitioDePatron = New-Object System.Text.RegularExpressions.Regex('^(?:\|\||\|?https?://|://)([a-z0-9_-]+(?:\.[a-z0-9_-]+)*(?:\.\*)?)(?:[\^/:?|].*)?$', $opcReI)
$reProcedural = New-Object System.Text.RegularExpressions.Regex(
    ':(?:-abp-[a-z-]+|-ext-[a-z-]+|has-text|contains|xpath|upward|remove|remove-attr|remove-class|style|matches-css(?:-before|-after)?|matches-path|matches-attr|matches-media|matches-prop|min-text-length|watch-attr|nth-ancestor|if|if-not|others)\(', $opcReI)
$reDelicado = New-Object System.Text.RegularExpressions.Regex('[\[\]()"''\\]', $opcRe)
$idn = New-Object System.Globalization.IdnMapping

$mapaTipos = @{
    'script' = 'script'; 'image' = 'image'; 'stylesheet' = 'stylesheet'; 'css' = 'stylesheet'
    'object' = 'object'; 'object-subrequest' = 'object'; 'xmlhttprequest' = 'xmlhttprequest'; 'xhr' = 'xmlhttprequest'
    'subdocument' = 'sub_frame'; 'frame' = 'sub_frame'; 'media' = 'media'; 'font' = 'font'
    'websocket' = 'websocket'; 'ping' = 'ping'; 'other' = 'other'; 'document' = 'main_frame'; 'doc' = 'main_frame'
}
# Opciones que se entienden pero que las reglas de Chrome no pueden imitar: la regla se omite
$opcionesNoConvertibles = @{
    'csp' = '$csp'; 'redirect' = '$redirect'; 'redirect-rule' = '$redirect'; 'rewrite' = '$rewrite'
    'removeparam' = '$removeparam'; 'queryprune' = '$removeparam'; 'popup' = '$popup'; 'popunder' = '$popup'
    'badfilter' = '$badfilter'; 'genericblock' = '$genericblock'; 'sitekey' = '$sitekey'
}

# --- Estado ---------------------------------------------------------------------------------------
function NuevoConjuntoTexto { return , (New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)) }
function NuevoDiccionario { return , (New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)) }

$vistas = NuevoConjuntoTexto                 # reglas ya escritas (para no repetir)
$reglas = @{}; $agrupadas = @{}; $ordenGrupos = @{}
foreach ($c in $conjuntos) {
    $reglas[$c] = New-Object 'System.Collections.Generic.List[object]'
    $agrupadas[$c] = NuevoDiccionario
    $ordenGrupos[$c] = New-Object 'System.Collections.Generic.List[string]'
}
$genericos = New-Object 'System.Collections.Generic.List[string]'
$genericosVistos = NuevoConjuntoTexto
$excepcionGlobal = NuevoConjuntoTexto
$ocultar = NuevoDiccionario                  # dominio -> selectores
$excepciones = NuevoDiccionario              # dominio -> selectores que no se ocultan ahí
$sinGenericos = NuevoConjuntoTexto           # @@...$generichide
$sinOcultar = NuevoConjuntoTexto             # @@...$elemhide y @@...$document

# --- Ayudantes ------------------------------------------------------------------------------------
function JsonCadena([string]$s) {
    $t = $s.Replace('\', '\\').Replace('"', '\"')
    if ($reControl.IsMatch($t)) {
        $t = $reControl.Replace($t, [System.Text.RegularExpressions.MatchEvaluator] { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    }
    return '"' + $t + '"'
}

function JsonLista($lista) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('[')
    $primero = $true
    foreach ($x in $lista) {
        if (-not $primero) { [void]$sb.Append(',') }
        [void]$sb.Append((JsonCadena $x))
        $primero = $false
    }
    [void]$sb.Append(']')
    return $sb.ToString()
}

function Ordenado($coleccion) {
    $arr = [string[]]@($coleccion)
    [System.Array]::Sort($arr, [System.StringComparer]::Ordinal)
    return , $arr
}

function DominioAscii([string]$d) {
    $comodin = $false
    if ($d.EndsWith('.*')) { $comodin = $true; $d = $d.Substring(0, $d.Length - 2) }
    if ($reNoAscii.IsMatch($d)) {
        try { $d = $idn.GetAscii($d).ToLowerInvariant() } catch { return '' }
    }
    if (-not $reDominio.IsMatch($d)) { return '' }
    if ($comodin) { return $d + '.*' }
    return $d
}

function Agregar($diccionario, [string]$clave, [string]$valor) {
    $conjunto = $null
    if (-not $diccionario.TryGetValue($clave, [ref]$conjunto)) {
        $conjunto = NuevoConjuntoTexto
        $diccionario[$clave] = $conjunto
    }
    [void]$conjunto.Add($valor)
}

function Omitir($e, [string]$tipo, [string]$motivo) {
    $clave = $tipo + '|' + $motivo
    $n = 0
    if ($e.Omitidos.TryGetValue($clave, [ref]$n)) { $e.Omitidos[$clave] = $n + 1 } else { $e.Omitidos[$clave] = 1 }
    if ($tipo -eq 'red') { $e.RedOmitidas++ } else { $e.CosmOmitidos++ }
}

# Devuelve '' si el selector se puede poner en el CSS, o el motivo para omitirlo.
function MotivoSelector([string]$s) {
    if ($s.Length -eq 0 -or $s.Length -gt 2000) { return 'selector vacío o demasiado largo' }
    if ($s.IndexOf('{') -ge 0 -or $s.IndexOf('}') -ge 0) { return 'cambia estilos ({...}), no oculta' }
    if ($s.Contains('/*') -or $s.Contains('*/')) { return 'selector mal cerrado' }
    if (-not $reDelicado.IsMatch($s) -and $s.IndexOf(';') -lt 0) { return '' }
    # Comillas, corchetes y paréntesis tienen que cerrar, y no puede haber «;» fuera de comillas:
    # si no, el selector arrastraría a los que vienen detrás.
    $comilla = [char]0
    $corchetes = 0
    $parentesis = 0
    $n = $s.Length
    for ($i = 0; $i -lt $n; $i++) {
        $c = $s[$i]
        if ($c -eq [char]'\') { $i++; continue }
        if ($comilla -ne [char]0) { if ($c -eq $comilla) { $comilla = [char]0 }; continue }
        if ($c -eq [char]'"' -or $c -eq [char]"'") { $comilla = $c }
        elseif ($c -eq [char]';') { return 'selector mal cerrado' }
        elseif ($c -eq [char]'[') { $corchetes++ }
        elseif ($c -eq [char]']') { $corchetes--; if ($corchetes -lt 0) { return 'selector mal cerrado' } }
        elseif ($c -eq [char]'(') { $parentesis++ }
        elseif ($c -eq [char]')') { $parentesis--; if ($parentesis -lt 0) { return 'selector mal cerrado' } }
    }
    if ($n -gt 0 -and $s[$n - 1] -eq [char]'\') { return 'selector mal cerrado' }
    if ($comilla -ne [char]0 -or $corchetes -ne 0 -or $parentesis -ne 0) { return 'selector mal cerrado' }
    return ''
}

# --- Bloqueo de red -------------------------------------------------------------------------------
$cabezaBloqueo = '"priority":1,"action":{"type":"block"}'

# Muchos «||dominio^» con las mismas opciones caben en una sola regla (requestDomains)
function AgregarDominio([string]$conjunto, [string]$cabeza, [string]$resto, [string]$dominio, [int]$nivel, $e) {
    $clave = $cabeza + '#' + $resto
    $grupo = $null
    if (-not $agrupadas[$conjunto].TryGetValue($clave, [ref]$grupo)) {
        $grupo = [pscustomobject]@{ Cabeza = $cabeza; Resto = $resto; Dominios = (NuevoConjuntoTexto); Nivel = $nivel }
        $agrupadas[$conjunto][$clave] = $grupo
        $ordenGrupos[$conjunto].Add($clave)
    }
    if ($grupo.Dominios.Add($dominio)) { $e.RedAgrupadas++ } else { $e.RedRepetidas++ }
}

function ConvertirRed([string]$texto, $e, [string]$conjunto) {
    $e.Red++
    # Camino rápido: la gran mayoría de las líneas son «||dominio^» sin opciones
    if ($texto.StartsWith('||') -and $texto.IndexOf('$') -lt 0) {
        $m = $reDominioSolo.Match($texto)
        if ($m.Success) { AgregarDominio $conjunto $cabezaBloqueo '' $m.Groups[1].Value.ToLowerInvariant() 1 $e; return }
    }
    $excepcion = $false
    if ($texto.StartsWith('@@')) { $excepcion = $true; $texto = $texto.Substring(2) }
    $patron = $texto
    $opciones = ''
    if ($texto.IndexOf('$') -ge 0) {
        $m = $reOpciones.Match($texto)
        if ($m.Success) { $patron = $texto.Substring(0, $m.Index); $opciones = $m.Groups[1].Value }
    }
    if ($patron.Length -gt 1 -and $patron.StartsWith('/') -and $patron.EndsWith('/')) { Omitir $e 'red' 'expresión regular'; return }
    if ($reNoAscii.IsMatch($texto)) { Omitir $e 'red' 'no es ASCII'; return }

    $tipos = New-Object 'System.Collections.Generic.List[string]'
    $noTipos = New-Object 'System.Collections.Generic.List[string]'
    $iniciadores = New-Object 'System.Collections.Generic.List[string]'
    $excluidos = New-Object 'System.Collections.Generic.List[string]'
    $sitiosComodin = New-Object 'System.Collections.Generic.List[string]'   # los «sitio.*» de $domain=
    $tipoDominio = ''
    $mayus = $false; $importante = $false; $sinGen = $false; $sinTodo = $false

    if ($opciones) {
        foreach ($o in $opciones.Split([char]',')) {
            $neg = $o.StartsWith('~')
            if ($neg) { $o = $o.Substring(1) }
            $valor = ''
            $i = $o.IndexOf('=')
            if ($i -ge 0) { $valor = $o.Substring($i + 1); $o = $o.Substring(0, $i) }
            $o = $o.ToLowerInvariant()
            if ($mapaTipos.ContainsKey($o)) {
                if ($neg) { $noTipos.Add($mapaTipos[$o]) } else { $tipos.Add($mapaTipos[$o]) }
            }
            elseif ($o -eq 'third-party' -or $o -eq '3p') { $tipoDominio = $(if ($neg) { 'firstParty' } else { 'thirdParty' }) }
            elseif ($o -eq 'first-party' -or $o -eq '1p') { $tipoDominio = $(if ($neg) { 'thirdParty' } else { 'firstParty' }) }
            elseif ($o -eq 'match-case') { $mayus = -not $neg }
            elseif ($o -eq 'important') { $importante = $true }
            elseif ($o -eq 'generichide' -or $o -eq 'ghide') { $sinGen = $true }
            elseif ($o -eq 'elemhide' -or $o -eq 'ehide') { $sinTodo = $true }
            elseif ($o -eq 'domain' -or $o -eq 'from') {
                foreach ($d in $valor.Split([char]'|')) {
                    $d = $d.Trim().ToLowerInvariant()
                    $dneg = $d.StartsWith('~')
                    if ($dneg) { $d = $d.Substring(1) }
                    if (-not $d) { continue }
                    if ($d.StartsWith('[')) {
                        # Direcciones IPv6 como [::1]: Chrome no las acepta aquí. Si solo se excluían, se quitan.
                        if ($dneg) { continue }
                        Omitir $e 'red' 'dominio no válido en $domain'; return
                    }
                    $d = DominioAscii $d
                    if (-not $d) { Omitir $e 'red' 'dominio no válido en $domain'; return }
                    if ($d.EndsWith('.*')) {
                        # Las reglas de Chrome no entienden «sitio.*»: si solo se excluía, la regla no se puede usar
                        if ($dneg) { Omitir $e 'red' 'dominio con comodín (sitio.*)'; return }
                        $sitiosComodin.Add($d)
                        continue
                    }
                    if ($dneg) { $excluidos.Add($d) } else { $iniciadores.Add($d) }
                }
            }
            elseif ($opcionesNoConvertibles.ContainsKey($o)) { Omitir $e 'red' $opcionesNoConvertibles[$o]; return }
            else { Omitir $e 'red' ('opción desconocida ($' + $o + ')'); return }
        }
    }
    # Excepciones que solo apagan el ocultar huecos: van al JSON por sitio, no a las reglas de red.
    # Valen para los sitios de $domain= o, si no hay, para el sitio del patrón (si trae una ruta, para
    # todo el sitio: es mejor ocultar de menos que esconder lo que no es un anuncio).
    if ($sinGen -or $sinTodo) {
        if (-not $excepcion) { Omitir $e 'red' '$generichide o $elemhide sin @@'; return }
        $sitios = New-Object 'System.Collections.Generic.List[string]'
        foreach ($d in $iniciadores) { $sitios.Add($d) }
        foreach ($d in $sitiosComodin) { $sitios.Add($d) }
        if ($sitios.Count -eq 0) {
            $m = $reSitioDePatron.Match($patron)
            if ($m.Success) { $sitios.Add($m.Groups[1].Value.ToLowerInvariant()) }
        }
        if ($sitios.Count -eq 0) { Omitir $e 'red' '$generichide o $elemhide sin un sitio claro'; return }
        foreach ($s in $sitios) { if ($sinTodo) { [void]$sinOcultar.Add($s) } else { [void]$sinGenericos.Add($s) } }
        $e.RedCosmeticas++
        if ($tipos.Count -eq 0 -and $noTipos.Count -eq 0) { return }
    }
    if ($sitiosComodin.Count) {
        if ($iniciadores.Count -eq 0) { Omitir $e 'red' 'dominio con comodín (sitio.*)'; return }
        $e.RedSinComodin++
    }

    $accion = 'block'
    $prioridad = 1
    $rt = $null
    $ert = $null
    if ($excepcion) {
        $accion = 'allow'
        $prioridad = 2
        if ($tipos.Contains('main_frame')) {
            # @@...$document: todo lo de esa página queda permitido, y tampoco se oculta nada ahí
            $accion = 'allowAllRequests'
            $rt = [string[]]@('main_frame', 'sub_frame')
            $m = $reSitioDePatron.Match($patron)
            if ($m.Success) { [void]$sinOcultar.Add($m.Groups[1].Value.ToLowerInvariant()) }
        }
    }
    elseif ($importante) { $prioridad = 3 }

    if (-not $rt) {
        if ($tipos.Count -gt 0) {
            $quedan = NuevoConjuntoTexto
            foreach ($t in $tipos) { if (-not $noTipos.Contains($t)) { [void]$quedan.Add($t) } }
            if ($quedan.Count -eq 0) { Omitir $e 'red' 'sin tipos de recurso'; return }
            $rt = Ordenado $quedan
        }
        elseif ($noTipos.Count -gt 0) {
            # Sin tipos propios, Adblock Plus nunca bloquea la página entera: main_frame queda fuera
            $fuera = NuevoConjuntoTexto
            foreach ($t in $noTipos) { [void]$fuera.Add($t) }
            [void]$fuera.Add('main_frame')
            $ert = Ordenado $fuera
        }
    }

    # Patrón
    $dominioSolo = ''
    if (-not $mayus) {
        $m = $reDominioSolo.Match($patron)
        if ($m.Success) { $dominioSolo = $m.Groups[1].Value.ToLowerInvariant() }
    }
    $filtro = ''
    if (-not $dominioSolo) {
        $filtro = $patron
        if ($filtro.StartsWith('||*')) { $filtro = '*' + $filtro.Substring(3) }
        if ($filtro.Trim([char]'*').Length -eq 0) { $filtro = '' }
        if ($filtro) {
            $medio = $filtro
            if ($medio.StartsWith('||')) { $medio = $medio.Substring(2) } elseif ($medio.StartsWith('|')) { $medio = $medio.Substring(1) }
            if ($medio.EndsWith('|')) { $medio = $medio.Substring(0, $medio.Length - 1) }
            if ($medio.Contains('|') -or $medio.Contains(' ') -or $medio.Length -eq 0) { Omitir $e 'red' 'patrón que Chrome no acepta'; return }
        }
    }

    $partes = New-Object 'System.Collections.Generic.List[string]'
    if ($filtro) {
        $partes.Add('"urlFilter":' + (JsonCadena $filtro))
        if ($mayus) { $partes.Add('"isUrlFilterCaseSensitive":true') }
    }
    if ($iniciadores.Count) { $partes.Add('"initiatorDomains":' + (JsonLista (Ordenado $iniciadores))) }
    if ($excluidos.Count) { $partes.Add('"excludedInitiatorDomains":' + (JsonLista (Ordenado $excluidos))) }
    if ($tipoDominio) { $partes.Add('"domainType":"' + $tipoDominio + '"') }
    if ($rt) { $partes.Add('"resourceTypes":' + (JsonLista $rt)) }
    if ($ert) { $partes.Add('"excludedResourceTypes":' + (JsonLista $ert)) }
    $resto = [string]::Join(',', $partes.ToArray())
    $cabeza = '"priority":' + $prioridad + ',"action":{"type":"' + $accion + '"}'

    if ($dominioSolo) {
        AgregarDominio $conjunto $cabeza $resto $dominioSolo $(if ($excepcion) { 0 } else { 1 }) $e
        return
    }

    if ($partes.Count -eq 0) { Omitir $e 'red' 'demasiado general (valdría para todo)'; return }
    $json = '{' + $cabeza + ',"condition":{' + $resto + '}}'
    if (-not $vistas.Add($json)) { $e.RedRepetidas++; return }
    $nivel = 2
    if ($excepcion) { $nivel = 0 } elseif ($iniciadores.Count) { $nivel = 3 }
    $reglas[$conjunto].Add([pscustomobject]@{ Json = $json; Nivel = $nivel; Lista = $e.Nombre })
    $e.RedPropias++
}

# --- Ocultar huecos (cosmético) -------------------------------------------------------------------
function ConvertirCosmetico([string]$dominios, [string]$separador, [string]$selector, $e) {
    $e.Cosm++
    if ($separador.Contains('?')) { Omitir $e 'cosm' 'extendido (#?#)'; return }
    if ($separador.Contains('$')) { Omitir $e 'cosm' 'fragmento de código (#$#)'; return }
    if ($separador.Contains('%')) { Omitir $e 'cosm' 'script (#%#)'; return }
    $esExcepcion = $separador.Contains('@')
    $selector = $selector.Trim()
    if ($selector.StartsWith('+js(')) { Omitir $e 'cosm' 'script (##+js)'; return }
    if ($reProcedural.IsMatch($selector)) { Omitir $e 'cosm' 'extendido (:has-text, :-abp-..., etc.)'; return }
    $motivo = MotivoSelector $selector
    if ($motivo) { Omitir $e 'cosm' $motivo; return }

    $si = New-Object 'System.Collections.Generic.List[string]'
    $no = New-Object 'System.Collections.Generic.List[string]'
    $habiaSi = $false
    if ($dominios) {
        foreach ($d in $dominios.Split([char]',')) {
            $d = $d.Trim().ToLowerInvariant()
            if (-not $d) { continue }
            $neg = $d.StartsWith('~')
            if ($neg) { $d = $d.Substring(1) } else { $habiaSi = $true }
            $d = DominioAscii $d
            if (-not $d) { continue }
            if ($neg) { $no.Add($d) } else { $si.Add($d) }
        }
        if ($habiaSi -and $si.Count -eq 0) { Omitir $e 'cosm' 'dominio no válido'; return }
    }

    if ($esExcepcion) {
        if (-not $dominios) { [void]$excepcionGlobal.Add($selector) }
        foreach ($d in $si) { Agregar $excepciones $d $selector }
        $e.CosmExcepciones++
        return
    }
    if ($si.Count -eq 0) {
        if ($genericosVistos.Add($selector)) { $genericos.Add($selector) }
        foreach ($d in $no) { Agregar $excepciones $d $selector }
        $e.CosmGenericos++
    }
    else {
        foreach ($d in $si) { Agregar $ocultar $d $selector }
        foreach ($d in $no) { Agregar $excepciones $d $selector }
        $e.CosmPorSitio++
    }
}

# --- Leer las listas ------------------------------------------------------------------------------
$estadisticas = New-Object 'System.Collections.Generic.List[object]'
foreach ($f in $fuentes) {
    $archivo = Get-ChildItem -LiteralPath $Listas -File |
        Where-Object { $_.Name -match ('^' + [regex]::Escape($f.Clave) + '-\d{4}-\d{2}-\d{2}\.txt$') } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $archivo) { throw "No encuentro $($f.Clave)-AAAA-MM-DD.txt en $Listas. Corre herramientas\actualizar-listas.ps1." }
    $e = [pscustomobject]@{
        Nombre = $f.Nombre; Archivo = $archivo.Name; Conjunto = $f.Conjunto
        Lineas = 0; Comentarios = 0
        Red = 0; RedPropias = 0; RedAgrupadas = 0; RedCosmeticas = 0; RedRepetidas = 0; RedOmitidas = 0; RedSinComodin = 0
        Cosm = 0; CosmGenericos = 0; CosmPorSitio = 0; CosmExcepciones = 0; CosmOmitidos = 0
        Omitidos = (New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal))
    }
    $lineas = [System.IO.File]::ReadAllLines($archivo.FullName, [System.Text.Encoding]::UTF8)
    foreach ($linea in $lineas) {
        $e.Lineas++
        $t = $linea.Trim()
        if ($t.Length -eq 0 -or $t[0] -eq [char]'!' -or $t[0] -eq [char]'[') { $e.Comentarios++; continue }
        $m = $reCosmetico.Match($t)
        if ($m.Success) { ConvertirCosmetico $m.Groups[1].Value $m.Groups[2].Value $m.Groups[3].Value $e }
        else { ConvertirRed $t $e $f.Conjunto }
    }
    $estadisticas.Add($e)
}

# --- Armar las reglas de red ----------------------------------------------------------------------
function CubiertoPor([string]$dominio, $conjunto, [bool]$tambienElMismo) {
    if ($tambienElMismo -and $conjunto.Contains($dominio)) { return $true }
    $d = $dominio
    while ($true) {
        $i = $d.IndexOf('.')
        if ($i -lt 0) { return $false }
        $d = $d.Substring($i + 1)
        if ($conjunto.Contains($d)) { return $true }
    }
}

$cubiertos = 0
$final = @{}
foreach ($c in $conjuntos) {
    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($clave in $ordenGrupos[$c]) {
        $g = $agrupadas[$c][$clave]
        $previo = $null
        if ($c -ne 'anuncios' -and $agrupadas['anuncios'].ContainsKey($clave)) { $previo = $agrupadas['anuncios'][$clave].Dominios }
        $quedan = New-Object 'System.Collections.Generic.List[string]'
        foreach ($d in (Ordenado $g.Dominios)) {
            if ((CubiertoPor $d $g.Dominios $false) -or ($previo -and (CubiertoPor $d $previo $true))) { $cubiertos++; continue }
            $quedan.Add($d)
        }
        if ($quedan.Count -eq 0) { continue }
        $cond = '"requestDomains":' + (JsonLista $quedan)
        if ($g.Resto) { $cond += ',' + $g.Resto }
        $lista.Add([pscustomobject]@{ Json = ('{' + $g.Cabeza + ',"condition":{' + $cond + '}}'); Nivel = $g.Nivel; Dominios = $quedan.Count })
    }
    foreach ($r in $reglas[$c]) { $lista.Add($r) }
    $final[$c] = $lista
}

# Límite: si no caben, se quitan primero las reglas que solo valen en unos pocos sitios ($domain=),
# después las de patrón; nunca las excepciones ni las de dominios agrupados.
$recorte = New-Object 'System.Collections.Generic.List[string]'
$total = 0
foreach ($c in $conjuntos) { $total += $final[$c].Count }
foreach ($nivel in 3, 2) {
    foreach ($c in 'rastreadores', 'anuncios') {
        $quitadas = 0
        for ($i = $final[$c].Count - 1; $i -ge 0 -and $total -gt $Limite; $i--) {
            if ($final[$c][$i].Nivel -eq $nivel) { $final[$c].RemoveAt($i); $total--; $quitadas++ }
        }
        if ($quitadas) {
            $tipo = $(if ($nivel -eq 3) { 'que valen solo en algunos sitios ($domain=)' } else { 'de patrón' })
            $recorte.Add(('{0}: se quitaron {1} reglas {2}, empezando por el final de la lista.' -f $c, $quitadas, $tipo))
        }
    }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$dirReglas = Join-Path $Salida 'reglas'
$dirCosm = Join-Path $Salida 'cosmetico'
foreach ($d in $Salida, $dirReglas, $dirCosm) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

$conteo = @{}
foreach ($c in $conjuntos) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("[`n")
    $id = 0
    foreach ($r in $final[$c]) {
        $id++
        if ($id -gt 1) { [void]$sb.Append(",`n") }
        [void]$sb.Append('{"id":').Append($id).Append(',').Append($r.Json.Substring(1))
    }
    [void]$sb.Append("`n]`n")
    [System.IO.File]::WriteAllText((Join-Path $dirReglas "$c.json"), $sb.ToString(), $utf8)
    $grupos = 0; $domsAgrupados = 0
    foreach ($r in $final[$c]) {
        if ($r.PSObject.Properties['Dominios']) { $grupos++; $domsAgrupados += $r.Dominios }
    }
    $conteo[$c] = [pscustomobject]@{ Reglas = $id; Grupos = $grupos; Dominios = $domsAgrupados }
}

# --- Armar el ocultar huecos ----------------------------------------------------------------------
$conExcepcionVistos = NuevoConjuntoTexto
foreach ($lista in $excepciones.Values) { foreach ($s in $lista) { [void]$conExcepcionVistos.Add($s) } }

$css = New-Object 'System.Collections.Generic.List[string]'
$conExcepcion = New-Object 'System.Collections.Generic.List[string]'
foreach ($s in $genericos) {
    if ($excepcionGlobal.Contains($s)) { continue }
    if ($conExcepcionVistos.Contains($s)) { $conExcepcion.Add($s) } else { $css.Add($s) }
}
$enCss = NuevoConjuntoTexto
foreach ($s in $css) { [void]$enCss.Add($s) }

$usados = NuevoConjuntoTexto
foreach ($s in $conExcepcion) { [void]$usados.Add($s) }
$ocultarFinal = NuevoDiccionario
$parejas = 0; $redundantes = 0
foreach ($d in (Ordenado $ocultar.Keys)) {
    $lista = New-Object 'System.Collections.Generic.List[string]'
    foreach ($s in $ocultar[$d]) {
        if ($excepcionGlobal.Contains($s) -or $enCss.Contains($s)) { $redundantes++; continue }
        $lista.Add($s); [void]$usados.Add($s)
    }
    if ($lista.Count) { $ocultarFinal[$d] = $lista; $parejas += $lista.Count }
}
$excepcionesFinal = NuevoDiccionario
foreach ($d in (Ordenado $excepciones.Keys)) {
    $lista = New-Object 'System.Collections.Generic.List[string]'
    foreach ($s in $excepciones[$d]) { if ($usados.Contains($s)) { $lista.Add($s) } }
    if ($lista.Count) { $excepcionesFinal[$d] = $lista }
}

$tabla = Ordenado $usados
$indice = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
for ($i = 0; $i -lt $tabla.Length; $i++) { $indice[$tabla[$i]] = $i }

function Indices($selectores) {
    $nums = New-Object 'System.Collections.Generic.List[int]'
    foreach ($s in $selectores) { $nums.Add($indice[$s]) }
    $nums.Sort()
    return '[' + [string]::Join(',', $nums.ToArray()) + ']'
}
function MapaJson($diccionario) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('{')
    $primero = $true
    foreach ($d in (Ordenado $diccionario.Keys)) {
        [void]$sb.Append($(if ($primero) { "`n" } else { ",`n" }))
        [void]$sb.Append((JsonCadena $d)).Append(':').Append((Indices $diccionario[$d]))
        $primero = $false
    }
    [void]$sb.Append("`n}")
    return $sb.ToString()
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("{`n`"version`":1,`n`"selectores`":[")
for ($i = 0; $i -lt $tabla.Length; $i++) {
    [void]$sb.Append($(if ($i -eq 0) { "`n" } else { ",`n" })).Append((JsonCadena $tabla[$i]))
}
[void]$sb.Append("`n],`n`"conExcepcion`":").Append((Indices $conExcepcion))
[void]$sb.Append(",`n`"ocultar`":").Append((MapaJson $ocultarFinal))
[void]$sb.Append(",`n`"excepciones`":").Append((MapaJson $excepcionesFinal))
[void]$sb.Append(",`n`"sinGenericos`":").Append((JsonLista (Ordenado $sinGenericos)))
[void]$sb.Append(",`n`"sinOcultar`":").Append((JsonLista (Ordenado $sinOcultar)))
[void]$sb.Append("`n}`n")
[System.IO.File]::WriteAllText((Join-Path $dirCosm 'por-sitio.json'), $sb.ToString(), $utf8)

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("/* Mosquitero: oculta los huecos de los anuncios en todas las páginas.`n")
[void]$sb.Append("   Hecho con EasyList, EasyList Spanish y EasyPrivacy (The EasyList authors, https://easylist.to/),`n")
[void]$sb.Append("   que se usan bajo la licencia CC BY-SA 3.0. Lo genera armar.ps1: no se edita a mano.`n")
[void]$sb.Append("   Si la página tiene data-mosquitero-pausa (sitio apagado o con excepción), no se oculta nada. */`n")
[void]$sb.Append(":root:not([data-mosquitero-pausa]) {`n")
$gruposCss = 0
for ($i = 0; $i -lt $css.Count; $i += $Grupo) {
    $fin = [Math]::Min($i + $Grupo, $css.Count)
    $partes = New-Object 'System.Collections.Generic.List[string]'
    for ($j = $i; $j -lt $fin; $j++) { $partes.Add('& ' + $css[$j]) }
    [void]$sb.Append([string]::Join(",`n", $partes.ToArray())).Append(" { display: none !important; }`n")
    $gruposCss++
}
[void]$sb.Append("}`n")
[System.IO.File]::WriteAllText((Join-Path $dirCosm 'genericos.css'), $sb.ToString(), $utf8)

# --- Resumen --------------------------------------------------------------------------------------
$r = New-Object System.Text.StringBuilder
function L([string]$texto = '') { [void]$r.Append($texto).Append("`n") }
L 'Mosquitero: resumen de la conversión de las listas'
L '=================================================='
L ''
foreach ($e in $estadisticas) {
    $convertidas = $e.RedPropias + $e.RedAgrupadas + $e.RedCosmeticas
    L ('{0} ({1}), conjunto «{2}»' -f $e.Nombre, $e.Archivo, $e.Conjunto)
    L ('  Líneas: {0} ({1} comentarios o vacías)' -f $e.Lineas, $e.Comentarios)
    L ('  Bloqueo de red: {0} filtros' -f $e.Red)
    L ('    aprovechados:              {0}' -f $convertidas)
    L ('      como regla propia:       {0}' -f $e.RedPropias)
    L ('      «||dominio^» agrupados:  {0}' -f $e.RedAgrupadas)
    L ('      excepciones del ocultar: {0}' -f $e.RedCosmeticas)
    L ('    repetidos:                 {0}' -f $e.RedRepetidas)
    L ('    omitidos:                  {0}' -f $e.RedOmitidas)
    foreach ($k in (Ordenado $e.Omitidos.Keys)) {
        if ($k.StartsWith('red|')) { L ('      {0,-34} {1}' -f ($k.Substring(4) + ':'), $e.Omitidos[$k]) }
    }
    if ($e.RedSinComodin) { L ('    (a {0} se les quitó un «sitio.*» de $domain=, que Chrome no entiende)' -f $e.RedSinComodin) }
    L ('  Ocultar huecos: {0} filtros' -f $e.Cosm)
    L ('    generales (##):            {0}' -f $e.CosmGenericos)
    L ('    de un sitio (dominio##):   {0}' -f $e.CosmPorSitio)
    L ('    excepciones (#@#):         {0}' -f $e.CosmExcepciones)
    L ('    omitidos:                  {0}' -f $e.CosmOmitidos)
    foreach ($k in (Ordenado $e.Omitidos.Keys)) {
        if ($k.StartsWith('cosm|')) { L ('      {0,-34} {1}' -f ($k.Substring(5) + ':'), $e.Omitidos[$k]) }
    }
    L ''
}
$totalReglas = 0
foreach ($c in $conjuntos) { $totalReglas += $conteo[$c].Reglas }
L 'Reglas de red que van en la extensión'
foreach ($c in $conjuntos) {
    L ('  {0,-13} {1,6} reglas ({2} de ellas agrupan {3} dominios)' -f ($c + ':'), $conteo[$c].Reglas, $conteo[$c].Grupos, $conteo[$c].Dominios)
}
L ('  total:        {0,6} de {1} posibles' -f $totalReglas, $Limite)
L ('  Dominios que sobraban porque otro dominio más general ya los cubre: {0}' -f $cubiertos)
if ($recorte.Count) { L '  Recorte por el límite:'; foreach ($x in $recorte) { L ('    ' + $x) } } else { L '  Recorte por el límite: ninguno, caben todas.' }
L ''
L 'Ocultar huecos'
L ('  genericos.css:  {0} selectores en {1} grupos de hasta {2}' -f $css.Count, $gruposCss, $Grupo)
L ('  por-sitio.json: {0} sitios con selectores propios ({1} parejas sitio-selector)' -f $ocultarFinal.Count, $parejas)
L ('                  {0} selectores generales que se aplican aparte porque algún sitio los exceptúa' -f $conExcepcion.Count)
L ('                  {0} sitios con excepciones, {1} sin los generales ($generichide), {2} sin ocultar nada' -f $excepcionesFinal.Count, $sinGenericos.Count, $sinOcultar.Count)
L ('  Selectores de un sitio que ya estaban entre los generales (no hacía falta repetirlos): {0}' -f $redundantes)
L ('  Excepciones para todos los sitios (#@# sin dominio): {0}' -f $excepcionGlobal.Count)

$textoResumen = $r.ToString()
[System.IO.File]::WriteAllText((Join-Path $Salida 'resumen.txt'), $textoResumen, $utf8)
Write-Host $textoResumen
if ($totalReglas -gt $Limite) { throw "Quedaron $totalReglas reglas, más que el límite de $Limite." }
