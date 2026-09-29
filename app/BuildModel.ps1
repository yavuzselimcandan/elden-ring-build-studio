# Preset model: parsing, catalog resolution and loadout (slot) planning.
# The heavy lifting (normalisation, fuzzy search, string parsing) lives in lib/Resolver.cs.

if (-not ('ERBS.CatalogIndex' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'lib\Resolver.cs') -ReferencedAssemblies System.Core
}

$script:BuildAttributeKeys = @('vig','mind','end','str','dex','int','fai','arc')
$script:CatalogIndexCache = @{}

# Names seen in guides/videos that differ from the catalog's canonical spelling.
$script:BuildAliases = [ordered]@{
    'Great Helm'                 = 'Greathelm'
    'Misericorde'                = 'Miséricorde'
    'Moonveil Katana'            = 'Moonveil'
    'RoB'                        = 'Rivers of Blood'
    'Mimic Tear Ash'             = 'Mimic Tear Ashes'
    'Mimic Tear'                 = 'Mimic Tear Ashes'
    'Physick Flask'              = 'Flask of Wondrous Physick'
    'Wondrous Physick'           = 'Flask of Wondrous Physick'
    'Shard of Alexander Talisman'= 'Shard of Alexander'
}

# Plan entries with these methods are trusted enough to apply without user review.
$script:AutoAcceptMethods = @('exact','plural','alias','category-corrected','duplicate-lowest-id','fuzzy-confident')

function Get-BuildCatalog {
    param([string]$Root)
    @(Get-Content -LiteralPath (Join-Path $Root 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-CatalogIndex {
    param($Catalog)
    $key = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Catalog)
    if ($script:CatalogIndexCache.ContainsKey($key)) { return $script:CatalogIndexCache[$key] }
    $cats = [string[]]@($Catalog | ForEach-Object { [string]$_.category })
    $ids = [long[]]@($Catalog | ForEach-Object { [long]$_.itemId })
    $names = [string[]]@($Catalog | ForEach-Object { [string]$_.name })
    $index = [ERBS.CatalogIndex]::new($cats, $ids, $names)
    foreach ($a in $script:BuildAliases.Keys) { $index.AddAlias($a, $script:BuildAliases[$a]) }
    $script:CatalogIndexCache[$key] = $index
    return $index
}

function New-BuildRow {
    param([string]$Category, [string]$Name, $Upgrade = 0, $Quantity = 1, [string]$AshOfWar = '', [string]$Slot = '', [string]$Affinity = '')
    [pscustomobject]@{ category = $Category; name = $Name; upgrade = $Upgrade; quantity = $Quantity; ashOfWar = $AshOfWar; slot = $Slot; affinity = $Affinity }
}

# Turns any supported preset shape (v2/v3 items, legacy equipment strings) into flat editable rows.
function ConvertTo-BuildItems {
    param($Build)
    $result = New-Object System.Collections.ArrayList
    $source = @()
    if ($Build.items) {
        foreach ($i in $Build.items) { $source += ,@([string]$i.category, [string]$i.name, $i.upgrade, $i.quantity, [string]$i.ashOfWar, [string]$i.slot, [string]$i.affinity) }
    } elseif ($Build.equipment) {
        $groups = [ordered]@{ weapons = 'weapon'; armor = 'armor'; talismans = 'talisman'; spells = 'goods'; materials = 'goods' }
        foreach ($g in $groups.Keys) { foreach ($value in @($Build.equipment.$g)) { if ($value) { $source += ,@($groups[$g], [string]$value, $null, $null, '', '', '') } } }
    }
    foreach ($s in $source) {
        $p = [ERBS.ItemParser]::Parse($s[1], $s[0])
        if (-not $p.Name) { continue }
        $upgrade = if ($null -ne $p.Upgrade -and -not ($s[2] -as [int])) { $p.Upgrade } elseif ($null -ne $s[2] -and "$($s[2])" -ne '') { $s[2] } else { 0 }
        $quantity = if ($null -ne $s[3] -and "$($s[3])" -ne '' -and [int]$s[3] -gt 1) { $s[3] } elseif ($p.Quantity) { $p.Quantity } elseif ($null -ne $s[3] -and "$($s[3])" -ne '') { $s[3] } else { 1 }
        $ash = if ($s[4]) { $s[4] } elseif ($p.AshOfWar) { $p.AshOfWar } else { '' }
        $slot = if ($s[5]) { $s[5] } elseif ($p.Slot) { $p.Slot } else { '' }
        $affinity = if ($s[6]) { $s[6] } elseif ($p.Affinity) { $p.Affinity } else { '' }
        $tears = [ERBS.ItemParser]::SplitPhysick($p.Name)
        if ($tears.Count -eq 2) {
            foreach ($tear in $tears) { [void]$result.Add((New-BuildRow 'goods' $tear 0 1)) }
            continue
        }
        [void]$result.Add((New-BuildRow $p.Category $p.Name $upgrade $quantity $ash $slot $affinity))
    }
    return $result
}

function Get-EntryView {
    param($Entry)
    if (-not $Entry) { return $null }
    [pscustomobject]@{ category = $Entry.Category; itemId = $Entry.ItemId; name = $Entry.Name }
}

# Resolves one name to a single catalog entry. Never guesses silently: every non-exact
# decision is reported through .method and .note, and weak matches stay unresolved with suggestions.
function Resolve-CatalogName {
    param([ERBS.CatalogIndex]$Index, [string]$Name, [string]$Category, [string]$Affinity)
    $query = $Name
    if ($Affinity -and $Category -eq 'weapon') { $query = "$Affinity $Name" }
    $method = $null
    $hits = @($Index.Exact($query, $Category, [ref]$method))
    if ($hits.Count -eq 0 -and $query -ne $Name) { $hits = @($Index.Exact($Name, $Category, [ref]$method)) }
    if ($hits.Count -gt 0) {
        $note = $null
        if ($method -eq 'category-corrected') {
            $cats = @($hits | ForEach-Object Category | Select-Object -Unique)
            if ($cats.Count -gt 1) { return [pscustomobject]@{ entry = $null; method = 'ambiguous'; note = "'$Name' exists in several categories: $($cats -join ', ')"; suggestions = @($hits | ForEach-Object { "$($_.Name) [$($_.Category)]" }) } }
            $note = "category corrected: $Category -> $($cats[0])"
        }
        if ($hits.Count -gt 1) {
            $pick = $hits | Sort-Object ItemId | Select-Object -First 1
            return [pscustomobject]@{ entry = $pick; method = 'duplicate-lowest-id'; note = "catalog has $($hits.Count) entries named '$($pick.Name)'; using primary ID $($pick.ItemId)"; suggestions = @() }
        }
        return [pscustomobject]@{ entry = $hits[0]; method = $method; note = $note; suggestions = @() }
    }
    $cands = @($Index.Search($query, $Category, 6))
    if ($cands.Count -eq 0 -and $Category) { $cands = @($Index.Search($query, '', 6)) }
    $suggestions = @($cands | ForEach-Object { $_.Entry.Name } | Select-Object -Unique -First 5)
    if ($cands.Count -gt 0) {
        $best = $cands[0]
        $rival = @($cands | Where-Object { $_.Entry.Name -ne $best.Entry.Name } | Select-Object -First 1)
        $margin = if ($rival.Count) { $best.Score - $rival[0].Score } else { 1 }
        if ($best.Score -ge 0.9 -and $margin -ge 0.04) {
            return [pscustomobject]@{ entry = $best.Entry; method = 'fuzzy-confident'; note = "'$Name' matched to '$($best.Entry.Name)' ($([math]::Round($best.Score * 100))%)"; suggestions = $suggestions }
        }
    }
    [pscustomobject]@{ entry = $null; method = 'unresolved'; note = $null; suggestions = $suggestions }
}

function Resolve-BuildPlan {
    param($Build, $Catalog)
    $index = Get-CatalogIndex $Catalog
    $issues = New-Object System.Collections.ArrayList
    $notes = New-Object System.Collections.ArrayList
    $resolved = New-Object System.Collections.ArrayList
    $rowIndex = -1
    foreach ($i in @(ConvertTo-BuildItems $Build)) {
        $rowIndex++
        $name = ([string]$i.name).Trim()
        if (-not $name) { continue }
        $category = [string]$i.category
        $r = Resolve-CatalogName $index $name $category ([string]$i.affinity)
        $row = [ordered]@{ rowIndex = $rowIndex; category = $category; name = $name; requestedName = $name; itemId = $null; upgrade = $i.upgrade; quantity = $i.quantity; ashOfWarId = $null; ashOfWar = [string]$i.ashOfWar; slot = [string]$i.slot; match = $r.method; suggestions = @($r.suggestions); gameValidated = $false; unresolved = $true }
        if (-not $r.entry) {
            $parsed = [ERBS.ItemParser]::Parse($name, $category)
            if ($parsed.LooksLikeNote) { $row.match = 'note'; [void]$notes.Add("Ignored note-like entry: $name") ; continue }
            [void]$issues.Add($(if ($r.method -eq 'ambiguous') { "Ambiguous item: $name ($($r.note))" } else { "Unresolved item: $name" + $(if ($row.suggestions.Count) { " (did you mean: $($row.suggestions -join ', ')?)" } else { '' }) }))
            [void]$resolved.Add([pscustomobject]$row); continue
        }
        if ($r.note) { [void]$notes.Add($r.note) }
        $entry = $r.entry
        $row.category = $entry.Category; $row.name = $entry.Name; $row.itemId = [long]$entry.ItemId; $row.unresolved = $false
        $q = 0; $u = 0
        if (-not [int]::TryParse([string]$i.quantity, [ref]$q) -or $q -lt 1 -or $q -gt 999) { [void]$issues.Add("Invalid quantity: $name"); $row.unresolved = $true; [void]$resolved.Add([pscustomobject]$row); continue }
        if (-not [int]::TryParse([string]$i.upgrade, [ref]$u) -or $u -lt 0 -or $u -gt 25) { [void]$issues.Add("Invalid upgrade: $name"); $row.unresolved = $true; [void]$resolved.Add([pscustomobject]$row); continue }
        if ($entry.Category -ne 'weapon' -and $u -ne 0) { [void]$notes.Add("Upgrade +$u dropped for non-weapon $($entry.Name)"); $u = 0 }
        if ($entry.Category -eq 'weapon' -and $entry.WeaponClass -in @('arrow','bolt') -and $u -ne 0) { [void]$notes.Add("Ammunition cannot be upgraded: $($entry.Name)"); $u = 0 }
        $row.upgrade = $u; $row.quantity = $q
        if ($row.ashOfWar -and $entry.Category -eq 'weapon') {
            $ar = Resolve-CatalogName $index $row.ashOfWar 'ash' ''
            if (-not $entry.HasAffinities) {
                # Unique/somber weapons (no infused variants) cannot take Ashes of War; the named skill is built in.
                [void]$notes.Add("'$($row.ashOfWar)' is treated as the built-in skill of $($entry.Name)")
                $row.ashOfWar = ''
            } elseif ($ar.entry -and $ar.entry.Category -eq 'ash') {
                $row.ashOfWarId = [long]$ar.entry.ItemId; $row.ashOfWar = $ar.entry.Name -replace '^Ash of War:\s*', ''
                if ($ar.note) { [void]$notes.Add("Ash of War $($ar.note)") }
            } else {
                [void]$issues.Add("Unresolved Ash of War: $($row.ashOfWar)" + $(if ($ar.suggestions.Count) { " (did you mean: $(@($ar.suggestions | Select-Object -First 3) -join ', ')?)" } else { '' }))
                $row.unresolved = $true
            }
        } elseif ($row.ashOfWar) { [void]$notes.Add("Ash of War ignored for non-weapon $($entry.Name)"); $row.ashOfWar = '' }
        [void]$resolved.Add([pscustomobject]$row)
    }
    $attrs = [ordered]@{}
    foreach ($key in $script:BuildAttributeKeys) {
        $value = $Build.attributes.$key
        if ($null -ne $value -and [string]$value -ne '') {
            $number = 0
            if (-not [int]::TryParse([string]$value, [ref]$number) -or $number -lt 1 -or $number -gt 99) { [void]$issues.Add("Invalid attribute: $key") } else { $attrs[$key] = $number }
        }
    }
    $plan = [pscustomobject]@{ schemaVersion = '3.0'; name = $Build.name; attributes = $attrs; items = @($resolved); issues = @($issues); notes = @($notes); loadout = $null; catalogValidated = ($issues.Count -eq 0); gameValidated = $false }
    $plan.loadout = Get-BuildLoadout $plan $index
    return $plan
}

$script:LoadoutSlots = @('R1','R2','R3','L1','L2','L3','Arrow1','Arrow2','Bolt1','Bolt2','Head','Chest','Arms','Legs','Talisman1','Talisman2','Talisman3','Talisman4') + @(1..14 | ForEach-Object { "Spell$_" })

function Get-LoadoutSlotNames { $script:LoadoutSlots }

function Test-SpellId { param([long]$Id) ($Id -ge 4000 -and $Id -lt 8000) -or ($Id -ge 2004000 -and $Id -lt 2008000) }

# Assigns equipment slots. Explicit slots in the preset win; the rest are placed by item type:
# armor by ID suffix, shields/seals/staves/torches to the left hand, ammo to quivers,
# talismans and spells in listed order.
function Get-BuildLoadout {
    param($Plan, [ERBS.CatalogIndex]$Index)
    $loadout = [ordered]@{}
    $free = { param($prefix, $count) foreach ($n in 1..$count) { if (-not $loadout.Contains("$prefix$n")) { return "$prefix$n" } }; $null }
    $items = @($Plan.items | Where-Object { $_.itemId -and -not $_.unresolved })
    $pending = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        $slot = [string]$it.slot
        if ($slot -eq 'Inventory') { continue }
        if ($slot -and $slot -in $script:LoadoutSlots -and -not $loadout.Contains($slot)) { $loadout[$slot] = $it } else { [void]$pending.Add($it) }
    }
    foreach ($it in $pending) {
        # One copy per item: a duplicate row must not occupy a second slot (spells can only be memorised once).
        if (@($loadout.Values | Where-Object { $_.itemId -eq $it.itemId -and $_.category -eq $it.category }).Count) { continue }
        $slot = $null
        switch ($it.category) {
            'armor' { $slot = @('Head','Chest','Arms','Legs')[[int](([long]$it.itemId % 1000) / 100) % 4]; if ($loadout.Contains($slot)) { $slot = $null } }
            'talisman' { $slot = & $free 'Talisman' 4 }
            'goods' { if (Test-SpellId $it.itemId) { $slot = & $free 'Spell' 14 } }
            'weapon' {
                $entry = $Index.WeaponById([long]$it.itemId)
                $class = if ($entry) { $entry.WeaponClass } else { 'melee' }
                switch ($class) {
                    'arrow' { $slot = & $free 'Arrow' 2 }
                    'bolt' { $slot = & $free 'Bolt' 2 }
                    { $_ -in @('shield','seal','staff','torch') } { $slot = & $free 'L' 3; if (-not $slot) { $slot = & $free 'R' 3 } }
                    default { $slot = & $free 'R' 3; if (-not $slot) { $slot = & $free 'L' 3 } }
                }
            }
        }
        if ($slot) { $loadout[$slot] = $it }
    }
    $out = [ordered]@{}
    foreach ($s in $script:LoadoutSlots) { if ($loadout.Contains($s)) { $it = $loadout[$s]; $out[$s] = [pscustomobject]@{ rowIndex = $it.rowIndex; category = $it.category; itemId = [long]$it.itemId; name = $it.name; upgrade = [int]$it.upgrade } } }
    return [pscustomobject]$out
}

function Search-Catalog {
    param($Catalog, [string]$Query, [string]$Category = '', [int]$Max = 40)
    $index = Get-CatalogIndex $Catalog
    @($index.Search($Query, $Category, $Max) | ForEach-Object { [pscustomobject]@{ name = $_.Entry.Name; category = $_.Entry.Category; itemId = $_.Entry.ItemId; score = $_.Score; weaponClass = $_.Entry.WeaponClass } })
}
