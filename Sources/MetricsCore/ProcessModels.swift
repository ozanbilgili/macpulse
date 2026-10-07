import Foundation

public struct ProcessIdentity: Hashable, Sendable, Codable {
    public let pid: Int32
    public let startMicroseconds: UInt64
    public init(pid: Int32, startMicroseconds: UInt64) { self.pid = pid; self.startMicroseconds = startMicroseconds }
    public var key: String { "\(pid):\(startMicroseconds)" }
    public var startDate: Date { Date(timeIntervalSince1970: Double(startMicroseconds) / 1_000_000) }
}

public struct ApplicationDescriptor: Sendable, Equatable {
    public let name: String
    public let bundlePath: String
    public let bundleIdentifier: String?
    public init(name: String, bundlePath: String, bundleIdentifier: String? = nil) {
        self.name = name; self.bundlePath = bundlePath; self.bundleIdentifier = bundleIdentifier
    }
    public var key: String { "app:" + ProcessGrouping.stableKey(bundlePath) }
}

public struct RawProcessReading: Sendable {
    public let identity: ProcessIdentity
    public let parentPID: Int32
    public let name: String
    public let executablePath: String?
    public let coalition: UInt64?
    public let cpuNanoseconds: UInt64?
    public let footprint, resident: UInt64?
    public let uptime: Double
    public init(identity: ProcessIdentity, parentPID: Int32, name: String, executablePath: String?, coalition: UInt64? = nil,
                cpuNanoseconds: UInt64?, footprint: UInt64?, resident: UInt64?, uptime: Double) {
        self.identity = identity; self.parentPID = parentPID; self.name = name; self.executablePath = executablePath
        self.coalition = coalition; self.cpuNanoseconds = cpuNanoseconds; self.footprint = footprint; self.resident = resident; self.uptime = uptime
    }
}

public enum Attribution: String, Sendable, Codable {
    case bundle, parent, coalition, independent
    public var label: String {
        switch self { case .bundle: "Uygulama paketi"; case .parent: "Ebeveyn süreci"; case .coalition: "macOS uygulama grubu"; case .independent: "Bağımsız süreç" }
    }
}

public struct ProcessUsage: Sendable, Codable, Identifiable {
    public let identity: ProcessIdentity
    public var id: ProcessIdentity { identity }
    public let parentPID: Int32
    public let name: String
    public let cpuPercent: Double?
    public let footprint, resident: UInt64?
    public let attribution: Attribution
}

public enum UsageGroupKind: String, Sendable, Codable { case application, independent }

public struct ApplicationUsage: Sendable, Codable, Identifiable {
    public let id, name: String
    public let kind: UsageGroupKind
    public let bundleIdentifier: String?
    // Asset locator only. Executable/bundle paths are never encoded into probe reports.
    public var bundlePath: String? = nil
    public let processes: [ProcessUsage]
    public var cpuMeasuredCount: Int { processes.filter { $0.cpuPercent != nil }.count }
    public var memoryMeasuredCount: Int { processes.filter { $0.footprint != nil }.count }
    public var cpuPercent: Double? { cpuMeasuredCount > 0 ? processes.compactMap(\.cpuPercent).reduce(0, +) : nil }
    public var footprint: UInt64? { memoryMeasuredCount > 0 ? processes.compactMap(\.footprint).reduce(0, +) : nil }
    public var resident: UInt64? {
        let values = processes.compactMap(\.resident)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    public var cpuIsPartial: Bool { cpuMeasuredCount < processes.count }
    public var memoryIsPartial: Bool { memoryMeasuredCount < processes.count }
    enum CodingKeys: String, CodingKey { case id, name, kind, bundleIdentifier, processes }
}

public struct ProcessCoverage: Sendable, Codable {
    public var enumerated = 0
    public var otherUsers = 0
    public var metadataUnavailable = 0
    public var exitedOrChanged = 0
    public var usageUnavailable = 0
    public var coalitionUnavailable = 0
    public var truncated = false
    public init() { }
}

public struct ProcessSnapshot: Sendable, Codable {
    public let groups: [ApplicationUsage]
    public let coverage: ProcessCoverage
    public var processCount: Int { groups.reduce(0) { $0 + $1.processes.count } }
    public var applicationCount: Int { groups.filter { $0.kind == .application }.count }
    public var independentCount: Int { groups.filter { $0.kind == .independent }.reduce(0) { $0 + $1.processes.count } }
    public var memoryMeasuredCount: Int { groups.reduce(0) { $0 + $1.memoryMeasuredCount } }
    public var cpuMeasuredCount: Int { groups.reduce(0) { $0 + $1.cpuMeasuredCount } }
}

public enum ProcessSort: String, Sendable, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Bellek", name = "Ad"
    public var id: Self { self }
    public func sorted(_ groups: [ApplicationUsage]) -> [ApplicationUsage] {
        groups.sorted { left, right in
            switch self {
            case .cpu:
                if left.cpuPercent != right.cpuPercent { return (left.cpuPercent ?? -1) > (right.cpuPercent ?? -1) }
            case .memory:
                if left.footprint != right.footprint {
                    if let lhs = left.footprint, let rhs = right.footprint { return lhs > rhs }
                    return left.footprint != nil
                }
            case .name: break
            }
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }
}

public enum ProcessCPU {
    public static func percent(previous: RawProcessReading, current: RawProcessReading) -> Double? {
        guard previous.identity == current.identity, let before = previous.cpuNanoseconds, let after = current.cpuNanoseconds,
              after >= before else { return nil }
        let seconds = current.uptime - previous.uptime
        guard seconds.isFinite, seconds > 0, seconds <= 20 else { return nil }
        return Double(after - before) / 1_000_000_000 / seconds * 100
    }
}
