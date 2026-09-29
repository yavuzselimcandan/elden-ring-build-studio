$ErrorActionPreference = 'Stop'
function Get-BuildBackendStatus {
    param([string]$Root = $PSScriptRoot)
    $game=Get-Process -Name eldenring -ErrorAction SilentlyContinue; $ce=Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.Path -like '*Cheat Engine*' -or $_.ProcessName -like 'cheatengine*'}; $eac=Get-Process -Name EasyAntiCheat_EOS -ErrorAction SilentlyContinue
    $version=if(Test-Path 'D:\Games\ELDEN RING\Game\eldenring.exe'){(Get-Item 'D:\Games\ELDEN RING\Game\eldenring.exe').VersionInfo.FileVersion}else{$null}
    $heartbeat=Join-Path $Root 'runtime/heartbeat.txt';$liveHeartbeat=$false;$probe='absent';$heartbeatGamePid=0;$heartbeatCePid=0;if(Test-Path $heartbeat){$parts=(Get-Content $heartbeat -Raw).Trim() -split '\|';$t=[long]0;[long]::TryParse($parts[0],[ref]$t)|Out-Null;$age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-$t;$liveHeartbeat=($age -ge 0 -and $age -lt 15);if($parts.Count -gt 1){[int]::TryParse($parts[1],[ref]$heartbeatCePid)|Out-Null};if($parts.Count -gt 2){[int]::TryParse($parts[2],[ref]$heartbeatGamePid)|Out-Null};if($parts.Count -gt 3){$probe=$parts[3]}}
    $pidMatch=[bool]($game -and $ce -and $heartbeatGamePid -eq $game.Id -and $heartbeatCePid -eq $ce.Id)
    [pscustomobject]@{ready=[bool]($game -and $ce -and -not $eac -and $liveHeartbeat -and $pidMatch -and $probe -eq 'probe-ok');gamePid=if($game){$game.Id}else{$null};cePid=if($ce){$ce.Id}else{$null};gameVersion=$version;tableVersion='2.7.0.0';gameRunning=[bool]$game;cheatEngineRunning=[bool]$ce;eacRunning=[bool]$eac;probeHeartbeat=$liveHeartbeat;probe=$probe;message=if($eac){'EAC is running; offline mode required'}elseif(-not $game){'Game process absent'}elseif(-not $ce){'Cheat Engine is not running or lacks permission'}elseif(-not $liveHeartbeat -or -not $pidMatch){'Cheat Engine heartbeat is stale or belongs to another process'}elseif($probe -ne 'probe-ok'){'Game process probe failed; character/signatures not checked'}else{'Read-only process probe ready; character/signatures remain pending'}}
}
function Start-BuildBackend {
    param([string]$Root = $PSScriptRoot)
    $dir=Join-Path $Root 'runtime';New-Item -ItemType Directory -Force $dir|Out-Null
    if(-not (Get-Process -Name eldenring -ErrorAction SilentlyContinue)){return [pscustomobject]@{ok=$false;message='Game process absent'}}
    $ce=Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.Path -like '*Cheat Engine*' -or $_.ProcessName -like 'cheatengine*'}
    if(-not $ce){$exe='C:\Program Files\Cheat Engine\cheatengine-x86_64.exe';if(-not(Test-Path $exe)){return [pscustomobject]@{ok=$false;message='Cheat Engine executable not found'}};Set-Content (Join-Path $dir 'boot.flag') ([int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())) -Encoding ASCII;Start-Process -FilePath $exe -Verb RunAs -WindowStyle Hidden|Out-Null}
    [pscustomobject]@{ok=$true;message='Cheat Engine startup requested; poll Get-BuildBackendStatus'}
}
function Backup-ActiveBuildSave {
    param([string]$Root)
    $saveRoot=Join-Path $env:APPDATA 'EldenRing';$active=Get-ChildItem $saveRoot -Directory -ErrorAction Stop|Where-Object Name -match '^\d+$'|ForEach-Object{Get-Item (Join-Path $_.FullName 'ER0000.sl2') -ErrorAction SilentlyContinue}|Select-Object -First 1
    if(-not $active){throw 'Active ER0000.sl2 not found; refusing writes'}
    $dir=Join-Path $Root ('runtime/backups/'+(Get-Date -Format yyyyMMdd-HHmmssfff)+'-'+([guid]::NewGuid().ToString('N')));New-Item -ItemType Directory -Force $dir|Out-Null
    $copy=Join-Path $dir 'ER0000.sl2';Copy-Item $active.FullName $copy -ErrorAction Stop; if((Get-FileHash $active.FullName).Hash -ne (Get-FileHash $copy).Hash){throw 'Save backup hash mismatch'}
    $bak=Join-Path $active.DirectoryName 'ER0000.sl2.bak';if(Test-Path $bak){Copy-Item $bak (Join-Path $dir 'ER0000.sl2.bak') -ErrorAction Stop}
    [pscustomobject]@{source=$active.FullName;backup=$dir;sha256=(Get-FileHash $copy).Hash}
}
function Invoke-BuildPlan {
    param($Plan,[string]$Root = $PSScriptRoot)
    if(-not $Plan){throw 'Plan is required'}; $items=@($Plan.items)
    $allowed=@('vig','mind','end','str','dex','int','fai','arc'); $attrs=@{}
    if($Plan.attributes -is [System.Collections.IDictionary]){$Plan.attributes.Keys|ForEach-Object{$attrs[[string]$_]=$Plan.attributes[$_]}}elseif($Plan.attributes){$Plan.attributes.psobject.Properties|ForEach-Object{$attrs[$_.Name]=$_.Value}}
    foreach($name in $attrs.Keys){if($name -notin $allowed -or [int]$attrs[$name] -lt 1 -or [int]$attrs[$name] -gt 99){throw "Invalid attribute: $name"}}
    foreach($i in $items){if($null -eq $i.itemId){continue};if([string]$i.category -notin @('weapon','armor','talisman','goods','ash')){throw "Unsupported item category: $($i.category)"};if([long]$i.itemId -le 0 -or [int]$i.quantity -lt 1 -or [int]$i.quantity -gt 999){throw 'Invalid typed item request'}}
    $dir=Join-Path $Root 'runtime';New-Item -ItemType Directory -Force $dir|Out-Null
    $status=Get-BuildBackendStatus $Root;if(-not $status.ready){return [pscustomobject]@{ok=$false;applied=$false;message=$status.message}}
    # Weapons are granted even when an Ash of War is requested; attaching the Ash is not supported yet and is reported as pending.
    $pendingItems=@($items|Where-Object {$null -eq $_.itemId}|ForEach-Object{$_.name})+@($items|Where-Object {$null -ne $_.itemId -and $null -ne $_.ashOfWarId}|ForEach-Object{"$($_.name) (Ash of War not attached)"});$requestItems=@($items|Where-Object {$null -ne $_.itemId -and -not $_.unresolved})
    $backup=Backup-ActiveBuildSave $Root
    Remove-Item (Join-Path $dir 'result.txt') -Force -ErrorAction SilentlyContinue
    $requestId=[guid]::NewGuid().ToString('N');$mode=if($requestItems.Count){'build'}else{'stats'};$lines=@('version=1',("mode=$mode"),("requestId=$requestId"))+@($requestItems|ForEach-Object{'item={0}|{1}|{2}|{3}' -f $_.category,$_.itemId,$_.upgrade,$_.quantity})+@($attrs.Keys|ForEach-Object{'stat={0}|{1}' -f $_,$attrs[$_]})
    # Slot placement for granted gear. Memory (spell) slots are not calibrated yet and stay planned only.
    if($mode -eq 'build' -and $Plan.loadout){foreach($p in $Plan.loadout.psobject.Properties){if($p.Name -notlike 'Spell*' -and $p.Value.category -in @('weapon','armor','talisman')){$lines+=('equip={0}|{1}|{2}|{3}' -f $p.Name,$p.Value.category,$p.Value.itemId,[int]$p.Value.upgrade)}}}
    Set-Content (Join-Path $dir 'request.txt') $lines -Encoding ASCII;Set-Content (Join-Path $dir 'boot.flag') ([int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())) -Encoding ASCII
    [pscustomobject]@{ok=$false;applied=$false;pending=$true;requestId=$requestId;message='Build sent to the game; waiting for verified readback';pendingItems=$pendingItems;backup=$backup}
}
