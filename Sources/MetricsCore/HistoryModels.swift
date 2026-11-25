import Foundation

public enum HistoryMetric: String, Codable, Sendable, CaseIterable {
    case cpu, memory, memoryPercent, swap, diskAvailable, diskRead, diskWrite, download, upload, battery
}

public struct HistoryMoment: Codable, Sendable {
    public var total = 0.0
    public var seconds = 0.0
    public var peak = 0.0
    public var average: Double? { seconds > 0 ? total / seconds : nil }
    mutating func add(_ value: Double, seconds duration: Double) {
        guard value.isFinite, value >= 0, duration.isFinite, duration > 0 else { return }
        total += value * duration; seconds += duration; peak = max(peak, value)
    }
    mutating func mergeDelta(new: Self, old: Self) {
        total += new.total - old.total; seconds += new.seconds - old.seconds
        peak = max(peak, new.peak)
    }
}

public struct HistoryApplication: Codable, Sendable, Identifiable {
    public let id, name: String
    public let kind: UsageGroupKind
    public var cpu = HistoryMoment()
    public var memory = HistoryMoment()
}

public struct HistoryBucket: Codable, Sendable, Identifiable {
    public let start: Int64
    public var id: Int64 { start }
    public var date: Date { Date(timeIntervalSince1970: Double(start)) }
    public var moments: [HistoryMetric: HistoryMoment] = [:]
    public var applications: [String: HistoryApplication] = [:]
    public var observedSeconds = 0.0
    public var intervals = 0
    public var gaps = 0
    public var applicationsTruncated = false
    public var lastEnd = 0.0
    public init(start: Int64) { self.start = start }
    public func average(_ metric: HistoryMetric) -> Double? { moments[metric]?.average }
    // Days contain deltas of persisted minutes; updating a minute cannot double-count it.
    mutating func mergeDelta(new: Self, old: Self) {
        observedSeconds += new.observedSeconds - old.observedSeconds
        intervals += new.intervals - old.intervals; gaps += new.gaps - old.gaps
        lastEnd = max(lastEnd, new.lastEnd)
        for (metric, moment) in new.moments { moments[metric, default: .init()].mergeDelta(new: moment, old: old.moments[metric] ?? .init()) }
        for (id, app) in new.applications {
            guard applications[id] != nil || applications.count < 256 else { applicationsTruncated = true; continue }
            var value = applications[id] ?? HistoryApplication(id: id, name: app.name, kind: app.kind)
            value.cpu.mergeDelta(new: app.cpu, old: old.applications[id]?.cpu ?? .init())
            value.memory.mergeDelta(new: app.memory, old: old.applications[id]?.memory ?? .init())
            applications[id] = value
        }
        applicationsTruncated = applicationsTruncated || new.applicationsTruncated
    }
}

struct HistoryApplicationReading: Sendable {
    let id, name: String
    let kind: UsageGroupKind
    let cpu, memory: Double?
    let identities: [ProcessIdentity]
}

struct HistorySample: Sendable {
    let date: Date
    let uptime: Double
    let values: [HistoryMetric: Double]
    let applications: [HistoryApplicationReading]
    init(snapshot: MetricSnapshot) {
        date = snapshot.date; uptime = snapshot.system.uptime
        var values: [HistoryMetric: Double] = [:]
        values[.cpu] = snapshot.cpu?.used
        values[.memory] = snapshot.memory.map { Double($0.used) }
        values[.memoryPercent] = snapshot.memory?.usedPercent
        values[.swap] = snapshot.memory?.swap.map { Double($0) }
        values[.diskAvailable] = snapshot.disk.map { Double($0.available) }
        values[.diskRead] = snapshot.disk?.io?.incomingRate; values[.diskWrite] = snapshot.disk?.io?.outgoingRate
        values[.download] = snapshot.network?.incomingRate; values[.upload] = snapshot.network?.outgoingRate
        values[.battery] = snapshot.battery?.percent.map(Double.init)
        self.values = values
        applications = (snapshot.processes?.groups ?? []).map {
            HistoryApplicationReading(id: $0.id, name: $0.name, kind: $0.kind,
                cpu: $0.cpuIsPartial ? nil : $0.cpuPercent,
                memory: $0.memoryIsPartial ? nil : $0.footprint.map { Double($0) }, identities: $0.processes.map(\.identity))
        }
    }
    init(date: Date, uptime: Double, values: [HistoryMetric: Double], applications: [HistoryApplicationReading] = []) {
        self.date = date; self.uptime = uptime; self.values = values; self.applications = applications
    }
}

enum HistoryMath {
    static func start(_ date: Date, size: Int64 = 60) -> Int64 { Int64(floor(date.timeIntervalSince1970 / Double(size))) * size }
    static func retentionCutoff(_ now: Date) -> Int64 { start(now, size: 86_400) - 29 * 86_400 }
    static func interval(previous: HistorySample?, current: HistorySample) -> Double? {
        guard let previous else { return nil }
        let elapsed = current.uptime - previous.uptime
        let wall = current.date.timeIntervalSince(previous.date)
        guard elapsed.isFinite, elapsed > 0, elapsed <= 20, wall > 0, abs(wall - elapsed) <= 2 else { return nil }
        return elapsed
    }
    static func add(_ sample: HistorySample, from: Double, to: Double, measureScale: Double = 1, bucket: inout HistoryBucket) {
        // A backwards wall-clock change or a second session cannot reuse covered time.
        let effectiveStart = max(from, bucket.lastEnd)
        let duration = (to - effectiveStart) * measureScale
        guard duration > 0 else { return }
        bucket.observedSeconds += duration; bucket.intervals += 1; bucket.lastEnd = to
        for (metric, value) in sample.values { bucket.moments[metric, default: .init()].add(value, seconds: duration) }
        let cpu = sample.applications.sorted { ($0.cpu ?? -1) > ($1.cpu ?? -1) }.prefix(10)
        let memory = sample.applications.sorted { ($0.memory ?? -1) > ($1.memory ?? -1) }.prefix(10)
        let selected = Set(cpu.map(\.id) + memory.map(\.id))
        for app in sample.applications where selected.contains(app.id) || bucket.applications[app.id] != nil {
            guard bucket.applications[app.id] != nil || bucket.applications.count < 20 else { bucket.applicationsTruncated = true; continue }
            var value = bucket.applications[app.id] ?? HistoryApplication(id: app.id, name: app.name, kind: app.kind)
            if let cpu = app.cpu { value.cpu.add(cpu, seconds: duration) }
            if let memory = app.memory { value.memory.add(memory, seconds: duration) }
            bucket.applications[app.id] = value
        }
    }
}

public enum HistoryRange: String, CaseIterable, Sendable, Identifiable {
    case hour, day, week, month
    public var id: Self { self }
    public var label: String {
        switch self {
        case .hour: String(localized: "1 hour"); case .day: String(localized: "24 hours")
        case .week: String(localized: "7 days"); case .month: String(localized: "30 days")
        }
    }
    public var daily: Bool { self == .week || self == .month }
    public var seconds: Double {
        switch self { case .hour: 3600; case .day: 86400; case .week: 7 * 86400; case .month: 30 * 86400 }
    }
}

public struct HistoryReport: Sendable {
    public let buckets: [HistoryBucket]
    public let range: HistoryRange
    public let generated: Date
    public let alerts: [MonitorAlert]
    public var observedSeconds: Double { buckets.reduce(0) { $0 + $1.observedSeconds } }
    public var gapCount: Int { buckets.reduce(0) { $0 + $1.gaps } }
    public var applications: [HistoryApplication] {
        var merged: [String: HistoryApplication] = [:]
        for bucket in buckets {
            for (id, app) in bucket.applications {
                var value = merged[id] ?? HistoryApplication(id: id, name: app.name, kind: app.kind)
                value.cpu.mergeDelta(new: app.cpu, old: .init()); value.memory.mergeDelta(new: app.memory, old: .init())
                merged[id] = value
            }
        }
        return merged.values.sorted { ($0.cpu.average ?? -1) > ($1.cpu.average ?? -1) }
    }
    public func moment(_ metric: HistoryMetric) -> HistoryMoment {
        buckets.reduce(into: HistoryMoment()) { result, bucket in result.mergeDelta(new: bucket.moments[metric] ?? .init(), old: .init()) }
    }
}
