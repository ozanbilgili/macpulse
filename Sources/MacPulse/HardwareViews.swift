import SwiftUI
import MetricsCore

enum HardwareFormat {
    static func temperature(_ value: Double?) -> String { value.map { MetricFormat.number($0) + " °C" } ?? "—" }
    static func watts(_ value: Double?) -> String { value.map { MetricFormat.number($0, digits: 2) + " W" } ?? "—" }
    static func flow(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value > 0 { return "↑ " + watts(value) }
        if value < 0 { return "↓ " + watts(-value) }
        return watts(0)
    }
}

struct HardwareView: View {
    let snapshot: HardwareSnapshot?
    let system: SystemMetrics
    let history: [MetricSnapshot]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("GPU ve enerji", systemImage: "square.3.layers.3d").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Palette.gpu)
                Spacer()
                Text("\(system.chip) · \(system.cores) çekirdek").font(.caption).foregroundStyle(Palette.secondary)
            }
            if let snapshot {
                ForEach(snapshot.gpus) { gpu in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("GPU kullanımı").font(.headline)
                            Spacer()
                            Text(MetricFormat.percent(gpu.devicePercent)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.gpu)
                        }
                        FactRow(facts: [StatFact(title: "Renderer", value: MetricFormat.percent(gpu.rendererPercent)), StatFact(title: "Tiler", value: MetricFormat.percent(gpu.tilerPercent)), StatFact(title: "Kullanılan sürücü belleği", value: MetricFormat.bytes(gpu.memoryInUse, binary: true)), StatFact(title: "Ayrılmış sürücü belleği", value: MetricFormat.bytes(gpu.memoryAllocated, binary: true))])
                        MetricChart(points: plotPoints(history) { $0.hardware?.gpus.first { $0.id == gpu.id }?.devicePercent }, color: Palette.gpu, ceiling: 100, detailed: true).frame(height: 190)
                        Text("AGX sürücüsünün kullanım sayaçlarıdır; sürücünün ölçüm penceresi bilinmez. Bellek değerleri GPU kaynaklarına ayrılan sistem belleğidir; ayrı VRAM veya fiziksel RAM toplamına eklenebilen değerler değildir.")
                            .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                }
                if snapshot.gpus.isEmpty { unavailable(snapshot.gpuStatus) }
                Text("Güç ve sıcaklık").font(.title3.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    HardwareValue(title: "Sistem güç kanalı", value: HardwareFormat.watts(snapshot.systemWatts), caption: "SMC PSTR · bildirilen değer", color: Palette.accent)
                    HardwareValue(title: "GPU enerji modeli", value: HardwareFormat.watts(snapshot.gpuModelWatts), caption: "IOReport · aralık ortalaması", color: Palette.gpu)
                    HardwareValue(title: "Pil net akışı", value: HardwareFormat.flow(snapshot.batteryNetWatts), caption: "↑ pile giriş · ↓ pilden çıkış", color: Palette.battery)
                    HardwareValue(title: "CPU sensörleri · kısmi", value: HardwareFormat.temperature(snapshot.cpuTemperatureAverage), caption: "Yalnız doğrulanan sensör grubu", color: Palette.cpu)
                    HardwareValue(title: "GPU sensör ortalaması", value: HardwareFormat.temperature(snapshot.gpuTemperatureAverage), caption: "Yalnız geçerli Tg sensörleri", color: Palette.gpu)
                    HardwareValue(title: "macOS termal durumu", value: system.thermalState, caption: "İşletim sistemi · derece değildir", color: Palette.disk)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(snapshot.energyStatus, systemImage: "info.circle")
                    Text("GPU watt değeri enerji modelinden hesaplanır; donanım güç ölçeri değildir. Sistem güç kanalı ve pil akışı farklı kapsamdadır; birbirine eklenmez ve prizden çekilen güç olarak sunulmaz. CPU/ANE watt ve uygulama başına enerji bu sürümde ölçülmez.")
                    Text(snapshot.batteryFlowStatus + (snapshot.batteryUpdatedAt.map { " · Kaynak güncellemesi " + $0.formatted(date: .omitted, time: .standard) } ?? ""))
                }.font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 14) {
                    HardwarePlot(title: "GPU enerji modeli · W", points: plotPoints(history) { $0.hardware?.gpuModelWatts }, color: Palette.gpu)
                    HardwarePlot(title: "Sistem güç kanalı · W", points: plotPoints(history) { $0.hardware?.systemWatts }, color: Palette.accent)
                }
                HStack {
                    Text("Sensör okumaları").font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(snapshot.sensors.count) geçerli · \(snapshot.invalidSensors) geçersiz · \(snapshot.sensorFailures) okunamadı").font(.caption).foregroundStyle(Palette.secondary)
                }
                Text(snapshot.sensorStatus + (snapshot.sensorsTruncated ? " · Liste kısmi" : "") + " · " + snapshot.date.formatted(date: .omitted, time: .standard))
                    .font(.caption).foregroundStyle(Palette.secondary)
                if snapshot.sensors.isEmpty { unavailable("Sensör verisi doğrulanamıyor; fan hızı ve sıcaklık sıfır kabul edilmez.") }
                else {
                    VStack(spacing: 0) {
                        ForEach(snapshot.sensors) { sensor in
                            HStack {
                                Image(systemName: sensor.kind == .fan ? "fan" : sensor.kind == .systemPower ? "bolt" : "thermometer.medium").frame(width: 24).foregroundStyle(sensor.kind == .gpu ? Palette.gpu : Palette.secondary)
                                Text(sensor.id).font(.system(.body, design: .monospaced)).frame(width: 70, alignment: .leading)
                                Text(sensor.kind == .fan ? "Fan · gerçek devir" : sensor.kind == .systemPower ? "Sistem güç kanalı" : sensor.kind == .gpu ? "GPU sensör grubu" : "CPU sensör grubu").foregroundStyle(Palette.secondary)
                                Spacer()
                                Text(sensor.kind == .fan ? MetricFormat.number(sensor.value, digits: 0) + " rpm" : sensor.kind == .systemPower ? HardwareFormat.watts(sensor.value) : HardwareFormat.temperature(sensor.value)).monospacedDigit()
                            }.font(.system(size: 12)).padding(12)
                            Divider()
                        }
                    }.background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                }
                Text("SMC sensör adları ve eşlemeleri belgelenmemiştir; ortalama yalnız bu cihazda geçerli okunan grubu kapsar, tüm çekirdeklerin kesin sıcaklığı değildir. macOS 27+ üzerinde doğrulanamayan Tp grubu dışarıda kalır; CPU sıcaklığı kısmi Te grubudur. Sıcaklık iki geçerli ardışık okumadan sonra görünür. Eksik/geçersiz veri ortalamaya girmez. Fanlar yalnız okunur. GPU/SMC/IOReport erişimi cihaz veya macOS sürümüyle değişebilir; yetkili yardımcı kurulmaz.")
                    .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Ayrıntılı sensör listesi yalnız canlı bellektedir. Grafikler son 90 donanım örneğini kapsar; 30 günlük kayıt bu metriklerle genişletilmedi.")
                    .font(.caption).foregroundStyle(Palette.secondary)
            } else { unavailable("Donanım ölçümleri bekleniyor") }
        }
    }
    private func unavailable(_ text: String) -> some View {
        Label(text, systemImage: "info.circle").font(.callout).foregroundStyle(Palette.secondary)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
private struct HardwareValue: View {
    let title, value, caption: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 15))
    }
}
private struct HardwarePlot: View {
    let title: String
    let points: [PlotPoint]
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            MetricChart(points: points, color: color, detailed: true).frame(height: 150)
        }.padding(18).frame(maxWidth: .infinity).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
