# MacPulse yerel derleme ve güncelleme

MacPulse yalnız bu Mac için kullanılan yerel uygulamadır. Teslim proje kökündeki `MacPulse.app` dosyasıdır. Sertifika, Apple hesabı veya notarizasyon profili yerel geliştirme akışının gereği değildir.

## Yerel paket

Önce MacPulse'tan normal Cmd+Q ile çıkın. Paketleme çalışan hedefi değiştirmez. Hatalı derleme, kaynak veya imza durumunda önceki uygulama yerinde kalır; başarılı paket staging klasöründen değiştirilir. SQLite ve tercihlere dokunulmaz.

```sh
SIGNING_MODE=adhoc Scripts/package_app.sh release
Scripts/launch.sh
```

Varsayılan mimari mevcut Mac'in mimarisidir; bu cihazda arm64. Paket kendi makinesinde çalıştırılmak üzere yerel ad-hoc imzalanır. Gizlilik manifesti, ikon, lisanslar, boş entitlement, gerçek Mach-O mimarisi ve minimum macOS sürümü doğrulanır. Güncel sürüm 0.9.0 (10).

Hesaplama değişikliklerinde ve gerektiğinde yerel doğrulama:

```sh
swift test --build-system native
python3 Scripts/test_release_gates.py
swift run --build-system native MacPulseProbe --verify-history
```

Swift 6.4'ün bu araç zincirindeki varsayılan backend'i mimari çıktısını aynı klasöre yazdığı için mevcut paketleme scripti native backend kullanır. Gerçek binary yolları ve Mach-O target'ı ayrıca doğrulanır. Native backend deprecated olduğundan araç zinciri değiştiğinde tekrar değerlendirilmelidir.

## İzole ilk açılış kabulü

Yeni, boş bir dizin `--acceptance-directory` ile açık test eyleminde kullanılabilir. Normal açılışın veri konumu değişmez. İşaretli profile geçmiş ve JSON tercihler yazılır; normal UserDefaults tercihleri okunmaz/yazılmaz, sistem bildirimleri ve giriş öğesi değişimi kapalıdır. Var olan işaretsiz klasör ve canlı geçmiş dizini reddedilir; geçersiz argümanda canlı kullanıcı verisine geçilmez.

```sh
open -n MacPulse.app --args --acceptance-directory "$PWD/artifacts/new-clean-profile" --diagnostics-file "$PWD/artifacts/clean-live.json"
```

Bu profil ilk açılış, pencere/panel, tercih kaydetme ve yeniden açılışı canlı geçmişe test verisi eklemeden kontrol eder. Test bittikten sonra Cmd+Q ile çıkıp normal uygulamayı açın.

## Yerel kabul

Apple M4 Pro/macOS 27 üzerinde kaynaklar, sekmeler, hızlı panel, veri koruyan güncelleme ve izole ilk açılış doğrulandı. Fiziksel uyku/uyanma, uzun süreli çalışma, bağlı aksesuar ve güç karşılaştırması cihazla ayrıca denenmelidir. Sistem klavye dolaşımı/VoiceOver ve kullanıcı istediğinde giriş öğesi/bildirim davranışı açık kabul maddeleridir.

Önceden hazırlanan dağıtım scriptleri ve 0.8.0 DMG/ZIP tarihsel artefakt olarak yerinde kalır; güncel yerel akışta çalıştırılmaz. Dağıtım veya başka cihaz desteği bu çalışmanın hedefi değildir.
