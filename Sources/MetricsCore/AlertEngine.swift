import Foundation

public enum AlertKind: String, Codable, Sendable {
    case systemCPU, applicationCPU, memoryGrowth, swapUsage, network, disk
    public var title: String {
        switch self {
        case .systemCPU: "Sistem CPU'su uzun süre yüksek"
        case .applicationCPU: "Uygulama CPU'su uzun süre yüksek"
        case .memoryGrowth: "Uygulama belleği büyüyor"
        case .swapUsage: "Swap kullanımı"
        case .network: "Ağ etkinliği uzun süre yüksek"
        case .disk: "Disk etkinliği uzun süre yüksek"
        }
    }
}

public struct MonitorAlert: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let key: String
    public let kind: AlertKind
    public let target: String
    public let started: Date
    public let emitted: Date
    public var updated: Date
    public var value: Double
    public var resolved: Date?
    public var interrupted = false
    public var active: Bool { resolved == nil }
}

// Thresholds are explicit sustained observations, not health/leak diagnoses.
struct AlertPolicy: Sendable {
    var systemCPU = 85.0
    var applicationCPU = 80.0
    var cpuDuration = 120.0
    var networkRate = 50_000_000.0
    var diskRate = 100_000_000.0
    var transferDuration = 60.0
    var memoryGrowth = 512.0 * 1024 * 1024
    var memoryWindow = 600.0
    var cooldown = 600.0
}

struct AlertEngine {
    private struct Candidate { var seconds = 0.0; let started: Date }
    private struct MemoryPoint { let uptime: Double; let bytes: Double }
    private struct MemoryWindow { let identities: [ProcessIdentity]; var points: [MemoryPoint] }
    var records: [String: MonitorAlert] = [:]
    private var candidates: [String: Candidate] = [:]
    private var windows: [String: MemoryWindow] = [:]
    private var activeKeys: [String: String] = [:]
    private var lastEmission: [String: Date] = [:]
    private var swapLevel: Double?
    private var swapUptime: Double?
    let policy: AlertPolicy
    init(records: [MonitorAlert] = [], policy: AlertPolicy = .init()) {
        self.policy = policy
        for var record in records {
            // Restart never implies that an old condition is still observed.
            if record.active { record.resolved = record.updated; record.interrupted = true }
            self.records[record.id] = record
            lastEmission[record.key] = max(lastEmission[record.key] ?? .distantPast, record.emitted)
        }
    }
    mutating func interrupt() {
        for id in activeKeys.values {
            if var record = records[id] {
                record.resolved = record.updated; record.interrupted = true; records[id] = record
            }
        }
        activeKeys = [:]; candidates = [:]; windows = [:]
    }
    mutating func evaluate(_ sample: HistorySample, elapsed: Double?) -> [MonitorAlert] {
        if elapsed == nil { interrupt() }
        let oldIDs = Set(records.keys)
        let date = sample.date
        func combined(_ first: HistoryMetric, _ second: HistoryMetric) -> Double? {
            guard let a = sample.values[first], let b = sample.values[second] else { return nil }
            return a + b
        }
        var observed: Set<String> = []
        func key(_ kind: AlertKind, _ id: String) -> String { kind.rawValue + ":" + id }
        let swap = key(.swapUsage, "system")
        observed.insert(swap)
        observeSwap(swap, bytes: sample.values[.swap], uptime: sample.uptime, date: date)
        let system = key(.systemCPU, "system")
        observed.insert(system)
        condition(system, kind: .systemCPU, target: "Bu Mac", value: sample.values[.cpu], threshold: policy.systemCPU,
                  duration: policy.cpuDuration, elapsed: elapsed, date: date)
        let network = key(.network, "system"), disk = key(.disk, "system")
        observed.formUnion([network, disk])
        condition(network, kind: .network, target: "Fiziksel ağ", value: combined(.download, .upload), threshold: policy.networkRate,
                  duration: policy.transferDuration, elapsed: elapsed, date: date)
        condition(disk, kind: .disk, target: "Fiziksel disk", value: combined(.diskRead, .diskWrite), threshold: policy.diskRate,
                  duration: policy.transferDuration, elapsed: elapsed, date: date)
        for app in sample.applications {
            let cpuKey = key(.applicationCPU, app.id)
            observed.insert(cpuKey)
            condition(cpuKey, kind: .applicationCPU, target: app.name, value: app.cpu, threshold: policy.applicationCPU,
                      duration: policy.cpuDuration, elapsed: elapsed, date: date)
            let memoryKey = key(.memoryGrowth, app.id)
            observed.insert(memoryKey)
            guard let bytes = app.memory, bytes.isFinite, bytes >= 0 else {
                windows[app.id] = nil; resolve(memoryKey, at: date); continue
            }
            if windows[app.id]?.identities != app.identities { windows[app.id] = MemoryWindow(identities: app.identities, points: []) }
            var window = windows[app.id]!
            window.points.append(MemoryPoint(uptime: sample.uptime, bytes: bytes))
            let cutoff = sample.uptime - policy.memoryWindow
            while window.points.count > 1 && window.points[1].uptime <= cutoff { window.points.removeFirst() }
            // Observations are at most 20 seconds apart; no unbounded process inventory is retained.
            if let baseline = window.points.first, sample.uptime - baseline.uptime >= policy.memoryWindow {
                let growth = bytes - baseline.bytes
                if growth >= policy.memoryGrowth {
                    emit(memoryKey, kind: .memoryGrowth, target: app.name, value: growth,
                         started: date.addingTimeInterval(-policy.memoryWindow), at: date)
                } else { resolve(memoryKey, at: date) }
            } else { resolve(memoryKey, at: date) }
            windows[app.id] = window
        }
        for existing in Array(candidates.keys) where !observed.contains(existing) { candidates[existing] = nil }
        for existing in Array(activeKeys.keys) where !observed.contains(existing) { resolve(existing, at: date) }
        let appIDs = Set(sample.applications.map(\.id))
        windows = windows.filter { appIDs.contains($0.key) }
        // Retention also bounds the engine's cooldown/event memory.
        let cutoff = Date(timeIntervalSince1970: Double(HistoryMath.retentionCutoff(date)))
        records = records.filter { $0.value.updated >= cutoff }
        if records.count > 2000 {
            let keep = Set(records.values.sorted { $0.updated > $1.updated }.prefix(2000).map(\.id)).union(activeKeys.values)
            records = records.filter { keep.contains($0.key) }
        }
        lastEmission = lastEmission.filter { date.timeIntervalSince($0.value) < policy.cooldown }
        return records.values.filter { !oldIDs.contains($0.id) }.sorted { $0.emitted < $1.emitted }
    }
    private mutating func condition(_ key: String, kind: AlertKind, target: String, value: Double?, threshold: Double,
                                   duration: Double, elapsed: Double?, date: Date) {
        guard let value, value.isFinite, value >= threshold else {
            candidates[key] = nil; resolve(key, at: date); return
        }
        if var candidate = candidates[key] {
            candidate.seconds += elapsed ?? 0
            candidates[key] = candidate
            if candidate.seconds >= duration { emit(key, kind: kind, target: target, value: value, started: candidate.started, at: date) }
        } else { candidates[key] = Candidate(started: date) }
    }
    private mutating func observeSwap(_ key: String, bytes: Double?, uptime: Double, date: Date) {
        // Pause, missing readings and sleep do not re-arm a previously reported level.
        // A fresh app session, a reboot or an observed zero starts a new swap episode.
        if let previous = swapUptime, uptime < previous { swapLevel = nil; resolve(key, at: date) }
        swapUptime = uptime
        guard let bytes, bytes.isFinite, bytes >= 0 else { resolve(key, at: date); return }
        guard bytes > 0 else { swapLevel = nil; resolve(key, at: date); return }
        let level = floor(bytes / 1_000_000_000) // Decimal GB, matching the notification's unit.
        if let previous = swapLevel, level <= previous { return }
        swapLevel = level
        // One current reading per crossed level, even if several GB changed between samples.
        resolve(key, at: date)
        emit(key, kind: .swapUsage, target: "Bu Mac", value: bytes, started: date, at: date, usesCooldown: false)
    }
    private mutating func emit(_ key: String, kind: AlertKind, target: String, value: Double, started: Date, at date: Date,
                               usesCooldown: Bool = true) {
        if let id = activeKeys[key] { records[id]?.updated = date; records[id]?.value = value; return }
        if usesCooldown, let last = lastEmission[key], date.timeIntervalSince(last) < policy.cooldown { return }
        let record = MonitorAlert(id: UUID().uuidString, key: key, kind: kind, target: target, started: started,
                                  emitted: date, updated: date, value: value)
        records[record.id] = record; activeKeys[key] = record.id; lastEmission[key] = date
    }
    private mutating func resolve(_ key: String, at date: Date) {
        if let id = activeKeys.removeValue(forKey: key) { records[id]?.resolved = date; records[id]?.updated = date }
    }
}
