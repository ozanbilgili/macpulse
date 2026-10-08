# AI Kullanımı

Usage uygulamasının özellikleri MacPulse'un kartları, teması ve tek menü çubuğuna eklendi. Referans uygulama değiştirilmez.

Claude Code'un varsayılan ve numaralı hesapları, mevcut Codex oturumu ve mevcut OpenRouter anahtarı kullanılır. Hesap adı/plan/e-posta ve erişilebilen 5 saatlik/haftalık kullanım görünür. Codex pencere sırası yerine süresi dikkate alınır; planda olmayan pencere çizilmez. OpenRouter hesap kredisi gösterilir; anahtarın haftalık limiti farklıdır.

Yenileme kontrolü mevcut sistem sampler'ından, en sık 60 saniyede bir tetiklenir. API isteği yalnız cache 300 saniyeden eskiyse veya Yenile seçilmişse yapılır. Token süresi ve paylaşılan `.attempt` backoff'u manuel yenilemede de korunur. Keychain ve Codex oturumu salt okunurdur; token yenileme, yeni giriş veya credential yazımı yapılmaz. İstekler ephemeral URLSession ile sabit sağlayıcı uç noktalarına gider; yönlendirmeler takip edilmez. Kullanım cache'leri, isim dosyası ve MacPulse token dizini özel dosya izinleriyle atomik yazılır.

Tempo Usage ile aynı doğrusal yöntemdir: pencerenin %1'i (en az 60 saniye) geçince kullanımın pencere sonunda ulaşacağı yüzde hesaplanır. %90 üstü sınırda, %100 üstü sıfırlanmadan dolacak olarak gösterilir; %5 altı kullanımda erken alarm bastırılır. Saatler en yakın dakikaya yuvarlanır. API'nin null Claude penceresi başlamadı durumudur; eksik/bozuk veri veya sıfırlanması geçmiş ama yeni okuması olmayan pencere — gösterilir.

Claude aylık token toplamı aboneliğin yıl dönümünden hesaplanır. Girdi, çıktı ve iki önbellek sayısı yerel assistant usage alanlarından, mesaj/request kimliğiyle tekilleştirilir. Hesap session-env metadata'sından saat kovasıyla eşlenir; alt ajan ana oturuma aittir. Eşlenemeyen toplam ayrı gösterilir. Silinmiş transcript'ler, yarım/bozuk veya aşırı büyük satırlar toplamı eksiltebilir; bu fatura tutarı veya sağlayıcının eksiksiz token raporu değildir. MacPulse kendi özel artımlı dizinini kullanır ve Usage'ın token dizinine yazmaz. Mesaj içeriği saklanmaz veya gönderilmez.

AI Kullanımı ekranı Cmd+Shift+U, yenileme Cmd+R. Yüzdeye tıklayınca kullanılan/kalan, sıfırlanmaya tıklayınca saat/geri sayım değişir. Menü çubuğu widget düzenleyicisi Cmd+Shift+W veya Tercihler → Menü çubuğunu düzenle ile açılır. CPU, GPU, bellek, ağ, disk, pil, her Claude hesabı, Codex ve OpenRouter ayrı eklenir/kaldırılır; oklarla sıraya konur. Elle seçimde hesap başına 5 saat/haftalık/iki limit, Çubuk/Yüzde/İkisi ve kalan/kullanılan seçilir. Düzen kalıcıdır; yeni keşfedilen hesap kaydedilmiş düzene kendiliğinden eklenmez. Veri olmayan seçili widget — gösterir. Eski tercihler ilk düzenlemede korunarak taşınır; sıfır widget açıkça simge anlamına gelir. Önizleme ve gerçek menü aynı renderer ile çizilir. Hızlı panel her açılışta AI Kullanımı ile başlar; Mac ve Piller görünümüne geçilebilir. AI paneli hesapları 52 pt yüksekliğinde tek sütunda alt alta gösterir. Hesap/plan/okuma yaşı ve dönem token toplamı solda; 5 saat ve haftalık yüzde/bar/sıfırlanma/tempo yan yana hizalanır. Eksik limit — / Planda yok olarak görünür; kullanılmayan limit için yüzde uydurulmaz. OpenRouter tek bakiye satırıdır. Liste ekran yüksekliğine sığmadığında dikey kaydırılır; bilgi düğmesi tam kartı açar. E-posta, token dönem/çıktı/dört sayı dökümü, sorgu bekleme ve kredi ayrıntıları tam kartlarda korunur. Tema ve başlangıçta açılma MacPulse'un mevcut tercihlerini kullanır.

Widget düzenleyicisindeki **AI · En yüksek 4 (5 saat)** modu, tüm hesaplar içinden güncel 5 saatlik kullanım yüzdesi en yüksek dört kaynağı büyük tek yüzdeyle gösterir. Kullanım azaldıkça/yükseldikçe veya limit sıfırlandıkça sıralama yeniden hesaplanır. Eşit yüzdelerde kaynak/hesap numarası sırası kararlıdır. Yalnız bilinen, güncel, oturumu açık ve süresi dolmamış 5 saatlik limitler uygundur; haftalık-only Codex planı ve eski/sıfırlanmış/verisiz okumalar bu sıralamaya girmez. Dört uygun hesap yoksa yalnız uygun olanlar gösterilir. Elle seçilen widget düzeni ayrı saklanır; mod değişimi onu silmez. Eski tercih dosyaları elle seçimle açılır. Açık bir widget ekleme/düzenleme yeniden elle seçime geçer.

Hızlı panelde ve widget listesindeki hesap adı, e-postanın kullanıcı bölümü ile alanın ilk harfinden oluşur: `kullanıcı@örnek.com` → `kullanıcı@ö`. Adres bulunamazsa mevcut hesap etiketi kullanılır. Tam adres yardım metninde ve ayrıntı kartında görünür; kaynak adres ve kaydedilmiş özel hesap adları değiştirilmez.

İzole kabul profilinde gerçek kimlikler, kullanım cache'i, transcript ve ağ açılmaz. AI hesap envanteri/token/bakiye verileri sistem ölçüm geçmişine, SQLite dakika/gün kayıtlarına veya 90 örneklik kısa sistem grafiğine eklenmez. Tanılama yalnız hesap/kaynak sayıları ve zaman içerir.

Claude kimliği ve abonelik başlangıcı, mevcut bearer token ile salt okunur OAuth profilinden alınır; yerel `.claude.json` kaydı oturum değişiminden sonra eski kalabilir. Profil yalnız bellekte bir saat tutulur ve kimlik değişince bırakılır. Başarısız sorguda aynı kimliğin daha önce doğrulanmış profili korunur; ilk profil bulunamazsa e-posta uydurulmaz ve mevcut hesap etiketi görünür. Hatalı sorgu en az beş dakika bekler, sağlayıcının daha uzun bekleme süresine uyulur. Profil yanıtı ve e-posta diske kaydedilmez; credential yenilemesi ve yeni giriş yapılmaz. Token dönemleri doğrulanmış profil yıl dönümünü kullanır; bilinmeyen yıl dönümü için eski yerel kayda dönülmez. Kimlik/dönem değişimi devam eden eski token taramasının sonucunu geçersiz kılar.

## Usage özellik eşlemesi

| Usage özelliği | MacPulse karşılığı |
| --- | --- |
| Claude varsayılan/numaralı hesap keşfi | Ayrı hesap kartları ve ayrı widget'lar |
| Hesap numarası, ad, plan ve e-posta | Kart başlığı; Claude adını düzenleme |
| 5 saat ve haftalık limit, Pro Lite'ta olmayan pencere | Planın sağladığı limitler; süreye göre Codex pencere eşlemesi |
| Kullanılan/kalan yüzde, saat/geri sayım | Tıklayarak değiştirilen kalıcı kart tercihleri; widget başına kalan tercihi |
| Doluluk, tempo, tahmini tükenme saati ve çentik | Aynı tempo matematiği, renk, limit zamanı ve bar çentiği |
| Başlamadı, giriş yok, süresi dolmuş, eski veri, dolu | Açık durum metinleri; bilinmeyen veri — |
| Aylık token toplamı, dönem, çıktı ve dört sayı dökümü | Aynı yerel Claude hesap eşlemesi; çıktı satırı ve açılır ayrıntı |
| Hesabı belirlenemeyen token'lar | Ayrı toplam ve döküm ipucu |
| OpenRouter kalan/alınan/harcanan kredi, doluluk | Kredi kartı ve bakiye widget'ı; bitti/anahtar yok/eski veri durumu |
| Yenile, cache yaşı, 300 saniye TTL/backoff | Manuel/otomatik yenileme, kaynak yaşı ve sonraki sorgu |
| Menüde çubuk/yüzde/ikisi ve tükenme noktası | Her hesap için bağımsız görünüm, pencere ve kırmızı nokta |
| Girişte aç, açık/koyu görünüm, çıkış | MacPulse'un mevcut ortak tercihleri ve hızlı paneli |
| Menüden tüm hesaplara erişme | Tüm hesap özetleri hızlı panelde; tam kart ve ana kullanım ekranına bağlantı |

Kaynak app'in CLI dump/snapshot araçları kullanıcı arayüzü özellikleri değildir ve çalıştırılmadı. MacPulse ikonları ve kart stili korunur. Hesap limitlerinden bağımsız sağlayıcı fatura/token API'si vaat edilmez; yerel Claude transcript toplamı Usage ile aynı kapsamdadır.

## Yerel doğrulama

`Scripts/verify_ai_sources.py` credentials, Keychain ve transcript içeriklerini okumadan iki numeric token dizinini, saat kovalarını ve hesap dönemi toplamlarını karşılaştırır; sabit kaynak dosyalarını ve eski tamamlanmış SQLite kayıtlarını hash ile kontrol eder. Gerçek kayıtlar devam ederken farklı tarama anları son saatin toplamlarını değiştirebilir. UI için beklenen token toplamlarını bağımsız dönem/hesap matematiğiyle hesaplar. Yalnız sayı ve durum içeren sonuç özel izinli yerel kabul artefaktına yazılır.

Bu araç referans Usage'ın yerel abonelik kaydını kullanır. Kayıt etkin OAuth profiliyle uyuşmuyorsa dönem toplamının birebir eşliği beklenmez; MacPulse'un güncel yıl dönümü ayrıca doğrulanmalıdır.


Limit göstergeleri ve tempo notları: normal yeşil, uyarı sarı-turuncu, kritik/dolu kırmızı. Renk, mevcut limit/tempo durumunu izler; bu nedenle kullanım henüz %100 olmasa da tempo sınır aşımı öngörüyorsa kırmızı olabilir. Bilinmeyen veri nötr gösterilir.
