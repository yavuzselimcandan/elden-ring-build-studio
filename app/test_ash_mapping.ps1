$ErrorActionPreference = 'Stop'
$ct = 'C:\Users\YAVUZ-PC\Downloads\eldenring_all-in-one_Hexinton-v8.0.1.CT'
if (-not (Test-Path -LiteralPath $ct)) { throw 'Hexinton CT not found' }
$text = Get-Content -Raw -LiteralPath $ct
$m = [regex]::Match($text, 'ConvertAshofWarTable = \{(?<body>.*?)\n\}', 'Singleline')
$values = [regex]::Matches($m.Groups['body'].Value, '(?m)^\s*(-?\d+),?\s*$')
if ($values.Count -ne 92) { throw "expected 92 conversion values, got $($values.Count)" }
if ($values[0].Groups[1].Value -ne '-1' -or $values[91].Groups[1].Value -ne '2147494648') { throw 'conversion table endpoints changed' }
[xml]$xml = $text
$rec = $xml.SelectSingleNode('//CheatEntry[ID="22032404"]')
$rows = @($rec.DropDownList.'#text' -split "`n" | Where-Object { $_ -match ':' })
if ($rows.Count -ne 116) { throw "expected 116 Ash dropdown rows, got $($rows.Count)" }
if ($rows[0] -notmatch '^10000:') { throw 'first Ash row changed' }
if ($rows[110] -notmatch '^418000:.*Carian Sovereignty') { throw 'Carian Sovereignty row changed' }
'Ash conversion source check passed: 92 indexed values; 116 record rows are not treated as equivalent.'
