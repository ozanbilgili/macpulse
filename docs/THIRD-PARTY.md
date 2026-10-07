# Paketleme scripti

`Scripts/package_app.sh`, Thomas Ricouard'ın [Skills](https://github.com/Dimillian/Skills) koleksiyonundaki guide-macos-spm-packaging şablonundan alınmıştır.

MIT License

Copyright (c) Thomas Ricouard

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# İsteğe bağlı SMC / IOReport protokolü

`HardwareBridge.c` içindeki SMC ABI düzeni, salt okunur komut numaraları ve IOReport sembol sözleşmeleri [vladkens/macmon](https://github.com/vladkens/macmon/blob/64cd23417afb7df7bc76f7fa10b94929a6db578b/src_lib/sources.rs) incelemesinden uyarlanmıştır. Referans revizyonu `64cd23417afb7df7bc76f7fa10b94929a6db578b`. Rust kodu/dependency veya yardımcı executable paketlenmez; yerel C köprüsü ve doğrulama matematiği bu uygulamada yazıldı. Belgelenmemiş APIler cihaz/OS kabulüne bağlıdır.

MIT License

Copyright (c) 2024 vladkens

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


# Yerel mobil pil araçları

PilBar'ın kullanıcıya ait yerel kaynakları MacPulse'a taşındı. `pilbar-mobile-native`, macOS MobileDevice framework'ünü çalışma zamanında salt okunur sorgular için açar. `pilbar-watch`, bu Mac'te zaten kurulu libimobiledevice ve libplist kütüphanelerine dinamik bağlanır; kütüphaneler pakete kopyalanmaz. libimobiledevice ve libplist LGPL-2.1 kapsamındadır; yerel kaynak/kurulum bilgileri Homebrew paketleri üzerinden erişilebilirdir. Finder eşleşmesi, izinler veya sistem servisleri değiştirilmez.

# Sağlayıcı logoları

`ProviderLogos.swift`, kullanıcının yerel Usage uygulamasındaki `Logos.swift` vektör yollarını ve çizim geometrisini kullanır. Referans kaynak Claude/Codex yollarını OpenUsage `ProviderIcons` ve OpenRouter yolunu lobe-icons olarak belirtir. Sağlayıcı logoları ilgili marka sahiplerine aittir; yalnız hesap ve bakiye tanımlaması için gösterilir. Usage kaynakları değiştirilmez.
