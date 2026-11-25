import SwiftUI
import AppKit
import Charts
import MetricsCore

enum Palette {
    static let background = adaptive((0.085, 0.091, 0.105), (0.94, 0.95, 0.97))
    static let card = adaptive((0.125, 0.134, 0.151), (0.99, 0.99, 1.0))
    static let elevated = adaptive((0.165, 0.176, 0.196), (0.86, 0.89, 0.93))
    static let secondary = adaptive((0.60, 0.63, 0.68), (0.34, 0.38, 0.44))
    static let accent = adaptive((0.40, 0.86, 0.72), (0.02, 0.43, 0.34))
    static let cpu = adaptive((0.32, 0.60, 1.0), (0.06, 0.36, 0.77))
    static let memory = adaptive((0.68, 0.56, 0.98), (0.45, 0.25, 0.72))
    static let disk = adaptive((0.97, 0.69, 0.28), (0.56, 0.32, 0.02))
    static let network = adaptive((0.23, 0.80, 0.68), (0.01, 0.43, 0.36))
    static let battery = adaptive((0.42, 0.83, 0.43), (0.14, 0.45, 0.16))
    static let gpu = adaptive((0.96, 0.42, 0.65), (0.65, 0.13, 0.36))
    static let limitNormal = adaptive((0.32, 0.84, 0.43), (0.02, 0.43, 0.15))
    static let limitWarning = adaptive((1.0, 0.73, 0.22), (0.61, 0.36, 0.02))
    static let limitCritical = adaptive((1.0, 0.32, 0.32), (0.75, 0.12, 0.12))
    private static func adaptive(_ dark: (Double, Double, Double), _ light: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: v.0, green: v.1, blue: v.2, alpha: 1)
        })
    }
}

enum MetricFormat {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
    static func bytes(_ value: UInt64?, binary: Bool = false) -> String {
        guard let value else { return "—" }
        return byteAmount(Double(value), binary: binary)
    }
    static func byteAmount(_ value: Double, binary: Bool = false) -> String {
        let base = binary ? 1024.0 : 1000.0
        let units = binary ? ["B", "KiB", "MiB", "GiB", "TiB"] : ["B", "KB", "MB", "GB", "TB"]
        var amount = value
        var unit = 0
        while amount >= base && unit < units.count - 1 { amount /= base; unit += 1 }
        return "\(number(amount, digits: amount < 10 && unit > 0 ? 2 : (unit == 0 ? 0 : 1))) \(units[unit])"
    }
    static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return byteAmount(value) + "/s"
    }
    static func percent(_ value: Double?) -> String { value.map { LocalizedFormat.percent($0) } ?? "—" }
    static func percent(_ value: Int?) -> String { value.map { LocalizedFormat.percent($0) } ?? "—" }
    static func duration(_ seconds: Double) -> String { AIUsage.formatDuration(seconds) }
}

struct StatFact: Identifiable {
    let title, value: String
    var id: String { title }
}

struct FactRow: View {
    let facts: [StatFact]
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 5) {
                    Text(fact.title).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Text(fact.value).font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore).accessibilityLabel(fact.title).accessibilityValue(fact.value)
            }
        }
    }
}

struct PlotPoint: Identifiable {
    let date: Date
    let value: Double
    let segment: Int
    var id: Date { date }
}

func plotPoints(_ snapshots: [MetricSnapshot], value: (MetricSnapshot) -> Double?) -> [PlotPoint] {
    var points: [PlotPoint] = []
    var segment = 0
    var previousDate: Date?
    for snapshot in snapshots {
        guard let number = value(snapshot), number.isFinite else { segment += 1; previousDate = nil; continue }
        if let previousDate, snapshot.date.timeIntervalSince(previousDate) > 20 { segment += 1 }
        points.append(PlotPoint(date: snapshot.date, value: number, segment: segment))
        previousDate = snapshot.date
    }
    return points
}

struct MetricChart: View {
    let points: [PlotPoint]
    let color: Color
    var ceiling: Double? = nil
    var detailed = false
    var emptyLabel = String(localized: "Collecting samples for the chart")
    private var upper: Double { ceiling ?? max(1, (points.map(\.value).max() ?? 0) * 1.2) }
    var body: some View {
        Group {
            if points.count < 2 {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path")
                    Text(emptyLabel)
                }.font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                Chart(points) { point in
                    AreaMark(x: .value("Time", point.date), y: .value("Value", point.value), series: .value("Range", point.segment))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value), series: .value("Range", point.segment))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: detailed ? 2.5 : 1.7))
                }
                .chartYScale(domain: 0...upper)
                .chartXAxis(detailed ? .automatic : .hidden)
                .chartYAxis(detailed ? .automatic : .hidden)
                .chartLegend(.hidden)
                .accessibilityLabel("Live measurement history")
            }
        }
    }
}

struct MetricCard: View {
    let title, icon, eyebrow, value: String
    let color: Color
    let facts: [StatFact]
    let points: [PlotPoint]
    var ceiling: Double? = nil
    var badge: String? = nil
    var emptyLabel = String(localized: "Collecting samples for the chart")
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    HStack(alignment: .lastTextBaseline) {
                        Text(value).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                        Spacer(minLength: 5)
                        if let badge {
                            Text(badge).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.1), in: Capsule())
                        }
                    }
                }
                FactRow(facts: facts)
                MetricChart(points: points, color: color, ceiling: ceiling, emptyLabel: emptyLabel).frame(height: 38)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.035)))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title).accessibilityValue(value).accessibilityHint("Open details")
    }
}

struct RingSlice: Identifiable {
    let title: String
    let value: Double
    let color: Color
    var id: String { title }
}

struct BreakdownCard: View {
    let title, icon, center, subtitle: String
    let color: Color
    let slices: [RingSlice]
    var binary = false
    var percentages = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            HStack(spacing: 20) {
                ZStack {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("Amount", slice.value), innerRadius: .ratio(0.78), angularInset: 1.4)
                            .foregroundStyle(slice.color)
                    }.chartLegend(.hidden).frame(width: 112, height: 112)
                    VStack(spacing: 4) {
                        Text(center).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue("\(center) \(subtitle)")
                VStack(spacing: 10) {
                    ForEach(slices) { slice in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(slice.color).frame(width: 6, height: 6)
                            Text(slice.title).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            Spacer(minLength: 5)
                            Text(percentages ? MetricFormat.percent(slice.value) : MetricFormat.byteAmount(slice.value, binary: binary))
                                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
