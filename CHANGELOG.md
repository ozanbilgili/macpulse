# Değişiklikler

## 0.10.9 (21) — 12 Claude hesabı renkleri

- Claude hesap renkleri terminaldeki hesap seçici ve durum satırıyla aynı: 5–8 artık ayrı renkte (önceden 3 ile aynı mor), yeni 9–12 hesapları mercan, turkuaz, açık mavi ve altın. Hesap keşfi zaten dinamikti; `~/.claude-hesap9…12` ek ayar olmadan listelenir.

## 0.10.8 (20) — Sade pil görünümü

- Ana Pil sayfasında Mac pili, güç kaynağı, kalan süre ve düşük güç modu üstte; bağlı cihazlar pencere genişliğine uyarlanan kartlarda. AirPods kutusu kart içinde ayrı satırdır.
- Menüde okunur cihaz adları, hizalı yüzdeler ve ince pil çubukları. Şarj ve taze mobil watt bilgisi kısa alt satırda; kutu ayrıntıları açılabilir.
- Eski cihazlar iki görünümde de başlangıçta kapalı “Son görülen cihazlar” bölümünde. Eski ölçümler nötr renkte ve tarihli; bilinmeyen yüzde — olarak kalır.
- Geçmiş, widget ve cihaz işlemleri korunur. Mac grafiği ve bağlantı açıklamaları isteğe bağlı açılır; menü yüzey yoğunluğu mevcut tercihi kullanır.

## 0.10.7 (19) — Claude kimlik eşlemesi

- Claude e-postası ve abonelik yıl dönümü, aynı kullanım oturumunun salt okunur OAuth profilinden alınır. Eski `.claude.json` giriş kaydı başka hesaba ait adı veya token dönemini belirlemez.
- Profil yalnız bellekte, etkin kimliğe bağlı tutulur; oturum değişince önceki kimlik bırakılır. Profil alınamıyorsa hesap etiketi kullanılır. Kimlik/e-posta dosyası yazılmaz, credential yenilemesi yapılmaz.
- Kimlik veya abonelik dönemi değiştiğinde token toplamı yeniden hesaplanır; önceki taramanın sonucu yeni hesaba uygulanmaz.

## 0.10.6 (18) — Kompakt AI paneli ve en yüksek dört hesap

- Hızlı panel ve widget listesindeki hesap adları `kullanıcı@alanın ilk harfi` olarak kısalır; tam e-posta ayrıntılarda ve yardım metninde korunur.

- AI hızlı panelinde 52 pt hesap satırları: hesap/plan/token/okuma yaşı solda, 5 saat ve haftalık limitler yan yana; yüzde, renk, sıfırlanma ve tempo aynı sütunlarda hizalanır. Tüm hesap ve bakiye ayrıntıları bilgi düğmesinde korunur.
- Üst çubukta 5 saatlik kullanımı en yüksek dört hesabı güncel verilere göre otomatik gösterme. Haftalık-only planlar, eski/bilinmeyen/sıfırlanmış okumalar ve kapalı/süresi dolmuş oturumlar sıralamaya girmez.
- Widget düzenleyicisinde otomatik/elle seçim. Önceki elle düzen saklanır; yeni tercih eski ayarlarla uyumludur. Otomatik görünümde tek yüzde daha büyük yazılır.

## 0.10.5 (17) — PilBar pil görünümü

- Ana Pil sayfası ve menüdeki Piller sekmesi PilBar’ın tek sütunlu cam panelini kullanır: küçük cihaz ikonları, yüzde, orantılı pil simgesi ve şarj işareti.
- Bağlı cihazlar ve son ölçümler ayrı başlıklarda; çevrimdışı değerler soluk gösterilir. AirPods/kutu açma-daraltma, satırdan geçmiş ve sağ tık cihaz işlemleri iki görünümde de kullanılabilir.
- Menü listesi ekran yüksekliğine sığar; kompakt/rahat ve cam yoğunluğu tercihleri korunur.

## 0.10.4 (16) — Limit renk ölçeği

- Ana kullanım kartları, menü paneli, tempo notları ve bakiye göstergelerinde normal yeşil, uyarı sarı-turuncu, kritik/dolu kırmızı renkleri kullanılır.
- Limit ve tempo kararları korunur; renkler açık/koyu temaya uyarlanır.

## 0.10.3 (15) — AI hızlı panelinde dikey hesap listesi

- Menüden açılan AI Kullanımı panelinde Claude hesapları, Codex ve OpenRouter tek sütunda alt alta gösterilir.
- Panel daraltıldı; boş kart yüksekliği kaldırıldı. Liste ekran yüksekliğine göre büyür, sığmayan hesaplar dikey kaydırmayla erişilir. Kullanım, sıfırlanma, tempo, token ve bakiye ayrıntıları korunur.

## 0.10.2 (14) — Varsayılan AI hızlı paneli

- Menü çubuğu paneli her açılışta AI Kullanımı ile başlar. Açık panelde Mac ve Piller sekmeleri kullanılabilir; geçici sekme seçimi varsayılanı değiştirmez.

## 0.10.1 (13) — Menü çubuğunda Usage görünümü

- Claude grup logosu, renkli hesap numaraları, Codex ve OpenRouter vektör logoları.
- AI yüzdeleri 5 saat üstte, haftalık altta hizalanır; tek limit dikey ortalanır. Uyarı noktası için ayrı alan ayrılır.
- Hesap kartları ve widget düzenleyicisinde aynı sağlayıcı logoları kullanılır. Mevcut widget sırası ve görünüm tercihleri korunur.

## 0.10.0 (12) — PilBar birleşimi ve menü yerleşimi

- MacPulse Pil ekranına çoklu cihaz pilleri, HID++/MobileDevice/Watch/Pencil kaynakları, geçmiş ve cihaz ayarları eklendi.
- PilBar cihaz, 7 günlük geçmiş, favori/ad/sıra ve uyarı durumları bir kez kopyalanır; kaynak korunur.
- Cihaz başına pil simgesi/yüzde/ikisi widget'ı; üst çubukta otomatik sıkıştırma ve yatay kaydırmasız önizleme.
- Mac/AI/Piller hızlı paneli çok sütunlu özetler gösterir; geçmiş ve tam kullanım kartları bir tıkla açılır.
- Mevcut sistem/SQLite/AI örneklemesi korunur; cihaz sorguları aynı döngüden yönetilir, duraklatma/çıkışta yalnız uygulamanın okuyucu süreçleri kapatılır.

## 0.9.0 (11) — 7 Ekim 2026

- AI Kullanımı ekranı: çoklu Claude hesapları, Codex limitleri, OpenRouter bakiyesi, sıfırlanma ve tempo göstergeleri.
- Claude fatura dönemi token toplamları, ayrıntılı girdi/çıktı/önbellek sayıları; özel ve artımlı yerel dizin.
- Yenileme, sağlayıcı filtresi, hesap adı düzenleme, kullanılan/kalan ve saat/geri sayım tercihleri.
- Menü çubuğu widget düzeni: sistem metrikleri ve her AI hesabı için ekleme/kaldırma/sıralama; hesap başına 5 saat/haftalık/iki limit, Çubuk/Yüzde/İkisi ve kalan/kullanılan. Canlı önizleme, kalıcı düzen ve simge seçeneği; eski üç metrik sınırı kaldırıldı.
- Hızlı panelde tüm limit/reset/tempo/token/bakiye kartları, yenileme ve AI Kullanımı seçimi; Cmd+Shift+U kullanım, Cmd+Shift+W widget düzenleyicisi.
- Aktif transcript envanterden sonra büyürse okunan prefix metadata'sı korunur; sonraki artımlı taramada tekrar tam okuma gerekmez.
- Hedef yalnız bu Mac'teki yerel kullanım olarak netleştirildi; plan ve çalıştırma/güncelleme rehberi buna göre sadeleştirildi.
- Hakkında ekranı yerel kullanım bilgisini gösterir.
- Yerel paket mevcut cihaz mimarisinde oluşturulur; dağıtım adımları güncel iş akışından çıkarıldı.

## 0.8.0 (8) — 7 Ekim 2026

- Apple silicon/Intel universal yerel önizleme paketi, doğrulanan DMG/ZIP ve SHA-256 manifesti.
- Eski uygulamayı başarılı doğrulamadan önce değiştirmeyen paketleme; Developer ID ve notarizasyon için ayrı, ad-hoc'a düşmeyen dağıtım yolu.
- Gizlilik manifesti, paket içi lisanslar, Hakkında ekranı ve kurulum/dağıtım rehberleri.
- Metrik kartları ve hızlı panelde daha kısa erişilebilir etiket/değerler; açık temada seçili Disk metninin kontrastı iyileştirildi.
- Canlı geçmiş ve tercihlerden ayrı, açıkça seçilen temiz kurulum kabul profili.

Apple imzası/notarizasyon ve diğer cihaz/macOS kabulleri açık; genel dağıtım sürümü değildir.

## 0.7.0 (7)

Bluetooth envanteri ve bildirilen pil bileşenleri, Core Audio cihazları; sekme dolgu alanlarının tıklama düzeltmesi.

## 0.6.0 (6)

GPU, enerji modeli, geçerli sensörler ve fan devirleri.

## 0.5.0 (5)

Menü çubuğu, hızlı panel, tercihler ve tek örnekleme yaşam döngüsü.

## 0.1.0–0.4.0

Temel metrikler, uygulama/süreç gruplama, SQLite geçmiş/uyarılar, projeler ve salt okunur container görünümü.
