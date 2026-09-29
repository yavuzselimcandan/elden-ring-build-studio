param([switch]$CheckOnly, [string]$Preset)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $PSScriptRoot 'BuildModel.ps1')
. (Join-Path $PSScriptRoot 'BuildText.ps1')
. (Join-Path $PSScriptRoot 'backend.ps1')

$root = $PSScriptRoot
$catalog = Get-BuildCatalog $root
$index = Get-CatalogIndex $catalog
$dir = Join-Path $root 'configs'
New-Item -ItemType Directory -Force -Path $dir, (Join-Path $root 'runtime') | Out-Null
$settingsPath = Join-Path $root 'runtime\studio-settings.json'

$w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml](Get-Content -LiteralPath (Join-Path $root 'ui\MainWindow.xaml') -Raw -Encoding UTF8))))
$iconPath = Join-Path $root 'assets\BuildStudio.ico'
if (Test-Path $iconPath) { try { $w.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath) } catch { } }
$ui = @{}
foreach ($n in 'PresetFilter','PresetList','NewBtn','PasteBtn','PromptBtn','FolderBtn','ConnChip','ConnDot','ConnText','AutoApply','ApplyBtn','BuildName','SourceText','StatusText','LevelText','StatsGrid','EquipPanel','InventoryPanel','PickerTitle','PickerSub','SearchBox','CategoryChips','Results','SelectedName','UpgradeBox','UpgradeInput','QtyInput','AshBox','AshInput','PlaceBtn','ClearSlotBtn','IssuesTitle','IssuesPanel') {
    $ui[$n] = $w.FindName($n)
}

# All mutable state lives in one hashtable so WPF event handlers can update it without scope surprises.
$State = @{
    path = $null; name = 'New build'; source = $null; rows = New-Object System.Collections.ArrayList; stats = @{}
    plan = $null; target = $null; selected = $null; editRow = $null; category = ''
    dirty = $false; changedAt = [datetime]::MinValue; loading = $false; lastSavedJson = ''
    lastApplied = ''
    backend = $null
}

function Brush([string]$hex) { $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)); $b.Freeze(); $b }
$C = @{ gold = Brush '#C9A45C'; goldDim = Brush '#6E5A33'; line = Brush '#2A2E37'; panel2 = Brush '#1C1F26'; text = Brush '#E8E1D3'; muted = Brush '#8C8676'; ok = Brush '#7FB38A'; warn = Brush '#D9A45B'; err = Brush '#D46A5F'; errBg = Brush '#2A1A19'; empty = Brush '#15171C' }

function Set-Status([string]$text) { $ui.StatusText.Text = $text }

function New-Text([string]$text, $brush = $null, [double]$size = 13, [string]$weight = 'Normal') {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text; $t.FontSize = $size; $t.FontWeight = $weight; $t.TextTrimming = 'CharacterEllipsis'
    if ($brush) { $t.Foreground = $brush }
    $t
}

# ---------------------------------------------------------------- presets

function Get-SafeFileName([string]$name) { $s = ($name -replace '[^\w .()-]', '_').Trim('. '); if (-not $s) { 'New build' } else { $s } }

function Update-PresetList([string]$select) {
    $filter = $ui.PresetFilter.Text
    $list = foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.json -File | Where-Object { $_.Name -notmatch '\.plan\.json$' } | Sort-Object LastWriteTime -Descending) {
        $title = $f.BaseName; $count = 0
        try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; if ($j.name) { $title = [string]$j.name }; $count = @($j.items).Count + @($j.equipment.weapons).Count + @($j.equipment.armor).Count } catch { }
        if ($filter -and $title -notlike "*$filter*") { continue }
        [pscustomobject]@{ Title = $title; Subtitle = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0} items · {1:dd MMM HH:mm}', $count, $f.LastWriteTime); Path = $f.FullName }
    }
    $State.loading = $true
    $ui.PresetList.ItemsSource = @($list)
    if ($select) { $ui.PresetList.SelectedItem = @($list | Where-Object Path -eq $select | Select-Object -First 1)[0] }
    $State.loading = $false
}

function Import-BuildObject($b, [string]$path) {
    $State.loading = $true
    try {
        $State.path = $path; $State.name = if ($b.name) { [string]$b.name } else { 'New build' }; $State.source = $b.source
        $State.rows = New-Object System.Collections.ArrayList
        foreach ($r in @(ConvertTo-BuildItems $b)) { [void]$State.rows.Add($r) }
        $State.stats = @{}; foreach ($k in $script:BuildAttributeKeys) { $v = $b.attributes.$k; if ($null -ne $v -and "$v" -ne '') { $State.stats[$k] = [string]$v } }
        $ui.BuildName.Text = $State.name
        $ui.SourceText.Text = if ($b.source.url) { [string]$b.source.url } elseif ($path) { [IO.Path]::GetFileName($path) } else { 'Unsaved build' }
        foreach ($k in $script:BuildAttributeKeys) { $script:StatInputs[$k].Text = [string]$State.stats[$k] }
        $State.target = $null; $State.editRow = $null; $State.lastSavedJson = ''; $State.lastApplied = ''
    } finally { $State.loading = $false }
    Update-View
    Select-Target $null
}

function Open-Preset([string]$path) {
    try {
        $b = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        Import-BuildObject $b $path
        Set-Status "Opened $([IO.Path]::GetFileName($path))"
        Save-Settings
    } catch { Set-Status "Could not open preset: $($_.Exception.Message)" }
}

function Get-BuildObject {
    $attrs = [ordered]@{}; foreach ($k in $script:BuildAttributeKeys) { $v = $State.stats[$k]; $attrs[$k] = if ($v -match '^\d+$') { [int]$v } elseif ($v) { $v } else { $null } }
    $items = @($State.rows | ForEach-Object {
        $o = [ordered]@{ category = $_.category; name = $_.name; upgrade = [int]("0$($_.upgrade)" -replace '\D', ''); quantity = [int]$(if ("$($_.quantity)" -match '^\d+$') { $_.quantity } else { 1 }) }
        if ($_.ashOfWar) { $o.ashOfWar = $_.ashOfWar }
        if ($_.slot) { $o.slot = $_.slot }
        if ($_.affinity) { $o.affinity = $_.affinity }
        [pscustomobject]$o
    })
    [pscustomobject]@{ schemaVersion = '3.0'; name = $State.name; source = $State.source; attributes = $attrs; items = $items }
}

function Save-Current {
    $b = Get-BuildObject
    $json = $b | ConvertTo-Json -Depth 8
    if ($json -eq $State.lastSavedJson) { return $false }
    if (-not $State.path) {
        $base = Get-SafeFileName $State.name; $p = Join-Path $dir "$base.json"; $n = 2
        while (Test-Path -LiteralPath $p) { $p = Join-Path $dir "$base ($n).json"; $n++ }
        $State.path = $p
    } elseif (-not $State.lastSavedJson -and (Test-Path -LiteralPath $State.path)) {
        # One restore point per editing session, taken before the first overwrite.
        Copy-Item -LiteralPath $State.path -Destination ($State.path + '.previous') -Force
    }
    $utf8 = New-Object Text.UTF8Encoding $true
    [IO.File]::WriteAllText($State.path, $json, $utf8)
    [IO.File]::WriteAllText(($State.path -replace '\.json$', '.plan.json'), ($State.plan | ConvertTo-Json -Depth 8), $utf8)
    $State.lastSavedJson = $json
    Update-PresetList $State.path
    return $true
}

function Save-Settings {
    try { [pscustomobject]@{ lastPreset = $State.path; autoApply = [bool]$ui.AutoApply.IsChecked; lastClipboardHash = $State.lastClipboardHash } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8 } catch { }
}

function Set-Dirty {
    if ($State.loading) { return }
    $State.dirty = $true; $State.changedAt = [datetime]::UtcNow
    Update-View
}

# ---------------------------------------------------------------- rendering

$script:StatInputs = @{}
$statNames = [ordered]@{ vig = 'VIGOR'; mind = 'MIND'; end = 'ENDURANCE'; str = 'STRENGTH'; dex = 'DEXTERITY'; int = 'INTELLIGENCE'; fai = 'FAITH'; arc = 'ARCANE' }
foreach ($k in $statNames.Keys) {
    $cell = New-Object Windows.Controls.StackPanel; $cell.Margin = '0,0,14,10'
    [void]$cell.Children.Add((New-Text $statNames[$k] $C.muted 11 'SemiBold'))
    $row = New-Object Windows.Controls.DockPanel; $row.Margin = '0,4,0,0'
    $tb = New-Object Windows.Controls.TextBox; $tb.FontSize = 15; $tb.Height = 34; $tb.VerticalContentAlignment = 'Center'; $tb.Padding = '10,0'; $tb.Tag = $k; $tb.MaxLength = 2
    foreach ($d in @(-1, 1)) {
        $btn = New-Object Windows.Controls.Button; $btn.Content = $(if ($d -lt 0) { '−' } else { '+' }); $btn.Padding = '0'; $btn.Width = 30; $btn.Height = 34; $btn.Margin = '4,0,0,0'; $btn.Tag = @($k, $d)
        [Windows.Controls.DockPanel]::SetDock($btn, 'Right')
        $btn.Add_Click({ param($s, $e) $key = $s.Tag[0]; $cur = 0; [void][int]::TryParse($script:StatInputs[$key].Text, [ref]$cur); if ($cur -lt 1) { $cur = 10 }; $script:StatInputs[$key].Text = [string]([math]::Min(99, [math]::Max(1, $cur + $s.Tag[1]))) })
        [void]$row.Children.Add($btn)
    }
    [void]$row.Children.Add($tb)
    $tb.Add_TextChanged({ param($s, $e) if ($State.loading) { return }; $State.stats[$s.Tag] = $s.Text.Trim(); Set-Dirty })
    [void]$cell.Children.Add($row)
    [void]$ui.StatsGrid.Children.Add($cell)
    $script:StatInputs[$k] = $tb
}

$slotGroups = [ordered]@{
    'Right hand' = @('R1','R2','R3'); 'Left hand' = @('L1','L2','L3'); 'Armor' = @('Head','Chest','Arms','Legs')
    'Talismans' = @('Talisman1','Talisman2','Talisman3','Talisman4'); 'Ammunition' = @('Arrow1','Arrow2','Bolt1','Bolt2')
}
$slotLabels = @{ R1 = 'RIGHT 1'; R2 = 'RIGHT 2'; R3 = 'RIGHT 3'; L1 = 'LEFT 1'; L2 = 'LEFT 2'; L3 = 'LEFT 3'; Head = 'HEAD'; Chest = 'CHEST'; Arms = 'ARMS'; Legs = 'LEGS'; Arrow1 = 'ARROW 1'; Arrow2 = 'ARROW 2'; Bolt1 = 'BOLT 1'; Bolt2 = 'BOLT 2' }

function Get-SlotLabel([string]$slot) {
    if ($slotLabels.ContainsKey($slot)) { return $slotLabels[$slot] }
    if ($slot -match '^Talisman(\d)$') { return "TALISMAN $($Matches[1])" }
    if ($slot -match '^Spell(\d+)$') { return "MEMORY $($Matches[1])" }
    $slot
}

function Get-SlotCategory([string]$slot) {
    if ($slot -match '^(R|L|Arrow|Bolt)\d$') { 'weapon' } elseif ($slot -in 'Head','Chest','Arms','Legs') { 'armor' } elseif ($slot -like 'Talisman*') { 'talisman' } elseif ($slot -like 'Spell*') { 'goods' } else { '' }
}

function New-SlotTile([string]$slot) {
    $entry = if ($State.plan -and $State.plan.loadout) { $State.plan.loadout.$slot } else { $null }
    $bad = if ($State.plan) { @($State.plan.items | Where-Object { $_.unresolved -and $_.slot -eq $slot } | Select-Object -First 1)[0] } else { $null }
    $b = New-Object Windows.Controls.Border
    $b.Width = 176; $b.Height = 66; $b.CornerRadius = 8; $b.Margin = '0,0,10,10'; $b.Padding = '11,8'; $b.Cursor = 'Hand'; $b.BorderThickness = 1; $b.Tag = $slot
    $b.Background = if ($bad) { $C.errBg } elseif ($entry) { $C.panel2 } else { $C.empty }
    $b.BorderBrush = if ($State.target -eq $slot) { $C.gold } elseif ($bad) { $C.err } elseif ($entry) { $C.goldDim } else { $C.line }
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text (Get-SlotLabel $slot) $C.muted 10 'SemiBold'))
    if ($entry) {
        [void]$sp.Children.Add((New-Text $entry.name $C.text 13 'SemiBold'))
        $row = $State.rows[[int]$entry.rowIndex]
        $sub = @(); if ($entry.upgrade) { $sub += "+$($entry.upgrade)" }; if ($row -and $row.ashOfWar) { $sub += $row.ashOfWar }
        if ($sub.Count) { [void]$sp.Children.Add((New-Text ($sub -join ' · ') $C.gold 11)) }
        $b.ToolTip = "$($entry.name)  [$($entry.category) $($entry.itemId)]"
    } elseif ($bad) {
        [void]$sp.Children.Add((New-Text $bad.requestedName $C.err 13 'SemiBold'))
        [void]$sp.Children.Add((New-Text 'not found in catalog' $C.err 11))
    } else { [void]$sp.Children.Add((New-Text 'Empty' (Brush '#4A4D55') 12)) }
    $b.Child = $sp
    $b.Add_MouseLeftButtonUp({ param($s, $e) Select-Target $s.Tag })
    $b
}

function Update-Equipment {
    $ui.EquipPanel.Children.Clear()
    $groups = [ordered]@{}; foreach ($k in $slotGroups.Keys) { $groups[$k] = $slotGroups[$k] }
    $spells = @(1..14 | Where-Object { $State.plan -and $State.plan.loadout."Spell$_" } | ForEach-Object { "Spell$_" })
    $nextSpell = @(1..14 | Where-Object { -not ($State.plan -and $State.plan.loadout."Spell$_") } | Select-Object -First 1)
    if ($nextSpell.Count) { $spells += "Spell$($nextSpell[0])" }
    $groups['Spells'] = $spells
    foreach ($g in $groups.Keys) {
        [void]$ui.EquipPanel.Children.Add(($t = New-Text $g.ToUpperInvariant() $C.muted 11 'SemiBold')); $t.Margin = '0,4,0,6'
        $wrap = New-Object Windows.Controls.WrapPanel
        foreach ($slot in $groups[$g]) { [void]$wrap.Children.Add((New-SlotTile $slot)) }
        [void]$ui.EquipPanel.Children.Add($wrap)
    }
}

function Update-Inventory {
    $ui.InventoryPanel.Children.Clear()
    if (-not $State.plan) { return }
    $equipped = @{}; foreach ($p in $State.plan.loadout.psobject.Properties) { $equipped[[int]$p.Value.rowIndex] = $true }
    $shown = 0
    foreach ($it in $State.plan.items) {
        if ($equipped.ContainsKey([int]$it.rowIndex) -or ($it.unresolved -and $it.slot -and $it.slot -ne 'Inventory')) { continue }
        $shown++
        $chip = New-Object Windows.Controls.Border
        $chip.CornerRadius = 14; $chip.Padding = '11,5,6,5'; $chip.Margin = '0,0,8,8'; $chip.BorderThickness = 1; $chip.Cursor = 'Hand'; $chip.Tag = [int]$it.rowIndex
        $chip.Background = if ($it.unresolved) { $C.errBg } else { $C.panel2 }
        $chip.BorderBrush = if ($it.unresolved) { $C.err } elseif ($State.editRow -eq [int]$it.rowIndex) { $C.gold } else { $C.line }
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $label = if ($it.unresolved) { $it.requestedName } else { $it.name }
        if ([int]$it.quantity -gt 1) { $label += "  ×$($it.quantity)" }
        if ($it.upgrade -and [int]$it.upgrade -gt 0) { $label += "  +$($it.upgrade)" }
        [void]$sp.Children.Add((New-Text $label $(if ($it.unresolved) { $C.err } else { $C.text }) 12.5))
        $x = New-Object Windows.Controls.Button; $x.Content = '×'; $x.Padding = '6,0'; $x.Margin = '6,0,0,0'; $x.Background = [Windows.Media.Brushes]::Transparent; $x.BorderBrush = [Windows.Media.Brushes]::Transparent; $x.Foreground = $C.muted; $x.Tag = [int]$it.rowIndex; $x.ToolTip = 'Remove from build'
        $x.Add_Click({ param($s, $e) $e.Handled = $true; Remove-Row ([int]$s.Tag) })
        [void]$sp.Children.Add($x)
        $chip.Child = $sp
        $chip.Add_MouseLeftButtonUp({ param($s, $e) Edit-Row ([int]$s.Tag) })
        [void]$ui.InventoryPanel.Children.Add($chip)
    }
    if (-not $shown) { [void]$ui.InventoryPanel.Children.Add((New-Text 'Consumables, materials and spare gear appear here.' $C.muted 12)) }
}

function Update-Issues {
    $ui.IssuesPanel.Children.Clear()
    if (-not $State.plan) { return }
    $bad = @($State.plan.items | Where-Object unresolved)
    $ui.IssuesTitle.Text = if ($bad.Count) { "RESOLUTION · $($bad.Count) need attention" } else { "RESOLUTION · all $(@($State.plan.items).Count) items matched" }
    foreach ($it in $bad) {
        $box = New-Object Windows.Controls.StackPanel; $box.Margin = '0,0,0,8'
        $t = New-Text "✗ $($it.requestedName)" $C.err 12.5 'SemiBold'; $t.TextWrapping = 'Wrap'; [void]$box.Children.Add($t)
        if ($it.ashOfWar -and $it.itemId) { [void]$box.Children.Add((New-Text "Ash of War '$($it.ashOfWar)' not found" $C.muted 11.5)) }
        $wrap = New-Object Windows.Controls.WrapPanel
        foreach ($sug in @($it.suggestions | Select-Object -First 4)) {
            $btn = New-Object Windows.Controls.Button; $btn.Content = $sug; $btn.Style = $w.FindResource('Link'); $btn.Tag = @([int]$it.rowIndex, $sug)
            $btn.Add_Click({ param($s, $e) $r = $State.rows[$s.Tag[0]]; $r.name = $s.Tag[1]; Set-Dirty; Set-Status "Replaced with $($s.Tag[1])" })
            [void]$wrap.Children.Add($btn)
        }
        $rm = New-Object Windows.Controls.Button; $rm.Content = 'remove'; $rm.Style = $w.FindResource('Link'); $rm.Foreground = $C.muted; $rm.Tag = [int]$it.rowIndex
        $rm.Add_Click({ param($s, $e) Remove-Row ([int]$s.Tag) })
        [void]$wrap.Children.Add($rm)
        [void]$box.Children.Add($wrap)
        [void]$ui.IssuesPanel.Children.Add($box)
    }
    foreach ($n in @($State.plan.notes)) { $t = New-Text "• $n" $C.muted 11.5; $t.TextWrapping = 'Wrap'; $t.Margin = '0,0,0,4'; [void]$ui.IssuesPanel.Children.Add($t) }
    foreach ($i in @($State.plan.issues | Where-Object { $_ -match '^Invalid' })) { $t = New-Text "✗ $i" $C.err 12; [void]$ui.IssuesPanel.Children.Add($t) }
}

function Update-Level {
    $vals = @($script:BuildAttributeKeys | ForEach-Object { $v = 0; if ([int]::TryParse([string]$State.stats[$_], [ref]$v)) { $v } })
    $ui.LevelText.Text = if ($vals.Count -eq 8) { "Rune level $(($vals | Measure-Object -Sum).Sum - 79)" } else { 'Blank attributes keep the character''s current values' }
}

function Update-View {
    $State.plan = Resolve-BuildPlan (Get-BuildObject) $catalog
    Update-Level; Update-Equipment; Update-Inventory; Update-Issues
}

# ---------------------------------------------------------------- editing

function Remove-Row([int]$i) {
    if ($i -lt 0 -or $i -ge $State.rows.Count) { return }
    $name = $State.rows[$i].name; $State.rows.RemoveAt($i); $State.editRow = $null
    Set-Dirty; Set-Status "Removed $name"
}

function Edit-Row([int]$i) {
    $r = $State.rows[$i]; $State.editRow = $i; $State.target = $null
    $ui.PickerTitle.Text = 'Edit inventory item'; $ui.PickerSub.Text = 'Change quantity/upgrade, or search to replace it'
    $ui.PlaceBtn.Content = 'Update'; $ui.ClearSlotBtn.Visibility = 'Collapsed'
    $State.selected = $null
    $ui.SelectedName.Text = $r.name; $ui.QtyInput.Text = [string]$r.quantity; $ui.UpgradeInput.Text = [string]$r.upgrade; $ui.AshInput.Text = [string]$r.ashOfWar
    $ui.UpgradeBox.Visibility = if ($r.category -eq 'weapon') { 'Visible' } else { 'Hidden' }
    $ui.AshBox.Visibility = if ($r.category -eq 'weapon') { 'Visible' } else { 'Collapsed' }
    Update-Equipment; Update-Inventory
}

function Select-Target($slot) {
    $State.target = $slot; $State.editRow = $null; $State.selected = $null
    if ($slot) {
        $entry = $State.plan.loadout.$slot
        $ui.PickerTitle.Text = Get-SlotLabel $slot
        $ui.PickerSub.Text = if ($entry) { "Equipped: $($entry.name)" } else { 'Empty slot — search to equip' }
        $ui.PlaceBtn.Content = 'Equip'; $ui.ClearSlotBtn.Visibility = if ($entry) { 'Visible' } else { 'Collapsed' }
        $cat = Get-SlotCategory $slot
        foreach ($chip in $ui.CategoryChips.Children) { $chip.IsChecked = ([string]$chip.Tag -eq $cat) }
        if ($entry) { $row = $State.rows[[int]$entry.rowIndex]; $ui.UpgradeInput.Text = [string]$row.upgrade; $ui.AshInput.Text = [string]$row.ashOfWar; $ui.SelectedName.Text = $entry.name }
        else { $ui.SelectedName.Text = 'Nothing selected'; $ui.UpgradeInput.Text = '0'; $ui.AshInput.Text = '' }
        $ui.QtyInput.Text = '1'
        $ui.SearchBox.Focus() | Out-Null
    } else {
        $ui.PickerTitle.Text = 'Add to inventory'; $ui.PickerSub.Text = "Search $($catalog.Count.ToString('N0')) catalog items — or click a slot"
        $ui.PlaceBtn.Content = 'Add'; $ui.ClearSlotBtn.Visibility = 'Collapsed'; $ui.SelectedName.Text = 'Nothing selected'
        $ui.UpgradeInput.Text = '0'; $ui.QtyInput.Text = '1'; $ui.AshInput.Text = ''
    }
    Update-PickerFields
    Update-Equipment; Update-Inventory
    Invoke-Search
}

function Update-PickerFields {
    $cat = if ($State.selected) { $State.selected.category } elseif ($State.target) { Get-SlotCategory $State.target } elseif ($null -ne $State.editRow) { $State.rows[$State.editRow].category } else { '' }
    $ui.UpgradeBox.Visibility = if ($cat -eq 'weapon' -or -not $cat) { 'Visible' } else { 'Hidden' }
    $ui.AshBox.Visibility = if ($cat -eq 'weapon' -or -not $cat) { 'Visible' } else { 'Collapsed' }
}

function Test-FitsSlot($result, [string]$slot) {
    if (-not $slot) { return $true }
    $cat = Get-SlotCategory $slot
    if ($result.category -ne $cat) { return $false }
    switch -regex ($slot) {
        '^(Head|Chest|Arms|Legs)$' { return (@('Head','Chest','Arms','Legs')[[int](([long]$result.itemId % 1000) / 100) % 4] -eq $slot) }
        '^Arrow' { return $result.weaponClass -eq 'arrow' }
        '^Bolt' { return $result.weaponClass -eq 'bolt' }
        '^[RL]\d' { return $result.weaponClass -notin @('arrow','bolt') }
        '^Spell' { return (Test-SpellId ([long]$result.itemId)) }
    }
    $true
}

function Invoke-Search {
    $q = $ui.SearchBox.Text.Trim()
    if (-not $q) { $ui.Results.ItemsSource = $null; return }
    $found = @(Search-Catalog $catalog $q $State.category 250 | Where-Object { Test-FitsSlot $_ $State.target } | Select-Object -First 60)
    $ui.Results.ItemsSource = @($found | ForEach-Object { $_ | Add-Member -NotePropertyName Meta -NotePropertyValue ('{0} · {1}' -f $_.category, $_.itemId) -PassThru })
    if ($found.Count) { $ui.Results.SelectedIndex = 0 }
}

function Invoke-Place {
    $upgrade = 0; [void][int]::TryParse($ui.UpgradeInput.Text, [ref]$upgrade)
    $qty = 1; [void][int]::TryParse($ui.QtyInput.Text, [ref]$qty); if ($qty -lt 1) { $qty = 1 }
    $ash = $ui.AshInput.Text.Trim()
    if ($null -ne $State.editRow) {
        $r = $State.rows[$State.editRow]
        if ($State.selected) { $r.category = $State.selected.category; $r.name = $State.selected.name }
        $r.quantity = $qty; $r.upgrade = $(if ($r.category -eq 'weapon') { $upgrade } else { 0 }); $r.ashOfWar = $(if ($r.category -eq 'weapon') { $ash } else { '' })
        Set-Dirty; Set-Status "Updated $($r.name)"; return
    }
    if ($State.target) {
        $entry = $State.plan.loadout.($State.target)
        if (-not $State.selected -and $entry) {
            # Only the upgrade / Ash of War of the equipped item changed.
            $r = $State.rows[[int]$entry.rowIndex]; $r.upgrade = $upgrade; $r.ashOfWar = $ash; Set-Dirty; Set-Status "Updated $($r.name)"; return
        }
        if (-not $State.selected) { Set-Status 'Pick an item from the results first.'; return }
        # The previous occupant stays in the build as an unequipped inventory item.
        foreach ($r in $State.rows) { if ($r.slot -eq $State.target) { $r.slot = 'Inventory' } }
        if ($entry) { $State.rows[[int]$entry.rowIndex].slot = 'Inventory' }
        $cat = $State.selected.category
        [void]$State.rows.Add((New-BuildRow $cat $State.selected.name $(if ($cat -eq 'weapon') { $upgrade } else { 0 }) 1 $(if ($cat -eq 'weapon') { $ash } else { '' }) $State.target))
        $slot = $State.target; Set-Dirty; Set-Status "Equipped $($State.selected.name) in $(Get-SlotLabel $slot)"; Select-Target $slot; return
    }
    if (-not $State.selected) { Set-Status 'Pick an item from the results first.'; return }
    $cat = $State.selected.category
    $slot = if ($cat -eq 'goods' -and (Test-SpellId ([long]$State.selected.itemId))) { '' } elseif ($cat -in 'goods','ash') { '' } else { 'Inventory' }
    [void]$State.rows.Add((New-BuildRow $cat $State.selected.name $(if ($cat -eq 'weapon') { $upgrade } else { 0 }) $qty $(if ($cat -eq 'weapon') { $ash } else { '' }) $slot))
    Set-Dirty; Set-Status "Added $($State.selected.name)"
}

# ---------------------------------------------------------------- game application

function Update-Connection {
    try { $s = Get-BuildBackendStatus -Root $root } catch { $s = $null }
    $State.backend = $s
    if (-not $s -or -not $s.gameRunning) { $ui.ConnDot.Fill = $C.muted; $ui.ConnText.Text = 'Game not running' }
    elseif ($s.eacRunning) { $ui.ConnDot.Fill = $C.err; $ui.ConnText.Text = 'EAC active — start offline' }
    elseif ($s.ready) { $ui.ConnDot.Fill = $C.ok; $ui.ConnText.Text = "Connected · Lv $($s.level)" }
    elseif ($s.needsElevation) { $ui.ConnDot.Fill = $C.gold; $ui.ConnText.Text = 'Click to connect as admin' }
    elseif ($s.message -like 'Cannot attach*') { $ui.ConnDot.Fill = $C.err; $ui.ConnText.Text = 'Cannot attach' }
    else { $ui.ConnDot.Fill = $C.warn; $ui.ConnText.Text = 'Load your character' }
    $ui.ConnText.ToolTip = if ($s) { "$($s.message)$(if ($s.gameVersion) { "`nGame $($s.gameVersion)" })" } else { $null }
}

# The game was started as administrator, so only an elevated Studio can open it. Save and reopen elevated.
function Restart-Elevated {
    if ($State.dirty) { [void](Save-Current); $State.dirty = $false }
    Save-Settings
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', "`"$root\BuildStudio.ps1`"")
    if ($State.path) { $argList += @('-Preset', "`"$($State.path)`"") }
    try { Start-Process (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -ArgumentList $argList; $w.Close() }
    catch { Set-Status 'Administrator approval was declined; the game cannot be reached without it.' }
}

function Invoke-Apply([switch]$Force) {
    $json = Get-BuildObject | ConvertTo-Json -Depth 8
    if (-not $Force -and $json -eq $State.lastApplied) { return }
    if (@($State.plan.issues | Where-Object { $_ -match '^Invalid attribute' }).Count) { Set-Status 'Fix invalid attributes before applying.'; return }
    Update-Connection
    $s = $State.backend
    if (-not $s -or -not $s.gameRunning) { Set-Status 'Start Elden Ring in offline mode, load your character, then apply.'; return }
    if ($s.needsElevation) { Restart-Elevated; return }
    if (-not $s.ready) { Set-Status $s.message; return }
    Set-Status 'Applying to game…'
    # Let WPF paint the status before the (short) blocking apply.
    $w.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
    try {
        $result = Invoke-BuildPlan -Plan $State.plan -Root $root
        if ($result.ok) { $State.lastApplied = $json }
        $skipped = @($State.plan.items | Where-Object unresolved).Count
        Set-Status ("{0}{1}{2}" -f $(if ($result.applied) { 'Applied ✓ ' } elseif ($result.ok) { 'Partly applied: ' } else { '' }), $result.message, $(if ($skipped) { " · $skipped unresolved row(s) skipped" } else { '' }))
        $ui.StatusText.ToolTip = ($result.lines -join "`n")
    } catch { Set-Status "Apply failed: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- wiring

$searchTimer = New-Object Windows.Threading.DispatcherTimer; $searchTimer.Interval = [TimeSpan]::FromMilliseconds(120)
$searchTimer.Add_Tick({ $searchTimer.Stop(); Invoke-Search })
$ui.SearchBox.Add_TextChanged({ $searchTimer.Stop(); $searchTimer.Start() })
$ui.SearchBox.Add_PreviewKeyDown({ param($s, $e)
    if ($e.Key -eq 'Down' -and $ui.Results.Items.Count) { $ui.Results.SelectedIndex = [math]::Min($ui.Results.Items.Count - 1, $ui.Results.SelectedIndex + 1); $ui.Results.ScrollIntoView($ui.Results.SelectedItem); $e.Handled = $true }
    elseif ($e.Key -eq 'Up' -and $ui.Results.Items.Count) { $ui.Results.SelectedIndex = [math]::Max(0, $ui.Results.SelectedIndex - 1); $ui.Results.ScrollIntoView($ui.Results.SelectedItem); $e.Handled = $true }
    elseif ($e.Key -eq 'Enter') { Invoke-Place; $e.Handled = $true }
    elseif ($e.Key -eq 'Escape') { $ui.SearchBox.Text = ''; Select-Target $null; $e.Handled = $true } })
foreach ($chip in $ui.CategoryChips.Children) { $chip.Add_Checked({ param($s, $e) $State.category = [string]$s.Tag; Invoke-Search }) }
$ui.Results.Add_SelectionChanged({
    $State.selected = $ui.Results.SelectedItem
    if ($State.selected) { $ui.SelectedName.Text = "$($State.selected.name)"; Update-PickerFields }
})
$ui.Results.Add_MouseDoubleClick({ Invoke-Place })
$ui.PlaceBtn.Add_Click({ Invoke-Place })
$ui.ClearSlotBtn.Add_Click({
    if (-not $State.target) { return }
    $entry = $State.plan.loadout.($State.target)
    if ($entry) { $State.rows[[int]$entry.rowIndex].slot = 'Inventory'; $slot = $State.target; Set-Dirty; Set-Status "Unequipped $($entry.name) (kept in inventory)"; Select-Target $slot }
})

$ui.BuildName.Add_TextChanged({ if ($State.loading) { return }; $State.name = $ui.BuildName.Text; $State.dirty = $true; $State.changedAt = [datetime]::UtcNow })
$ui.PresetFilter.Add_TextChanged({ Update-PresetList $State.path })
$ui.PresetList.Add_SelectionChanged({ if ($State.loading) { return }; $it = $ui.PresetList.SelectedItem; if ($it -and $it.Path -ne $State.path) { if ($State.dirty) { [void](Save-Current); $State.dirty = $false }; Open-Preset $it.Path } })
$ui.NewBtn.Add_Click({ if ($State.dirty) { [void](Save-Current); $State.dirty = $false }; Import-BuildObject ([pscustomobject]@{ name = 'New build'; items = @(); attributes = @{} }) $null; $ui.PresetList.SelectedItem = $null; $ui.BuildName.Focus() | Out-Null; $ui.BuildName.SelectAll(); Set-Status 'New build. Click a slot to start equipping.' })
$ui.FolderBtn.Add_Click({ Start-Process explorer.exe $dir })
# Clipboard import: the line format from the Gemini prompt, or preset JSON. Each distinct text is imported once.
function Get-TextHash([string]$t) { [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t))) }
function Import-FromClipboard([switch]$Quiet) {
    try { $text = [Windows.Clipboard]::GetText() } catch { return }
    if (-not (Test-BuildText $text)) { if (-not $Quiet) { Set-Status 'Clipboard has no build. Copy the chat answer (BUILD: … lines or preset JSON) first.' }; return }
    $hash = Get-TextHash $text
    if ($Quiet -and $hash -eq $State.lastClipboardHash) { return }
    $State.lastClipboardHash = $hash; Save-Settings
    $b = ConvertFrom-BuildText $text
    if (-not $b) { Set-Status 'Could not read a build from the clipboard text.'; return }
    if ($State.dirty) { [void](Save-Current); $State.dirty = $false }
    Import-BuildObject $b $null
    [void](Save-Current)
    $ui.SourceText.Text = "Imported from clipboard · " + [IO.Path]::GetFileName($State.path)
    $ok = @($State.plan.items | Where-Object { -not $_.unresolved }).Count
    Set-Status "Imported '$($State.name)' from clipboard — $ok of $(@($State.plan.items).Count) items matched$(if ($ok -lt @($State.plan.items).Count) { '; fix the red ones on the right' })."
}
$ui.PasteBtn.Add_Click({ Import-FromClipboard })
$ui.PromptBtn.Add_Click({
    [Windows.Clipboard]::SetText($script:GeminiPrompt)
    Set-Status 'Prompt copied. On YouTube press "Ask" (✦), paste it, send, then copy Gemini''s answer — Build Studio imports it when you come back.'
})
$ui.ApplyBtn.Add_Click({ if ($State.dirty) { [void](Save-Current); $State.dirty = $false }; Update-Connection; Invoke-Apply -Force })
$ui.ConnChip.Cursor = [Windows.Input.Cursors]::Hand
$ui.ConnChip.Add_MouseLeftButtonUp({ if ($State.backend -and $State.backend.needsElevation) { Restart-Elevated } })
$ui.AutoApply.Add_Click({ Save-Settings; if ($ui.AutoApply.IsChecked) { Set-Status 'Auto-apply on: changes are sent to the running offline game automatically.' } })

$saveTimer = New-Object Windows.Threading.DispatcherTimer; $saveTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$saveTimer.Add_Tick({
    try {
        if ($State.dirty -and (([datetime]::UtcNow - $State.changedAt).TotalMilliseconds -ge 800)) {
            $State.dirty = $false
            if ($State.name -ne $State.plan.name) { Update-View }
            $isBlank = ($State.rows.Count -eq 0 -and $State.stats.Values.Where({ $_ }).Count -eq 0)
            if (-not $isBlank -and (Save-Current)) { if ($ui.AutoApply.IsChecked) { Invoke-Apply } }
        }
    } catch { Set-Status $_.Exception.Message }
})
$pollTimer = New-Object Windows.Threading.DispatcherTimer; $pollTimer.Interval = [TimeSpan]::FromSeconds(2)
$pollTimer.Add_Tick({ try { Update-Connection } catch { } })
$w.Add_Closed({ $saveTimer.Stop(); $pollTimer.Stop(); if ($State.dirty) { try { [void](Save-Current) } catch { } }; Save-Settings })

# ---------------------------------------------------------------- start

$settings = $null; try { if (Test-Path $settingsPath) { $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json } } catch { }
$ui.AutoApply.IsChecked = [bool]$settings.autoApply
$State.lastClipboardHash = [string]$settings.lastClipboardHash
Update-PresetList $null
$startPath = if ($Preset) { $Preset } elseif ($settings.lastPreset -and (Test-Path -LiteralPath $settings.lastPreset)) { $settings.lastPreset } else { $null }
if ($startPath) { Open-Preset $startPath; Update-PresetList $startPath } else { Import-BuildObject ([pscustomobject]@{ name = 'New build'; items = @(); attributes = @{} }) $null }
Update-Connection

if ($CheckOnly) {
    $filled = @($State.plan.loadout.psobject.Properties).Count
    "UI XAML and catalog loaded successfully; preset='$($State.name)' items=$(@($State.plan.items).Count) equipped=$filled"
    $w.Close(); return
}
$saveTimer.Start(); $pollTimer.Start()
$State.focused = $false
$w.Add_Activated({ if (-not $State.focused) { $State.focused = $true; [Windows.Input.Keyboard]::Focus($ui.SearchBox) | Out-Null }; Import-FromClipboard -Quiet })
# Ctrl+V anywhere outside a text box imports a copied build.
$w.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'V' -and [Windows.Input.Keyboard]::Modifiers -eq 'Control' -and -not ([Windows.Input.Keyboard]::FocusedElement -is [Windows.Controls.TextBox])) { Import-FromClipboard; $e.Handled = $true } })
[void]$w.ShowDialog()
