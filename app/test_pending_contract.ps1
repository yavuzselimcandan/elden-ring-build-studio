$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'BuildStudio.ps1')
$tokens = $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0].Message }
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Apply-Pending' }, $true)
if (-not $fn) { throw 'Apply-Pending was not found' }
$body = $fn.Extent.Text
foreach($needle in @('pendingSent','pendingRequestId','Start-BuildBackend','result.txt','ERROR:','PARTIAL:','OK:\s*APPLIED','pendingPlan=$null')) {
    if ($body -notmatch [regex]::Escape($needle)) { throw "Apply-Pending missing contract behavior: $needle" }
}
'Pending contract smoke check passed.'
