import Foundation

public struct CPUTicks: Sendable {
    public let user, system, idle, nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32 = 0) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public struct CPUUsage: Sendable, Codable {
    public let user, system, idle: Double
    public var used: Double { user + system }
    public static func between(_ previous: CPUTicks, _ current: CPUTicks) -> CPUUsage? {
        let user = Double(current.user &- previous.user) + Double(current.nice &- previous.nice)
        let system = Double(current.system &- previous.system)
        let idle = Double(current.idle &- previous.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUUsage(user: user / total * 100, system: system / total * 100, idle: idle / total * 100)
    }
}

public enum MemoryPressure: String, Sendable, Codable {
    case normal, warning, critical, unavailable
    public var label: String {
        switch self { case .normal: "Normal"; case .warning: "Yüksek"; case .critical: "Kritik"; case .unavailable: "Ölçülemiyor" }
    }
}

public struct MemoryMetrics: Sendable, Codable {
    public let total, app, wired, compressed, cached, free: UInt64
    public let swap: UInt64?
    public let pressure: MemoryPressure
    public var used: UInt64 { min(total, app + wired + compressed) }
    public var usedPercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
}

public struct TransferCounters: Sendable {
    public let incoming, outgoing: UInt64
    public init(incoming: UInt64, outgoing: UInt64) { self.incoming = incoming; self.outgoing = outgoing }
}

public struct TransferDelta: Sendable, Codable {
    public let incomingBytes, outgoingBytes: UInt64
    public let incomingRate, outgoingRate: Double
    public static func between(_ previous: TransferCounters, _ current: TransferCounters, seconds: Double) -> TransferDelta? {
        guard seconds.isFinite, seconds > 0, current.incoming >= previous.incoming, current.outgoing >= previous.outgoing else { return nil }
        let incoming = current.incoming - previous.incoming
        let outgoing = current.outgoing - previous.outgoing
        return TransferDelta(incomingBytes: incoming, outgoingBytes: outgoing,
                             incomingRate: Double(incoming) / seconds, outgoingRate: Double(outgoing) / seconds)
    }
}

public enum CounterMath {
    public static func deltas<Key: Hashable>(previous: [Key: TransferCounters], current: [Key: TransferCounters], seconds: Double) -> [Key: TransferDelta] {
        current.reduce(into: [:]) { result, entry in
            guard let baseline = previous[entry.key], let delta = TransferDelta.between(baseline, entry.value, seconds: seconds) else { return }
            result[entry.key] = delta
        }
    }
}

public struct DiskMetrics: Sendable, Codable {
    public let total, available: UInt64
    public let io: TransferDelta?
    public let driverCount: Int
    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedPercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
}

public struct NetworkInterface: Sendable, Codable, Identifiable {
    public let id: String
    public let transfer: TransferDelta?
}

public struct NetworkMetrics: Sendable, Codable {
    public let interfaces: [NetworkInterface]
    public let incomingRate, outgoingRate: Double?
    public let sessionReceived, sessionSent: UInt64
}

public struct BatteryMetrics: Sendable, Codable {
    public let present: Bool
    public let percent: Int?
    public let onAC, charging: Bool
    public let minutesRemaining: Int?
    public let lowPowerMode: Bool
    public var stateLabel: String {
        if !present { return "Pil yok" }
        if charging { return "Şarj oluyor" }
        return onAC ? "Adaptöre bağlı" : "Pille çalışıyor"
    }
}

public struct SystemMetrics: Sendable, Codable {
    public let chip: String
    public let cores: Int
    public let physicalMemory: UInt64
    public let operatingSystem: String
    public let uptime: Double
    public let thermalState: String
}

public struct MetricIssue: Sendable, Codable, Identifiable {
    public let id: String
    public let message: String
}

public struct MetricSnapshot: Sendable, Codable, Identifiable {
    public let date: Date
    public var id: Date { date }
    public let cpu: CPUUsage?
    public let memory: MemoryMetrics?
    public let disk: DiskMetrics?
    public let network: NetworkMetrics?
    public let battery: BatteryMetrics?
    public let system: SystemMetrics
    public var processes: ProcessSnapshot? = nil
    public var developer: DeveloperSnapshot? = nil
    public var containers: ContainerSnapshot? = nil
    public var hardware: HardwareSnapshot? = nil
    public var bluetooth: BluetoothSnapshot? = nil
    public var audio: AudioSnapshot? = nil
    public let issues: [MetricIssue]
    public let collectionMilliseconds: Double
    // Developer paths, socket metadata and containers stay transient; only explicit safe probe summaries are encoded.
    enum CodingKeys: String, CodingKey { case date, cpu, memory, disk, network, battery, system, processes, hardware, issues, collectionMilliseconds }

    public var historySample: MetricSnapshot {
        var copy = self
        copy.processes = nil
        copy.developer = nil
        copy.containers = nil
        copy.hardware = hardware?.chartSample
        copy.bluetooth = nil
        copy.audio = nil
        return copy
    }
}
