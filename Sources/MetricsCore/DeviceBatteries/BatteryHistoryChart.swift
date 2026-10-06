import Foundation

/// Display bounds and summaries contain measured points only. The original
/// segments remain separate, including explicit offline and missing-poll gaps.
public struct BatteryHistoryChart: Sendable {
    public let segments: [[BatteryHistoryPoint]]
    public let timeRange: ClosedRange<Date>
    public let levelRange: ClosedRange<Int>
    public let levelTicks: [Int]
    public var points: [BatteryHistoryPoint] { segments.flatMap { $0 } }
    public var change: Int? {
        guard let first = points.first?.level, let last = points.last?.level else { return nil }
        return last - first
    }
    public var measuredRange: ClosedRange<Int>? {
        let values = points.compactMap(\.level)
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }

    public init(history: BatteryHistory, deviceID: String, since: Date, until: Date, focused: Bool) {
        let end = max(since.addingTimeInterval(1), until)
        segments = history.segments(for: deviceID, since: since, until: end)
        let measured = segments.flatMap { $0 }
        if focused, let first = measured.first, let last = measured.last {
            // A single point still gets space, but never becomes a line.
            let padding = max(30, last.date.timeIntervalSince(first.date) * 0.04)
            var start = max(since, first.date.addingTimeInterval(-padding))
            var finish = min(end, last.date.addingTimeInterval(padding))
            if finish.timeIntervalSince(start) < 900 {
                let center = first.date.addingTimeInterval(last.date.timeIntervalSince(first.date) / 2)
                start = max(since, center.addingTimeInterval(-450))
                finish = min(end, start.addingTimeInterval(900))
                start = max(since, finish.addingTimeInterval(-900))
            }
            timeRange = start...max(start.addingTimeInterval(1), finish)
            let levels = measured.compactMap(\.level)
            let low = levels.min()!, high = levels.max()!
            let center = Double(low + high) / 2
            let halfSpan = max(10, Double(high - low) / 2 + 4)
            let bottom = max(0, Int(floor((center - halfSpan) / 5)) * 5)
            let top = min(100, Int(ceil((center + halfSpan) / 5)) * 5)
            levelRange = bottom...top
            let step = top - bottom <= 30 ? 5 : (top - bottom <= 60 ? 10 : 20)
            var ticks = Array(stride(from: bottom, through: top, by: step))
            if ticks.last != top { ticks.append(top) }
            levelTicks = ticks
        } else {
            timeRange = since...end
            levelRange = 0...100
            levelTicks = [0, 25, 50, 75, 100]
        }
    }

    /// Only select a real point near the pointer; blank intervals stay blank.
    public func nearestPoint(to date: Date, tolerance: TimeInterval) -> BatteryHistoryPoint? {
        guard let point = points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
              abs(point.date.timeIntervalSince(date)) <= tolerance else { return nil }
        return point
    }
}
