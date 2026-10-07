import SwiftUI
import MetricsCore

struct DetailView: View {
    let tab: MonitorTab
    let snapshot: MetricSnapshot
    let history: [MetricSnapshot]

    private var value: String {
        switch tab {
        case .cpu: MetricFormat.percent(snapshot.cpu?.used)
        case .memory: MetricFormat.bytes(snapshot.memory?.used, binary: true)
        case .disk: MetricFormat.bytes(snapshot.disk?.available)
        case .network: MetricFormat.rate(snapshot.network?.incomingRate)
        case .battery: snapshot.battery?.present == false ? "Pil yok" : snapshot.battery?.percent.map { "\($0)%" } ?? "—"
        case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: ""
        }
    }
    private var caption: String {
        switch tab {
        case .cpu: "Tüm çekirdeklerde kullanım"
        case .memory: "Kullanılan fiziksel bellek"
        case .disk: "Başlangıç diskinde boş alan"
        case .network: "Fiziksel arayüzlerde indirme hızı"
        case .battery: snapshot.battery?.stateLabel ?? "Güç kaynağı"
        case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: ""
        }
    }
    private var points: [PlotPoint] {
        plotPoints(history) { sample in
            switch tab {
            case .cpu: sample.cpu?.used
            case .memory: sample.memory?.usedPercent
            case .disk: sample.disk?.io.map { $0.incomingRate + $0.outgoingRate }
            case .network: sample.network?.incomingRate
            case .battery: sample.battery?.percent.map(Double.init)
            case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: nil
            }
        }
    }
    private var facts: [StatFact] {
        switch tab {
        case .cpu:
            return [StatFact(title: "Kullanıcı", value: MetricFormat.percent(snapshot.cpu?.user)), StatFact(title: "Sistem", value: MetricFormat.percent(snapshot.cpu?.system)), StatFact(title: "Boşta", value: MetricFormat.percent(snapshot.cpu?.idle)), StatFact(title: "Mantıksal çekirdek", value: "\(snapshot.system.cores)")]
        case .memory:
            return [StatFact(title: "Toplam", value: MetricFormat.bytes(snapshot.memory?.total, binary: true)), StatFact(title: "Bellek baskısı", value: snapshot.memory?.pressure.label ?? "—"), StatFact(title: "Swap", value: MetricFormat.bytes(snapshot.memory?.swap, binary: true)), StatFact(title: "Kullanım", value: MetricFormat.percent(snapshot.memory?.usedPercent))]
        case .disk:
            return [StatFact(title: "Toplam", value: MetricFormat.bytes(snapshot.disk?.total)), StatFact(title: "Kullanılan", value: MetricFormat.bytes(snapshot.disk?.used)), StatFact(title: "Okuma", value: MetricFormat.rate(snapshot.disk?.io?.incomingRate)), StatFact(title: "Yazma", value: MetricFormat.rate(snapshot.disk?.io?.outgoingRate))]
        case .network:
            return [StatFact(title: "Yükleme hızı", value: MetricFormat.rate(snapshot.network?.outgoingRate)), StatFact(title: "Oturumda alınan", value: MetricFormat.bytes(snapshot.network?.sessionReceived)), StatFact(title: "Oturumda gönderilen", value: MetricFormat.bytes(snapshot.network?.sessionSent)), StatFact(title: "Arayüz", value: "\(snapshot.network?.interfaces.count ?? 0)")]
        case .battery:
            return [StatFact(title: "Güç kaynağı", value: snapshot.battery.map { $0.onAC ? "Adaptör" : ($0.present ? "Pil" : "Şebeke") } ?? "—"), StatFact(title: "Kalan / şarja kalan", value: snapshot.battery?.minutesRemaining.map { MetricFormat.duration(Double($0 * 60)) } ?? "Hesaplanmıyor"), StatFact(title: "Şarj", value: snapshot.battery.map { $0.charging ? "Şarj oluyor" : "Şarj olmuyor" } ?? "—"), StatFact(title: "Düşük güç modu", value: snapshot.battery.map { $0.lowPowerMode ? "Açık" : "Kapalı" } ?? "—")]
        case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: return []
        }
    }
    private var explanation: String {
        switch tab {
        case .cpu: "Kullanıcı ve sistem sürelerinin toplamı, tüm çekirdeklerde 0–100% ölçeğinde gösterilir. İlk örnek hız hesaplamak için başlangıç noktasıdır."
        case .memory: "Kullanılan bellek uygulama, sabit ve sıkıştırılmış belleğin toplamıdır. Bellek baskısı macOS'un ayrı bir ölçümüdür; yüksek doluluk tek başına sorun anlamına gelmez."
        case .disk: "Kapasite başlangıç diskindeki veri birimine aittir. Grafikteki toplam okuma/yazma hızı, erişilebilen tüm fiziksel disk sürücülerini kapsar."
        case .network: "Fiziksel en* arayüzleri ölçülür. VPN, köprü ve loopback trafiği eklenmez; aynı veri iki kez sayılmaz. Oturum toplamı yalnız kesintisiz ölçülen aralıkları içerir."
        case .battery: "Seviye ve süre macOS güç kaynağından alınır. Kalan süre bazı güç durumlarında sistem tarafından hesaplanmaz."
        case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: ""
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label(tab.rawValue, systemImage: tab.icon).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(tab.color)
            VStack(alignment: .leading, spacing: 18) {
                Text(caption).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Text(value).font(.system(size: 60, weight: .semibold, design: .rounded)).monospacedDigit()
                FactRow(facts: facts)
                Divider().overlay(Color.primary.opacity(0.04)).padding(.vertical, 8)
                HStack {
                    Text(tab == .disk ? "Toplam disk I/O" : tab == .memory ? "Bellek kullanım oranı" : "Canlı ölçüm geçmişi")
                    Spacer()
                    Text("\(history.count) örnek").foregroundStyle(Palette.secondary)
                }.font(.system(size: 12, weight: .medium))
                MetricChart(points: points, color: tab.color, ceiling: [.cpu, .memory, .battery].contains(tab) ? 100 : nil, detailed: true,
                            emptyLabel: tab == .battery && snapshot.battery?.present == false ? "Bu Mac'te dahili pil bulunmuyor" : "Ölçüm geçmişi birikiyor")
                    .frame(height: 240)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            if tab == .memory, let memory = snapshot.memory {
                FactRow(facts: [StatFact(title: "Uygulamalar", value: MetricFormat.bytes(memory.app, binary: true)), StatFact(title: "Sabit", value: MetricFormat.bytes(memory.wired, binary: true)), StatFact(title: "Sıkıştırılmış", value: MetricFormat.bytes(memory.compressed, binary: true)), StatFact(title: "Önbellek", value: MetricFormat.bytes(memory.cached, binary: true)), StatFact(title: "Boş", value: MetricFormat.bytes(memory.free, binary: true))])
                    .padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            }
            if tab == .network { NetworkSummary(network: snapshot.network) }
            Label(explanation, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
