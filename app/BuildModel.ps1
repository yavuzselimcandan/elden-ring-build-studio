function Get-BuildCatalog {
    param([string]$Root)
    @(Get-Content -LiteralPath (Join-Path $Root 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function ConvertTo-BuildItems {
    param($Build)
    $result = New-Object System.Collections.ArrayList
    if ($Build.items) {
        foreach ($i in $Build.items) {
            $category=[string]$i.category; $name=[string]$i.name.Trim(); $upgrade=[int]$(if($i.upgrade){$i.upgrade}else{0}); $ash=[string]$i.ashOfWar; $slot=[string]$i.slot
            if($category -eq 'armor') { if(-not $slot -and $name -match '^(Head|Chest|Arms|Legs):\s*'){ $slot=$Matches[1] }; $name=$name -replace '^(Head|Chest|Arms|Legs):\s*',''; if($name -ieq 'Great Helm'){$name='Greathelm'} }
            if($category -eq 'weapon') {
                if($name -match '^(.*?)\s*\+(\d+)\s*\(Ash of War:\s*([^)]*)\)\s*$') { $name=$Matches[1].Trim();$upgrade=[int]$Matches[2];$ash=$Matches[3].Trim() }
                elseif($name -match '^(.*?)\s*\+(\d+)\s*$') { $name=$Matches[1].Trim();$upgrade=[int]$Matches[2] }
                elseif($name -match '^(.*?)\s*\(Ash of War:\s*([^)]*)\)\s*$') { $name=$Matches[1].Trim();$ash=$Matches[2].Trim() }
                if(($name -ieq "Maliketh's Black Blade" -and $ash -ieq 'Destined Death') -or ($name -ieq 'Black Knife' -and $ash -ieq 'Blade of Death')) { $ash='' }
            }
            if($category -eq 'goods' -and $name -match '^Wondrous Physick:\s*(Holy-Shrouding Cracked Tear|Stonebarb Cracked Tear)\s*\+\s*(Holy-Shrouding Cracked Tear|Stonebarb Cracked Tear)\s*$') {
                foreach($tear in @($Matches[1],$Matches[2])) {[void]$result.Add([pscustomobject]@{category='goods';name=$tear;upgrade=0;quantity=$(if($i.quantity){$i.quantity}else{1});ashOfWar='';slot=''})}; continue
            }
            [void]$result.Add([pscustomobject]@{category=$category;name=$name;upgrade=$upgrade;quantity=$(if($i.quantity){$i.quantity}else{1});ashOfWar=$ash;slot=$slot})
        }
    } elseif ($Build.equipment) {
        $groups = @{weapons='weapon';armor='armor';talismans='talisman';spells='goods';materials='goods'}
        foreach ($g in $groups.Keys) {
            foreach ($value in $Build.equipment.$g) {
                $parts = ([string]$value) -split '\s*\|\s*',2
                $name=$parts[0].Trim(); $upgrade=0; $ash=''
                if ($groups[$g] -eq 'weapon' -and $name -match '^(.*?)\s+\+(\d+)$') { $name=$Matches[1]; $upgrade=[int]$Matches[2] }
                if ($parts.Count -gt 1) { $ash=$parts[1] -replace '^Ash of War:\s*','' }
                [void]$result.Add([pscustomobject]@{category=$groups[$g];name=$name;upgrade=$upgrade;quantity=1;ashOfWar=$ash;slot=''})
            }
        }
    }
    return $result
}
function Resolve-BuildPlan {
    param($Build,$Catalog)
    $issues=New-Object System.Collections.ArrayList
    $resolved=New-Object System.Collections.ArrayList
    foreach ($i in @(ConvertTo-BuildItems $Build)) {
        if (-not $i.name.Trim()) { continue }
        $category=$i.category
        if($category -in @('spell','material')){$category='goods'}
        $matches=@($Catalog | Where-Object {$_.category -eq $category -and $_.name -ieq $i.name.Trim()})
        # User-approved Golden Vow spell choice; catalog also contains a separate consumable with the same display name.
        if($category -eq 'goods' -and $i.name.Trim() -ieq 'Golden Vow') { $matches=@($matches | Where-Object {[long]$_.itemId -eq 6600}) }
        if($matches.Count -ne 1){
            [void]$issues.Add("Unresolved item: $($i.name)")
            # Keep the row visible in the plan so an unresolved item is never silently dropped.
            [void]$resolved.Add([pscustomobject]@{category=$category;name=$i.name.Trim();itemId=$null;upgrade=$i.upgrade;quantity=$i.quantity;ashOfWarId=$null;slot=$i.slot;gameValidated=$false;unresolved=$true})
            continue
        }
        $q=0; $u=0
        if(-not [int]::TryParse([string]$i.quantity,[ref]$q) -or $q -lt 1 -or $q -gt 999){[void]$issues.Add("Invalid quantity: $($i.name)");continue}
        if(-not [int]::TryParse([string]$i.upgrade,[ref]$u) -or $u -lt 0 -or $u -gt 25){[void]$issues.Add("Invalid upgrade: $($i.name)");continue}
        if($category -ne 'weapon' -and $u -ne 0){[void]$issues.Add("Only weapons accept an upgrade here: $($i.name)");continue}
        $ashId=$null
        if($i.ashOfWar){
            $ash=@($Catalog|Where-Object {$_.category -eq 'ash' -and ($_.name -ieq $i.ashOfWar -or $_.name -ieq ('Ash of War: '+$i.ashOfWar))})
            if($ash.Count -eq 1){$ashId=$ash[0].itemId}else{
                [void]$issues.Add("Unresolved Ash of War: $($i.ashOfWar)")
                [void]$resolved.Add([pscustomobject]@{category=$category;name=$matches[0].name;itemId=[long]$matches[0].itemId;upgrade=$u;quantity=$q;ashOfWarId=$null;slot=$i.slot;gameValidated=$false;unresolved=$true;ashOfWar=$i.ashOfWar})
                continue
            }
        }
        [void]$resolved.Add([pscustomobject]@{category=$category;name=$matches[0].name;itemId=[long]$matches[0].itemId;upgrade=$u;quantity=$q;ashOfWarId=$ashId;slot=$i.slot;gameValidated=$false})
    }
    $attrs=[ordered]@{}
    foreach($key in @('vig','mind','end','str','dex','int','fai','arc')){
        $value=$Build.attributes.$key
        if($null -ne $value -and [string]$value -ne ''){
            $number=0
            if(-not [int]::TryParse([string]$value,[ref]$number) -or $number -lt 1 -or $number -gt 99){[void]$issues.Add("Invalid attribute: $key")}else{$attrs[$key]=$number}
        }
    }
    [pscustomobject]@{schemaVersion='2.0';name=$Build.name;attributes=$attrs;items=@($resolved);issues=@($issues);catalogValidated=($issues.Count -eq 0);gameValidated=$false}
}
