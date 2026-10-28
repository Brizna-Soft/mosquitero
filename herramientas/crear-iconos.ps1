# Dibuja el ícono de Mosquitero: un escudo blanco con la malla de un mosquitero, sobre un cuadrado
# redondeado verde azulado (#0F8C7E). Genera extension\comun\iconos\icono-16.png, -32, -48 y -128.
# En 16 px la malla se reduce a una cruz, para que el escudo se siga leyendo.
#
# Uso: powershell -ExecutionPolicy Bypass -File herramientas\crear-iconos.ps1 [-Muestra C:\carpeta]
# Con -Muestra también deja una lámina con los cuatro tamaños ampliados, para revisarlos.
param(
    [string]$Raiz = (Split-Path $PSScriptRoot -Parent),
    [string]$Muestra = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$verde = [System.Drawing.Color]::FromArgb(255, 0x0F, 0x8C, 0x7E)
$blanco = [System.Drawing.Color]::White

function Redondeado([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return , $p
}

function Punto([double]$x, [double]$y, [double]$k) {
    return New-Object System.Drawing.PointF([single]($x * $k), [single]($y * $k))
}

# Escudo en una cuadrícula de 100 x 100
function Escudo([double]$k) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddLine((Punto 21 23 $k), (Punto 50 13 $k))
    $p.AddLine((Punto 50 13 $k), (Punto 79 23 $k))
    $p.AddLine((Punto 79 23 $k), (Punto 79 47 $k))
    $p.AddBezier((Punto 79 47 $k), (Punto 79 68 $k), (Punto 66 80 $k), (Punto 50 89 $k))
    $p.AddBezier((Punto 50 89 $k), (Punto 34 80 $k), (Punto 21 68 $k), (Punto 21 47 $k))
    $p.CloseFigure()
    return , $p
}

function Dibujar([int]$lado) {
    $bmp = New-Object System.Drawing.Bitmap($lado, $lado, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $k = $lado / 100.0

    $margen = $(if ($lado -le 16) { 0 } else { 3 * $k })
    $caja = Redondeado $margen $margen ($lado - 2 * $margen) ($lado - 2 * $margen) (21 * $k)
    $g.FillPath((New-Object System.Drawing.SolidBrush($verde)), $caja)

    $escudo = Escudo $k
    $g.FillPath((New-Object System.Drawing.SolidBrush($blanco)), $escudo)

    # La malla: líneas del color del fondo, solo dentro del escudo
    $g.SetClip($escudo)
    if ($lado -le 16) { $xs = @(50.0); $ys = @(47.0); $grosor = 1 }
    elseif ($lado -le 32) { $xs = @(40.0, 60.0); $ys = @(38.0, 58.0); $grosor = 2 }
    elseif ($lado -le 48) { $xs = @(39.0, 61.0); $ys = @(37.0, 57.0, 75.0); $grosor = 2 }
    else { $xs = @(35.0, 50.0, 65.0); $ys = @(32.0, 46.0, 60.0, 74.0); $grosor = [int][Math]::Round(3.2 * $k) }
    $lapiz = New-Object System.Drawing.Pen($verde, [single]$grosor)
    # Las líneas caen en píxeles enteros para que se vean nítidas
    $xs = @($xs | ForEach-Object { [Math]::Round($_ * $k) / $k })
    $ys = @($ys | ForEach-Object { [Math]::Round($_ * $k) / $k })
    if ($lado -le 16) {
        # En 16 px, líneas de un píxel exacto para que no se vean borrosas
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::None
        $g.FillRectangle((New-Object System.Drawing.SolidBrush($verde)), 7, 2, 1, 13)
        $g.FillRectangle((New-Object System.Drawing.SolidBrush($verde)), 3, 7, 10, 1)
    }
    else {
        foreach ($x in $xs) { $g.DrawLine($lapiz, [single]($x * $k), [single](5 * $k), [single]($x * $k), [single](95 * $k)) }
        foreach ($y in $ys) { $g.DrawLine($lapiz, [single](5 * $k), [single]($y * $k), [single](95 * $k), [single]($y * $k)) }
    }
    $g.ResetClip()
    $g.Dispose()
    return , $bmp
}

$carpeta = Join-Path (Join-Path (Join-Path $Raiz 'extension') 'comun') 'iconos'
New-Item -ItemType Directory -Force $carpeta | Out-Null
$hechos = @{}
foreach ($t in 16, 32, 48, 128) {
    $bmp = Dibujar $t
    $bmp.Save((Join-Path $carpeta "icono-$t.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $hechos[$t] = $bmp
}

if ($Muestra) {
    # Lámina de revisión: cada tamaño a su tamaño real y ampliado (sin suavizar) sobre fondo claro y oscuro
    $lamina = New-Object System.Drawing.Bitmap(700, 600)
    $g = [System.Drawing.Graphics]::FromImage($lamina)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 245, 245, 245))
    $g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 32, 33, 36))), 0, 300, 700, 300)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    foreach ($fila in 0, 1) {
        $x = 20
        foreach ($t in 16, 32, 48, 128) {
            $y = 20 + 300 * $fila
            $g.DrawImage($hechos[$t], $x, $y, $t, $t)
            if ($t -lt 128) { $g.DrawImage($hechos[$t], $x, $y + 140, 128, 128) }
            $x += 165
        }
    }
    $g.Dispose()
    New-Item -ItemType Directory -Force $Muestra | Out-Null
    $lamina.Save((Join-Path $Muestra 'iconos-muestra.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
Write-Host 'Íconos listos.'
