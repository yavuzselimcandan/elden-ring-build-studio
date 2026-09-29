$ErrorActionPreference = 'Stop'
$line = 'entry0=rawID:1073741939,quantity:1'
if($line -notmatch '^entry\d+=rawID:(\d+),quantity:(\d+)$'){throw 'inventory line parse failed'}
$raw=[uint32]$Matches[1];$id=$raw -band 0x0FFFFFFF;$kind=$raw -shr 28
if($kind -ne 4 -or $id -ne 115){throw "inventory decode failed: kind=$kind id=$id"}
$weapon=[uint32](268435456 + 123);$weaponId=$weapon -band 0x0FFFFFFF
if(($weapon -shr 28) -ne 1 -or $weaponId -ne 123){throw 'armor decode failed'}
'Inventory decode smoke checks passed.'
