# One-time setup for this checkout of Build Studio. Safe to re-run.
#  - points the Desktop shortcut at app/Launch.vbs (custom icon)
#  - copies presets from the older install locations into app/configs (never overwrites)
# No Cheat Engine and no administrator rights are needed: the app talks to the game directly.
$ErrorActionPreference = 'Stop'
$app = (Resolve-Path (Join-Path $PSScriptRoot '..\app')).Path
New-Item -ItemType Directory -Force -Path (Join-Path $app "configs"), (Join-Path $app "runtime") | Out-Null

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

