# MacPulse veri kapsamı

MacPulse ölçümleri bu cihazda işler. Hesap, analitik, reklam, çökme gönderimi veya uygulama sunucusu yoktur. Manifestte `NSPrivacyCollectedDataTypes` boş olması yerel geçmiş tutulmadığı anlamına gelmez; veri başka tarafa toplanmak üzere gönderilmez.

AI Kullanımı mevcut Claude/Codex/OpenRouter oturumlarını salt okunur kullanarak ilgili sağlayıcıdan limit veya kredi sorgular. Bu isteklerde credential yalnız Authorization başlığına konur; yenilenmez, loglanmaz veya MacPulse tarafından kaydedilmez. Kullanım cache'i ve hesap adları Usage ile uyumludur. Claude transcript'leri token toplamı için yerelde okunur; yalnız sayılar, tekilleştirme ve dosya metadata'sı MacPulse'a özel dizinde saklanır. Mesaj içeriği ve sistem ölçümleri sağlayıcılara gönderilmez. Ayrıntılar [AI Kullanımı](AI-USAGE.md) rehberindedir.

Uygulama CPU/bellek/disk/ağ/pil/GPU/sensör ölçümleri ile erişilebilir mevcut kullanıcı süreç metadata'sını okur. Proje eşleme için çalışma dizinindeki proje işaretlerinin yalnız varlığı kontrol edilir; dosya içerikleri, süreç argümanları ve ortam değişkenleri okunmaz. Container API yalnız çalışan yerel motorda seçilmiş GET sorgularıdır. Bluetooth mevcut macOS envanteri, ses Core Audio cihaz özellikleridir; yeni eşleme ve ses kaydı yoktur.

SQLite 30 günlük dakika/gün özetleri, sınırlı uygulama adı/kimlik özetleri ve uyarılar içerir. Dosyalar mevcut kullanıcıya özel tutulur. Tam süreç envanteri, proje yolları/portlar, container, sensör, Bluetooth adresleri ve ses cihazları sistemin SQLite geçmişine eklenmez. Cihaz pilleri için ayrı özel JSON deposu cihaz kimliği/adı/bağlantı türü/son ölçüm ve 7 günlük pil yüzdesini saklar. Açıkça etkinleştirilen geliştirme tanılaması yalnız durum/sayım/zamanlama içerir.

PilBar'ın cihaz/geçmiş/tercih/uyarı dosyaları ilk açılışta doğrulanıp yalnız eksik hedef dosyalara kopyalanır; kaynak uygulama ve dosyalar değiştirilmez. MacPulse `DeviceBatteries` dizini 0700, JSON dosyaları 0600'dır. Ham mobil syslog satırları saklanmaz; yalnız Pencil filtresi sınırlı bellekte ayrıştırılır. Logitech HID++ pil sorguları salt okunurdur; Giriş İzleme izni kullanıcı düğmesiyle istenir. Mobil okuyucu mevcut güven ilişkisini kullanır; eşleşme/Finder ayarlarını değiştirmez. Mobil veriler yalnız bu Mac/önceden güvenilmiş cihaz arasında okunur. Pil bildirim izni kullanıcı düğmesiyle istenir.

Paketin `Contents/Resources/PrivacyInfo.xcprivacy` dosyasındaki nedenler:

| API kategorisi | Neden | Gerçek kullanım |
| --- | --- | --- |
| UserDefaults | CA92.1 | MacPulse tercihleri ve bildirim tercihi; PilBar eski mobil seçenek aktarımı |
| SystemBootTime | 35F9.1 | Örnekler arasındaki monoton süre, hız/enerji hesaplaması ve timeout/zamanlayıcı |
| DiskSpace | 85F4.1 | Başlangıç diski toplam/boş kapasitesini ekranda gösterme |

Socket türü/kimliği için Foundation'ın yalnız bu iki metadata alanı istenir; timestamp alanları kullanılmaz. Doğrudan `stat` çağrıları kaldırıldı. Gizlilik manifesti yerel olarak yapı/şema/kaynak eşlemesi için kontrol edildi; Apple incelemesi veya App Store kabulü değildir. SMC/IOReport gibi özel donanım arayüzlerinin kabulü bu Mac üzerinde yapılır. Hedef yerel kullanımdır.

Yerel derleme akışı Apple'a paket göndermez. AI kullanım sorguları yukarıdaki sağlayıcılarla sınırlıdır.

Kaynak: [Apple required-reason API açıklaması](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
