$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
$catalog=Get-BuildCatalog $PSScriptRoot
$items=@(
 [pscustomobject]@{category='armor';name='Head: Great Helm';upgrade=0;quantity=1;ashOfWar=''},
 [pscustomobject]@{category='armor';name='Chest: Ronin''s Armor';upgrade=0;quantity=1;ashOfWar=''},
 [pscustomobject]@{category='weapon';name='Maliketh''s Black Blade +10 (Ash of War: Destined Death)';upgrade=0;quantity=1;ashOfWar=''},
 [pscustomobject]@{category='weapon';name='Black Knife +10 (Ash of War: Blade of Death)';upgrade=0;quantity=1;ashOfWar=''},
 [pscustomobject]@{category='goods';name='Wondrous Physick: Holy-Shrouding Cracked Tear + Stonebarb Cracked Tear';upgrade=0;quantity=1;ashOfWar=''},
 [pscustomobject]@{category='goods';name='Golden Vow';upgrade=0;quantity=1;ashOfWar=''},
 [pscustomobject]@{category='weapon';name='Magic Claymore +25 (Ash of War: Carian Sovereignty)';upgrade=0;quantity=1;ashOfWar=''}
)
$plan=Resolve-BuildPlan ([pscustomobject]@{name='luna';attributes=@{};items=$items}) $catalog
if(@($plan.items|Where-Object name -eq 'Greathelm').Count -ne 1){throw 'Great Helm alias failed'}
foreach($n in 'Ronin''s Armor','Maliketh''s Black Blade','Black Knife','Holy-Shrouding Cracked Tear','Stonebarb Cracked Tear'){if(@($plan.items|Where-Object name -eq $n).Count -ne 1){throw "missing $n"}}
foreach($n in 'Maliketh''s Black Blade','Black Knife'){ $x=@($plan.items|Where-Object name -eq $n)[0]; if($x.upgrade -ne 10 -or $null -ne $x.ashOfWarId){throw "intrinsic skill handling failed: $n"} }
$custom=@($plan.items|Where-Object name -eq 'Magic Claymore')[0]; if($custom.upgrade -ne 25 -or $custom.ashOfWarId -ne 418000){throw 'custom Ash handling failed'}
$golden=@($plan.items|Where-Object name -eq 'Golden Vow'); if($golden.Count -ne 1 -or $golden[0].itemId -ne 6600){throw 'Golden Vow spell choice failed'}
'Luna normalization regression passed.'
