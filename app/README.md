# Elden Ring Offline Build Configurator

Yerel ve çevrimdışı bir build planlayıcısıdır. Link/metin yalnızca veri olarak işlenir; dışarıdan içerik indirmez. Hexinton tabloları sadece arşiv adı, SHA-256 ve okunabilir kayıt adı manifesti için incelenmiştir. Cheat Engine, Lua, tablo veya oyun belleği çalıştırılmaz.

## Çalıştırma

Masaüstündeki `Elden Ring Build Configurator` kısayoluna çift tıklayın. Panel ayrı bir Windows penceresi olarak açılır; tarayıcı ve Cheat Engine penceresi gösterilmez.

Chatten bir build linki gönderildiğinde Codex, `configs/` klasörüne şema uyumlu preset JSON'u oluşturur. Panelde bu preset açılır, düzenlenir ve compile edilir. Compile yalnız aktif `eldenring.exe`yi tespit ettikten sonra v8.0.1 Hexinton tablosunu gizli başlatıp config'i aşamalar; henüz oyun belleğine item/stat yazmaz.

Ardından `http://127.0.0.1:8765` adresini açın. Python 3.9+ yeterlidir; harici paket yoktur.

## Güvenlik sınırı

Apply düğmesi doğrulanmış capability manifesti bulunmadığı için kilitlidir. Uygulama save dosyasına, oyun belleğine, Cheat Engine'e veya DRM/EAC davranışına dokunmaz. Gerçek uygulama için oyun kapalıyken timestamp'li save yedeği, sürüm doğrulaması ve kullanıcı onayı olan ayrı bir backend gerekir.

Build veri sözleşmesi `build.schema.json`, tekrar kullanılabilir import kuralları ise `BUILD_IMPORT.md` içindedir.
