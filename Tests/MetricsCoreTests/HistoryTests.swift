import Foundation
import Testing
@testable import MetricsCore

private func sample(_ date: Date, _ uptime: Double, cpu: Double? = 20, download: Double? = 100, apps: [HistoryApplicationReading] = []) -> HistorySample {
    var values: [HistoryMetric: Double] = [:]
    values[.cpu] = cpu; values[.download] = download
    return HistorySample(date: date, uptime: uptime, values: values, applications: apps)
}
private func baseDate() -> Date { Date(timeIntervalSince1970: Double(HistoryMath.start(Date()) - 180)) }
private func temporaryURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("history.sqlite")
}
private func app(cpu: Double? = 90, memory: Double? = 10, start: UInt64 = 1, id: String = "test") -> HistoryApplicationReading {
    .init(id: id, name: "Synthetic app", kind: .application, cpu: cpu, memory: memory,
          identities: [.init(pid: 101, startMicroseconds: start)])
}

@Test func historyUsesDurationWeightsAndRateIntegrals() {
    let base = baseDate(); var bucket = HistoryBucket(start: HistoryMath.start(base))
    HistoryMath.add(sample(base, 0, cpu: 20, download: 50), from: base.timeIntervalSince1970, to: base.timeIntervalSince1970 + 10, bucket: &bucket)
    HistoryMath.add(sample(base, 10, cpu: 80, download: 50), from: base.timeIntervalSince1970 + 10, to: base.timeIntervalSince1970 + 12, bucket: &bucket)
    #expect(bucket.average(.cpu) == 30)
    #expect(bucket.moments[.cpu]?.peak == 80)
    #expect(bucket.moments[.download]?.total == 600)
    #expect(bucket.observedSeconds == 12)
}
@Test func historyMissingMetricsDoNotBecomeZero() {
    let base = baseDate(); var bucket = HistoryBucket(start: HistoryMath.start(base))
    HistoryMath.add(sample(base, 0, cpu: nil, download: nil), from: base.timeIntervalSince1970, to: base.timeIntervalSince1970 + 10, bucket: &bucket)
    #expect(bucket.average(.cpu) == nil)
    #expect(bucket.average(.download) == nil)
    #expect(bucket.observedSeconds == 10)
}
@Test func historyClockChangesAndLongGapsBreakContinuity() {
    let base = baseDate(), first = sample(base, 100)
    #expect(HistoryMath.interval(previous: nil, current: first) == nil)
    #expect(HistoryMath.interval(previous: first, current: sample(base.addingTimeInterval(2), 102)) == 2)
    #expect(HistoryMath.interval(previous: first, current: sample(base.addingTimeInterval(21), 121)) == nil)
    #expect(HistoryMath.interval(previous: first, current: sample(base.addingTimeInterval(10), 102)) == nil)
    #expect(HistoryMath.interval(previous: first, current: sample(base.addingTimeInterval(-2), 102)) == nil)
}
@Test func historyCoveredWallTimeCannotBeCountedTwice() {
    let base = baseDate(); var bucket = HistoryBucket(start: HistoryMath.start(base))
    let start = base.timeIntervalSince1970
    HistoryMath.add(sample(base, 0), from: start, to: start + 10, bucket: &bucket)
    HistoryMath.add(sample(base, 0), from: start + 5, to: start + 15, bucket: &bucket)
    #expect(bucket.observedSeconds == 15)
    #expect(bucket.moments[.download]?.total == 1500)
}
@Test func historyMinuteHasBoundedApplicationSummary() {
    let base = baseDate(); var bucket = HistoryBucket(start: HistoryMath.start(base))
    let apps = (0..<100).map { app(cpu: Double($0), memory: Double(100 - $0), id: "\($0)") }
    HistoryMath.add(sample(base, 0, apps: apps), from: base.timeIntervalSince1970, to: base.timeIntervalSince1970 + 2, bucket: &bucket)
    #expect(bucket.applications.count == 20)
    #expect(bucket.applications["99"] != nil && bucket.applications["0"] != nil)
}
@Test func historyPayloadContainsNoProcessIdentityOrPaths() throws {
    let base = baseDate(); var bucket = HistoryBucket(start: HistoryMath.start(base))
    HistoryMath.add(sample(base, 0, apps: [app()]), from: base.timeIntervalSince1970, to: base.timeIntervalSince1970 + 2, bucket: &bucket)
    let json = String(decoding: try JSONEncoder().encode(bucket), as: UTF8.self)
    for forbidden in ["identities", "pid", "startMicroseconds", "executablePath", "bundlePath", "environment", "arguments"] { #expect(!json.contains(forbidden)) }
}
@Test func historyFootprintConvertsUInt64NumericallyAndExcludesPartialValues() {
    let process = ProcessUsage(identity: .init(pid: 101, startMicroseconds: 1), parentPID: 1, name: "Synthetic",
        cpuPercent: 50, footprint: 1_073_741_824, resident: 100, attribution: .bundle)
    let restricted = ProcessUsage(identity: .init(pid: 102, startMicroseconds: 1), parentPID: 1, name: "Restricted",
        cpuPercent: nil, footprint: nil, resident: nil, attribution: .bundle)
    let full = ApplicationUsage(id: "full", name: "Synthetic", kind: .application, bundleIdentifier: nil, processes: [process])
    let partial = ApplicationUsage(id: "partial", name: "Partial", kind: .application, bundleIdentifier: nil, processes: [process, restricted])
    let system = SystemMetrics(chip: "Synthetic", cores: 4, physicalMemory: 1024, operatingSystem: "Test", uptime: 10, thermalState: "Normal")
    let snapshot = MetricSnapshot(date: Date(), cpu: nil, memory: nil, disk: nil, network: nil, battery: nil, system: system,
        processes: .init(groups: [full, partial], coverage: .init()), issues: [], collectionMilliseconds: 1)
    let sample = HistorySample(snapshot: snapshot)
    #expect(sample.applications[0].memory == 1_073_741_824)
    #expect(sample.applications[1].memory == nil)
    #expect(sample.applications[1].cpu == nil)
}
@Test func historySplitsMinuteAndDayBoundariesWithoutDoubleCounting() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let base = Date(timeIntervalSince1970: Double(HistoryMath.start(Date(), size: 86400) - 2))
    let repository = try HistoryRepository(url: url)
    _ = try await repository.ingest(sample(base, 100))
    _ = try await repository.ingest(sample(base.addingTimeInterval(4), 104))
    let minutes = try await repository.report(range: .hour, now: base.addingTimeInterval(4))
    let days = try await repository.report(range: .week, now: base.addingTimeInterval(4))
    #expect(minutes.buckets.count == 2 && days.buckets.count == 2)
    #expect(minutes.observedSeconds == 4 && days.observedSeconds == 4)
    #expect(days.moment(.download).total == 400)
    try await repository.flush(now: base.addingTimeInterval(4))
    let again = try await repository.report(range: .week, now: base.addingTimeInterval(4))
    #expect(again.observedSeconds == 4)
    #expect(try await repository.integrityCheck())
}
@Test func historyReopenPreservesMinuteAndStartsFreshInterval() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let base = baseDate()
    let first = try HistoryRepository(url: url)
    _ = try await first.ingest(sample(base, 100))
    _ = try await first.ingest(sample(base.addingTimeInterval(2), 102))
    try await first.interrupt()
    let second = try HistoryRepository(url: url)
    _ = try await second.ingest(sample(base.addingTimeInterval(10), 200))
    _ = try await second.ingest(sample(base.addingTimeInterval(12), 202))
    let report = try await second.report(range: .hour, now: base.addingTimeInterval(12))
    #expect(report.observedSeconds == 4)
    #expect(report.gapCount == 2)
    #expect(report.moment(.download).total == 400)
}
@Test func historyPauseAndMissingIntervalsDoNotInventTraffic() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let base = baseDate(); let repository = try HistoryRepository(url: url)
    for (wall, up) in [(0.0, 100.0), (2, 102), (64, 164), (66, 166)] {
        _ = try await repository.ingest(sample(base.addingTimeInterval(wall), up))
    }
    let report = try await repository.report(range: .hour, now: base.addingTimeInterval(66))
    #expect(report.observedSeconds == 4)
    #expect(report.moment(.download).total == 400)
    #expect(report.gapCount == 2)
}
@Test func historySmallClockDriftUsesMonotonicDurationForBytes() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let base = baseDate(); let repository = try HistoryRepository(url: url)
    _ = try await repository.ingest(sample(base, 100))
    _ = try await repository.ingest(sample(base.addingTimeInterval(3), 102))
    let report = try await repository.report(range: .hour, now: base.addingTimeInterval(3))
    #expect(report.observedSeconds == 2)
    #expect(report.moment(.download).total == 200)
}
@Test func historyDatabaseFilesArePrivateToCurrentUser() throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let db = try SQLiteConnection(url: url)
    #expect(try db.scalar("PRAGMA user_version") == 2)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
@Test func historyDayApplicationDeltaDoesNotCountMinuteTwice() {
    let base = baseDate(); var minute = HistoryBucket(start: HistoryMath.start(base))
    var day = HistoryBucket(start: HistoryMath.start(base, size: 86400))
    let start = base.timeIntervalSince1970
    HistoryMath.add(sample(base, 0, apps: [app(cpu: 50, memory: 100)]), from: start, to: start + 2, bucket: &minute)
    day.mergeDelta(new: minute, old: HistoryBucket(start: minute.start))
    let old = minute
    HistoryMath.add(sample(base, 0, apps: [app(cpu: 100, memory: 200)]), from: start + 2, to: start + 4, bucket: &minute)
    day.mergeDelta(new: minute, old: old)
    #expect(day.applications["test"]?.cpu.average == 75)
    #expect(day.applications["test"]?.memory.peak == 200)
    #expect(day.observedSeconds == 4)
}
@Test func historyRetentionRemovesOldMinutesDaysAndAlerts() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let now = Date(), old = now.addingTimeInterval(-31 * 86400)
    let repository = try HistoryRepository(url: url)
    _ = try await repository.ingest(sample(old, 100))
    _ = try await repository.ingest(sample(old.addingTimeInterval(2), 102))
    try await repository.flush(now: now)
    let report = try await repository.report(range: .month, now: now)
    #expect(report.buckets.isEmpty)
    let db = try SQLiteConnection(url: url)
    #expect(try db.scalar("SELECT COUNT(*) FROM minutes") == 0)
    #expect(try db.scalar("SELECT COUNT(*) FROM days") == 0)
    let record = MonitorAlert(id: "expired", key: "test", kind: .systemCPU, target: "Synthetic", started: old, emitted: old, updated: old, value: 90)
    try db.write(record)
    try db.retain(since: HistoryMath.retentionCutoff(now))
    #expect(try db.scalar("SELECT COUNT(*) FROM alerts") == 0)
}
@Test func historyWeekIncludesExactlySevenUTCDateBuckets() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let db = try SQLiteConnection(url: url)
    let today = HistoryMath.start(Date(), size: 86400)
    for offset in 0...7 {
        var bucket = HistoryBucket(start: today - Int64(offset * 86400))
        bucket.observedSeconds = 1
        try db.write(bucket, table: "days")
    }
    let repository = try HistoryRepository(url: url)
    let now = Date(timeIntervalSince1970: Double(today + 3600))
    #expect(try await repository.report(range: .week, now: now).buckets.count == 7)
    #expect(try await repository.report(range: .month, now: now).buckets.count == 8)
}
@Test func historyFutureSchemaAndCorruptPayloadAreExplicitErrors() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let db = try SQLiteConnection(url: url)
    try db.exec("PRAGMA user_version=9")
    #expect(throws: HistoryError.self) { try HistoryRepository(url: url) }
    #expect(try db.scalar("PRAGMA user_version") == 9)
    try db.exec("PRAGMA user_version=2")
    let start = HistoryMath.start(Date())
    try db.exec("INSERT INTO minutes(start,payload) VALUES (\(start),'invalid json')")
    let repository = try HistoryRepository(url: url)
    await #expect(throws: (any Error).self) { try await repository.report(range: .hour) }
    #expect(try db.scalar("SELECT COUNT(*) FROM minutes") == 1)
}
@Test func historySchemaOneMemoryRepairIsBackedUpAndKeepsOtherMetrics() async throws {
    let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let db = try SQLiteConnection(url: url)
    let base = baseDate(); var bucket = HistoryBucket(start: HistoryMath.start(base))
    var record = HistoryApplication(id: "synthetic", name: "Synthetic", kind: .application)
    record.memory.add(Double(bitPattern: UInt64(1000)), seconds: 2)
    record.memory.add(Double(bitPattern: UInt64(2000)), seconds: 2)
    record.cpu.add(50, seconds: 4)
    bucket.applications[record.id] = record
    bucket.observedSeconds = 4
    try db.write(bucket, table: "minutes")
    try db.exec("PRAGMA user_version=1")
    let repository = try HistoryRepository(url: url)
    let report = try await repository.report(range: .hour, now: base.addingTimeInterval(10))
    let memory = try #require(report.applications.first?.memory)
    #expect(abs((memory.average ?? 0) - 1500) < 1)
    #expect(memory.peak == 2000)
    #expect(report.applications.first?.cpu.average == 50)
    #expect(report.observedSeconds == 4)
    let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
    #expect(files.contains { $0.hasPrefix("history-before-schema2-") })
    #expect(try db.scalar("PRAGMA user_version") == 2)
}

@Test func alertsRequireSustainedCPUAndMergeActiveEpisodes() {
    let base = baseDate(); var engine = AlertEngine()
    for index in 0..<60 { #expect(engine.evaluate(sample(base.addingTimeInterval(Double(index * 2)), Double(index * 2), cpu: 90), elapsed: index == 0 ? nil : 2).isEmpty) }
    let events = engine.evaluate(sample(base.addingTimeInterval(120), 120, cpu: 90), elapsed: 2)
    #expect(events.count == 1 && events.first?.kind == .systemCPU)
    #expect(engine.evaluate(sample(base.addingTimeInterval(122), 122, cpu: 95), elapsed: 2).isEmpty)
    #expect(engine.records.count == 1 && engine.records.values.first?.value == 95)
    _ = engine.evaluate(sample(base.addingTimeInterval(124), 124, cpu: 20), elapsed: 2)
    #expect(engine.records.values.first?.active == false)
}
@Test func alertsMissingValueOrGapResetsDuration() {
    let base = baseDate(); var engine = AlertEngine()
    for index in 0...40 { _ = engine.evaluate(sample(base.addingTimeInterval(Double(index * 2)), Double(index * 2), cpu: 90), elapsed: index == 0 ? nil : 2) }
    _ = engine.evaluate(sample(base.addingTimeInterval(82), 82, cpu: nil), elapsed: 2)
    for index in 42...90 { #expect(engine.evaluate(sample(base.addingTimeInterval(Double(index * 2)), Double(index * 2), cpu: 90), elapsed: 2).isEmpty) }
    _ = engine.evaluate(sample(base.addingTimeInterval(200), 200, cpu: 90), elapsed: nil)
    #expect(engine.records.isEmpty)
}
@Test func alertsRestartEndsOldEpisodeAndKeepsCooldown() {
    let base = baseDate()
    let record = MonitorAlert(id: "old", key: "systemCPU:system", kind: .systemCPU, target: "Synthetic", started: base, emitted: base, updated: base, value: 90)
    var engine = AlertEngine(records: [record])
    #expect(engine.records["old"]?.interrupted == true && engine.records["old"]?.active == false)
    for index in 0...60 { #expect(engine.evaluate(sample(base.addingTimeInterval(Double(index * 2 + 10)), Double(index * 2), cpu: 90), elapsed: index == 0 ? nil : 2).isEmpty) }
    #expect(engine.records.count == 1)
}
@Test func alertsMemoryGrowthNeedsStableMembersAndFullWindow() {
    let base = baseDate(); var policy = AlertPolicy(); policy.memoryWindow = 10; policy.memoryGrowth = 100
    var engine = AlertEngine(policy: policy)
    for index in 0..<5 {
        #expect(engine.evaluate(sample(base.addingTimeInterval(Double(index * 2)), Double(index * 2), apps: [app(cpu: 0, memory: Double(index * 30))]), elapsed: index == 0 ? nil : 2).isEmpty)
    }
    let emitted = engine.evaluate(sample(base.addingTimeInterval(10), 10, apps: [app(cpu: 0, memory: 150)]), elapsed: 2)
    #expect(emitted.first?.kind == .memoryGrowth)
    _ = engine.evaluate(sample(base.addingTimeInterval(12), 12, apps: [app(cpu: 0, memory: 500, start: 2)]), elapsed: 2)
    #expect(engine.records.values.first?.active == false)
    #expect(engine.records.count == 1)
}
@Test func alertsTransfersIgnoreWarmupAndNeedBothDirections() {
    let base = baseDate(); var policy = AlertPolicy(); policy.transferDuration = 4
    var engine = AlertEngine(policy: policy)
    for index in 0...3 {
        let values: [HistoryMetric: Double] = [.download: 60_000_000]
        #expect(engine.evaluate(.init(date: base.addingTimeInterval(Double(index * 2)), uptime: Double(index * 2), values: values), elapsed: index == 0 ? nil : 2).isEmpty)
    }
    for index in 4...6 {
        let values: [HistoryMetric: Double] = [.download: 60_000_000, .upload: 0, .diskRead: 120_000_000, .diskWrite: 0]
        let events = engine.evaluate(.init(date: base.addingTimeInterval(Double(index * 2)), uptime: Double(index * 2), values: values), elapsed: 2)
        #expect(events.count == (index == 6 ? 2 : 0))
    }
}
