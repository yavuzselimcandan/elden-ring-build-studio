# Applies a preset to the running offline game from the command line (same code path as the Apply button).
param([Parameter(Mandatory)][string]$Preset)
$ErrorActionPreference = 'Stop'
trap { "ERROR: $($_.Exception.Message) at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"; $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException; "  inner: $($e.Message)" }; break }
$app = Join-Path $PSScriptRoot '..\app'
. (Join-Path $app 'BuildModel.ps1')
. (Join-Path $app 'backend.ps1')
$catalog = Get-BuildCatalog $app
$build = Get-Content -LiteralPath $Preset -Raw -Encoding UTF8 | ConvertFrom-Json
$plan = Resolve-BuildPlan $build $catalog
"plan: $(@($plan.items).Count) items, $(@($plan.issues).Count) issues, $(@($plan.loadout.psobject.Properties).Count) slots"
$r = Invoke-BuildPlan -Plan $plan -Root $app
"applied=$($r.applied) ok=$($r.ok): $($r.message)"
$r.lines
