import SwiftUI
import MetricsCore

struct DeviceBatteryHistoryView: View {
    let store: DeviceBatteryStore
    let deviceID: String
    @State private var hours = 6
    @State private var focused = true
    private var device: BatteryDevice? { store.devices.first { $0.id == deviceID } }

    var body: some View {
        let now = Date()
        let chart = BatteryHistoryChart(history: store.history, deviceID: deviceID,
                                        since: now.addingTimeInterval(-Double(hours) * 3600), until: now, focused: focused)
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(spacing: 0) {
                HistoryMetric(title: "Change", value: chart.change.map { change in String(localized: "\((change > 0 ? "+" : "") + String(change)) pts") } ?? "—",
                              detail: String(localized: "First and last reading"), symbol: chart.change.map { $0 > 0 ? "arrow.up.right" : ($0 < 0 ? "arrow.down.right" : "arrow.right") } ?? "minus")
                Divider().frame(height: 34).padding(.horizontal, 18)
                HistoryMetric(title: "Battery range", value: chart.measuredRange.map { $0.lowerBound == $0.upperBound ? LocalizedFormat.percent($0.lowerBound) : LocalizedFormat.percent($0.lowerBound) + "–" + LocalizedFormat.percent($0.upperBound) } ?? "—",
                              detail: String(localized: "Lowest · highest"), symbol: "battery.75percent")
                Divider().frame(height: 34).padding(.horizontal, 18)
                HistoryMetric(title: "Readings", value: "\(chart.points.count)", detail: measurementSpan(chart), symbol: "waveform.path")
            }
            .padding(.horizontal, 2)

            VStack(spacing: 12) {
                HStack {
                    Picker("Time range", selection: $hours) {
                        Text("6 hours").tag(6)
                        Text("24 hours").tag(24)
                        Text("7 days").tag(168)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 224)
                    .accessibilityIdentifier("history-period")
                    Spacer()
                    Toggle(isOn: $focused) { Label("Focus on data", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .toggleStyle(.button).buttonStyle(.bordered).controlSize(.small)
                        .help("Zoom in on the times and battery levels that have readings. When off, the whole range and a 0–100% scale are shown.")
                        .accessibilityIdentifier("history-focus")
                }
                HistoryPlot(chart: chart, hours: hours, focused: focused)
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.07), lineWidth: 1) }

            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.tertiary)
                Text(store.history.samples[deviceID]?.first.map { String(localized: "Recording since \($0.date.formatted(date: .abbreviated, time: .shortened))") } ?? String(localized: "Readings are recorded while MacPulse is running."))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let device, device.source != .mac {
                    Button { ConnectionSettings.open(device) } label: {
                        Label(device.connection?.label ?? String(localized: "Connection"), systemImage: "network")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Open connection settings")
                }
            }
            .font(.system(size: 11))
        }
        .padding(24).frame(width: 680, height: 520)
        .background(Palette.background)
        
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 21, weight: .medium)).foregroundStyle(.blue)
                .frame(width: 46, height: 46)
                .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(device.map { store.name($0) } ?? String(localized: "Battery history"))
                    .font(.system(size: 21, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(!store.isPaused && device?.isLive(at: store.now) == true ? Color.green : Color.secondary).frame(width: 5, height: 5)
                    Text(device.map { (!store.isPaused && $0.isLive(at: store.now)) ? ($0.isCharging && $0.displayLevel() != nil ? String(localized: "Charging") : String(localized: "Connected")) : String(localized: "Offline") } ?? String(localized: "Battery history"))
                    if let connection = device?.connection { Text("· " + connection.label) }
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if !store.isPaused && device?.isLive(at: store.now) == true, device?.isCharging == true, device?.displayLevel() != nil {
                        Image(systemName: "bolt.fill").font(.system(size: 18)).foregroundStyle(.green)
                    }
                    Text(device?.displayLevel().map { (device?.approximate == true ? "≈" : "") + LocalizedFormat.percent($0) } ?? "—")
                        .font(.system(size: 31, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Text(!store.isPaused && device?.isLive(at: store.now) == true && device?.displayLevel() != nil ? "Current battery" : "Last measured")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if !store.isPaused, let power = device?.displayPower(at: store.now) {
                    Text(power.powerText).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(power.netWatts > 0 ? Color.green : .secondary)
                        .help(power.powerHelp).accessibilityIdentifier("history-power")
                }
            }
        }
    }

    private func measurementSpan(_ chart: BatteryHistoryChart) -> String {
        guard let first = chart.points.first, let last = chart.points.last else { return String(localized: "No records yet") }
        if first.date == last.date { return String(localized: "Single reading") }
        if Calendar.current.isDate(first.date, inSameDayAs: last.date) {
            return first.date.formatted(date: .omitted, time: .shortened) + " – " + last.date.formatted(date: .omitted, time: .shortened)
        }
        return first.date.formatted(.dateTime.day().month(.abbreviated)) + " – " + last.date.formatted(.dateTime.day().month(.abbreviated))
    }
}

private struct HistoryMetric: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).help(detail)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryPlot: View {
    let chart: BatteryHistoryChart
    let hours: Int
    let focused: Bool
    @State private var selectedDate: Date?
    @State private var pinned = false
    private let blue = Palette.accent
    private let green = Palette.battery
    private var selected: BatteryHistoryPoint? { chart.points.first { $0.date == selectedDate } }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                legend("Battery level", color: blue)
                legend("Charge", color: green)
                Spacer()
                Text(focused && !chart.points.isEmpty ? "Zoomed view · \(LocalizedFormat.percent(chart.levelRange.lowerBound))–\(LocalizedFormat.percent(chart.levelRange.upperBound))" : "Full scale · \(LocalizedFormat.percent(0))–\(LocalizedFormat.percent(100))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                HStack(spacing: 9) {
                    GeometryReader { geometry in
                        ForEach(chart.levelTicks, id: \.self) { level in
                            Text(LocalizedFormat.percent(level)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                                .position(x: 17, y: yPosition(level, height: geometry.size.height))
                        }
                    }.frame(width: 34).accessibilityHidden(true)
                    GeometryReader { geometry in
                        plot(size: geometry.size)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                guard !pinned else { return }
                                switch phase {
                                case .active(let location): selectedDate = nearest(at: location.x, width: geometry.size.width)?.date
                                case .ended: selectedDate = nil
                                }
                            }
                            .gesture(SpatialTapGesture().onEnded { value in
                                let point = nearest(at: value.location.x, width: geometry.size.width)
                                if pinned && selectedDate == point?.date { pinned = false; selectedDate = nil }
                                else { selectedDate = point?.date; pinned = point != nil }
                            })
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Battery chart, last \(hours) hours")
                    .accessibilityValue(chart.points.last?.level.map { level in
                        String(localized: "Last reading \(LocalizedFormat.percent(level)). \(chart.points.count) readings, \(chart.segments.count) separate measurement intervals.") + " "
                            + (focused ? String(localized: "Zoomed battery scale from \(LocalizedFormat.percent(chart.levelRange.lowerBound)) to \(LocalizedFormat.percent(chart.levelRange.upperBound)).")
                                : String(localized: "Battery scale from \(LocalizedFormat.percent(0)) to \(LocalizedFormat.percent(100))."))
                    } ?? String(localized: "No readings yet"))
                }
                .padding(.vertical, 7)
                GeometryReader { geometry in
                    ForEach(0..<5, id: \.self) { index in
                        let fraction = Double(index) / 4
                        let date = chart.timeRange.lowerBound.addingTimeInterval(timeSpan * fraction)
                        Text(axisLabel(date)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 100, alignment: index == 0 ? .leading : (index == 4 ? .trailing : .center))
                            .position(x: index == 0 ? 50 : (index == 4 ? geometry.size.width - 50 : geometry.size.width * fraction), y: 7)
                    }
                }.frame(height: 14).padding(.leading, 43).accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                if let point = selected ?? chart.points.last, let level = point.level {
                    Image(systemName: point.charging ? "bolt.fill" : "circle.fill")
                        .font(.system(size: point.charging ? 10 : 5)).foregroundStyle(point.charging ? green : blue)
                    Text(selected != nil ? (pinned ? "Selected reading" : "Reading") : "Last measured").foregroundStyle(.secondary)
                    Text(point.date.formatted(date: Calendar.current.isDateInToday(point.date) ? .omitted : .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    Text("· \(LocalizedFormat.percent(level))").fontWeight(.semibold)
                    if point.charging { Text("· Charging").foregroundStyle(green) }
                    if pinned {
                        Button { pinned = false; selectedDate = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear reading selection")
                            .accessibilityLabel("Clear reading selection")
                    }
                } else { Text("The chart builds as readings arrive").foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                Text("Gaps: no readings").foregroundStyle(.tertiary)
            }
            .font(.system(size: 10)).monospacedDigit().frame(height: 16)
        }
        .onChange(of: hours) { selectedDate = nil; pinned = false }
        .onChange(of: focused) { selectedDate = nil; pinned = false }
    }

    private func legend(_ text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func plot(size: CGSize) -> some View {
        ZStack {
            Path { path in
                for level in chart.levelTicks {
                    let y = yPosition(level, height: size.height)
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }.stroke(.primary.opacity(0.07), style: StrokeStyle(lineWidth: 0.7, dash: [3, 5]))
            ForEach(Array(chart.segments.enumerated()), id: \.offset) { _, points in
                if points.count > 1 {
                    Path { path in
                        let positions = points.map { position($0, size: size) }
                        path.move(to: CGPoint(x: positions[0].x, y: size.height))
                        for xy in positions { path.addLine(to: xy) }
                        path.addLine(to: CGPoint(x: positions.last!.x, y: size.height)); path.closeSubpath()
                    }.fill(LinearGradient(colors: [blue.opacity(0.15), blue.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                    // Each edge is bounded by actual observations in one continuous segment.
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let xy = position(point, size: size)
                            if index == 0 { path.move(to: xy) } else { path.addLine(to: xy) }
                        }
                    }.stroke(blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    Path { path in
                        for index in 1..<points.count where points[index - 1].charging && points[index].charging {
                            path.move(to: position(points[index - 1], size: size)); path.addLine(to: position(points[index], size: size))
                        }
                    }.stroke(green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    Circle().fill(last.charging ? green : blue).frame(width: 6, height: 6).position(position(last, size: size))
                }
            }
            if let selected {
                let xy = position(selected, size: size)
                Path { path in
                    path.move(to: CGPoint(x: xy.x, y: 0)); path.addLine(to: CGPoint(x: xy.x, y: size.height))
                }.stroke(.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 10, height: 10)
                    .overlay { Circle().strokeBorder(selected.charging ? green : blue, lineWidth: 2.5) }.position(xy)
            }
            if chart.points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                    Text("No readings in this range yet").font(.system(size: 13, weight: .medium))
                    Text("You can pick a wider range or wait for new readings.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var timeSpan: TimeInterval { chart.timeRange.upperBound.timeIntervalSince(chart.timeRange.lowerBound) }
    private func yPosition(_ level: Int, height: CGFloat) -> CGFloat {
        (1 - Double(level - chart.levelRange.lowerBound) / Double(chart.levelRange.upperBound - chart.levelRange.lowerBound)) * height
    }
    private func position(_ point: BatteryHistoryPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.date.timeIntervalSince(chart.timeRange.lowerBound) / timeSpan * size.width,
                y: yPosition(point.level ?? 0, height: size.height))
    }
    private func nearest(at x: CGFloat, width: CGFloat) -> BatteryHistoryPoint? {
        guard width > 0 else { return nil }
        let date = chart.timeRange.lowerBound.addingTimeInterval(max(0, min(1, x / width)) * timeSpan)
        return chart.nearestPoint(to: date, tolerance: min(90, timeSpan * 12 / width))
    }
    private func axisLabel(_ date: Date) -> String {
        if timeSpan >= 3 * 86400 { return date.formatted(.dateTime.day().month(.abbreviated)) }
        if !Calendar.current.isDate(chart.timeRange.lowerBound, inSameDayAs: chart.timeRange.upperBound) {
            return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
