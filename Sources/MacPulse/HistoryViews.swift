import SwiftUI
import Charts
import MetricsCore

enum AlertFormat {
    static func value(_ alert: MonitorAlert) -> String {
        switch alert.kind {
        case .systemCPU, .applicationCPU: MetricFormat.number(alert.value) + "% CPU"
        case .memoryGrowth: "+" + MetricFormat.byteAmount(alert.value, binary: true) + " / 10 dk"
        case .swapUsage: "Toplam swap: " + MetricFormat.byteAmount(alert.value)
        case .network, .disk: MetricFormat.rate(alert.value)
        }
    }
}

private enum HistoryFormat {
    static func duration(_ seconds: Double) -> String { seconds < 60 ? "\(max(0, Int(seconds))) sn" : MetricFormat.duration(seconds) }
    static func total(_ report: HistoryReport, _ metric: HistoryMetric) -> String {
        let moment = report.moment(metric)
        return moment.seconds > 0 ? MetricFormat.byteAmount(moment.total) : "—"
    }
}

struct AlertListView: View {
    let alerts: [MonitorAlert]
    var limit: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if alerts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Henüz uyarı yok", systemImage: "checkmark.circle").font(.system(size: 14, weight: .medium))
                    Text("Swap kullanımı başladığında ve her 1 GB eşiğinde uyarı oluşur. CPU, bellek büyümesi ve aktarım kuralları süre koşullarına göre değerlendirilir.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }.padding(22)
            }
            ForEach(Array(alerts.prefix(limit ?? alerts.count))) { alert in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: alert.active ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(alert.active ? Palette.disk : Palette.secondary).font(.system(size: 20)).frame(width: 26)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alert.kind.title).font(.system(size: 13, weight: .semibold))
                        Text("\(alert.target) · \(AlertFormat.value(alert))").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Text(alert.interrupted ? "İzleme kesildi; devam ettiği varsayılmadı" : alert.kind == .swapUsage ? (alert.active ? "Swap kullanımı gözlendi" : "Swap ölçümü kaydedildi") : (alert.active ? "Süre koşulu sağlandı · izleniyor" : "Koşul sona erdi"))
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(alert.emitted.formatted(date: .abbreviated, time: .shortened))
                        Text("İzlenen süre: \(MetricFormat.duration(alert.updated.timeIntervalSince(alert.started)))")
                    }.font(.system(size: 10)).foregroundStyle(Palette.secondary).monospacedDigit()
                }.padding(18)
                Divider().opacity(0.3)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AlertsView: View {
    @Bindable var store: MonitorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Dikkat gerektiren durumlar").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(store.alerts.filter(\.active).count) etkin · son \(store.alerts.count) kayıt").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 14) {
                Image(systemName: store.notifications.enabled ? "bell.badge" : "bell.slash").foregroundStyle(Palette.disk)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sistem bildirimleri").font(.system(size: 13, weight: .semibold))
                    Text(store.notifications.status).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button(store.notifications.enabled ? "Bildirimleri kapat" : "Bildirimleri aç") { Task { await store.notifications.toggle() } }
                    .disabled(store.notifications.requesting)
            }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            AlertListView(alerts: store.alerts)
            VStack(alignment: .leading, spacing: 12) {
                Text("Uyarı koşulları").font(.system(size: 15, weight: .semibold))
                rule("Sistem CPU", "Tüm çekirdeklerde ≥ %85, kesintisiz 2 dakika")
                rule("Uygulama CPU", "Bir çekirdek ölçeğinde ≥ %80, kesintisiz 2 dakika")
                rule("Bellek büyümesi", "Aynı süreç üyeleriyle 10 dakikada ≥ 512 MiB artış")
                rule("Swap", "İlk kullanımda ve 1, 2, 3… GB eşikleri geçildiğinde toplam miktar")
                rule("Ağ / disk", "Okuma + yazma veya indirme + yükleme: 50 / 100 MB/s, kesintisiz 1 dakika")
                Text("Swap için süre veya 10 dakika bekleme koşulu yoktur. Aynı seviye tekrar bildirilmez; swap sıfırlanınca veya uygulama yeniden açılınca takip yeniden başlar. Bir ölçümde birden fazla eşik geçilirse güncel toplamla tek uyarı oluşur. Diğer kurallarda ilk hız örneği, eksik ölçüm, duraklatma ve 20 saniyeyi aşan aralıklar süre koşulunu sıfırlar; aynı konu için en az 10 dakika beklenir. Bellek büyümesi tek başına bellek sızıntısı tanısı değildir.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func rule(_ title: String, _ text: String) -> some View {
        HStack { Text(title).fontWeight(.medium).frame(width: 145, alignment: .leading); Text(text).foregroundStyle(Palette.secondary) }.font(.system(size: 12))
    }
}

struct HistoryView: View {
    @Bindable var store: MonitorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Ölçüm geçmişi").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                if store.historyLoading { ProgressView().controlSize(.small) }
                Picker("Dönem", selection: $store.historyRange) {
                    ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 340)
            }
            if let report = store.historyReport, report.range == store.historyRange {
                FactRow(facts: [StatFact(title: "Ölçülen süre", value: HistoryFormat.duration(report.observedSeconds)),
                    StatFact(title: "Özet", value: "\(report.buckets.count) \(report.range.daily ? "gün" : "dakika")"),
                    StatFact(title: "CPU ortalaması", value: MetricFormat.percent(report.moment(.cpu).average)),
                    StatFact(title: "CPU tepesi", value: report.moment(.cpu).seconds > 0 ? MetricFormat.percent(report.moment(.cpu).peak) : "—")])
                    .padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                Text("\(report.range.daily ? "Gün özetleri UTC gün sınırlarıyla hesaplanır." : "Dakika özetleri ölçülen süreye göre ağırlıklandırılır.") Ölçülmeyen süreler toplam ve ortalamaya eklenmez. \(report.gapCount) başlangıç / kesinti kaydı.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    HistoryChart(title: "Sistem CPU · %", metric: .cpu, report: report, color: Palette.cpu, ceiling: 100)
                    HistoryChart(title: "Kullanılan RAM · GiB", metric: .memory, report: report, color: Palette.memory, divisor: 1_073_741_824)
                    HistoryChart(title: "İndirme · MB/s", metric: .download, report: report, color: Palette.network, divisor: 1_000_000)
                    HistoryChart(title: "Disk yazma · MB/s", metric: .diskWrite, report: report, color: Palette.disk, divisor: 1_000_000)
                }
                FactRow(facts: [StatFact(title: "Ölçülen indirme", value: HistoryFormat.total(report, .download)),
                    StatFact(title: "Ölçülen yükleme", value: HistoryFormat.total(report, .upload)),
                    StatFact(title: "Disk okuma", value: HistoryFormat.total(report, .diskRead)),
                    StatFact(title: "Disk yazma", value: HistoryFormat.total(report, .diskWrite))])
                    .padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                historyApplications(report)
                Text("Kayıt bu Mac'te tutulur: bugün ve önceki 29 UTC günü. Uygulama kaydı dakika başına en çok 20 grup, CPU/bellek ilk 10 adayından seçilir; gün başına en çok 256 farklı grup tutulur. Grup ortalamaları yalnız kaydedilen, tam ölçülmüş üyelerin gözlem sürelerine aittir. Komut argümanları, ortam bilgisi, PID listesi ve dosya yolları kaydedilmez.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.historyError == nil ? "Geçmiş hazırlanıyor. İlk hız ölçümlerinden sonra dakika özeti görünür." : "Geçmiş şu anda kullanılamıyor.")
                    .foregroundStyle(Palette.secondary).padding(.vertical, 40)
            }
        }
    }
    private func historyApplications(_ report: HistoryReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Kaydedilen uygulama grupları").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("CPU ortalamasına göre ilk 10").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            if report.buckets.contains(where: \.applicationsTruncated) {
                Text("Bazı özetlerde grup sınırına ulaşıldı; liste tüm uygulamaları kapsamaz.").font(.system(size: 11)).foregroundStyle(Palette.disk)
            }
            HStack {
                Text("Grup"); Spacer()
                Text("Gözlem").frame(width: 120, alignment: .trailing)
                Text("CPU ort.").frame(width: 100, alignment: .trailing)
                Text("Bellek tepesi").frame(width: 145, alignment: .trailing)
            }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
            ForEach(Array(report.applications.prefix(10))) { app in
                HStack {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(HistoryFormat.duration(max(app.cpu.seconds, app.memory.seconds))).frame(width: 120, alignment: .trailing)
                    Text(ApplicationFormat.cpu(app.cpu.average)).foregroundStyle(Palette.cpu).frame(width: 100, alignment: .trailing)
                    Text(app.memory.seconds > 0 ? MetricFormat.byteAmount(app.memory.peak, binary: true) : "—").frame(width: 145, alignment: .trailing)
                }.font(.system(size: 12)).monospacedDigit()
                Divider().opacity(0.3)
            }
        }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HistoryChart: View {
    let title: String
    let metric: HistoryMetric
    let report: HistoryReport
    let color: Color
    var divisor = 1.0
    var ceiling: Double? = nil
    private var points: [PlotPoint] {
        var segment = 0
        var last: Int64?
        return report.buckets.compactMap { bucket in
            guard let value = bucket.average(metric) else { segment += 1; last = nil; return nil }
            let size: Int64 = report.range.daily ? 86_400 : 60
            if bucket.gaps > 0 || last.map({ bucket.start - $0 > size }) == true { segment += 1 }
            last = bucket.start
            return PlotPoint(date: bucket.date, value: value / divisor, segment: segment)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            if points.isEmpty {
                Text("Bu dönemde ölçüm yok").font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, minHeight: 190)
            } else {
                Chart(points) { point in
                    if report.range.daily {
                        BarMark(x: .value("Gün", point.date, unit: .day), y: .value(title, point.value)).foregroundStyle(color.opacity(0.7))
                    } else {
                        LineMark(x: .value("Zaman", point.date), y: .value(title, point.value), series: .value("Ölçülen aralık", point.segment)).foregroundStyle(color)
                        PointMark(x: .value("Zaman", point.date), y: .value(title, point.value)).foregroundStyle(color).symbolSize(18)
                    }
                }.chartLegend(.hidden).chartYScale(domain: 0...(ceiling ?? max(1, (points.map(\.value).max() ?? 0) * 1.2)))
                    .chartXScale(domain: min(report.generated.addingTimeInterval(-report.range.seconds), report.buckets.first?.date ?? report.generated)...report.generated)
                    .frame(height: 190).accessibilityLabel(title + ", ölçülen dönem ortalamaları")
            }
            Text(report.range.daily ? "Yalnız ölçülen günler · eksik süreler hariç" : "Kesinti içeren dakikalar ayrı çizgi segmentleri · dakika içi süreler özetlenir")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
