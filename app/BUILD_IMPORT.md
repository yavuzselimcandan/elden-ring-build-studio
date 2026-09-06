# Build import contract

1. Link/metin kullanıcı tarafından yapıştırılır; dışarıdan fetch yapılmaz.
2. Kayıtlar `build.schema.json` içindeki kategori, isim, seviye/miktar ve güven alanlarına dönüştürülür.
3. Belirsiz kayıtlar `unresolved` içine yazılır; onay olmadan planlanmaz.
4. Dry-run yalnızca planı gösterir. Capability manifesti doğrulanana kadar “Simulate Apply — verification required” kapalı kalır.
5. Hexinton/CT dosyaları yalnızca metadata/hash için referanslanır; Cheat Engine, CT/Lua, bellek, çevrimiçi mod veya DRM/EAC bypass çalıştırılmaz.

