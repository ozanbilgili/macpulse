# MacPulse yerel kullanım

MacPulse bu Mac'te çalışan bağımsız uygulamadır. Güncel uygulama proje kökündeki `MacPulse.app` dosyasıdır.

## Açma

Finder'da `MacPulse.app` dosyasına çift tıklayın veya proje klasöründe çalıştırın:

```sh
Scripts/launch.sh
```

Uygulama hesabı, sunucu veya yönetici yardımcısı gerektirmez. Sistem bildirimleri ve başlangıçta açılma tercihi varsayılan kapalıdır; her biri uygulama içindeki ayrı kullanıcı eylemiyle açılır.

## Güncelleme

Önce MacPulse'tan Cmd+Q ile çıkın. `SIGNING_MODE=adhoc Scripts/package_app.sh release` başarılı olunca yerel uygulama güncellenir. Mevcut tercihler ve 30 günlük geçmiş korunur; uygulama klasörünün yanında tutulmazlar. Daha yeni veya bozuk veritabanı otomatik silinmez; canlı ölçümler sürerken geçmiş hatası görünür. Ayrıntılar [yerel derleme](RELEASE.md) rehberindedir.

## Kullanım

Cmd+1…7 ana sekmeler; Cmd+8 geçmiş; Cmd+9 uyarılar; Cmd+Shift+B Bluetooth; Cmd+Shift+S ses; Cmd+Shift+U AI Kullanımı; Cmd+Shift+W menü çubuğu widget'ları; Cmd+Shift+M hızlı panel; Cmd+Shift+P duraklat/sürdür. Cmd+O ana pencere, Cmd+, tercihler, Cmd+Shift+H hakkında, Cmd+Q tam çıkış.

Menü çubuğunu Tercihler → Menü çubuğunu düzenle ile özelleştirin. Her metrik/hesap ayrı widget'tır; ekle/kaldır ve oklarla sırala. AI widget'larında limit, görünüm ve Kalan seçilir. Canlı önizleme anında güncellenir; kapatıp açınca düzen korunur. Yalnız simge bütün widget'ları kaldırır ve MacPulse simgesini bırakır. Hesaplar veya krediler okunamıyorsa seçili widget kaybolmaz, — gösterir.

Pencereyi kapatmak izlemeyi durdurmaz. Kayıt yalnız MacPulse çalışırken oluşur. `—` bilinmeyen ölçümdür; ilk örnek hız hesaplamak için başlangıçtır. CPU, GPU, güç ve pil ölçümlerinin kapsamları ekranlarda açıklanır. Bağlantısız/eski Bluetooth pili canlı değer olarak gösterilmez.
