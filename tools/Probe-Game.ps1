# Read-only diagnosis of the running offline game: attach, character, stats, inventory discovery,
# equipment layout calibration and the add-item signatures. Writes nothing to the game.
$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot '..\app'
. (Join-Path $app 'backend.ps1')
$s = Get-BuildBackendStatus -Root $app
"status: $($s.message) (game $($s.gameVersion), EAC $($s.eacRunning))"
if (-not $s.ready) { return }
$session = Get-GameSession
$player = $session.Player()
'player=0x{0:X}' -f $player
$st = $session.ReadStats($player)
'stats: ' + (0..7 | ForEach-Object { '{0}={1}' -f [ERBS.GameSession]::StatNames[$_], $st[$_] }) -join ' ' + " level=$($st[8])"
$ev = ''; $inv = [ERBS.Inventory]::Discover($session.Mem, $player, [ref]$ev)
"inventory: $ev"
if ($inv) {
    $rows = [ERBS.Inventory]::Read($session.Mem, $inv)
    "inventory rows: $($rows.Count)"
    $rep = New-Object 'System.Collections.Generic.List[string]'
    $layout = [ERBS.Equipment]::Calibrate($session.Mem, $player, $rows, $rep)
    $rep | Select-Object -Last 40
    if ($layout) { 'equip layout: idBase=0x{0:X} handleBase=0x{1:X} talisman={2} evidence={3}' -f $layout.IdBase, $layout.HandleBase, $layout.TalismanFormat, $layout.Evidence } else { 'equip layout: NOT verified' }
}
foreach ($name in 'AddItem', 'item manager') {
    try {
        if ($name -eq 'AddItem') { $h = $session.Mem.Scan('40 55 56 57 41 54 41 55 41 56 41 57 48 8D AC 24 ?? ?? ?? ?? 48 81 EC ?? ?? ?? ?? 48 C7 45 C8 ?? ?? ?? ?? 48 89 9C 24 ?? ?? ?? ?? 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 ?? ?? ?? ?? 44 89 4C 24 ?? 4D 8B F8') }
        else { $h = $session.Mem.Scan('44 8B 61 1C 41 8B FC C1 EF 07 40 80 E7 01 41 C1 EC 08 41 80 E4 01 48 8B 0D') }
        "$name signature matches: $($h.Count)"
    } catch { "$name scan failed: $($_.Exception.Message)" }
}
