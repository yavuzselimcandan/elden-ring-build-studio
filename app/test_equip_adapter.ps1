$ErrorActionPreference = 'Stop'
# Executes the Cheat Engine equip adapter under CE's own Lua 5.3 runtime with mocked memory.
$lua = 'C:\Program Files\Cheat Engine\lua53-64.dll'
if (-not (Test-Path $lua)) { 'SKIPPED: Cheat Engine lua53-64.dll not found'; return }
if (-not ('ERBS.LuaHost' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'lib\LuaHost.cs') }
$host_ = New-Object ERBS.LuaHost $lua
try {
    $root = $PSScriptRoot -replace '\\', '/'
    $spec = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'tests\equip_adapter_spec.lua')
    # The spec receives the app root as its vararg.
    $host_.Run("local f = assert(load([==[$spec]==], '@equip_adapter_spec.lua')); return f('$root')", 'runner')
} finally { $host_.Dispose() }
