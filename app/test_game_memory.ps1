$ErrorActionPreference = 'Stop'
# Proves the Win32 plumbing of lib/GameMemory.cs (open, read, write, scan, alloc, remote call)
# on a throw-away hidden PowerShell process started by this test. Never touches the game.
if (-not ('ERBS.GameMemory' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'lib\GameMemory.cs'), (Join-Path $PSScriptRoot 'lib\BuildEngine.cs') -ReferencedAssemblies System.Core }
$p = Start-Process powershell.exe -ArgumentList '-NoProfile','-Command','Start-Sleep 60' -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Milliseconds 800
    $mem = [ERBS.GameMemory]::Attach($p)
    try {
        if ($mem.ReadInt16($mem.ModuleBase) -ne 0x5A4D) { throw 'FAIL: MZ header not read' }
        $hits = $mem.Scan('4D 5A ?? 00')
        if ($hits.Count -lt 1 -or $hits[0] -ne $mem.ModuleBase) { throw "FAIL: scan did not find the header at the module base" }
        $a = $mem.Alloc(0x100)
        if (-not $mem.WriteInt32($a + 0x80, 0x1234567) -or $mem.ReadInt32($a + 0x80) -ne 0x1234567) { throw 'FAIL: write/read-back' }
        [void]$mem.Write($a, [byte[]](0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3))   # mov eax,42 ; ret
        $code = $mem.Execute($a, 0, 3000)
        if ($code -ne 42) { throw "FAIL: remote call returned $code" }
    } finally { $mem.Dispose() }
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
'GameMemory checks passed (attach, read, scan, write, alloc, remote call).'
