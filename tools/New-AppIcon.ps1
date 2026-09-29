# Builds app/assets/BuildStudio.ico (16-256 px, PNG-compressed frames) from a square source PNG.
param([string]$Source = (Join-Path $PSScriptRoot '..\app\assets\icon-source.png'), [string]$Out = (Join-Path $PSScriptRoot '..\app\assets\BuildStudio.ico'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$src = [Drawing.Image]::FromFile((Resolve-Path $Source))
$sizes = 256, 128, 64, 48, 32, 24, 16
$frames = foreach ($s in $sizes) {
    $bmp = New-Object Drawing.Bitmap $s, $s
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    # Clip to the rounded tile so the corners are transparent instead of black.
    $r = [single]($s * 0.2); $d = [single]($s - 1); $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc(0, 0, 2 * $r, 2 * $r, 180, 90); $p.AddArc($d - 2 * $r, 0, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($d - 2 * $r, $d - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc(0, $d - 2 * $r, 2 * $r, 2 * $r, 90, 90); $p.CloseFigure()
    $g.SetClip($p)
    $g.DrawImage($src, 0, 0, $s, $s); $g.Dispose()
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    , $ms.ToArray()
}
$src.Dispose()
$fs = [IO.File]::Create($Out); $w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $frames[$i].Length
    $w.Write([byte]($s % 256)); $w.Write([byte]($s % 256)); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$len); $w.Write([uint32]$offset)
    $offset += $len
}
foreach ($f in $frames) { $w.Write($f) }
$w.Close()
"Icon written: $Out"
