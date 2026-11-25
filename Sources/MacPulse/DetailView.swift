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
        case .battery: snapshot.battery?.present == false ? String(localized: "No battery") : MetricFormat.percent(snapshot.battery?.percent)
        case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: ""
        }
    }
    private var caption: String {
        switch tab {
        case .cpu: String(localized: "Usage across all cores")
        case .memory: String(localized: "Physical memory used")
        case .disk: String(localized: "Free space on startup disk")
        case .network: String(localized: "Download speed on physical interfaces")
        case .battery: snapshot.battery?.stateLabel ?? String(localized: "Power source")
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
            return [StatFact(title: String(localized: "User"), value: MetricFormat.percent(snapshot.cpu?.user)), StatFact(title: String(localized: "System"), value: MetricFormat.percent(snapshot.cpu?.system)), StatFact(title: String(localized: "Idle"), value: MetricFormat.percent(snapshot.cpu?.idle)), StatFact(title: String(localized: "Logical cores"), value: "\(snapshot.system.cores)")]
        case .memory:
            return [StatFact(title: String(localized: "Total"), value: MetricFormat.bytes(snapshot.memory?.total, binary: true)), StatFact(title: String(localized: "Memory pressure"), value: snapshot.memory?.pressure.label ?? "—"), StatFact(title: "Swap", value: MetricFormat.bytes(snapshot.memory?.swap, binary: true)), StatFact(title: String(localized: "Usage"), value: MetricFormat.percent(snapshot.memory?.usedPercent))]
        case .disk:
            return [StatFact(title: String(localized: "Total"), value: MetricFormat.bytes(snapshot.disk?.total)), StatFact(title: String(localized: "Used"), value: MetricFormat.bytes(snapshot.disk?.used)), StatFact(title: String(localized: "Read"), value: MetricFormat.rate(snapshot.disk?.io?.incomingRate)), StatFact(title: String(localized: "Write"), value: MetricFormat.rate(snapshot.disk?.io?.outgoingRate))]
        case .network:
            return [StatFact(title: String(localized: "Upload speed"), value: MetricFormat.rate(snapshot.network?.outgoingRate)), StatFact(title: String(localized: "Received this session"), value: MetricFormat.bytes(snapshot.network?.sessionReceived)), StatFact(title: String(localized: "Sent this session"), value: MetricFormat.bytes(snapshot.network?.sessionSent)), StatFact(title: String(localized: "Interfaces"), value: "\(snapshot.network?.interfaces.count ?? 0)")]
        case .battery:
            return [StatFact(title: String(localized: "Power source"), value: snapshot.battery.map { $0.onAC ? String(localized: "Adapter") : ($0.present ? String(localized: "Battery") : String(localized: "AC power")) } ?? "—"), StatFact(title: String(localized: "Remaining / until full"), value: snapshot.battery?.minutesRemaining.map { MetricFormat.duration(Double($0 * 60)) } ?? String(localized: "Not calculated")), StatFact(title: String(localized: "Charge"), value: snapshot.battery.map { $0.charging ? String(localized: "Charging") : String(localized: "Not charging") } ?? "—"), StatFact(title: String(localized: "Low Power Mode"), value: snapshot.battery.map { $0.lowPowerMode ? String(localized: "On") : String(localized: "Off") } ?? "—")]
        case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: return []
        }
    }
    private var explanation: String {
        switch tab {
        case .cpu: String(localized: "Sum of user and system time, shown on a 0–100 percent scale across all cores. The first sample is the baseline for calculating rates.")
        case .memory: String(localized: "Used memory is the sum of app, wired and compressed memory. Memory pressure is a separate macOS measurement; a nearly full memory alone doesn't mean there's a problem.")
        case .disk: String(localized: "Capacity belongs to the data volume on the startup disk. The total read/write rate in the chart covers all accessible physical disk drives.")
        case .network: String(localized: "Physical en* interfaces are measured. VPN, bridge and loopback traffic is excluded, so no data is counted twice. The session total includes only uninterrupted measurement intervals.")
        case .battery: String(localized: "Level and time come from the macOS power source. In some power states the system doesn't calculate the remaining time.")
        case .overview, .applications, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio, .usage: ""
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label(tab.label, systemImage: tab.icon).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(tab.color)
            VStack(alignment: .leading, spacing: 18) {
                Text(caption).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Text(value).font(.system(size: 60, weight: .semibold, design: .rounded)).monospacedDigit()
                FactRow(facts: facts)
                Divider().overlay(Color.primary.opacity(0.04)).padding(.vertical, 8)
                HStack {
                    Text(tab == .disk ? "Total disk I/O" : tab == .memory ? "Memory usage ratio" : "Live measurement history")
                    Spacer()
                    Text("\(history.count) samples").foregroundStyle(Palette.secondary)
                }.font(.system(size: 12, weight: .medium))
                MetricChart(points: points, color: tab.color, ceiling: [.cpu, .memory, .battery].contains(tab) ? 100 : nil, detailed: true,
                            emptyLabel: tab == .battery && snapshot.battery?.present == false ? String(localized: "This Mac has no internal battery") : String(localized: "Building measurement history"))
                    .frame(height: 240)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            if tab == .memory, let memory = snapshot.memory {
                FactRow(facts: [StatFact(title: String(localized: "Apps"), value: MetricFormat.bytes(memory.app, binary: true)), StatFact(title: String(localized: "Wired"), value: MetricFormat.bytes(memory.wired, binary: true)), StatFact(title: String(localized: "Compressed"), value: MetricFormat.bytes(memory.compressed, binary: true)), StatFact(title: String(localized: "Cached"), value: MetricFormat.bytes(memory.cached, binary: true)), StatFact(title: String(localized: "Free"), value: MetricFormat.bytes(memory.free, binary: true))])
                    .padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            }
            if tab == .network { NetworkSummary(network: snapshot.network) }
            Label(explanation, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
