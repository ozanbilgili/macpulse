import Foundation
import Testing
@testable import MetricsCore

private let chartEnd = Date(timeIntervalSince1970: 100_000)

@Test func focusedHistoryShowsSparseMeasurementsWithoutFillingGaps() {
    var history = BatteryHistory()
    let start = chartEnd.addingTimeInterval(-6 * 3600)
    history.samples["phone"] = [
        .init(date: chartEnd.addingTimeInterval(-1200), level: 87),
        .init(date: chartEnd.addingTimeInterval(-1140), level: 86),
        .init(date: chartEnd.addingTimeInterval(-1100), level: nil),
        .init(date: chartEnd.addingTimeInterval(-60), level: 83)
    ]
    let chart = BatteryHistoryChart(history: history, deviceID: "phone", since: start, until: chartEnd, focused: true)
    #expect(chart.segments.count == 2)
    #expect(chart.points.count == 3)
    #expect(chart.change == -4)
    #expect(chart.measuredRange == 83...87)
    #expect(chart.timeRange.upperBound.timeIntervalSince(chart.timeRange.lowerBound) < 1800)
    #expect(chart.levelRange.contains(83) && chart.levelRange.contains(87))
    #expect(chart.levelRange.lowerBound >= 0 && chart.levelRange.upperBound <= 100)
    #expect(chart.nearestPoint(to: chartEnd.addingTimeInterval(-600), tolerance: 90) == nil)
    #expect(chart.nearestPoint(to: chartEnd.addingTimeInterval(-62), tolerance: 10)?.level == 83)
    let full = BatteryHistoryChart(history: history, deviceID: "phone", since: start, until: chartEnd, focused: false)
    #expect(full.timeRange == start...chartEnd)
    #expect(full.levelRange == 0...100)
    #expect(full.segments == chart.segments)
}

@Test func singleAndExtremeHistoryPointsHaveUsableHonestBounds() {
    for level in [0, 83, 100] {
        var history = BatteryHistory()
        history.samples["phone"] = [.init(date: chartEnd, level: level)]
        let chart = BatteryHistoryChart(history: history, deviceID: "phone", since: chartEnd.addingTimeInterval(-3600), until: chartEnd, focused: true)
        #expect(chart.points.count == 1)
        #expect(chart.change == 0)
        #expect(chart.timeRange.upperBound.timeIntervalSince(chart.timeRange.lowerBound) == 900)
        #expect(chart.timeRange.contains(chartEnd))
        #expect(chart.levelRange.contains(level))
        #expect(chart.levelRange.lowerBound < chart.levelRange.upperBound)
        #expect(chart.levelTicks.first == chart.levelRange.lowerBound)
        #expect(chart.levelTicks.last == chart.levelRange.upperBound)
    }
}

@Test func emptyHistoryAndOutsideFilterSamplesDoNotProduceStatistics() {
    var history = BatteryHistory()
    history.samples["phone"] = [.init(date: chartEnd.addingTimeInterval(-8 * 86400), level: 50), .init(date: chartEnd, level: nil)]
    let since = chartEnd.addingTimeInterval(-6 * 3600)
    let chart = BatteryHistoryChart(history: history, deviceID: "phone", since: since, until: chartEnd, focused: true)
    #expect(chart.points.isEmpty)
    #expect(chart.change == nil)
    #expect(chart.measuredRange == nil)
    #expect(chart.timeRange == since...chartEnd)
    #expect(chart.levelRange == 0...100)
}
