function Get-BuildCatalog {
    param([string]$Root)
    @(Get-Content -LiteralPath (Join-Path $Root 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function ConvertTo-BuildItems {
    param($Build)
    $result = New-Object System.Collections.ArrayList
    if ($Build.items) {
        foreach ($i in $Build.items) { [void]$result.Add([pscustomobject]@{category=[string]$i.category;name=[string]$i.name;upgrade=$i.upgrade;quantity=$(if($i.quantity){$i.quantity}else{1});ashOfWar=[string]$i.ashOfWar}) }
    } elseif ($Build.equipment) {
        $groups = @{weapons='weapon';armor='armor';talismans='talisman';spells='goods';materials='goods'}
        foreach ($g in $groups.Keys) {
            foreach ($value in $Build.equipment.$g) {
                $parts = ([string]$value) -split '\s*\|\s*',2
                $name=$parts[0].Trim(); $upgrade=0; $ash=''
                if ($groups[$g] -eq 'weapon' -and $name -match '^(.*?)\s+\+(\d+)$') { $name=$Matches[1]; $upgrade=[int]$Matches[2] }
                if ($parts.Count -gt 1) { $ash=$parts[1] -replace '^Ash of War:\s*','' }
                [void]$result.Add([pscustomobject]@{category=$groups[$g];name=$name;upgrade=$upgrade;quantity=1;ashOfWar=$ash})
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
        if($matches.Count -ne 1){[void]$issues.Add("Unresolved item: $($i.name)");continue}
        $q=0; $u=0
        if(-not [int]::TryParse([string]$i.quantity,[ref]$q) -or $q -lt 1 -or $q -gt 999){[void]$issues.Add("Invalid quantity: $($i.name)");continue}
        if(-not [int]::TryParse([string]$i.upgrade,[ref]$u) -or $u -lt 0 -or $u -gt 25){[void]$issues.Add("Invalid upgrade: $($i.name)");continue}
        if($category -ne 'weapon' -and $u -ne 0){[void]$issues.Add("Only weapons accept an upgrade here: $($i.name)");continue}
        $ashId=$null
        if($i.ashOfWar){
            $ash=@($Catalog|Where-Object {$_.category -eq 'ash' -and ($_.name -ieq $i.ashOfWar -or $_.name -ieq ('Ash of War: '+$i.ashOfWar))})
            if($ash.Count -eq 1){$ashId=$ash[0].itemId}else{[void]$issues.Add("Unresolved Ash of War: $($i.ashOfWar)")}
        }
        [void]$resolved.Add([pscustomobject]@{category=$category;name=$matches[0].name;itemId=[long]$matches[0].itemId;upgrade=$u;quantity=$q;ashOfWarId=$ashId;gameValidated=$false})
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
