import SwiftUI
import Charts
import MetricsCore

enum AlertFormat {
    static func value(_ alert: MonitorAlert) -> String {
        switch alert.kind {
        case .systemCPU, .applicationCPU: LocalizedFormat.percent(alert.value, digits: 1) + " CPU"
        case .memoryGrowth: "+" + MetricFormat.byteAmount(alert.value, binary: true) + " / " + AIUsage.formatDuration(600)
        case .swapUsage: String(localized: "Total swap: \(MetricFormat.byteAmount(alert.value))")
        case .network, .disk: MetricFormat.rate(alert.value)
        }
    }
}

private enum HistoryFormat {
    static func duration(_ seconds: Double) -> String { seconds < 60 ? String(localized: "\(max(0, Int(seconds)))s") : MetricFormat.duration(seconds) }
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
                    Label("No alerts yet", systemImage: "checkmark.circle").font(.system(size: 14, weight: .medium))
                    Text("An alert is created when swap usage starts and at every 1 GB threshold. CPU, memory growth and transfer rules are evaluated against duration conditions.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }.padding(22)
            }
            ForEach(Array(alerts.prefix(limit ?? alerts.count))) { alert in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: alert.active ? "exclamationmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(alert.active ? Palette.disk : Palette.secondary).font(.system(size: 20)).frame(width: 26)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alert.kind.title).font(.system(size: 13, weight: .semibold))
                        Text("\(alert.displayTarget) · \(AlertFormat.value(alert))").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Text(alert.interrupted ? "Monitoring was interrupted; it wasn't assumed to continue" : alert.kind == .swapUsage ? (alert.active ? "Swap usage observed" : "Swap measurement recorded") : (alert.active ? "Duration condition met · monitoring" : "Condition ended"))
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(alert.emitted.formatted(date: .abbreviated, time: .shortened))
                        Text("Monitored for: \(MetricFormat.duration(alert.updated.timeIntervalSince(alert.started)))")
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
                Text("Needs attention").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(store.alerts.filter(\.active).count) active · last \(store.alerts.count) records").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 14) {
                Image(systemName: store.notifications.enabled ? "bell.badge" : "bell.slash").foregroundStyle(Palette.disk)
                VStack(alignment: .leading, spacing: 5) {
                    Text("System notifications").font(.system(size: 13, weight: .semibold))
                    Text(store.notifications.status).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button(store.notifications.enabled ? "Turn off notifications" : "Turn on notifications") { Task { await store.notifications.toggle() } }
                    .disabled(store.notifications.requesting)
            }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            AlertListView(alerts: store.alerts)
            VStack(alignment: .leading, spacing: 12) {
                Text("Alert conditions").font(.system(size: 15, weight: .semibold))
                rule("System CPU", "≥ 85% across all cores, for 2 minutes straight")
                rule("App CPU", "≥ 80% on a one-core scale, for 2 minutes straight")
                rule("Memory growth", "≥ 512 MiB increase in 10 minutes with the same member processes")
                rule("Swap", "Total amount on first use and when crossing 1, 2, 3… GB")
                rule("Network / disk", "Read + write or download + upload: 50 / 100 MB/s, for 1 minute straight")
                Text("Swap has no duration or 10-minute wait condition. The same level isn't reported twice; tracking restarts when swap resets or the app relaunches. If several thresholds are crossed in one reading, a single alert is created with the current total. For other rules, the first rate sample, a missing measurement, pausing and gaps longer than 20 seconds reset the duration condition; the same subject waits at least 10 minutes. Memory growth alone isn't a memory leak diagnosis.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func rule(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack { Text(title).fontWeight(.medium).frame(width: 145, alignment: .leading); Text(text).foregroundStyle(Palette.secondary) }.font(.system(size: 12))
    }
}

struct HistoryView: View {
    @Bindable var store: MonitorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Measurement history").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                if store.historyLoading { ProgressView().controlSize(.small) }
                Picker("Period", selection: $store.historyRange) {
                    ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(width: 340)
            }
            if let report = store.historyReport, report.range == store.historyRange {
                FactRow(facts: [StatFact(title: String(localized: "Measured time"), value: HistoryFormat.duration(report.observedSeconds)),
                    StatFact(title: String(localized: "Summary"), value: report.range.daily ? String(localized: "\(report.buckets.count) days") : String(localized: "\(report.buckets.count) minutes")),
                    StatFact(title: String(localized: "CPU average"), value: MetricFormat.percent(report.moment(.cpu).average)),
                    StatFact(title: String(localized: "CPU peak"), value: report.moment(.cpu).seconds > 0 ? MetricFormat.percent(report.moment(.cpu).peak) : "—")])
                    .padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                Text((report.range.daily ? String(localized: "Daily summaries use UTC day boundaries.") : String(localized: "Minute summaries are weighted by measured time."))
                     + " " + String(localized: "Unmeasured time isn't added to totals or averages. \(report.gapCount) start / interruption records."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    HistoryChart(title: String(localized: "System CPU · %"), metric: .cpu, report: report, color: Palette.cpu, ceiling: 100)
                    HistoryChart(title: String(localized: "Used RAM · GiB"), metric: .memory, report: report, color: Palette.memory, divisor: 1_073_741_824)
                    HistoryChart(title: String(localized: "Download · MB/s"), metric: .download, report: report, color: Palette.network, divisor: 1_000_000)
                    HistoryChart(title: String(localized: "Disk write · MB/s"), metric: .diskWrite, report: report, color: Palette.disk, divisor: 1_000_000)
                }
                FactRow(facts: [StatFact(title: String(localized: "Measured download"), value: HistoryFormat.total(report, .download)),
                    StatFact(title: String(localized: "Measured upload"), value: HistoryFormat.total(report, .upload)),
                    StatFact(title: String(localized: "Disk read"), value: HistoryFormat.total(report, .diskRead)),
                    StatFact(title: String(localized: "Disk write"), value: HistoryFormat.total(report, .diskWrite))])
                    .padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                historyApplications(report)
                Text("History is kept on this Mac: today and the previous 29 UTC days. App history records at most 20 groups per minute, chosen from the top 10 CPU/memory candidates, and at most 256 distinct groups per day. Group averages cover only the observed time of recorded, fully measured members. Command arguments, environment, PID lists and file paths aren't recorded.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.historyError == nil ? "Preparing history. Minute summaries appear after the first rate measurements." : "History isn't available right now.")
                    .foregroundStyle(Palette.secondary).padding(.vertical, 40)
            }
        }
    }
    private func historyApplications(_ report: HistoryReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recorded app groups").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("Top 10 by CPU average").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            if report.buckets.contains(where: \.applicationsTruncated) {
                Text("Some summaries hit the group limit; the list doesn't cover every app.").font(.system(size: 11)).foregroundStyle(Palette.disk)
            }
            HStack {
                Text("Group"); Spacer()
                Text("Observed").frame(width: 120, alignment: .trailing)
                Text("CPU avg.").frame(width: 100, alignment: .trailing)
                Text("Peak memory").frame(width: 145, alignment: .trailing)
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
                Text("No measurements in this period").font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, minHeight: 190)
            } else {
                Chart(points) { point in
                    if report.range.daily {
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value(title, point.value)).foregroundStyle(color.opacity(0.7))
                    } else {
                        LineMark(x: .value("Time", point.date), y: .value(title, point.value), series: .value("Measured interval", point.segment)).foregroundStyle(color)
                        PointMark(x: .value("Time", point.date), y: .value(title, point.value)).foregroundStyle(color).symbolSize(18)
                    }
                }.chartLegend(.hidden).chartYScale(domain: 0...(ceiling ?? max(1, (points.map(\.value).max() ?? 0) * 1.2)))
                    .chartXScale(domain: min(report.generated.addingTimeInterval(-report.range.seconds), report.buckets.first?.date ?? report.generated)...report.generated)
                    .frame(height: 190).accessibilityLabel(String(localized: "\(title), measured period averages"))
            }
            Text(report.range.daily ? "Measured days only · missing time excluded" : "Minutes with interruptions are separate line segments · time within a minute is summarized")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
