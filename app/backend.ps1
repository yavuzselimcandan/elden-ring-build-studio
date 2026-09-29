$ErrorActionPreference = 'Stop'
# Direct game backend (no Cheat Engine): lib/GameMemory.cs opens the offline game process,
# lib/BuildEngine.cs applies stats, grants and equipment with read-back.
if (-not ('ERBS.GameSession' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'lib\GameMemory.cs'), (Join-Path $PSScriptRoot 'lib\BuildEngine.cs') -ReferencedAssemblies System.Core
}

$script:GameSession = $null
$script:GameSessionError = $null

function Get-GameSession {
    $game = Get-Process -Name eldenring -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) { if ($script:GameSession) { $script:GameSession.Dispose(); $script:GameSession = $null }; return $null }
    if ($script:GameSession -and $script:GameSession.Mem.Pid -eq $game.Id) { return $script:GameSession }
    if ($script:GameSession) { $script:GameSession.Dispose(); $script:GameSession = $null }
    $mem = [ERBS.GameMemory]::Attach()
    try { $script:GameSession = New-Object ERBS.GameSession $mem } catch { $mem.Dispose(); throw }
    $script:GameSession
}

function Get-BuildBackendStatus {
    param([string]$Root = $PSScriptRoot)
    $game = Get-Process -Name eldenring -ErrorAction SilentlyContinue | Select-Object -First 1
    $eac = [bool](Get-Process -Name EasyAntiCheat_EOS, EasyAntiCheat -ErrorAction SilentlyContinue)
    $s = [ordered]@{ ready = $false; gameRunning = [bool]$game; eacRunning = $eac; characterLoaded = $false; gameVersion = $null; level = $null; message = '' }
    if (-not $game) { $s.message = 'Game not running'; return [pscustomobject]$s }
    if ($eac) { $s.message = 'Easy Anti-Cheat is running; start the game offline (EAC disabled)'; return [pscustomobject]$s }
    try {
        $session = Get-GameSession
        $s.gameVersion = $session.Mem.FileVersion
        $player = $session.Player()
        if ($player -eq 0) { $s.message = 'Game attached; load your character'; return [pscustomobject]$s }
        $stats = $session.ReadStats($player)
        if (@($stats[0..7] | Where-Object { $_ -lt 1 -or $_ -gt 99 }).Count) { $s.message = 'Game attached; waiting for the character to finish loading'; return [pscustomobject]$s }
        $s.characterLoaded = $true; $s.level = $stats[8]; $s.ready = $true
        $s.message = "Connected · level $($stats[8])"
        $script:GameSessionError = $null
    } catch {
        $script:GameSessionError = $_.Exception.Message
        $s.message = "Cannot attach: $($_.Exception.Message)"
    }
    [pscustomobject]$s
}

function Backup-ActiveBuildSave {
    param([string]$Root)
    $saveRoot = Join-Path $env:APPDATA 'EldenRing'
    $active = Get-ChildItem $saveRoot -Directory -ErrorAction Stop | Where-Object Name -match '^\d+$' | ForEach-Object { Get-Item (Join-Path $_.FullName 'ER0000.sl2') -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $active) { throw 'Active ER0000.sl2 not found; refusing writes' }
    $dir = Join-Path $Root ('runtime/backups/' + (Get-Date -Format yyyyMMdd-HHmmssfff))
    New-Item -ItemType Directory -Force $dir | Out-Null
    $copy = Join-Path $dir 'ER0000.sl2'; Copy-Item $active.FullName $copy
    if ((Get-FileHash $active.FullName).Hash -ne (Get-FileHash $copy).Hash) { throw 'Save backup hash mismatch' }
    $bak = Join-Path $active.DirectoryName 'ER0000.sl2.bak'; if (Test-Path $bak) { Copy-Item $bak (Join-Path $dir 'ER0000.sl2.bak') }
    [pscustomobject]@{ source = $active.FullName; backup = $dir }
}

# Applies a resolved plan. Returns a receipt; 'applied' is true only when every requested
# change was read back from the game.
function Invoke-BuildPlan {
    param($Plan, [string]$Root = $PSScriptRoot)
    if (-not $Plan) { throw 'Plan is required' }
    $status = Get-BuildBackendStatus $Root
    if (-not $status.ready) { return [pscustomobject]@{ ok = $false; applied = $false; message = $status.message; lines = @() } }
    $session = Get-GameSession
    $lines = New-Object System.Collections.Generic.List[string]
    $problems = New-Object System.Collections.Generic.List[string]
    $backup = Backup-ActiveBuildSave $Root
    $lines.Add("backup=$($backup.backup)")

    $player = $session.Player()
    $lines.Add(('game={0} pid={1} player=0x{2:X}' -f $session.Mem.FileVersion, $session.Mem.Pid, $player))

    # Stats
    $stats = New-Object 'System.Collections.Generic.Dictionary[string,int]'
    if ($Plan.attributes) {
        $pairs = if ($Plan.attributes -is [System.Collections.IDictionary]) { $Plan.attributes.GetEnumerator() | ForEach-Object { @($_.Key, $_.Value) } } else { $Plan.attributes.psobject.Properties | ForEach-Object { @($_.Name, $_.Value) } }
        for ($i = 0; $i -lt $pairs.Count; $i += 2) { if ($null -ne $pairs[$i + 1] -and "$($pairs[$i + 1])" -ne '') { $stats[[string]$pairs[$i]] = [int]$pairs[$i + 1] } }
    }
    if ($stats.Count) { $session.WriteStats($player, $stats); $lines.Add("stats=verified ($($stats.Count))") }

    # Inventory + grants (only the missing quantity is granted, so re-applying never duplicates)
    $evidence = ''
    $invBase = [ERBS.Inventory]::Discover($session.Mem, $player, [ref]$evidence)
    $lines.Add("inventory: $evidence")
    $items = @($Plan.items | Where-Object { $null -ne $_.itemId -and -not $_.unresolved })
    $granted = 0
    if ($items.Count) {
        if ($invBase -eq 0) { throw "Inventory not found ($evidence); nothing was granted" }
        $want = @{}
        foreach ($it in $items) {
            $raw = [ERBS.Categories]::Raw([string]$it.category, [int]$it.itemId, [int]$it.upgrade)
            if ($want.ContainsKey($raw)) { $want[$raw].qty += [int]$it.quantity } else { $want[$raw] = @{ qty = [int]$it.quantity; name = $it.name } }
        }
        foreach ($raw in $want.Keys) {
            $rows = [ERBS.Inventory]::Read($session.Mem, $invBase)
            $have = [ERBS.Inventory]::CountOf($rows, $raw)
            $deficit = $want[$raw].qty - $have
            if ($deficit -le 0) { $lines.Add("have $($want[$raw].name) x$have"); continue }
            $session.Grant($raw, $deficit)
            $after = 0
            for ($t = 0; $t -lt 10; $t++) { $after = [ERBS.Inventory]::CountOf([ERBS.Inventory]::Read($session.Mem, $invBase), $raw); if ($after -ge $want[$raw].qty) { break }; Start-Sleep -Milliseconds 100 }
            if ($after -ge $want[$raw].qty) { $granted++; $lines.Add("granted $($want[$raw].name) x$deficit (now $after)") }
            else { $problems.Add("$($want[$raw].name) not confirmed"); $lines.Add("NOT CONFIRMED $($want[$raw].name) (have $after)") }
        }
    }
    foreach ($it in @($Plan.items | Where-Object { $null -ne $_.ashOfWarId })) { $problems.Add("$($it.name): Ash of War not attached") }

    # Equipment
    $equipped = 0; $equipTotal = 0
    $requests = New-Object 'System.Collections.Generic.List[ERBS.EquipRequest]'
    if ($Plan.loadout) {
        foreach ($p in $Plan.loadout.psobject.Properties) {
            if ($p.Name -like 'Spell*' -or $p.Value.category -notin @('weapon', 'armor', 'talisman')) { continue }
            $r = New-Object ERBS.EquipRequest; $r.Slot = $p.Name; $r.Category = $p.Value.category; $r.Id = [int]$p.Value.itemId; $r.Upgrade = [int]$p.Value.upgrade
            $requests.Add($r)
        }
    }
    if ($requests.Count -and $invBase -ne 0) {
        $equipTotal = $requests.Count
        $rows = [ERBS.Inventory]::Read($session.Mem, $invBase)
        $report = New-Object 'System.Collections.Generic.List[string]'
        $layout = [ERBS.Equipment]::Calibrate($session.Mem, $player, $rows, $report)
        [IO.File]::WriteAllLines((Join-Path $Root 'runtime\equip-calibration.txt'), $report)
        if (-not $layout) { $problems.Add('equipment layout could not be verified; nothing equipped'); $lines.Add('equip=skipped (layout unverified, see runtime/equip-calibration.txt)') }
        else {
            $lines.Add(('equip layout idBase=0x{0:X} evidence={1}' -f $layout.IdBase, $layout.Evidence))
            foreach ($res in [ERBS.Equipment]::Apply($session.Mem, $player, $rows, $layout, $requests)) {
                $lines.Add("equip $($res.Slot) $($res.Id) $($res.Status)")
                if ($res.Status -in 'equipped', 'already-equipped') { $equipped++ } else { $problems.Add("$($res.Slot): $($res.Status)") }
            }
        }
    }
    $spells = @($Plan.loadout.psobject.Properties | Where-Object Name -like 'Spell*').Count
    if ($spells) { $lines.Add("spells: $spells granted, memorise them at a Site of Grace (slot writing not supported yet)") }

    $ledger = Join-Path $Root ('runtime\ledger-' + (Get-Date -Format yyyyMMdd-HHmmss) + '.txt')
    [IO.File]::WriteAllLines($ledger, $lines)
    $summary = @()
    if ($stats.Count) { $summary += 'stats set' }
    $summary += "$granted item(s) granted"
    if ($equipTotal) { $summary += "$equipped/$equipTotal slots equipped" }
    [pscustomobject]@{
        ok = $true; applied = ($problems.Count -eq 0)
        message = ($summary -join ' · ') + $(if ($problems.Count) { ' · ' + ($problems -join '; ') } else { '' })
        lines = $lines.ToArray(); ledger = $ledger; problems = $problems.ToArray()
    }
}
