$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
. (Join-Path $PSScriptRoot 'BuildText.ps1')
function Check($cond, $msg) { if (-not $cond) { throw "FAIL: $msg" } }
$catalog = Get-BuildCatalog $PSScriptRoot

# Typical chat answer: markdown bullets/bold, curly apostrophes, a comma list, unknowns, chatter around it.
$gemini = @"
Sure! Here is the build from the video:

**BUILD:** Lifesteal Facetank
**STATS:** VIG 60, MIND 20, END 30, STR 50, DEX 15, INT 9, FAI 40, ARC 10
* R1: Godslayer’s Greatsword +10 | Ash: ?
* L1: Brass Shield +25 | Ash: Barricade Shield
* R2: Claymore +25 (Ash: Lion's Claw)
- HEAD: Beast Champion Helm
- CHEST: Beast Champion Armor
- ARMS: ?
- LEGS: Beast Champion Greaves
- TALISMAN: Crimson Amber Medallion +3, Shard of Alexander
- TALISMAN: Erdtree's Favor +2
1. SPELL: Golden Vow
2. ITEM: Rowa Raisin x5

Let me know if you need anything else!
"@
Check (Test-BuildText $gemini) 'line format detected'
$b = ConvertFrom-BuildText $gemini
Check ($b.name -eq 'Lifesteal Facetank') "name ($($b.name))"
Check ($b.attributes.vig -eq 60 -and $b.attributes.fai -eq 40 -and $b.attributes.Count -eq 8) 'all eight stats'
Check (@($b.items).Count -eq 11) "item rows ($(@($b.items).Count))"
$plan = Resolve-BuildPlan $b $catalog
Check (@($plan.issues).Count -eq 0) ("resolves cleanly: " + ($plan.issues -join '; '))
Check ($plan.loadout.R1.name -eq "Godslayer's Greatsword" -and $plan.loadout.R1.upgrade -eq 10) 'R1 with upgrade, curly apostrophe'
Check ($plan.loadout.L1.name -eq 'Brass Shield') 'L1 shield'
$claymore = @($plan.items | Where-Object name -eq 'Claymore')[0]
Check ($claymore.upgrade -eq 25 -and $claymore.ashOfWarId) '(Ash: X) form parsed'
Check ($plan.loadout.Head.name -eq 'Beast Champion Helm' -and -not $plan.loadout.Arms) 'armor, unknown arms skipped'
Check ($plan.loadout.Talisman1 -and $plan.loadout.Talisman3) 'comma-separated talismans'
Check ($plan.loadout.Spell1.name -eq 'Golden Vow') 'spell'
$raisin = @($plan.items | Where-Object name -eq 'Rowa Raisin')[0]
Check ($raisin.quantity -eq 5 -and $raisin.slot -eq 'Inventory') 'item quantity, inventory only'

# JSON still works, including fences and a trailing comma.
$json = "Here you go:`n``````json`n{""schemaVersion"":""3.0"",""name"":""J"",""attributes"":{""vig"":40},""items"":[{""category"":""weapon"",""name"":""Moonveil"",""upgrade"":10,}]}`n``````"
$j = ConvertFrom-BuildText $json
Check ($j.name -eq 'J' -and @($j.items).Count -eq 1) 'fenced JSON with trailing comma'

Check (-not (Test-BuildText 'just some text I copied')) 'plain text ignored'
Check ($null -eq (ConvertFrom-BuildText 'hello world')) 'no build in plain text'
'Build text import checks passed.'
