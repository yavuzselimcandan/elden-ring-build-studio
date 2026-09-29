# Turning chat output (YouTube "Ask" / Gemini, ChatGPT, ...) into a preset.
# Two inputs are accepted: the line format below (preferred: robust to chat formatting) and preset JSON.

# Short on purpose: it has to fit comfortably in YouTube's "Ask about this video" box.
$script:GeminiPrompt = @'
Extract the Elden Ring build shown in this video. Reply ONLY in this exact format, one entry per line, official English item names, no other text:
BUILD: <build name>
STATS: VIG n, MIND n, END n, STR n, DEX n, INT n, FAI n, ARC n
R1: <weapon> +<upgrade> | Ash: <ash of war>
R2: ... (same for R3, L1, L2, L3)
HEAD: <armor>
CHEST: <armor>
ARMS: <armor>
LEGS: <armor>
TALISMAN: <talisman> (one line each)
SPELL: <spell> (one line each)
ITEM: <item> xN
Skip anything the video does not show. Do not guess.
'@

$script:BuildTextSlots = [ordered]@{
    'R1' = @('weapon', 'R1'); 'R2' = @('weapon', 'R2'); 'R3' = @('weapon', 'R3'); 'L1' = @('weapon', 'L1'); 'L2' = @('weapon', 'L2'); 'L3' = @('weapon', 'L3')
    'RIGHT1' = @('weapon', 'R1'); 'RIGHT2' = @('weapon', 'R2'); 'RIGHT3' = @('weapon', 'R3'); 'LEFT1' = @('weapon', 'L1'); 'LEFT2' = @('weapon', 'L2'); 'LEFT3' = @('weapon', 'L3')
    'WEAPON' = @('weapon', ''); 'SHIELD' = @('weapon', ''); 'CATALYST' = @('weapon', ''); 'SEAL' = @('weapon', ''); 'STAFF' = @('weapon', '')
    'ARROW' = @('weapon', ''); 'ARROWS' = @('weapon', ''); 'BOLT' = @('weapon', ''); 'BOLTS' = @('weapon', ''); 'AMMO' = @('weapon', '')
    'HEAD' = @('armor', 'Head'); 'HELM' = @('armor', 'Head'); 'HELMET' = @('armor', 'Head'); 'CHEST' = @('armor', 'Chest'); 'BODY' = @('armor', 'Chest'); 'ARMOR' = @('armor', '')
    'ARMS' = @('armor', 'Arms'); 'GAUNTLETS' = @('armor', 'Arms'); 'HANDS' = @('armor', 'Arms'); 'LEGS' = @('armor', 'Legs'); 'GREAVES' = @('armor', 'Legs')
    'TALISMAN' = @('talisman', ''); 'TALISMANS' = @('talisman', '')
    'SPELL' = @('goods', ''); 'SPELLS' = @('goods', ''); 'SORCERY' = @('goods', ''); 'INCANTATION' = @('goods', '')
    'ITEM' = @('goods', 'Inventory'); 'ITEMS' = @('goods', 'Inventory'); 'CONSUMABLE' = @('goods', 'Inventory'); 'TEAR' = @('goods', 'Inventory'); 'PHYSICK' = @('goods', 'Inventory'); 'SPIRIT' = @('goods', 'Inventory'); 'ASHES' = @('goods', 'Inventory')
}
$script:BuildTextStats = @{ VIG = 'vig'; VIGOR = 'vig'; MIND = 'mind'; MND = 'mind'; END = 'end'; ENDURANCE = 'end'; STR = 'str'; STRENGTH = 'str'; DEX = 'dex'; DEXTERITY = 'dex'; INT = 'int'; INTELLIGENCE = 'int'; FAI = 'fai'; FAITH = 'fai'; ARC = 'arc'; ARCANE = 'arc' }

function Invoke-Invariant([scriptblock]$Block) {
    # Case-insensitive regex follows the current culture; under tr-TR "I" does not match "i".
    $thread = [Threading.Thread]::CurrentThread; $old = $thread.CurrentCulture
    $thread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
    try { & $Block } finally { $thread.CurrentCulture = $old }
}

function Test-BuildText([string]$Text) { Invoke-Invariant { Test-BuildTextCore $Text } }
function ConvertFrom-BuildText([string]$Text) { Invoke-Invariant { ConvertFrom-BuildTextCore $Text } }

function Test-BuildTextCore([string]$Text) {
    if (-not $Text) { return $false }
    return ($Text -match '(?im)^\W*BUILD\s*:' -and $Text -match '(?im)^\W*(R[123]|L[123]|HEAD|CHEST|TALISMAN|STATS)\W*[:\-]') -or ($Text -match '"items"\s*:' -or $Text -match '"equipment"\s*:')
}

# Returns a preset object (schema 3.0) or $null when the text is not a build.
function ConvertFrom-BuildTextCore([string]$Text) {
    if (-not $Text) { return $null }
    $clean = $Text -replace "[‘’]", "'" -replace "[“”]", '"' -replace " ", ' '

    # JSON (possibly inside a ``` fence, possibly with trailing commas)
    $json = $clean
    if ($json -match '(?s)```(?:json)?\s*(\{.*\})\s*```') { $json = $Matches[1] }
    elseif ($json -match '(?s)(\{.*\})') { $json = $Matches[1] }
    if ($json -match '"(items|equipment)"\s*:') {
        try {
            $b = ($json -replace ',\s*([\]}])', '$1') | ConvertFrom-Json
            if ($b.items -or $b.equipment) { if (-not $b.name) { $b | Add-Member -NotePropertyName name -NotePropertyValue 'Imported build' -Force }; return $b }
        } catch { }
    }

    # Line format
    $name = $null; $attrs = [ordered]@{}; $items = New-Object System.Collections.ArrayList
    foreach ($raw in ($clean -split "\r?\n")) {
        $line = ($raw -replace '\*\*|__|`', '' -replace '^\s*(?:[-*+>•]|\d+[.)])\s*', '').Trim()
        if ($line -notmatch '^([A-Za-z]+)\s*(\d)?\s*[:\-–]\s*(.+)$') { continue }
        $key = ($Matches[1] + $Matches[2]).ToUpperInvariant(); $value = $Matches[3].Trim()
        if ($value -match '^(\?|n/?a|none|unknown|-+|empty)$') { continue }
        if ($key -in 'BUILD', 'NAME', 'TITLE') { if (-not $name) { $name = $value }; continue }
        if ($key -in 'STATS', 'ATTRIBUTES', 'STAT') {
            foreach ($m in [regex]::Matches($value, '([A-Za-z]+)\s*[:=]?\s*(\d{1,2})\b')) {
                $k = $script:BuildTextStats[$m.Groups[1].Value.ToUpperInvariant()]
                if ($k) { $attrs[$k] = [int]$m.Groups[2].Value }
            }
            continue
        }
        if ($script:BuildTextStats.ContainsKey($key) -and $value -match '^\d{1,2}$') { $attrs[$script:BuildTextStats[$key]] = [int]$value; continue }
        $map = $script:BuildTextSlots[$key]
        if (-not $map) { continue }
        # "Talisman: A, B, C" or "Spells: A / B" lists
        $names = if ($map[1] -eq '' -and $map[0] -in 'talisman', 'goods') { @($value -split '\s*(?:,|;| / )\s*' | Where-Object { $_ }) } else { @($value) }
        foreach ($n in $names) {
            $ash = ''; $affinity = ''
            $parts = @($n -split '\s*\|\s*')
            $itemName = $parts[0].Trim()
            foreach ($extra in $parts | Select-Object -Skip 1) {
                if ($extra -match '^(?:ash(?: of war)?|aow|skill)\s*[:\-]\s*(.+)$') { $ash = $Matches[1].Trim() }
                elseif ($extra -match '^affinity\s*[:\-]\s*(.+)$') { $affinity = $Matches[1].Trim() }
            }
            if ($ash -match '^(\?|none|n/?a|default|unknown)$') { $ash = '' }
            [void]$items.Add([pscustomobject]@{ category = $map[0]; name = $itemName; ashOfWar = $ash; affinity = $affinity; slot = $map[1] })
        }
    }
    if ($items.Count -eq 0 -and $attrs.Count -eq 0) { return $null }
    [pscustomobject]@{
        schemaVersion = '3.0'; name = $(if ($name) { $name } else { 'Imported build' })
        source = [pscustomobject]@{ url = ''; evidence = 'Imported from chat text'; unresolved = @() }
        attributes = $attrs; items = @($items)
    }
}
