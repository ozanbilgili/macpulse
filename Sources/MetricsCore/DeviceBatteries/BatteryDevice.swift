import Foundation

public enum BatterySource: String, Codable, Sendable, CaseIterable {
    case mac, bluetooth, mobile, logitech, pencil
}

public enum BatteryTelemetry: String, Codable, Sendable {
    case iokit, macOSBluetooth, hidpp, mobileDevice, libimobiledevice, pencilStream
    public var label: String {
        switch self { case .iokit: "IOKit"; case .macOSBluetooth: "macOS kaydı"; case .hidpp: "HID++"; case .mobileDevice: "MobileDevice"; case .libimobiledevice: "libimobiledevice"; case .pencilStream: "Pencil bildirimi" }
    }
}

public struct BatteryDevice: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var level: Int?
    public var isCharging: Bool
    public var isConnected: Bool
    public var source: BatterySource
    public var measuredAt: Date?
    public var lastSeenAt: Date?
    public var approximate: Bool?
    public var connection: BatteryConnection?
    public var batteryPower: BatteryPowerReading?
    public var telemetry: BatteryTelemetry?

    public init(id: String, name: String, level: Int?, isCharging: Bool = false,
                isConnected: Bool = true, source: BatterySource, measuredAt: Date? = nil,
                lastSeenAt: Date? = nil, approximate: Bool = false, connection: BatteryConnection? = nil,
                batteryPower: BatteryPowerReading? = nil, telemetry: BatteryTelemetry? = nil) {
        self.id = id
        self.name = name
        self.level = level.flatMap { (0...100).contains($0) ? $0 : nil }
        self.isCharging = isCharging
        self.isConnected = isConnected
        self.source = source
        self.measuredAt = measuredAt
        self.lastSeenAt = lastSeenAt
        self.approximate = approximate
        self.connection = connection
        self.batteryPower = batteryPower
        self.telemetry = telemetry
    }

    public func isLive(at now: Date = Date()) -> Bool {
        isConnected && lastSeenAt.map { (-2..<600).contains(now.timeIntervalSince($0)) } == true
    }

    public func displayLevel(at now: Date = Date()) -> Int? {
        guard level.map({ (0...100).contains($0) }) == true,
              measuredAt.map({ now.timeIntervalSince($0) >= -2 }) ?? true else { return nil }
        if isLive(at: now) {
            guard let measuredAt, (-2..<600).contains(now.timeIntervalSince(measuredAt)) else { return nil }
        }
        return level
    }

    public func displayPower(at now: Date = Date()) -> BatteryPowerReading? {
        guard source == .mobile, id.hasPrefix("ios:"), isLive(at: now), let batteryPower,
              batteryPower.isValid, batteryPower.isCharging == isCharging,
              (0..<120).contains(now.timeIntervalSince(batteryPower.measuredAt)) else { return nil }
        return batteryPower
    }
}

public struct BatterySnapshot: Sendable {
    public var devices: [BatteryDevice]
    public var successfulSources: Set<BatterySource>
    public var issues: [String]
    public var pencilConnections: [PencilConnection]

    public init(devices: [BatteryDevice], successfulSources: Set<BatterySource>, issues: [String] = [],
                pencilConnections: [PencilConnection] = []) {
        self.devices = devices
        self.successfulSources = successfulSources
        self.issues = issues
        self.pencilConnections = pencilConnections
    }
}

public struct PencilConnection: Sendable, Equatable {
    public let id: String
    public let network: Bool
    public init(id: String, network: Bool) { self.id = id; self.network = network }
}

public enum BatteryLedger {
    /// Missing devices become offline only when their source completed successfully.
    /// A cached offline sample never receives a new measurement timestamp.
    public static func merge(_ previous: [BatteryDevice], snapshot: BatterySnapshot) -> [BatteryDevice] {
        var devices = previous
        let incomingIDs = Set(snapshot.devices.map(\.id))
        for index in devices.indices where snapshot.successfulSources.contains(devices[index].source) {
            if !incomingIDs.contains(devices[index].id) { devices[index].isConnected = false }
        }
        for incoming in snapshot.devices {
            if let index = devices.firstIndex(where: { $0.id == incoming.id }) {
                var merged = incoming
                if merged.connection == nil { merged.connection = devices[index].connection }
                if incoming.level == nil {
                    merged.level = devices[index].level
                    merged.measuredAt = devices[index].measuredAt
                    merged.approximate = devices[index].approximate
                    merged.isCharging = devices[index].isCharging
                    merged.telemetry = devices[index].telemetry
                } else if incoming.measuredAt == nil {
                    merged.measuredAt = devices[index].measuredAt
                }
                if !incoming.isConnected { merged.lastSeenAt = devices[index].lastSeenAt }
                devices[index] = merged
            } else {
                devices.append(incoming)
            }
        }
        return devices.sorted {
            if $0.source == .mac && $1.source != .mac { return true }
            if $1.source == .mac && $0.source != .mac { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
