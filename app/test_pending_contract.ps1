$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'BuildStudio.ps1')
$tokens = $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0].Message }
function Get-FunctionBody([string]$name) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name was not found" }
    $fn.Extent.Text
}
# Apply only after a live, verified backend; never mark a request applied without its matching receipt.
$apply = Get-FunctionBody 'Invoke-Apply'
foreach ($needle in @('pendingSent', 'pendingRequestId', 'Start-BuildBackend', 'Invoke-BuildPlan', 'eacRunning', 'Invalid attribute')) {
    if ($apply -notmatch [regex]::Escape($needle)) { throw "Invoke-Apply missing contract behavior: $needle" }
}
$read = Get-FunctionBody 'Read-ApplyResult'
foreach ($needle in @('result.txt', 'requestId=', 'ERROR:', 'PARTIAL:', 'OK:\s*APPLIED', 'Clear-Pending', '-ne $State.pendingRequestId')) {
    if ($read -notmatch [regex]::Escape($needle)) { throw "Read-ApplyResult missing contract behavior: $needle" }
}
'Pending contract smoke check passed.'
