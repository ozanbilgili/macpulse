import Foundation
import CoreFoundation

public enum BluetoothParser {
    public static func percentage(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            let value = number.doubleValue
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), value.isFinite, (0...100).contains(value), value.rounded(.towardZero) == value else { return nil }
            return Int(value)
        }
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        guard let number = Int(trimmed), (0...100).contains(number) else { return nil }
        return number
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> [BatteryDevice] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]],
              controllers.contains(where: { !$0.isEmpty }) else {
            throw ParseError.controllerUnavailable
        }
        var result: [BatteryDevice] = []
        func walk(_ node: Any) {
            if let dictionary = node as? [String: Any] {
                for (key, value) in dictionary {
                    if key == "device_connected" || key == "device_not_connected",
                       let entries = value as? [[String: Any]] {
                        for entry in entries {
                            for (name, details) in entry {
                                guard let attributes = details as? [String: Any] else { continue }
                                result += devices(name: name, attributes: attributes,
                                                  connected: key == "device_connected", now: now)
                            }
                        }
                    } else { walk(value) }
                }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(controllers)
        return result
    }

    private static func devices(name: String, attributes: [String: Any], connected: Bool, now: Date) -> [BatteryDevice] {
        let address = attributes["device_address"] as? String ?? name
        let baseID = "bt:" + address.lowercased().replacingOccurrences(of: "-", with: ":")
        let left = percentage(attributes["device_batteryLevelLeft"])
        let right = percentage(attributes["device_batteryLevelRight"])
        let main = percentage(attributes["device_batteryLevelMain"] ?? attributes["device_batteryLevel"])
        let caseLevel = percentage(attributes["device_batteryLevelCase"])
        // Logitech's generic Bluetooth service can report a static 100%. Use HID++.
        let logitech = name.lowercased().contains("mx ") || name.lowercased().contains("logitech")
        let level = logitech ? nil : main ?? [left, right].compactMap { $0 }.min()
        let charging = isCharging(attributes["device_isCharging"] ?? attributes["device_batteryIsCharging"])
        func make(_ id: String, _ label: String, _ value: Int?, _ charging: Bool) -> BatteryDevice {
            .init(id: id, name: label, level: value, isCharging: charging, isConnected: connected,
                  source: .bluetooth, measuredAt: connected && value != nil ? now : nil,
                  lastSeenAt: connected ? now : nil, connection: .bluetooth)
        }
        var result: [BatteryDevice] = []
        // Unknown connected peripherals remain visible as a dash; never invent a percentage.
        if connected || level != nil { result.append(make(baseID, name, level, charging)) }
        if let caseLevel {
            result.append(make(baseID + ":case", name + " Case", caseLevel,
                               isCharging(attributes["device_batteryIsChargingCase"])))
        }
        return result
    }

    private static func isCharging(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        return ["yes", "true", "1"].contains((value as? String ?? "").lowercased())
    }

    public enum ParseError: Error { case controllerUnavailable }
}
