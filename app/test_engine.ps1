$ErrorActionPreference = 'Stop'
# Exercises lib/BuildEngine.cs (inventory discovery, equip calibration/apply, rollback) against mocked
# memory shaped like the live probe of game 2.2.0.0 (2026-09-11). No game process is touched.
if (-not ('ERBSTest.MockMemory' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'lib\GameMemory.cs'), (Join-Path $PSScriptRoot 'lib\BuildEngine.cs'), (Join-Path $PSScriptRoot 'tests\MockMemory.cs') -ReferencedAssemblies System.Core }
function Check($cond, $msg) { if (-not $cond) { throw "FAIL: $msg" } }

$PLAYER = 0x10000000; $HOLDER = 0x20000000; $INV = 0x30000000
$inventory = @(
    @(0x807F0081, 110000), @(0x807F0083, 110000), @(0x807F0084, 110000),
    @(0x807F00D4, 34030025), @(0x807F00B2, 1040010),
    @(0x907F0101, (0x10000000 -bor 1101000)), @(0x907F0102, (0x10000000 -bor 860100)), @(0x907F0103, (0x10000000 -bor 170200)), @(0x907F0104, (0x10000000 -bor 80300)),
    @(0xA0000870, 0x20000870), @(0xA00007E4, 0x200007E4), @(0xA0001B76, 0x20001B76),
    @(0x807F0200, 3180825), @(0x907F0300, (0x10000000 -bor 130000)), @(0xA000047E, 0x2000047E), @(0x807F0201, 3180825)
)
function New-Character([int]$idBase) {
    $m = New-Object ERBSTest.MockMemory
    $m.Set32($INV - 8, $inventory.Count)
    for ($i = 0; $i -lt $inventory.Count; $i++) { $e = $INV + $i * 0x18; $m.Set32($e, $inventory[$i][0]); $m.Set32($e + 4, $inventory[$i][1]); $m.Set32($e + 8, 1) }
    # PlayerGameData -> [+0x5B8] holder object -> [+0x38] inventory array (two hops, as found by discovery)
    $m.Set64($PLAYER + 0x5B8, $HOLDER); $m.Set64($HOLDER + 0x38, $INV)
    # a decoy array with only unarmed entries
    $m.Set64($PLAYER + 0x600, 0x40000000); $m.Set32(0x40000000 - 8, 1); $m.Set32(0x40000000, 0x807F0081); $m.Set32(0x40000004, 110000); $m.Set32(0x40000008, 1)
    $handleBase = $idBase - 22 * 4
    $slots = @{ 0 = @(0x807F00D4, 34030025); 1 = @(0x807F00B2, 1040010); 2 = @(0x807F0081, 110000); 3 = @(0x807F0083, 110000); 4 = @(0x807F0084, 110000); 5 = @(0x807F0081, 110000)
        12 = @(0x907F0101, 1101000); 13 = @(0x907F0102, 860100); 14 = @(0x907F0103, 170200); 15 = @(0x907F0104, 80300)
        17 = @(0xA0000870, 2160); 18 = @(0xA00007E4, 2020); 19 = @(0xA0001B76, 7030); 20 = @(0, 0) }
    for ($i = 0; $i -lt 22; $i++) { $s = if ($slots.ContainsKey($i)) { $slots[$i] } else { @(0xFFFFFFFF, 0xFFFFFFFF) }; $m.Set32($PLAYER + $handleBase + 4 * $i, $s[0]); $m.Set32($PLAYER + $idBase + 4 * $i, $s[1]) }
    $m
}
function New-Req($slot, $cat, $id, $up) { $r = New-Object ERBS.EquipRequest; $r.Slot = $slot; $r.Category = $cat; $r.Id = $id; $r.Upgrade = $up; $r }
function ReqList { $l = New-Object 'System.Collections.Generic.List[ERBS.EquipRequest]'; foreach ($r in $args) { $l.Add($r) }; , $l }

# 1. inventory discovery without hooks
$m = New-Character 0x398; $ev = ''
$base = [ERBS.Inventory]::Discover($m, $PLAYER, [ref]$ev)
Check ($base -eq $INV) "discovers inventory via two hops ($ev)"
$rows = [ERBS.Inventory]::Read($m, $base)
Check ($rows.Count -eq $inventory.Count) 'reads all inventory rows'
Check ([ERBS.Inventory]::CountOf($rows, 3180825) -eq 2) 'counts owned copies by raw id'

# 2. calibration: 2.2.0.0 layout, shifted 2.7.0.0 layout, mismatch refusal
$rep = New-Object 'System.Collections.Generic.List[string]'
$layout = [ERBS.Equipment]::Calibrate($m, $PLAYER, $rows, $rep)
Check ($layout -and $layout.IdBase -eq 0x398 -and $layout.HandleBase -eq 0x340 -and $layout.TalismanFormat -eq 'id') 'calibrates 0x398 layout'
$m2 = New-Character 0x39C
$l2 = [ERBS.Equipment]::Calibrate($m2, $PLAYER, [ERBS.Inventory]::Read($m2, $INV), $rep)
Check ($l2 -and $l2.IdBase -eq 0x39C) 'calibrates shifted 0x39C layout'
$m3 = New-Character 0x398; $m3.Set32($PLAYER + 0x398 + 52, 999999)
Check ($null -eq [ERBS.Equipment]::Calibrate($m3, $PLAYER, [ERBS.Inventory]::Read($m3, $INV), $rep)) 'mismatch blocks calibration'

# 3. equip weapon / armor / talisman, idempotent re-apply, second instance, not-owned, wrong category
$res = [ERBS.Equipment]::Apply($m, $PLAYER, $rows, $layout, (ReqList (New-Req 'R1' 'weapon' 3180800 25) (New-Req 'Head' 'armor' 130000 0) (New-Req 'Talisman4' 'talisman' 1150 0)))
Check (@($res | Where-Object Status -eq 'equipped').Count -eq 3) 'three items equipped'
Check ($m.U($PLAYER + 0x340 + 4) -eq 0x807F0201 -and $m.U($PLAYER + 0x398 + 4) -eq 3180825) 'R1 handle (newest copy) + raw id'
Check ($m.U($PLAYER + 0x340 + 48) -eq 0x907F0300 -and $m.U($PLAYER + 0x398 + 48) -eq 130000) 'Head handle + param id'
Check ($m.U($PLAYER + 0x340 + 80) -eq 0xA000047E -and $m.U($PLAYER + 0x398 + 80) -eq 1150) 'Talisman4 handle + id'
$res = [ERBS.Equipment]::Apply($m, $PLAYER, $rows, $layout, (ReqList (New-Req 'R1' 'weapon' 3180800 25)))
Check ($res[0].Status -eq 'already-equipped') 'idempotent'
$res = [ERBS.Equipment]::Apply($m, $PLAYER, $rows, $layout, (ReqList (New-Req 'L2' 'weapon' 3180800 25) (New-Req 'L3' 'weapon' 3180800 25)))
Check ($res[0].Status -eq 'equipped' -and $m.U($PLAYER + 0x340 + 8) -eq 0x807F0200 -and $res[1].Status -eq 'already-equipped-elsewhere') 'second copy / no third copy'
$before = $m.U($PLAYER + 0x398 + 52)
$res = [ERBS.Equipment]::Apply($m, $PLAYER, $rows, $layout, (ReqList (New-Req 'Chest' 'armor' 424242 0) (New-Req 'Chest' 'weapon' 3180800 25)))
Check ($res[0].Status -eq 'not-owned' -and $res[1].Status -eq 'wrong-category' -and $m.U($PLAYER + 0x398 + 52) -eq $before) 'not-owned / wrong-category untouched'

# 4. rollback when a write fails
$m = New-Character 0x398; $rows = [ERBS.Inventory]::Read($m, $INV); $layout = [ERBS.Equipment]::Calibrate($m, $PLAYER, $rows, $rep)
$r1h = $m.U($PLAYER + 0x340 + 4); $r1v = $m.U($PLAYER + 0x398 + 4); $m.Writes = 0; $m.FailAt = 3
$failed = $false
try { [void][ERBS.Equipment]::Apply($m, $PLAYER, $rows, $layout, (ReqList (New-Req 'R1' 'weapon' 3180800 25) (New-Req 'Head' 'armor' 130000 0))) } catch { $failed = $_.Exception.Message -match 'rolled back' }
Check ($failed -and $m.U($PLAYER + 0x340 + 4) -eq $r1h -and $m.U($PLAYER + 0x398 + 4) -eq $r1v) 'rollback restores R1'

# 5. raw id encoding
Check ([ERBS.Categories]::Raw('weapon', 3180800, 25) -eq 3180825) 'weapon raw'
Check ([ERBS.Categories]::Raw('ash', 60700, 0) -eq [uint32]2147544348) 'ash raw nibble 8'
'Engine checks passed (inventory discovery, calibration, equip, rollback).'

# 6. pluggable equipper (live code passes the game's equip routine)
$m = New-Character 0x398; $rows = [ERBS.Inventory]::Read($m, $INV); $layout = [ERBS.Equipment]::Calibrate($m, $PLAYER, $rows, $rep)
$calls = New-Object System.Collections.ArrayList
$equipper = [Func[int, ERBS.InvRow, bool]] { param($slot, $row) [void]$calls.Add("$slot/$($row.Index)"); $m.Set32($PLAYER + 0x340 + 4 * $slot, $row.Handle); $m.Set32($PLAYER + 0x398 + 4 * $slot, $row.Raw); $true }
$res = [ERBS.Equipment]::Apply($m, $PLAYER, $rows, $layout, (ReqList (New-Req 'R2' 'weapon' 3180800 25)), $equipper)
Check ($res[0].Status -eq 'equipped' -and $calls.Count -eq 1 -and $calls[0] -eq '3/15') "equipper called with slot 3 and newest row ($($calls -join ','))"
$refuse = [Func[int, ERBS.InvRow, bool]] { param($slot, $row) $false }
$failed = $false; try { [void][ERBS.Equipment]::Apply($m, $PLAYER, $rows, $layout, (ReqList (New-Req 'R3' 'weapon' 1040000 10)), $refuse) } catch { $failed = $true }
Check (-not $failed) 'not-owned item never reaches the equipper'
'Equipper checks passed.'
