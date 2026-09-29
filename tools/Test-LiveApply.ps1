# Small, reversible live test (run elevated when the game runs as administrator):
#  1. backs up the save
#  2. grants one Rowa Raisin through the game's add-item routine and reads it back
#  3. equips an owned, currently unequipped helmet, screenshots, then restores the original helmet
param([string]$Out = "$env:TEMP\erbs-live")
$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot '..\app'
. (Join-Path $app 'backend.ps1')
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
New-Item -ItemType Directory -Force $Out | Out-Null
function Shot([string]$name) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
    $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size); $g.Dispose()
    $bmp.Save((Join-Path $Out "$name.png"), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
$s = Get-BuildBackendStatus -Root $app
"status: $($s.message)"
if (-not $s.ready) { return }
$session = Get-GameSession; $mem = $session.Mem; $player = $session.Player()
"backup: $((Backup-ActiveBuildSave $app).backup)"

$ev = ''; $inv = [ERBS.Inventory]::Discover($mem, $player, [ref]$ev); "inventory: $ev"
$raisin = [ERBS.Categories]::Raw('goods', 810, 0)
$before = [ERBS.Inventory]::CountOf([ERBS.Inventory]::Read($mem, $inv), $raisin)
$session.Grant($raisin, 1)
Start-Sleep -Milliseconds 300
$after = [ERBS.Inventory]::CountOf([ERBS.Inventory]::Read($mem, $inv), $raisin)
"grant Rowa Raisin: before=$before after=$after -> $(if ($after -eq $before + 1) { 'OK' } else { 'FAILED' })"

$rows = [ERBS.Inventory]::Read($mem, $inv)
$rep = New-Object 'System.Collections.Generic.List[string]'
$layout = [ERBS.Equipment]::Calibrate($mem, $player, $rows, $rep)
if (-not $layout) { 'equip layout not verified'; return }
$headIndex = 12
$origId = [uint32]$mem.ReadInt32($player + $layout.IdBase + 4 * $headIndex)
$equippedHandles = [ERBS.Inventory]::EquippedHandles($mem, $player)
$candidate = $rows | Where-Object { ($_.Raw -shr 28) -eq 1 -and (($_.Raw -band 0x0FFFFFFF) % 1000) -lt 100 -and ($_.Raw -band 0x0FFFFFFF) -ne $origId -and -not $equippedHandles.Contains($_.Handle) } | Select-Object -First 1
if (-not $candidate) { 'no spare helmet owned; equip test skipped'; return }
$newId = [int]($candidate.Raw -band 0x0FFFFFFF)
"head: original=$origId test=$newId"
Shot 'before'
$req = New-Object 'System.Collections.Generic.List[ERBS.EquipRequest]'
$r = New-Object ERBS.EquipRequest; $r.Slot = 'Head'; $r.Category = 'armor'; $r.Id = $newId; $req.Add($r)
$res = [ERBS.Equipment]::Apply($mem, $player, $rows, $layout, $req); "equip test helmet: $($res[0].Status)"
Start-Sleep -Seconds 3; Shot 'after-equip'
$req[0].Id = [int]$origId
$res = [ERBS.Equipment]::Apply($mem, $player, [ERBS.Inventory]::Read($mem, $inv), $layout, $req); "restore original helmet: $($res[0].Status)"
Start-Sleep -Seconds 3; Shot 'after-restore'
"screenshots: $Out"
