$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
$preset = 'C:\Users\YAVUZ-PC\Desktop\Elden Ring Build Configurator\configs\Sovereign Spellblade.json'
$catalogRoot = 'C:\Users\YAVUZ-PC\Desktop\Elden Ring Build Configurator'
$build = Get-Content -Raw -LiteralPath $preset -Encoding UTF8 | ConvertFrom-Json
$catalog = Get-BuildCatalog $catalogRoot
$plan = Resolve-BuildPlan $build $catalog
$names = @($plan.items | ForEach-Object name)
foreach($name in 'Magic Claymore','Spellblade''s Pointed Hat','Shard of Alexander','Gavel of Haima','Cannon of Haima') { if($name -notin $names){throw "missing typed item: $name"} }
$weapon = @($plan.items | Where-Object name -eq 'Magic Claymore'); if($weapon.Count -ne 1 -or $weapon[0].upgrade -ne 25){throw 'weapon upgrade was not serialized'}
$ash = @($plan.items | Where-Object name -eq 'Magic Claymore'); if($null -eq $ash[0].ashOfWarId){throw 'Ash attachment was not resolved'}
foreach($category in 'weapon','armor','talisman','goods'){if(@($plan.items|Where-Object category -eq $category).Count -eq 0){throw "missing category: $category"}}
$outgoing = [pscustomobject]@{schemaVersion=$plan.schemaVersion;name=$plan.name;attributes=$build.attributes;items=@($plan.items);issues=@($plan.issues)}
$json = $outgoing | ConvertTo-Json -Depth 12
if(@($outgoing.items).Count -lt 10 -or $json -notmatch '"attributes"' -or $json -notmatch '"Magic Claymore"'){throw 'full outgoing plan was not serialized'}
$rune=@($plan.items | Where-Object name -eq 'Godrick''s Great Rune'); if($rune.Count -ne 1 -or $rune[0].itemId -ne 191 -or @($plan.notes | Where-Object {$_ -match 'Godrick''s Great Rune'}).Count -eq 0){throw 'Godrick rune should resolve to primary ID 191 with a note'}
'Full plan integration check passed.'
