# MacPulse cihaz pilleri

Pil sekmesi (Cmd+6), menüde Piller, Cihaz ayarları ve widget düzenleyicisi (Cmd+Shift+W). PilBar referansı salt okunur; arayüz MacPulse’un ortak paletini/tercihlerini kullanır. Ana pencere Mac özeti ve cihaz kartları, menü kısa bir cihaz listesi gösterir.

| PilBar özelliği | MacPulse karşılığı |
| --- | --- |
| Mac dahili pil | Mevcut tek MetricSampler; Bu Mac ayrıntısı korunur |
| Bluetooth/AirPods/kutu | Mevcut 30 sn Bluetooth kaydı; sol/sağ minimumu, ayrı kutu, kaynak yaşı |
| Logitech MX | Salt okunur HID++ UNIFIED_BATTERY/BATTERY_STATUS; açık Giriş İzleme düğmesi |
| iPhone/iPad USB ve Wi-Fi | Native MobileDevice, mevcut libimobiledevice yedeği; yalnız güvenilmiş cihazlar |
| Watch | iPhone companion sorgusu; önceden kurulu yerel kütüphanelere dinamik bağlanan yardımcı |
| Pencil | iPad SpringBoard Pencil filtresi; en çok 64 KiB bellek, ham kayıt yok |
| Watt | Taze/tutarlı mobil net batarya akışı; eski/çevrimdışı/aksesuar verisinde gizli |
| AirPods gruplama | Ana kartta ayrı kutu satırı; menüde kutu yüzdesi alt bilgi, okla açılınca ayrı kutu satırı |
| Ad/favori/gizleme/sıra | Cihaz ayarları; sürükleme ve yukarı/aşağı, düşük pil önceliği |
| Menü cihazı ve yüzde | Her cihaz için ayrı widget; pil simgesi/yüzde/ikisi, kalıcı sıra |
| Geçmiş | 6 saat/24 saat/7 gün, odaklı/tam eksen, nokta seçimi, boşluklar korunur |
| Pil uyarıları | Cihaz eşiği, düşük/kritik/doldu, 5 puan histerezis, ses, yalnız yeni ölçüm |
| Tema/giriş öğesi | Ortak MacPulse tercihi; kompakt/rahat menü satırı ve yüzey yoğunluğu cihaz ayarında |
| Rehber/ayar bağlantısı | Paket içi rehber ve kullanıcı düğmeleri |
| Çevrimdışı liste temizliği | Kaynak geçmişi korunur; son temizleme Geri al ile döner |

PilBar'ın dört JSON dosyası ilk açılışta doğrulanır. Eksik MacPulse dosyaları kopyalanır, mevcut hedef dosyalar ve kaynak asla üzerine yazılmaz. Göç raporu kaynak hash'lerini ve adetleri tutar. Sistemin SQLite geçmişi değişmez. Kaynak ve hedef 7 günlük geçmiş aynı saklama sözleşmesini kullanır.

Yeni Swift Timer/döngü eklenmez. Mevcut sistem örneği Mac ve Bluetooth'u besler; aynı tick cihaz işleri için görünürken 15 sn, arka planda 60 sn kontrol eder. Yavaş mobil okumadan önce yerel sonuç yayınlanır. Duraklatma ve uyku canlı ölçümü keser; devam eski sayaçtan hız üretmez. Uygulamanın kendi okuyucuları iptal/çıkışta sınırlı sürede kapanır.

Ana Pil sayfasında Mac pili, güç kaynağı, kalan süre ve düşük güç modu üstte yer alır. Bağlı cihazlar pencere genişliğine uyarlanan kartlardadır; kartın yüzdesine tıklamak geçmişi, üç nokta cihaz işlemlerini açar. Mac pil ayrıntıları ve grafik ayrı bir açılır bölümdedir. Menüde cihaz ikonu, ad/bağlantı/şarj veya taze mobil watt bilgisi, hizalı yüzde ve ince pil çubuğu bulunur. Menü satırı geçmişi açar; sağ tık menüsünde widget, favori, düzenle ve gizle işlemleri vardır.

Eski cihazlar iki görünümde de kapalı “Son görülen cihazlar” bölümünden açılır. Bilinmeyen yüzde —, eski pil seviyesi nötr renkte ve ölçüm tarihiyle gösterilir; eski şarj/watt bilgisi güncelmiş gibi görünmez. AirPods kutusu ana kartta ayrı bir geçmiş satırıdır; menüde okla açılır. Ana sayfa kendi kaydırmasını kullanır; menü listesi ekran yüksekliğinde sınırlanır ve gerektiğinde dikey kaydırılır. Bağlantı açıklamaları ana sayfanın altındaki “Bağlantı bilgileri” düğmesindedir.

Üst çubuk seçilen tüm widget'ları tek satır görüntüler, yatay scroll yoktur. Normal genişlik yetmezse kısa etiket ve dar boşluk kullanılır; hâlâ çok genişse tüm çizim mevcut ekran bütçesine ölçeklenir. Çok fazla widget küçük görünebilir; düzenleyicide aynı sonuç görünür. Menüye tıklanınca Mac/AI/Piller özetleri; tam kullanım bilgisi ve pil geçmişi ayrı kart/pencerede açılır.

Kaynak bulunması her fiziksel cihaz için canlı kabul değildir. Mobil cihaz güveni, yerel ağ, OS sürümü ve aksesuar izni sonucu etkiler. Watt adaptör gücü değildir. Bluetooth sensör tazeliği garanti edilmez; eski ölçümün tarihi güncelmiş gibi değiştirilmez. Dağıtım hedefi yoktur; yalnız bu Mac için ad-hoc app.
