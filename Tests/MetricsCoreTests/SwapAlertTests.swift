import Foundation
import Testing
@testable import MetricsCore

private let swapGB = 1_000_000_000.0
private let swapDate = Date().addingTimeInterval(-120)
private func swapSample(_ bytes: Double?, at seconds: Double) -> HistorySample {
    var values: [HistoryMetric: Double] = [:]
    values[.swap] = bytes
    return .init(date: swapDate.addingTimeInterval(seconds), uptime: 1_000 + seconds, values: values)
}

@Test func swapWarnsAtFirstUseAndEachGBWithoutCooldown() {
    var engine = AlertEngine()
    #expect(engine.evaluate(swapSample(0, at: 0), elapsed: nil).isEmpty)
    let first = engine.evaluate(swapSample(16_384, at: 2), elapsed: 2)
    #expect(first.count == 1 && first.first?.kind == .swapUsage && first.first?.value == 16_384)
    #expect(engine.evaluate(swapSample(swapGB - 1, at: 4), elapsed: 2).isEmpty)
    let one = engine.evaluate(swapSample(swapGB, at: 6), elapsed: 2)
    #expect(one.count == 1 && one.first?.value == swapGB)
    #expect(engine.evaluate(swapSample(1.99 * swapGB, at: 8), elapsed: 2).isEmpty)
    let two = engine.evaluate(swapSample(2 * swapGB, at: 10), elapsed: 2)
    #expect(two.count == 1 && two.first?.value == 2 * swapGB)
    #expect(engine.records.count == 3)
    #expect(engine.records.values.filter(\.active).count == 1)
}

@Test func swapJumpReportsOneCurrentTotalAndDoesNotRepeatOnFluctuation() {
    var engine = AlertEngine()
    _ = engine.evaluate(swapSample(0.2 * swapGB, at: 0), elapsed: nil)
    let jump = engine.evaluate(swapSample(4.25 * swapGB, at: 2), elapsed: 2)
    #expect(jump.count == 1 && jump.first?.value == 4.25 * swapGB)
    for (index, value) in [4.25, 3.9, 4.1, 1, 4.99].enumerated() {
        #expect(engine.evaluate(swapSample(value * swapGB, at: Double(4 + index * 2)), elapsed: 2).isEmpty)
    }
    let next = engine.evaluate(swapSample(5 * swapGB, at: 14), elapsed: 2)
    #expect(next.count == 1 && next.first?.value == 5 * swapGB)
}

@Test func swapZeroResolvesAndRearmsImmediately() {
    var engine = AlertEngine()
    let first = engine.evaluate(swapSample(2 * swapGB, at: 0), elapsed: nil)
    #expect(engine.evaluate(swapSample(0, at: 2), elapsed: 2).isEmpty)
    #expect(engine.records[first[0].id]?.resolved == swapDate.addingTimeInterval(2))
    let renewed = engine.evaluate(swapSample(100, at: 4), elapsed: 2)
    #expect(renewed.count == 1 && renewed.first?.value == 100)
}

@Test func swapMissingInvalidPausedAndGapSamplesDoNotRearmOrBecomeZero() {
    var engine = AlertEngine()
    _ = engine.evaluate(swapSample(2.1 * swapGB, at: 0), elapsed: nil)
    for (index, value) in [nil, Double.nan, .infinity, -1].enumerated() {
        #expect(engine.evaluate(swapSample(value, at: Double(2 + index * 2)), elapsed: 2).isEmpty)
    }
    engine.interrupt()
    #expect(engine.evaluate(swapSample(2.5 * swapGB, at: 60), elapsed: nil).isEmpty)
    let next = engine.evaluate(swapSample(3.1 * swapGB, at: 120), elapsed: nil)
    #expect(next.count == 1 && next.first?.value == 3.1 * swapGB)
}

@Test func swapFreshLaunchAndUptimeResetStartANewObservation() {
    var engine = AlertEngine()
    let first = engine.evaluate(swapSample(4 * swapGB, at: 0), elapsed: nil)
    var reopened = AlertEngine(records: first)
    let current = reopened.evaluate(swapSample(4 * swapGB, at: 10), elapsed: nil)
    #expect(current.count == 1 && current.first?.value == 4 * swapGB)
    let reset = HistorySample(date: swapDate.addingTimeInterval(20), uptime: 1, values: [.swap: 0.1 * swapGB])
    #expect(engine.evaluate(reset, elapsed: nil).count == 1)
}

@Test func swapSnapshotKeepsMeasuredAndUnknownValuesDistinct() {
    let system = SystemMetrics(chip: "Fixture", cores: 4, physicalMemory: 1_000_000_000,
        operatingSystem: "Test", uptime: 100, thermalState: "Normal")
    for amount: UInt64? in [nil, 0, 1_234_567_890] {
        let memory = MemoryMetrics(total: 1_000_000_000, app: 0, wired: 0, compressed: 0, cached: 0,
            free: 1_000_000_000, swap: amount, pressure: .normal)
        let snapshot = MetricSnapshot(date: swapDate, cpu: nil, memory: memory, disk: nil, network: nil,
            battery: nil, system: system, issues: [], collectionMilliseconds: 0)
        #expect(HistorySample(snapshot: snapshot).values[.swap] == amount.map { Double($0) })
    }
}

@Test func swapRepositoryPersistsAmountsAndReadsLegacyPayloads() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-swap-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("history.sqlite")
    let repository = try HistoryRepository(url: url)
    let initial = try await repository.ingest(swapSample(0.2 * swapGB, at: 0))
    let increased = try await repository.ingest(swapSample(1.2 * swapGB, at: 2))
    #expect(initial.count == 1 && increased.count == 1)
    try await repository.interrupt()
    let reopened = try HistoryRepository(url: url)
    let records = try await reopened.recentAlerts()
    #expect(records.count == 2)
    #expect(records.allSatisfy { $0.kind == .swapUsage })
    #expect(Set(records.map(\.value)) == Set([0.2 * swapGB, 1.2 * swapGB]))
    #expect(try await reopened.integrityCheck())
    // Alert payloads written before this feature still decode without a migration.
    let legacy = Data(#"{"id":"old","key":"systemCPU:system","kind":"systemCPU","target":"Bu Mac","started":0,"emitted":0,"updated":0,"value":90,"interrupted":false}"#.utf8)
    #expect(try JSONDecoder().decode(MonitorAlert.self, from: legacy).kind == .systemCPU)
}
