import Foundation

public actor HistoryRepository {
    private let database: SQLiteConnection
    private var previous: HistorySample?
    private var pending: [Int64: HistoryBucket] = [:]
    private var engine: AlertEngine
    private var persistedRecords: [String: MonitorAlert] = [:]
    private var lastFlush: Double?
    private var retentionDay: Int64?
    private let url: URL
    public static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MacPulse", isDirectory: true).appendingPathComponent("history.sqlite")
    }
    public init(url: URL) throws {
        self.url = url
        database = try SQLiteConnection(url: url)
        let records = try database.payloads("SELECT payload FROM alerts ORDER BY updated DESC LIMIT 2000").map { try JSONDecoder().decode(MonitorAlert.self, from: $0) }
        engine = AlertEngine(records: records)
        // Persist interrupted status after restart, preserving original last-observed time.
        try database.exec("BEGIN IMMEDIATE")
        do {
            for record in engine.records.values where record.interrupted { try database.write(record) }
            try database.exec("COMMIT")
            persistedRecords = engine.records
        } catch { try? database.exec("ROLLBACK"); throw error }
    }
    public func ingest(_ snapshot: MetricSnapshot) throws -> [MonitorAlert] { try ingest(HistorySample(snapshot: snapshot)) }
    func ingest(_ sample: HistorySample) throws -> [MonitorAlert] {
        defer { previous = sample }
        let interval = HistoryMath.interval(previous: previous, current: sample)
        let events = engine.evaluate(sample, elapsed: interval)
        if let interval {
            var cursor = previous!.date.timeIntervalSince1970
            let end = sample.date.timeIntervalSince1970
            let measureScale = interval / (end - cursor)
            while cursor < end {
                let start = Int64(floor(cursor / 60)) * 60
                let next = min(end, Double(start + 60))
                var bucket = try loadMinute(start)
                HistoryMath.add(sample, from: cursor, to: next, measureScale: measureScale, bucket: &bucket)
                pending[start] = bucket; cursor = next
            }
        } else {
            let start = HistoryMath.start(sample.date)
            var bucket = try loadMinute(start)
            bucket.gaps += 1; pending[start] = bucket
        }
        let changedMinute = pending.keys.contains { $0 != HistoryMath.start(sample.date) }
        if changedMinute || lastFlush == nil || sample.uptime - (lastFlush ?? 0) >= 10 || !events.isEmpty {
            try flush(now: sample.date)
            lastFlush = sample.uptime
        }
        return events
    }
    public func interrupt() throws {
        previous = nil; engine.interrupt(); try flush()
    }
    public func flush(now: Date = Date()) throws {
        try database.exec("BEGIN IMMEDIATE")
        do {
            for bucket in pending.values.sorted(by: { $0.start < $1.start }) {
                let old = try database.bucket("minutes", start: bucket.start)
                let dayStart = Int64(floor(Double(bucket.start) / 86_400)) * 86_400
                var day = try database.bucket("days", start: dayStart)
                day.mergeDelta(new: bucket, old: old)
                try database.write(bucket, table: "minutes"); try database.write(day, table: "days")
            }
            for record in engine.records.values where persistedRecords[record.id] != record { try database.write(record) }
            let currentDay = HistoryMath.start(now, size: 86_400)
            if retentionDay != currentDay { try database.retain(since: HistoryMath.retentionCutoff(now)) }
            try database.exec("COMMIT")
            pending = [:]; retentionDay = currentDay; persistedRecords = engine.records
        } catch { try? database.exec("ROLLBACK"); throw error }
    }
    public func report(range: HistoryRange, now: Date = Date()) throws -> HistoryReport {
        try flush(now: now)
        let periodStart = range.daily ? Double(HistoryMath.start(now, size: 86_400) - (range == .week ? 6 : 29) * 86_400) : now.timeIntervalSince1970 - range.seconds
        let cutoff = max(Double(HistoryMath.retentionCutoff(now)), periodStart)
        let rounded = floor(cutoff / (range.daily ? 86_400 : 60)) * (range.daily ? 86_400 : 60)
        let table = range.daily ? "days" : "minutes"
        let buckets = try database.payloads("SELECT payload FROM \(table) WHERE start >= ? ORDER BY start", from: rounded)
            .map { try JSONDecoder().decode(HistoryBucket.self, from: $0) }.filter { $0.start <= Int64(now.timeIntervalSince1970) }
        return HistoryReport(buckets: buckets, range: range, generated: now, alerts: try recentAlerts())
    }
    public func recentAlerts() throws -> [MonitorAlert] {
        try database.payloads("SELECT payload FROM alerts ORDER BY updated DESC LIMIT 100")
            .map { try JSONDecoder().decode(MonitorAlert.self, from: $0) }
    }
    public func integrityCheck() throws -> Bool { try database.payloads("PRAGMA quick_check").first == Data("ok".utf8) }
    private func loadMinute(_ start: Int64) throws -> HistoryBucket {
        if let value = pending[start] { return value }
        return try database.bucket("minutes", start: start)
    }
}
