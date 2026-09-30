$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
$catalog = Get-BuildCatalog $PSScriptRoot
$build = [pscustomobject]@{ name='smoke'; attributes=@{}; items=@([pscustomobject]@{category='weapon';name='__missing__';upgrade=0;quantity=1}) }
$plan = Resolve-BuildPlan $build $catalog
if ($plan.items.Count -ne 1 -or $plan.items[0].itemId -ne $null -or $plan.issues.Count -ne 1) { throw 'unresolved item was not preserved' }
$valid = [pscustomobject]@{ name='smoke'; attributes=@{vig=10}; items=@() }
$validPlan = Resolve-BuildPlan $valid $catalog
if ($validPlan.issues.Count -ne 0 -or $validPlan.attributes.vig -ne 10) { throw 'valid plan smoke check failed' }
$slotBuild = [pscustomobject]@{ name='slot'; attributes=@{}; items=@([pscustomobject]@{category='armor';name='Head: Great Helm';upgrade=0;quantity=1}) }
$slotPlan = Resolve-BuildPlan $slotBuild $catalog
if ($slotPlan.items[0].slot -ne 'Head') { throw 'armor slot metadata was dropped' }
'BuildModel smoke checks passed.'
