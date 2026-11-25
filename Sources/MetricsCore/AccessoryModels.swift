import Foundation
import CoreFoundation

public enum BluetoothPower: String, Sendable { case on, off, unknown }
public enum AccessoryConnection: String, Sendable { case connected, disconnected, unknown }
public struct AccessoryBattery: Sendable, Equatable {
    /// Stable identifier: `main`, `left`, `right` or `case`.
    public let component: String
    public let percent: Int
    public var charging: Bool? = nil
    public var label: String {
        switch component {
        case "main": String(localized: "Main"); case "left": String(localized: "Left")
        case "right": String(localized: "Right"); case "case": String(localized: "Case")
        default: component
        }
    }
}
public struct BluetoothAccessory: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let connection: AccessoryConnection
    public let reportedBatteries: [AccessoryBattery]
    public let batteryLimitation: String?
    public var reportedCharging: Bool? = nil
}
public struct BluetoothSnapshot: Sendable {
    public let date: Date
    public let power: BluetoothPower
    public let accessories: [BluetoothAccessory]
    public let status: String
    public let available: Bool
    public let truncated: Bool
    public let discardedOfflineBatteryCount: Int
    public let collectionMilliseconds: Double
    public func fresh(at now: Date) -> Bool { AccessoryMath.fresh(date, at: now) }
    public func connection(_ device: BluetoothAccessory, at now: Date) -> AccessoryConnection {
        fresh(at: now) && available ? device.connection : .unknown
    }
    public func batteries(_ device: BluetoothAccessory, at now: Date, paused: Bool = false) -> [AccessoryBattery] {
        guard !paused, fresh(at: now), available, device.connection == .connected else { return [] }
        return device.reportedBatteries
    }
}
public struct AudioDeviceReading: Sendable, Identifiable {
    public let id: UInt32
    public let name: String
    public let transport: String
    public let inputChannels, outputChannels: Int?
    public let running: Bool?
    public let sampleRate: Double?
    public let inputVolume, outputVolume: Double?
    public let inputMuted, outputMuted: Bool?
}
public struct AudioSnapshot: Sendable {
    public let date: Date
    public let devices: [AudioDeviceReading]
    public let defaultInput, defaultOutput, defaultSystemOutput: UInt32?
    public let available: Bool
    public let failures: Int
    public let truncated: Bool
    public let collectionMilliseconds: Double
    public var input: AudioDeviceReading? { devices.first { $0.id == defaultInput } }
    public var output: AudioDeviceReading? { devices.first { $0.id == defaultOutput } }
    public var systemOutput: AudioDeviceReading? { devices.first { $0.id == defaultSystemOutput } }
}
public enum AccessoryMath {
    public static func fresh(_ date: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age.isFinite && age >= -2 && age <= 45
    }
    public static func scalar(_ value: Double) -> Double? { value.isFinite && (0...1).contains(value) ? value * 100 : nil }
    public static func sampleRate(_ value: Double) -> Double? { value.isFinite && (1...768_000).contains(value) ? value : nil }
    static func safeName(_ value: String, fallback: String) -> String {
        let cleaned = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }
}
enum BluetoothProfileParser {
    enum ParseError: Error { case invalidStructure, sizeLimit }
    static func percent(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
            let d = number.doubleValue
            return (0...100).contains(d) ? Int(d) : nil
        }
        guard let string = value as? String else { return nil }
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = s.hasPrefix("%") ? String(s.dropFirst()) : s.hasSuffix("%") ? String(s.dropLast()) : s
        guard let p = Int(t), (0...100).contains(p) else { return nil }
        return p
    }
    static func charging(_ value: Any?) -> Bool? {
        if let n = value as? NSNumber, [0, 1].contains(n.intValue), n.doubleValue == Double(n.intValue) { return n.boolValue }
        if let text = value as? String {
            switch text.lowercased() { case "true", "yes", "1": return true; case "false", "no", "0": return false; default: break }
        }
        return nil
    }
    static func identity(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let pieces = s.lowercased().replacingOccurrences(of: "-", with: ":").split(separator: ":")
        guard pieces.count == 6, pieces.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else { return nil }
        return pieces.joined(separator: ":")
    }
    static func parse(_ data: Data, date: Date, milliseconds: Double = 0) throws -> BluetoothSnapshot {
        guard data.count <= 1_048_576 else { throw ParseError.sizeLimit }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let controllers = root["SPBluetoothDataType"] as? [[String: Any]], !controllers.isEmpty else { throw ParseError.invalidStructure }
        var devices: [String: BluetoothAccessory] = [:], discarded = 0, truncated = controllers.count > 4
        var states: [BluetoothPower] = [], examined = 0
        for (ci, controller) in controllers.prefix(4).enumerated() {
            guard let properties = controller["controller_properties"] as? [String: Any], !properties.isEmpty else { throw ParseError.invalidStructure }
            switch (properties["controller_state"] as? String)?.lowercased() {
            case "attrib_on": states.append(.on)
            case "attrib_off": states.append(.off)
            default: states.append(.unknown)
            }
            // Disconnected wins a conflicting row; never retain its cached battery.
            for group in ["device_connected", "device_not_connected"] {
                guard let raw = controller[group] else { continue }
                guard let entries = raw as? [[String: Any]] else { throw ParseError.invalidStructure }
                if entries.count > 128 { truncated = true }
                for (ei, entry) in entries.prefix(128).enumerated() {
                    for (name, value) in entry.sorted(by: { $0.key < $1.key }) {
                        examined += 1
                        if examined > 256 { truncated = true; continue }
                        guard let fields = value as? [String: Any] else { throw ParseError.invalidStructure }
                        let id = identity(fields["device_address"]).map { "bt:" + $0 } ?? "unknown:\(ci):\(group):\(ei):\(name.prefix(120))"
                        let connected = group == "device_connected" && states.last != .off
                        let batteries = [("main", "device_batteryLevelMain"), ("main", "device_batteryLevel"), ("left", "device_batteryLevelLeft"), ("right", "device_batteryLevelRight"), ("case", "device_batteryLevelCase")]
                        var reported: [AccessoryBattery] = []
                        for (label, key) in batteries {
                            if let p = percent(fields[key]), !reported.contains(where: { $0.component == label }) { reported.append(.init(component: label, percent: p, charging: label == "case" ? charging(fields["device_batteryIsChargingCase"]) : charging(fields["device_isCharging"] ?? fields["device_batteryIsCharging"]))) }
                        }
                        let vendor = (fields["device_vendorID"] as? String)?.lowercased()
                        let logitech = name.lowercased().contains("logitech") || name.lowercased().contains("mx ") || vendor == "0x046d" || (fields["device_vendorID"] as? NSNumber)?.intValue == 0x046d
                        if !connected { discarded += reported.count }
                        let row = BluetoothAccessory(id: id, name: AccessoryMath.safeName(name, fallback: String(localized: "Bluetooth accessory")),
                            kind: AccessoryMath.safeName(fields["device_minorType"] as? String ?? "", fallback: String(localized: "Type not reported")),
                            connection: connected ? .connected : .disconnected, reportedBatteries: connected && !logitech ? reported : [],
                            batteryLimitation: logitech ? String(localized: "Logitech needs a verified HID++ source") : nil, reportedCharging: connected ? charging(fields["device_isCharging"] ?? fields["device_batteryIsCharging"]) : nil)
                        if let old = devices[id], old.connection == .disconnected { continue }
                        if devices[id] == nil && devices.count >= 64 { truncated = true; continue }
                        devices[id] = row
                    }
                }
            }
        }
        let power: BluetoothPower = states.contains(.on) ? .on : states.allSatisfy({ $0 == .off }) ? .off : .unknown
        return BluetoothSnapshot(date: date, power: power, accessories: devices.values.sorted {
            if $0.connection != $1.connection { return $0.connection == .connected }
            return $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }, status: String(localized: "macOS Bluetooth inventory · every 30 seconds"), available: true, truncated: truncated,
            discardedOfflineBatteryCount: discarded, collectionMilliseconds: milliseconds)
    }
}
