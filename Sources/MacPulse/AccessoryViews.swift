import SwiftUI
import MetricsCore

struct BluetoothView: View {
    let snapshot: BluetoothSnapshot?
    let paused: Bool
    @State private var onlyConnected = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right").font(.title2.weight(.semibold)).foregroundStyle(Palette.memory)
                    Spacer()
                    Toggle("Yalnız bağlı", isOn: $onlyConnected).toggleStyle(.switch).font(.caption)
                }
                if let snapshot {
                    let fresh = snapshot.fresh(at: context.date)
                    let connected = snapshot.accessories.filter { snapshot.connection($0, at: context.date) == .connected }
                    HStack(spacing: 14) {
                        AccessoryFact(title: "Bluetooth durumu", value: fresh && snapshot.available ? power(snapshot.power) : "Bilinmiyor", caption: "macOS envanter bildirimi", color: Palette.memory)
                        AccessoryFact(title: "Bağlı aksesuar", value: fresh && snapshot.available ? "\(connected.count)" : "—", caption: "Bağlantı taraması", color: Palette.accent)
                        AccessoryFact(title: "Envanter", value: snapshot.available ? "\(snapshot.accessories.count)" : "—", caption: snapshot.truncated ? "Liste kısmi" : "Bağlı ve eşlenmiş cihazlar", color: Palette.secondary)
                    }
                    HStack {
                        Text(snapshot.status).font(.caption)
                        Spacer()
                        Text((paused ? "Duraklatıldı · " : fresh ? "Son sorgu · " : "Sorgu eskidi · ") + snapshot.date.formatted(date: .omitted, time: .standard)).font(.caption).monospacedDigit()
                    }.foregroundStyle(Palette.secondary)
                    let rows = onlyConnected ? connected : snapshot.accessories
                    if rows.isEmpty {
                        Text(snapshot.available ? onlyConnected ? "Bağlı aksesuar yok." : "Bluetooth envanterinde aksesuar yok." : "Bluetooth verisi alınamadı. Sonuç bilinmeyen; eski envanter canlı gösterilmez.")
                            .foregroundStyle(Palette.secondary).padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(rows) { device in
                        let state = snapshot.connection(device, at: context.date)
                        let batteries = snapshot.batteries(device, at: context.date, paused: paused)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: icon(device.kind)).font(.title2).foregroundStyle(Palette.memory).frame(width: 34)
                                VStack(alignment: .leading, spacing: 4) { Text(device.name).font(.headline); Text(device.kind).font(.caption).foregroundStyle(Palette.secondary) }
                                Spacer()
                                Text(state == .connected ? "Bağlı" : state == .disconnected ? "Bağlı değil" : "Durum bilinmiyor")
                                    .font(.caption.weight(.medium)).foregroundStyle(state == .connected ? Palette.accent : Palette.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6).background(Palette.elevated, in: Capsule())
                            }
                            if batteries.isEmpty {
                                HStack { Text("Pil").foregroundStyle(Palette.secondary); Spacer(); Text("—").font(.title3).monospacedDigit() }
                                Text(paused ? "İzleme duraklatıldı." : state == .disconnected ? "Bağlantısız cihazın saklanan pil değeri gösterilmez." : state == .unknown ? "Güncel bağlantı doğrulanamıyor." : device.batteryLimitation ?? "Bu aksesuar için pil bildirimi yok.")
                                    .font(.caption).foregroundStyle(Palette.secondary)
                            } else {
                                HStack(spacing: 22) {
                                    ForEach(batteries, id: \.component) { battery in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(battery.component).font(.caption).foregroundStyle(Palette.secondary)
                                            Text("\(battery.percent)%").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.battery)
                                        }
                                    }
                                }
                                Text("Bildirilen pil · macOS kaydı · sensör güncelleme zamanı bilinmiyor")
                                    .font(.caption).foregroundStyle(Palette.secondary)
                            }
                        }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("Pil yüzdeleri macOS'un bildirdiği kayıtlardır; bu sorgunun zamanı sensör ölçüm zamanı değildir. Bağlantısız, 45 saniyeden eski veya duraklatılmış kayıtta pil gizlenir. Logitech'in genel pil kaydı güvenilir kabul edilmez; bu sürüm HID++ sorgulamaz. Yeni cihaz tarama, eşleme, bağlanma veya bağlantı kesme yapılmaz. iPhone/iPad, Watch ve Pencil için ayrı canlı pil kaynağı eklenmedi.")
                        .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                } else { ProgressView("Bluetooth envanteri bekleniyor") }
            }
        }
    }
    private func power(_ value: BluetoothPower) -> String { value == .on ? "Açık" : value == .off ? "Kapalı" : "Bilinmiyor" }
    private func icon(_ kind: String) -> String {
        let name = kind.lowercased()
        if name.contains("keyboard") { return "keyboard" }
        if name.contains("mouse") { return "computermouse" }
        if name.contains("head") || name.contains("audio") { return "headphones" }
        return "antenna.radiowaves.left.and.right"
    }
}

struct AudioDevicesView: View {
    let snapshot: AudioSnapshot?
    @State private var filter = "Tümü"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Ses cihazları", systemImage: "speaker.wave.2").font(.title2.weight(.semibold)).foregroundStyle(Palette.network)
                Spacer()
                Picker("Cihaz yönü", selection: $filter) { ForEach(["Tümü", "Giriş", "Çıkış"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 230)
            }
            if let snapshot {
                HStack(spacing: 14) {
                    AccessoryFact(title: "Varsayılan giriş", value: snapshot.input?.name ?? "—", caption: "Mikrofon / giriş aygıtı", color: Palette.network)
                    AccessoryFact(title: "Varsayılan çıkış", value: snapshot.output?.name ?? "—", caption: "Uygulama sesleri", color: Palette.accent)
                    AccessoryFact(title: "Sistem sesleri", value: snapshot.systemOutput?.name ?? "—", caption: "Uyarı seslerinin çıkışı", color: Palette.secondary)
                }
                HStack {
                    Text(snapshot.available ? "\(snapshot.devices.count) cihaz · \(snapshot.failures) eksik / değişen alan" + (snapshot.truncated ? " · Liste kısmi" : "") : "Core Audio envanteri alınamadı").font(.caption)
                    Spacer()
                    Text("Son sorgu " + snapshot.date.formatted(date: .omitted, time: .standard)).font(.caption).monospacedDigit()
                }.foregroundStyle(Palette.secondary)
                let devices = snapshot.devices.filter { filter == "Tümü" || (filter == "Giriş" ? ($0.inputChannels ?? 0) > 0 : ($0.outputChannels ?? 0) > 0) }
                if devices.isEmpty { Text("Bu kapsamda ses cihazı yok.").foregroundStyle(Palette.secondary).padding(22) }
                ForEach(devices) { device in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: (device.outputChannels ?? 0) > 0 ? "speaker.wave.2" : "mic").font(.title2).foregroundStyle(Palette.network).frame(width: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(device.name).font(.headline)
                                Text(device.transport + " · " + (device.sampleRate.map { MetricFormat.number($0 / 1000, digits: 1) + " kHz" } ?? "Örnekleme hızı bilinmiyor")).font(.caption).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            if device.id == snapshot.defaultInput { badge("Varsayılan giriş") }
                            if device.id == snapshot.defaultOutput { badge("Varsayılan çıkış") }
                        }
                        FactRow(facts: [StatFact(title: "Giriş kanalı", value: device.inputChannels.map(String.init) ?? "—"),
                            StatFact(title: "Çıkış kanalı", value: device.outputChannels.map(String.init) ?? "—"),
                            StatFact(title: "Giriş seviyesi", value: device.inputVolume.map { MetricFormat.percent($0) } ?? "—"),
                            StatFact(title: "Çıkış seviyesi", value: device.outputVolume.map { MetricFormat.percent($0) } ?? "—")])
                        HStack(spacing: 22) {
                            Text("Giriş sessiz: " + flag(device.inputMuted))
                            Text("Çıkış sessiz: " + flag(device.outputMuted))
                            Spacer()
                            Text(device.running.map { $0 ? "Cihaz I/O çalışıyor" : "Cihaz I/O boşta" } ?? "I/O durumu bilinmiyor")
                        }.font(.caption).foregroundStyle(Palette.secondary)
                    }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                }
                Text("Cihazlar Core Audio üzerinden salt okunur sorgulanır. Seviyeler sürücünün ana kanal kontrolüdür; kontrol yoksa — görünür. I/O çalışması duyulabilir ses veya belirli bir uygulamanın ses çıkarması anlamına gelmez. Mikrofon/sistem sesi kaydı, ses örneği, cihaz değiştirme, ses seviyesi ayarı ve uygulama başına karıştırıcı bu sürümde yoktur. Envanter yalnız güncel bellekte tutulur.")
                    .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else { ProgressView("Ses cihazları bekleniyor") }
        }
    }
    private func flag(_ value: Bool?) -> String { value.map { $0 ? "Evet" : "Hayır" } ?? "—" }
    private func badge(_ text: String) -> some View { Text(text).font(.caption2.weight(.medium)).foregroundStyle(Palette.accent).padding(7).background(Palette.elevated, in: Capsule()) }
}
private struct AccessoryFact: View {
    let title, value, caption: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(color)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(2).frame(minHeight: 52, alignment: .leading)
            Text(caption).font(.caption).foregroundStyle(Palette.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
