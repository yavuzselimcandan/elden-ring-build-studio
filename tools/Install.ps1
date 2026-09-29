# One-time setup for this checkout of Build Studio. Safe to re-run.
#  - points the Desktop shortcut at app/BuildStudio.ps1 in this repository
#  - records the app location for the Cheat Engine autorun (%LOCALAPPDATA%\EldenRingBuildStudio\root.txt)
#  - copies presets from the older install locations into app/configs (never overwrites)
#  - installs the Cheat Engine autorun hook (asks for administrator rights once; backs up the old file)
param([switch]$SkipAutorun, [string]$CheatEngineDir = 'C:\Program Files\Cheat Engine')
$ErrorActionPreference = 'Stop'
$app = (Resolve-Path (Join-Path $PSScriptRoot '..\app')).Path

$rootDir = Join-Path $env:LOCALAPPDATA 'EldenRingBuildStudio'
New-Item -ItemType Directory -Force -Path $rootDir, (Join-Path $app 'configs'), (Join-Path $app 'runtime') | Out-Null
[IO.File]::WriteAllText((Join-Path $rootDir 'root.txt'), ($app -replace '\\', '/'), (New-Object Text.UTF8Encoding $false))
"App location recorded: $app"

$legacy = @(
    (Join-Path $env:USERPROFILE 'Documents\Codex\2026-09-06\referenced-chatgpt-conversation-this-is-an\build_configurator\configs'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Elden Ring Build Configurator\configs')
)
foreach ($src in $legacy | Where-Object { Test-Path $_ }) {
    foreach ($f in Get-ChildItem -LiteralPath $src -Filter *.json -File) {
        $dest = Join-Path $app "configs\$($f.Name)"
        if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $f.FullName -Destination $dest; "Imported preset $($f.Name)" }
    }
}

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$icon = @((Join-Path $app 'assets\BuildStudio.ico'), 'D:\Games\ELDEN RING\Game\eldenring.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
# One shortcut, launched through Launch.vbs so no console window flashes. The older name is replaced.
$path = Join-Path $desktop 'Elden Ring Build Studio.lnk'
$lnk = $shell.CreateShortcut($path)
$lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$lnk.Arguments = "`"$app\Launch.vbs`""
$lnk.WorkingDirectory = $app
$lnk.Description = 'Elden Ring Build Studio - forge, equip and apply builds'
if ($icon) { $lnk.IconLocation = "$icon,0" }
$lnk.Save()
"Shortcut ready: $path"
$old = Join-Path $desktop 'Elden Ring Build Configurator.lnk'
if (Test-Path $old) { Remove-Item -LiteralPath $old; "Replaced old shortcut: $old" }

if (-not $SkipAutorun) {
    $target = Join-Path $CheatEngineDir 'autorun\zz_EldenRingBuildStudio.lua'
    $source = Join-Path $app 'BuildStudioAutorun.lua'
    if (-not (Test-Path (Split-Path $target))) { Write-Warning "Cheat Engine autorun folder not found: $(Split-Path $target)"; return }
    if ((Test-Path $target) -and ((Get-FileHash $target).Hash -eq (Get-FileHash $source).Hash)) { 'Cheat Engine autorun already up to date.'; return }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $copy = "if (Test-Path '$target') { Copy-Item '$target' '$target.bak' -Force }; Copy-Item '$source' '$target' -Force"
    if ($isAdmin) { Invoke-Expression $copy }
    else { Start-Process $ps -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList @('-NoProfile', '-Command', $copy) }
    if ((Get-FileHash $target).Hash -eq (Get-FileHash $source).Hash) { "Cheat Engine autorun installed: $target" } else { Write-Warning 'Cheat Engine autorun was not updated (administrator approval declined?).' }
}
