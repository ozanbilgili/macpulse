# MacPulse — teknik notlar

Bağımsız, yerel macOS sistem izleme uygulaması. SwiftUI + AppKit; SwiftPM, macOS 14+.

## Mevcut sürüm — 0.10.8 yerel uygulama

CPU, fiziksel bellek ve baskı, başlangıç diski kapasitesi, fiziksel disk I/O, fiziksel ağ arayüzleri, pil ve sistem bilgisi. Sistem/açık/koyu temalı ana ekran, canlı kısa grafikler ve CPU/Bellek/Disk/Ağ/Pil ayrıntıları. Çalışma boyunca son 90 örnek bellekte tutulur.

Faz 2: uygulama ve yardımcı süreç grupları, CPU/bellek/ad sıralaması, uygulama/süreç/PID arama, uygulama ve bağımsız süreç filtreleri. Her grubun canlı süreç ayrıntısında CPU, bellek yükü, RSS, PID, ebeveyn ve başlangıç zamanı görünür. Ana ekranda ilk beş; CPU/Bellek ekranlarında ilk on grup gösterilir.

Faz 3: yerel SQLite geçmişi, 1 saat/24 saat dakika ve 7 gün/30 gün özetleri; yüksek CPU, bellek büyümesi ve uzun süren disk/ağ etkinliği uyarıları. Sistem bildirimleri varsayılan kapalıdır; Uyarılar ekranındaki açık kullanıcı eylemiyle izin istenir.

Faz 4: TCP dinleyen portlar, çalışma dizininden proje eşleme, canlı süreç ağacı ve boşta adayı göstergesi. Çalışan yerel Docker Desktop/OrbStack/Podman için container durumu, port eşlemeleri, Compose adı ve erişilebilen CPU/bellek/ağ sayaçları. Tüm işlemler salt okunurdur.

Faz 5: seçilebilir menü çubuğu metrikleri ve altı kartlı hızlı panel; tema, 2/5/10 saniye yenileme ve kullanıcı eylemiyle giriş öğesi kaydı. Ana pencere kapalıyken tek ölçüm döngüsü ve yerel geçmiş devam eder.

Faz 6: ana ekranda GPU kartı; GPU ve enerji sekmesinde sürücü kullanım/bellek sayaçları, GPU enerji modeli, sistem güç kanalı, pil net akışı, geçerli sıcaklıklar ve fanların gerçek devri. GPU menü çubuğu metriği olarak da seçilebilir. Yönetici yetkisi veya yardımcı servis gerekmez; donanım erişimi yoksa veri bilinmeyen olarak kalır.

Faz 7: Bluetooth envanteri/bağlantı durumu ve macOS'un bildirdiği aksesuar pil bileşenleri; salt okunur Core Audio cihazları, varsayılan giriş/çıkış/sistem sesi, kanal sayısı, örnekleme hızı ve erişilebilen ana kanal seviyeleri. Sekme butonlarının dolgu alanları da tıklanabilir.

Faz 8: bu Mac için yerel `.app`, gizlilik manifesti, Hakkında/lisans ekranı, erişilebilir kart etiketleri, kontrast kontrolü ve izole ilk açılış profili. Hedef yalnız bu Mac'te kullanımdır. [Yerel kullanım](INSTALL.md), [derleme/güncelleme](RELEASE.md), [veri kapsamı](PRIVACY.md) ve [değişiklikler](../CHANGELOG.md).

Faz 9: AI Kullanımı ekranında çoklu Claude hesapları, Codex limitleri, OpenRouter bakiyesi, sıfırlanma süreleri ve tempo tahminleri. Claude fatura dönemi token toplamı ve girdi/çıktı/önbellek dökümü yerel transcript'lerden hesaplanır. Hızlı panel tüm hesapları kompakt satırlarda alt alta gösterir; 5 saat ve haftalık limitler yan yana hizalanır, bilgi düğmesi tam kartı açar. Üst çubukta güncel 5 saatlik kullanımı en yüksek dört hesabı otomatik gösterme seçeneği bulunur. Menü çubuğu widget düzenleyicisinde sistem metrikleri ve her AI hesabı ayrı eklenir/kaldırılır, sıralanır; hesap başına limit, Çubuk/Yüzde/İkisi ve kullanılan/kalan seçilir. Canlı önizleme aynı renderer'ı kullanır; düzen yeniden açılışta korunur. Kaynaklar mevcut Usage uygulamasıyla uyumludur; [özellik eşlemesi ve veri sözleşmesi](AI-USAGE.md).

Faz 10: PilBar cihaz pilleri MacPulse içinde birleşti. Ana Pil sayfasında Mac pili ve güç bilgileri üstte, bağlı cihazlar genişliğe uyarlanan kartlarda; menüde küçük ikon, ad/durum, hizalı yüzde ve ince pil çubuğu olan bir liste bulunur. Eski cihazlar kapalı “Son görülen cihazlar” bölümünden açılır. Mac/Bluetooth/Logitech HID++ ve önceden eşleşmiş iPhone/iPad/Watch/Pencil kaynakları, 6 saat/24 saat/7 gün geçmişi, ad/favori/gizleme/sıra ve pil uyarıları. PilBar kayıtları bir kez kopyalanır; kaynak korunur. Her cihaz ayrı menü widget'ı olabilir. Üst çubuk ve canlı önizleme tek satırdır; alan daralınca etiket/boşluklar kısalır. Hızlı panel her açılışta AI Kullanımı ile başlar; AI ve Piller listeleri alt alta gösterilir ve ekranı aştığında dikey kaydırılır. Üst çubuktaki widget’lar tek satırda kaydırmasızdır. [Özellikler ve bağlantı sınırları](DEVICE-BATTERIES.md).


## Çalıştırma

Xcode/Command Line Tools ve Swift 6+ gereklidir. Dış paket indirilmez.

```sh
swift test --build-system native
SIGNING_MODE=adhoc Scripts/package_app.sh release
Scripts/launch.sh
```

Paket `MacPulse.app` olarak proje kökünde oluşur. Önce çalışan uygulamadan Cmd+Q ile çıkılmalıdır; paketleme çalışan hedefi reddeder ve ancak doğrulama geçince eski paketi değiştirir. Paket mevcut Mac'in mimarisinde yerel ad-hoc imzalıdır. Ana pencereyi kapatmak uygulamayı sonlandırmaz; menü çubuğu ve kayıt devam eder.

Swift 6.4'ün bu Xcode sürümündeki varsayılan Swift Build backend'i mimari çıktısını aynı klasöre yazıyor; ikinci derleme ilk dilimin üzerine yazıyor. Paketleme bu cihazda doğru iki dilim/14.0 sonucunu veren `--build-system native` ile çalışır; bu backend deprecated olduğundan sonraki araç zincirinde tekrar kontrol edilmelidir. Script gerçek Mach-O min sürümünü ve dilimleri ayrıca doğrular.

```sh
swift run --build-system native MacPulseProbe
swift run --build-system native MacPulseProbe --samples 10
swift run --build-system native MacPulseProbe --verify-processes
swift run --build-system native MacPulseProbe --verify-history
swift run --build-system native MacPulseProbe --verify-projects --verify-history
swift run --build-system native MacPulseProbe --verify-hardware --verify-history
swift run --build-system native MacPulseProbe --verify-accessories --verify-history
```

Probe aynı metrik çekirdeğinin gerçek ölçümlerini JSON olarak verir; sıcak başlangıç, temel veri varlığı ve aralıkları kontrol eder. Masaüstünde dahili pil bulunmaması normaldir. Disk I/O veya OS baskı metriği alınamazsa bu durum ayrıca görünür. Varsayılan çıktı uygulama özeti ve kapsam sayılarını içerir; tam süreç listesi için açıkça `--include-processes` gerekir. Çalıştırılabilir dosya ve paket yolları çıktıya yazılmaz.

`--verify-processes` kendi alt sürecinde 16 MiB bellek ayırır ve yaklaşık altı saniyelik CPU yükü oluşturur. CPU ölçeğini, RSS'nin aynı alt süreç için `ps` ile eşleşmesini ve doğal çıkışından sonra listeden kaybolmasını kontrol eder. Diğer süreçlere sinyal göndermez.

`--verify-history` gerçek örnekleri geçici, ayrı bir SQLite veritabanına yazar; dakika/gün toplamlarını, yeniden açılış ve bütünlüğü kontrol eder. Uygulamanın geçmiş veritabanını değiştirmez. `--verify-processes --verify-history` birlikte kullanılabilir.

`--verify-projects` kendi geçici proje dizininde, loopback üzerinde rastgele TCP portu dinleyen yaklaşık 12 saniyelik bir test alt süreci oluşturur. Portu `lsof` ile, proje kökünü çalışma diziniyle, eşlemeyi süreç kimliğiyle karşılaştırır; doğal çıkışında listeden kaybolmasını doğrular. Geçici dizin temizlenir. Mevcut sunuculara bağlanmaz veya onları durdurmaz. Varsayılan probe proje adlarını/yollarını ve container envanterini kaydetmez; yalnız kapsam sayıları içerir.

`--verify-hardware` kendi Metal iş yükünü yaklaşık altı saniye çalıştırır; tamamlanan GPU komutlarını, kullanım/enerji sayacının tepki vermesini, erişilebilen sensörleri ve reset sonrası yeni baseline'ı kontrol eder. Bu seçenek kısa süreli gerçek GPU yükü oluşturur; varsayılan probe yük üretmez. Fiziksel güç ölçeri veya sıcaklık kalibrasyonu değildir. `--verify-history` ile birlikte uygulamanın veritabanına dokunmadan çalışabilir.

`--verify-accessories` Bluetooth/Core Audio kaynaklarını, bağlantısız/eski/duraklatılmış pil gizlemesini ve envanterin kısa geçmişten çıkarılmasını doğrular. Yeni cihaz bağlamaz, ses kaydı veya çıkış değişimi yapmaz. Bağlı aksesuar yoksa gerçek pil ölçümü kabul edilmiş sayılmaz. Varsayılan probe yalnız cihaz/kapsam sayıları verir; cihaz adları, Bluetooth adresleri ve ses envanteri snapshot JSON'a eklenmez.

## Ölçüm anlamı

- Sistem CPU'su tüm çekirdeklerde 0–100%; süreç/uygulama CPU'sunda bir çekirdek %100'dür. Çok çekirdek kullanan gruplar %100'ü aşabilir; ilk örnekte hız yoktur.
- Bellek değerleri ikili GiB/MiB, disk ve aktarım değerleri ondalık GB/MB cinsindedir.
- Bellek doluluğu, OS bellek baskısıyla aynı ölçüm değildir.
- Disk kapasitesi başlangıç veri birimidir. I/O erişilebilen fiziksel sürücülerin toplamıdır.
- Ağ `NET_RT_IFLIST2` 64 bit fiziksel `en*` sayaçlarından alınır. VPN, bridge ve loopback ayrıca eklenmez.
- Oturum aktarımı yalnız geçerli iki örnek arasındaki farkları kapsar. Duraklatma veya uyku sırasında ölçülmeyen süre "bugün" toplamı olarak gösterilmez.
- Pencere etkin olduğunda 2 saniye, arka planda 10 saniye örnekleme yapılır. 20 saniyeyi aşan aralıklar yeni bir hız başlangıcı oluşturur.
- Bilinmeyen/ilk örnek değeri `—`, gerçek sıfır `0` olarak görünür.
- Süreçler PID ve başlangıç zamanı ile izlenir. Paket yolu, geçerli ebeveyn zinciri ve tek uygulamaya ait macOS kaynak grubu üzerinden eşlenir; belirsiz eşlemeler bağımsız kalır. Terminalin paket dışındaki alt süreçleri terminal grubuna dahildir.
- Bellek yükü `ri_phys_footprint`, RSS `ri_resident_size` değeridir. Paylaşılan ve sıkıştırılmış bellek nedeniyle grup toplamları sistem RAM kullanımına eşit değildir. `≥` yalnız ölçülebilen üyelerin ara toplamını belirtir.
- Yalnız mevcut kullanıcıya ait erişilebilen süreçler ölçülür. Kapsam dışında kalanlar sayılır; tam sistem ölçümü için yönetici yardımcısı bu sürümde yoktur.
- Kaynak grubu bilgisi, Apple XNU'daki isteğe bağlı özel `libproc` arayüzünden alınır. Desteklenmeyen sistemlerde paket/ebeveyn eşlemesi devam eder; bazı ayrı XPC yardımcıları bağımsız kalabilir. Güncel cihaz kabulü yalnız bu Mac üzerindedir.
- Süreç listesi yalnız güncel örnekte tutulur; kısa donanım geçmişine tam süreç envanteri eklenmez.

Cmd+1…7 canlı sekmeleri, Cmd+8 Geçmiş, Cmd+9 Uyarılar, Cmd+0 Projeler, Cmd+Shift+0 Containerlar, Cmd+Shift+G GPU ve enerji, Cmd+Shift+B Bluetooth, Cmd+Shift+S Ses, Cmd+Shift+U AI Kullanımı ekranını açar. Cmd+Shift+P izlemeyi duraklatır/sürdürür. Cmd+Shift+M hızlı paneli, Cmd+O ana pencereyi, Cmd+, tercihleri açar. Süreç ayrıntısını Escape kapatır.

## Bluetooth ve ses

- Bluetooth mevcut macOS envanterinden, en fazla 30 saniyede bir okunur. Yalnız sabit sistem aracı ve argümanları kullanılır; shell yoktur. Okuma 3 saniye/1 MiB, 4 controller/64 cihaz sınırındadır. Kaynak hatasında eski liste canlıymış gibi tutulmaz. Yeni cihaz keşfi, eşleme, bağlama/kesme veya Bluetooth ayarı yapılmaz.
- Bağlı cihazın genel/sol/sağ/kutu pili ayrı **bildirilen** yüzdeler olarak görünür. Envanterin sorgu zamanı pil sensörünün ölçüm zamanı değildir; sensör tazeliği bilinmez. Bağlantısız, sorgusu 45 saniyeden eski, saat yönü tutarsız veya duraklatılmış kayıtta pil gizlenir. 0% gerçek bildirim olarak geçerlidir; eksik değer — olur. Genel Logitech yüzdesi güvenilir kabul edilmez; HID++ kaynağı bu sürümde eklenmedi. iPhone/iPad, Watch/Pencil için ayrı canlı pil kaynağı yoktur.
- Core Audio cihaz kimliğiyle giriş/çıkış kanal sayısı, varsayılan giriş/çıkış/sistem sesi, nominal örnekleme hızı, I/O çalışma durumu, erişilebilen ana kanal seviyesi/sessizliği okunur. Sürücüde ana seviye kontrolü yoksa kanal ortalaması veya sıfır uydurulmaz. Cihaz okuma sırasında kaybolursa satır çıkarılır; eksik alanlar görünür.
- I/O çalışması duyulan ses veya uygulama başına ses etkinliği değildir. Mikrofon/sistem sesi kaydı, IOProc/tap, ses örneği, cihaz değiştirme ve seviye ayarı yoktur. Uygulama başına karıştırıcı izin/cihaz araştırması olarak açık kalır.
- İki kaynak mevcut tek sampler içinde UI dışında okunur. Bluetooth 30 saniye önbellek, ses mevcut örnekleme aralığını kullanır; uyku/duraklatmadan sürdürmede Bluetooth sorgusu yenilenir. Cihaz ad/adres/kimlik envanteri yalnız güncel bellekte kalır; SQLite ve 90 örneklik grafik serisine eklenmez.

## GPU, enerji ve sensörler

- GPU yüzdesi AGX sürücüsünün cihaz/renderer/tiler sayaçlarıdır; sürücünün zaman penceresi bilinmez. Bellek, GPU kaynaklarına kullanılan/ayrılan sistem belleğidir; ayrı VRAM veya sistem RAM toplamına eklenen bir tüketim değildir. Birden fazla GPU varsa ayrı gösterilir; belirsiz bir toplam üretilmez.
- GPU watt değeri IOReport enerji modelindeki sayaç farkı ve monoton zamandan hesaplanan aralık ortalamasıdır. Donanım güç ölçeri değildir. İlk örnek, sayaç sıfırlaması, bilinmeyen birim, uzun boşluk veya ilerlediği doğrulanamayan sayaç `—` olur. CPU/ANE watt ve uygulama başına enerji bu sürümde ölçülmez; macOS 27 cihaz deneyinde CPU enerji sayacı sabit kaldı.
- Sistem güç kanalı SMC `PSTR` değeridir. Pil net akışı güncel, tutarlı voltaj × akımdır; pozitif pile giriş, negatif pilden çıkıştır. Eski/eksik/tutarsız kaynak gizlenir. Bu değerler farklı kapsamdadır; birbirine eklenmez, adaptör veya priz tüketimi olarak sunulmaz.
- SMC yalnız salt okunur sensör sorguları kullanır. Sıcaklıklar geçerli aralıkta iki ardışık okumadan sonra görünür. macOS 27+ üzerinde güvenilirliği doğrulanamayan `Tp` CPU grubu dışarıda tutulur; CPU ortalaması yalnız geçerli `Te` grubu için **kısmi** değerdir. GPU sıcaklığı geçerli `Tg` grubudur. OS termal durumu ayrı gösterilir ve derece değildir.
- Fanlar yalnız gerçek devir (`rpm`) okumalarıdır; geçerli sıfır durabilir. Fan kontrolü yoktur. Sensör liste sınırı, geçersiz ve okunamayan değerler görünür; liste kısmi olabilir. SMC ve IOReport belgelenmemiş arayüzlerdir; farklı cihaz/macOS desteği ayrıca kabul gerektirir.
- GPU/enerji/sensör grafikleri yalnız mevcut oturumun son 90 örneğidir. Bu faz yeni donanım verilerini 30 günlük SQLite geçmişine eklemez. Duraklatma/uyanma enerji ve sıcaklık doğrulamasını yeniden başlatır; aradaki boşluk birleştirilmez.

## Projeler ve containerlar

- `libproc` çalışma dizini ve socket metadata'sı, PID + başlangıç zamanı önce/sonra doğrulanarak alınır. Yalnız mevcut kullanıcı ve erişilebilir süreçler; 10 saniyelik tarama, süreç başına en çok 4096 FD/64 dinleyici. Erişilemeyen ve kırpılan listeler görünür.
- En yakın `.git`, SwiftPM, Node, Python, Rust, Go, Ruby, Java, PHP veya CMake proje işareti kök kabul edilir. Dosya içerikleri okunmaz; dizin üst zinciri 24 adımla, metadata cache'i 1024 giriş/30 saniyeyle sınırlıdır. `node_modules`, `.build`, `.venv`, `vendor` içindeki işaretler proje oluşturmaz. En yakın proje seçilir; monorepo içindeki paketler ayrı görünür. İşaretsiz çalışma dizini otomatik proje sayılmaz.
- Kendi çalışma dizini önceliklidir; dizini bulunamayan veya `/` olan süreç geçerli ebeveyn zincirinden eşlenebilir. PID yeniden kullanımı/döngü koruması vardır. Projeye bağlanamayan dinleyiciler ayrı listelenir. Her süreç bir projeye en fazla bir kez atanır. Proje grupları uygulama gruplarının başka bir görünümüdür; kaynaklar iki kez toplanmaz.
- Boşta adayı, en az bir TCP dinleyicisi olan proje için iki dakika CPU <%1 ve taranan TCP bağlantısı/bekleyen veri bulunmaması koşuludur. Üye/port değişimi, veri boşluğu, eksik veya eski socket ölçümü süreyi sıfırlar. Süreç başına TCP byte sayacı, UDP veya iki tarama arasında açılıp kapanan bağlantılar ölçülmez; gösterge kullanılmadığına dair kesin tanı değildir.
- Yerel Unix socket üzerinden yalnız `GET /containers/json?all=1` ve container kaynak sorgusu kullanılır. C köprüsü diğer endpointleri reddeder. Shell/CLI, uzak context, ortam/config/credential okuma, container başlatma/durdurma veya süreç sonlandırma yoktur.
- Socketin varlığı yeterli değildir; mevcut süreç envanteriyle çalışan runtime doğrulanır. Docker Desktop için backend ve VM süreci birlikte gerekir; Resource Saver'da VM yoksa socket sorgulanmaz. OrbStack için motor süreci; Podman için tanınan VM/forwarder ve standart geçici API socketi gerekir. Tanınmayan motor/special socket erişimi açık sınırdır; kapalı uygulama/VM açılmaz.
- Standart Docker/OrbStack socketleri ve en çok dört Podman socketi; aynı socket inode'u bir kez okunur. Runtime başına en fazla 1.5 saniye, envanter isteği 500 ms, kaynak isteği 400 ms; yanıt 2 MiB, envanter 128 container, sorgu 64 çalışan container sınırı. Başarısız sorguda eski envanter canlı gibi gösterilmez; eksik kaynak verisi `—` olur.
- Container CPU'su engine CPU sayaç farkı ve çekirdek sayısından hesaplanır. Tek seferlik yanıtta önceki sayaç yoksa iki ardışık yerel sorgu gerekir; reset/çekirdek değişimi/30 saniyeyi aşan aralıkta yeni baseline alınır. Bellek runtime'ın cache dahil kullanım değeridir; Mac footprint'i değildir. Ağ yalnız bildirilen container yaşam boyu sayacıdır, hız veya bugünkü toplam değildir.
- Proje yolları/portlar ve containerlar yalnız güncel bellekte tutulur; SQLite'a ve 90 örneklik donanım geçmişine yazılmaz. Proje/container ekranlarında arama ve kapsam filtreleri vardır. OrbStack/Podman'ın çalışan cihaz kabulü bu Mac'te yapılmadı.

## Geçmiş ve uyarılar

- Geçmiş `~/Library/Application Support/MacPulse/history.sqlite` içinde tutulur. SQLite WAL ve şema sürümü kullanılır; veritabanı dosyaları yalnız mevcut kullanıcı tarafından okunabilir/yazılabilir. Sürüme uyumsuz veya bozuk kayıt otomatik silinmez; hata görünür, canlı ölçüm devam eder.
- Bugün ve önceki 29 UTC günü saklanır; gün değişiminde ve başlangıçta eski dakika/gün/uyarı kayıtları temizlenir. Gün görünümünün sınırları UTC'dir; ekrandaki saatler cihazın saat dilimindedir.
- Ortalamalar örnek adedine değil, monoton ölçüm süresine göre ağırlıklandırılır. Aktarım toplamları yalnız ölçülmüş hız aralıklarının integralidir. İlk örnek, 20 saniyeyi aşan boşluk veya büyük duvar saati değişimi aktarım uydurmaz. Gün özeti, güncellenen dakika kaydının yalnız farkını ekler.
- Dakika başına en çok 20 grup CPU/bellek ilk 10 adayından seçilir; gün başına en çok 256 farklı grup tutulur. Kısmi CPU/bellek ara toplamları kesin ölçüm olarak kaydedilmez. Uygulama ortalamaları yalnız kaydedilmiş gözlemleri kapsar; tüm uygulamaların eksiksiz geçmişi değildir.
- Yazma en fazla yaklaşık 10 saniye arayla gruplanır; dakika geçişi, yeni uyarı, duraklatma ve normal kapanışta tamamlanır. Zorla kapanmada son birkaç saniye kaybolabilir. Kayıt yalnız MacPulse çalışırken oluşur; ana pencere kapalıyken de devam eder.
- Sistem CPU ≥ %85 ve uygulama CPU ≥ %80 için iki dakika; ağ toplamı ≥ 50 MB/s veya disk toplamı ≥ 100 MB/s için bir dakika gerekir. Bellek uyarısı aynı süreç üyeleriyle 10 dakikada ≥ 512 MiB büyümedir; bellek sızıntısı tanısı sayılmaz.
- Eksik ölçüm/boşluk süre koşulunu sıfırlar. Aktif durum tek uyarıda güncellenir; aynı konu için yeni kayıt en erken 10 dakika sonra oluşur. Yeniden açılışta eski etkin durum izleme kesildi olarak kapanır; eski eşik süresi taşınmaz. Son 100 uyarı ekranda görünür.
- Bildirimler yalnız yeni uyarı için, izin verilmişse gönderilir. Bildirim izni uygulama açılışında istenmez; kapalı veya reddedilmiş izinde uygulama içi uyarılar kalır.

Sistem izleme mevcut süreçleri sonlandırmaz, sistem ölçümlerini dış servise göndermez veya yönetici izni istemez. AI kullanım sorguları yalnız ilgili sağlayıcının kendi kullanım uç noktasına mevcut kimlik bilgisiyle yapılır. Paket ad/kimlik metadata'sı okunur; proje işaretlerinin yalnız varlığına bakılır; kullanıcı dosyalarının içeriği, süreç argümanları ve ortam değişkenleri okunmaz. Geçmiş kaydı PID envanteri ve dosya yolları içermez.

Paketleme scripti guide-macos-spm-packaging şablonundan, SMC/IOReport protokol sözleşmeleri MIT lisanslı macmon'dan uyarlanmıştır; kaynak ve lisanslar `docs/THIRD-PARTY.md` ve uygulama paketindeki `ThirdPartyNotices.md` dosyasında kayıtlıdır.

## Menü çubuğu ve yaşam döngüsü

- CPU, GPU, bellek doluluğu, fiziksel ağ indirme, başlangıç diski doluluğu ve pil oranından en fazla üç metrik seçilebilir. Hepsi kapalıysa yalnız simge görünür. Menüde C CPU, G GPU, M bellek, D disk, B pil; ↓ indirme anlamındadır. Bilinmeyen ölçüm `—` olur. Duraklatmada menü yalnız duraklatma simgesini gösterir; hızlı panel son ölçüm saatini açıkça belirtir.
- Ana pencere aktifken veya hızlı panel açıkken tercih edilen 2/5/10 saniye kullanılır. Arka planda 10 saniyede bir ölçülür. Ayar veya görünürlük değişikliği beklemeyi keser; ikinci bir sampler başlatmaz. Kapalı/minimize ana ekran ve kapalı hızlı panel grafikleri oluşturulmaz.
- Duraklatma ve sistem uyku bildirimi yeni örneği keser, devam eden eski nesil okumayı reddeder ve geçmişi tamamlar. Sürdürme/uyanmanın ilk örneği yeni sayaç baseline'ıdır; boşluktaki trafik yeni hız gibi sunulmaz. Uyku sonrası kullanıcı duraklatması korunur. Fiziksel uyku/uyanma kabulü ayrıca açıktır.
- Tema, yenileme ve menü seçimi yerel tercihlerde saklanır. Başlangıçta açılma için tercih düğmesi Apple ServiceManagement kullanır; açılışta register/unregister çağrılmaz. macOS'un gerçek durumu ve gerekli onay gösterilir. Geliştirme klasöründeki ad-hoc paket bu cihazda `notFound` bildiriyor; Kullanıcı başlangıçta açılmayı istediğinde yerel uygulama konumu, OS onayı ve gerçek oturum açılışı ayrıca doğrulanmalıdır.

GUI kaynak tüketimini yeniden ölçmek için uygulamayı isteğe bağlı yerel tanılama ile aç:

```sh
open MacPulse.app --args --diagnostics-file "$PWD/artifacts/phase-7-live.json"
python3 Scripts/measure_app.py --mode foreground --duration 60 --diagnostics artifacts/phase-7-live.json --output artifacts/phase-7-performance-foreground.json
```

Ölçüm yalnız paketlenmiş MacPulse GUI sürecinin CPU, footprint ve RSS değerlerini okur. CPU'da bir mantıksal çekirdek %100'dür; WindowServer ve diğer uygulamalar dahil değildir. Arka plan veya duraklatma için `--mode background`/`--mode paused` seçilir. Tanılama varsayılan kapalıdır; etkinleştirilirse yalnız sayım, durum ve zamanlama içerir, envanter içermez ve 0600 dosya izni kullanır. Probe RSS'si GUI kabulü yerine kullanılmaz.
