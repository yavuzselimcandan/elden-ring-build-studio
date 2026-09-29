$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
$script:catalog = Get-BuildCatalog $PSScriptRoot

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestItem {
    param([string]$Category, [string]$Name, $Upgrade = 0, $Quantity = 1, [string]$AshOfWar = '', [string]$Slot = '', [string]$Affinity = '')
    [pscustomobject]@{ category = $Category; name = $Name; upgrade = $Upgrade; quantity = $Quantity; ashOfWar = $AshOfWar; slot = $Slot; affinity = $Affinity }
}

function Resolve-TestRows {
    param([object[]]$Rows)
    $build = [pscustomobject]@{ name = 'resolver regression'; attributes = @{}; items = @($Rows) }
    Resolve-BuildPlan $build $script:catalog
}

$curlyApostrophe = 'Godrick' + [char]0x2019 + 's Great Rune'
Assert-That ([ERBS.Text]::Normalize('MiXeD Name') -eq 'mixed name') 'normalization did not ignore case'
Assert-That ([ERBS.Text]::Normalize($curlyApostrophe) -eq [ERBS.Text]::Normalize("Godrick's Great Rune")) 'normalization did not handle a curly apostrophe'
Assert-That ([ERBS.Text]::Normalize("Great-Jar's Arsenal") -eq [ERBS.Text]::Normalize("Great Jar's Arsenal")) 'normalization did not treat hyphen and space alike'
Assert-That ([ERBS.Text]::Normalize("Ash of War: Lion's Claw") -eq [ERBS.Text]::Normalize("Lion's Claw")) 'normalization did not strip the Ash of War prefix'

$aliasPlan = Resolve-TestRows @(
    (New-TestItem 'weapon' 'Misericorde'),
    (New-TestItem 'goods' "Ancient Dragon's Lightning Strike"),
    (New-TestItem 'weapon' 'Bone Bolts')
)
Assert-That ($aliasPlan.issues.Count -eq 0) 'normalization aliases produced an issue'
Assert-That ($aliasPlan.items[0].name -eq ('Mis' + [char]0x00E9 + 'ricorde')) 'Misericorde did not resolve to Miséricorde'
Assert-That ($aliasPlan.items[1].name -eq "Ancient Dragons' Lightning Strike") 'Ancient Dragon''s Lightning Strike did not resolve to the catalog spelling'
Assert-That ($aliasPlan.items[2].name -eq 'Bone Bolt' -and $aliasPlan.items[2].match -eq 'plural') 'Bone Bolts did not resolve through the plural match'

$parsedRows = @(ConvertTo-BuildItems ([pscustomobject]@{ items = @(
    (New-TestItem 'weapon' "Claymore +25 (Ash of War: Lion's Claw)" $null $null),
    (New-TestItem 'weapon' 'Claymore (Heavy)' $null $null),
    (New-TestItem 'armor' 'Head: Great Helm' $null $null),
    (New-TestItem 'weapon' 'Bone Arrow x3' $null $null),
    (New-TestItem 'goods' 'Flask of Cerulean Tears +5' $null $null)
) }))
Assert-That ($parsedRows.Count -eq 5) 'item parser dropped a supported input row'
Assert-That ($parsedRows[0].name -eq 'Claymore' -and $parsedRows[0].upgrade -eq 25 -and $parsedRows[0].ashOfWar -eq "Lion's Claw") 'Claymore upgrade/Ash of War parsing failed'
Assert-That ($parsedRows[1].name -eq 'Claymore' -and $parsedRows[1].affinity -eq 'Heavy') 'Heavy affinity parsing failed'
Assert-That ($parsedRows[2].name -eq 'Great Helm' -and $parsedRows[2].slot -eq 'Head') 'Head slot prefix parsing failed'
Assert-That ($parsedRows[3].name -eq 'Bone Arrow' -and $parsedRows[3].quantity -eq 3) 'x3 quantity parsing failed'
Assert-That ($parsedRows[4].name -eq 'Flask of Cerulean Tears +5' -and $parsedRows[4].upgrade -eq 0) 'flask +N name was altered'
$parsedPlan = Resolve-TestRows $parsedRows
Assert-That ($parsedPlan.issues.Count -eq 0) 'parsed catalog items did not resolve cleanly'
Assert-That ($parsedPlan.items[0].ashOfWarId -ne $null) 'Claymore Ash of War did not resolve to a catalog ID'
Assert-That ($parsedPlan.items[1].name -eq 'Heavy Claymore') 'Heavy Claymore affinity did not resolve'
Assert-That ($parsedPlan.items[2].name -eq 'Greathelm' -and $parsedPlan.items[2].slot -eq 'Head') 'Great Helm alias or Head slot was lost during resolution'
Assert-That ($parsedPlan.items[3].quantity -eq 3) 'parsed quantity was lost during resolution'
Assert-That ($parsedPlan.items[4].name -eq 'Flask of Cerulean Tears +5') 'flask upgrade suffix was lost during resolution'

$duplicatePlan = Resolve-TestRows @(
    (New-TestItem 'goods' "Godrick's Great Rune"),
    (New-TestItem 'goods' 'Golden Vow')
)
Assert-That ($duplicatePlan.items[0].itemId -eq 191 -and $duplicatePlan.items[0].match -eq 'duplicate-lowest-id') 'Godrick''s Great Rune did not select lowest ID 191'
Assert-That ($duplicatePlan.items[1].itemId -eq 6600 -and $duplicatePlan.items[1].match -eq 'duplicate-lowest-id') 'Golden Vow did not select lowest ID 6600'
Assert-That (($duplicatePlan.notes -join ' ') -match 'primary ID 191' -and ($duplicatePlan.notes -join ' ') -match 'primary ID 6600') 'duplicate resolution did not leave a note'

$builtInSkillPlan = Resolve-TestRows @((New-TestItem 'weapon' 'Rivers of Blood (Ash of War: Corpse Piler)' $null $null))
Assert-That ($builtInSkillPlan.issues.Count -eq 0 -and $builtInSkillPlan.items[0].ashOfWarId -eq $null) 'Rivers of Blood built-in skill produced an issue or Ash ID'
Assert-That (($builtInSkillPlan.notes -join ' ') -match 'built-in skill') 'Rivers of Blood built-in skill note is missing'
$unknownAshPlan = Resolve-TestRows @((New-TestItem 'weapon' "Claymore (Ash of War: Lion's Claw maybe)" $null $null))
Assert-That ($unknownAshPlan.items[0].itemId -ne $null -and $unknownAshPlan.items[0].ashOfWarId -eq $null) 'unknown Ash of War did not preserve the resolved weapon'
Assert-That (($unknownAshPlan.issues -join ' ') -match 'Unresolved Ash of War' -and ($unknownAshPlan.issues -join ' ') -match 'did you mean:.*Lion''s Claw') 'unknown Ash of War issue did not include suggestions'

$categoryPlan = Resolve-TestRows @((New-TestItem 'goods' 'Crimson Amber Medallion'))
Assert-That ($categoryPlan.items[0].category -eq 'talisman' -and $categoryPlan.items[0].match -eq 'category-corrected') 'talisman submitted as goods was not category-corrected'
Assert-That (($categoryPlan.notes -join ' ') -match 'category corrected: goods -> talisman') 'category correction note is missing'

$unresolvedPlan = Resolve-TestRows @(
    (New-TestItem 'weapon' 'Clamore'),
    (New-TestItem 'weapon' 'ZZZ-unknown-thing-xyz')
)
Assert-That ($unresolvedPlan.items.Count -eq 2) 'unresolved rows were not preserved'
Assert-That ($unresolvedPlan.items[0].itemId -eq $null -and $unresolvedPlan.items[1].itemId -eq $null) 'garbage input unexpectedly resolved'
Assert-That (($unresolvedPlan.issues -join ' ') -match 'did you mean:.*Claymore') 'unresolved typo did not include its available suggestion'
$notePlan = Resolve-TestRows @((New-TestItem 'weapon' 'Claymore / Greatsword'))
Assert-That ($notePlan.items.Count -eq 0 -and $notePlan.issues.Count -eq 0) 'slash-separated note-like row was not ignored'
Assert-That (($notePlan.notes -join ' ') -match 'Ignored note-like entry') 'ignored slash-separated row did not leave a note'

$physickName = 'Wondrous Physick: Crimsonburst Crystal Tear + Cerulean Hidden Tear'
$tearParts = [ERBS.ItemParser]::SplitPhysick($physickName)
Assert-That ($tearParts.Count -eq 2 -and $tearParts[0] -eq 'Crimsonburst Crystal Tear' -and $tearParts[1] -eq 'Cerulean Hidden Tear') 'Wondrous Physick did not split arbitrary tear names'
$arbitraryTears = [ERBS.ItemParser]::SplitPhysick('Wondrous Physick: Any First Tear + Any Second Tear')
Assert-That ($arbitraryTears.Count -eq 2 -and $arbitraryTears[0] -eq 'Any First Tear' -and $arbitraryTears[1] -eq 'Any Second Tear') 'Wondrous Physick splitting was restricted to known tear names'
$physickRows = @(ConvertTo-BuildItems ([pscustomobject]@{ items = @((New-TestItem 'goods' $physickName)) }))
Assert-That ($physickRows.Count -eq 2 -and $physickRows[0].name -eq $tearParts[0] -and $physickRows[1].name -eq $tearParts[1]) 'physick tears were not converted to item rows'
$physickPlan = Resolve-TestRows $physickRows
Assert-That ($physickPlan.items.Count -eq 2 -and $physickPlan.issues.Count -eq 0) 'physick tears did not resolve against the catalog'

$loadoutRows = @(
    (New-TestItem 'armor' 'Godrick Knight Helm'),
    (New-TestItem 'armor' 'Godrick Knight Armor'),
    (New-TestItem 'armor' 'Godrick Knight Gauntlets'),
    (New-TestItem 'armor' 'Godrick Knight Greaves'),
    (New-TestItem 'weapon' 'Brass Shield'),
    (New-TestItem 'weapon' 'Finger Seal'),
    (New-TestItem 'weapon' "Astrologer's Staff"),
    (New-TestItem 'weapon' 'Bone Arrow'),
    (New-TestItem 'weapon' 'Bone Bolt'),
    (New-TestItem 'weapon' 'Rivers of Blood'),
    (New-TestItem 'weapon' 'Claymore' 0 1 '' 'R3'),
    (New-TestItem 'weapon' 'Misericorde' 0 1 '' 'Inventory'),
    (New-TestItem 'talisman' 'Shard of Alexander'),
    (New-TestItem 'talisman' 'Crimson Amber Medallion'),
    (New-TestItem 'talisman' "Erdtree's Favor"),
    (New-TestItem 'talisman' "Great-Jar's Arsenal"),
    (New-TestItem 'goods' 'Glintstone Pebble'),
    (New-TestItem 'goods' 'Catch Flame'),
    (New-TestItem 'goods' 'Glintstone Pebble')
)
$loadoutPlan = Resolve-TestRows $loadoutRows
Assert-That ($loadoutPlan.issues.Count -eq 0) 'loadout fixture contains an unresolved item'
Assert-That ($loadoutPlan.loadout.Head.name -eq 'Godrick Knight Helm') 'armor ID suffix did not select Head'
Assert-That ($loadoutPlan.loadout.Chest.name -eq 'Godrick Knight Armor') 'armor ID suffix did not select Chest'
Assert-That ($loadoutPlan.loadout.Arms.name -eq 'Godrick Knight Gauntlets') 'armor ID suffix did not select Arms'
Assert-That ($loadoutPlan.loadout.Legs.name -eq 'Godrick Knight Greaves') 'armor ID suffix did not select Legs'
Assert-That ($loadoutPlan.loadout.L1.name -eq 'Brass Shield' -and $loadoutPlan.loadout.L2.name -eq 'Finger Seal' -and $loadoutPlan.loadout.L3.name -eq "Astrologer's Staff") 'shield, seal or staff did not auto-equip to a left-hand slot'
Assert-That ($loadoutPlan.loadout.Arrow1.name -eq 'Bone Arrow' -and $loadoutPlan.loadout.Bolt1.name -eq 'Bone Bolt') 'ammo did not auto-equip to its Arrow/Bolt slot'
Assert-That ($loadoutPlan.loadout.R3.name -eq 'Claymore' -and $loadoutPlan.loadout.R1.name -eq 'Rivers of Blood') 'explicit weapon slot did not win over automatic placement'
Assert-That ($loadoutPlan.loadout.Talisman1.name -eq 'Shard of Alexander' -and $loadoutPlan.loadout.Talisman2.name -eq 'Crimson Amber Medallion' -and $loadoutPlan.loadout.Talisman3.name -eq "Erdtree's Favor" -and $loadoutPlan.loadout.Talisman4.name -eq "Great-Jar's Arsenal") 'talismans did not fill Talisman1-4'
Assert-That ($loadoutPlan.loadout.Spell1.name -eq 'Glintstone Pebble' -and $loadoutPlan.loadout.Spell2.name -eq 'Catch Flame') 'spells did not fill Spell slots in order'
$pebbleId = ($loadoutPlan.items | Where-Object { $_.name -eq 'Glintstone Pebble' } | Select-Object -First 1).itemId
$pebbleSlots = @($loadoutPlan.loadout.PSObject.Properties | Where-Object { $_.Name -like 'Spell*' -and $_.Value.itemId -eq $pebbleId })
Assert-That ($pebbleSlots.Count -eq 1) 'duplicate spell occupied more than one loadout slot'
$inventoryId = ($loadoutPlan.items | Where-Object { $_.requestedName -eq 'Misericorde' } | Select-Object -First 1).itemId
$equippedIds = @($loadoutPlan.loadout.PSObject.Properties | ForEach-Object { $_.Value.itemId })
Assert-That (-not ($equippedIds -contains $inventoryId)) 'Inventory item was equipped'
Assert-That (-not ($loadoutPlan.loadout.PSObject.Properties.Name -contains 'Inventory')) 'Inventory appeared as an equipment slot'

$heavySearch = @(Search-Catalog $script:catalog 'claymore heavy' 'weapon' 5)
$riversSearch = @(Search-Catalog $script:catalog 'rivers' '' 5)
$wrongCategorySearch = @(Search-Catalog $script:catalog 'claymore heavy' 'talisman' 5)
Assert-That ($heavySearch.Count -gt 0 -and $heavySearch[0].name -eq 'Heavy Claymore') 'claymore heavy search ranking changed'
Assert-That ($riversSearch.Count -gt 0 -and $riversSearch[0].name -eq 'Rivers of Blood') 'rivers search ranking changed'
Assert-That (@($heavySearch | Where-Object { $_.category -ne 'weapon' }).Count -eq 0 -and $wrongCategorySearch.Count -eq 0) 'Search-Catalog did not respect its category filter'

$performanceRows = @($loadoutRows + (New-TestItem 'goods' 'Cerulean Hidden Tear'))
Assert-That ($performanceRows.Count -eq 20) 'performance fixture is not exactly 20 items'
$performanceBuild = [pscustomobject]@{ name = 'resolver performance'; attributes = @{}; items = $performanceRows }
$warmPlan = Resolve-BuildPlan $performanceBuild $script:catalog
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$timedPlan = Resolve-BuildPlan $performanceBuild $script:catalog
$timer.Stop()
Assert-That ($warmPlan.items.Count -eq 20 -and $timedPlan.items.Count -eq 20 -and $timedPlan.issues.Count -eq 0) '20-item performance build did not resolve cleanly'
Assert-That ($timer.ElapsedMilliseconds -lt 1500) ("20-item build took {0} ms after warm-up" -f $timer.ElapsedMilliseconds)

'Resolver regression checks passed.'
