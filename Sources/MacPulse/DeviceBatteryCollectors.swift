import Foundation
import MetricsCore
import TelemetryBridge

enum DeviceBatteryCollector {
    static func collect(includeMobile: Bool, bluetooth: [BatteryDevice], localResult: @escaping @Sendable (BatterySnapshot) -> Void) -> BatterySnapshot {
        let logitech = LogitechCollector.collect()
        var devices = logitech.devices.map { device -> BatteryDevice in
            let matches = bluetooth.filter { $0.isConnected && $0.name.caseInsensitiveCompare(device.name) == .orderedSame }
            guard matches.count == 1 else { return device }
            var merged = BatteryDevice(id: matches[0].id, name: device.name, level: device.level, isCharging: device.isCharging,
                                       source: .bluetooth, measuredAt: device.measuredAt, lastSeenAt: device.lastSeenAt,
                                       approximate: device.approximate == true, connection: device.connection ?? .bluetooth, telemetry: .hidpp)
            merged.batteryPower = device.batteryPower
            return merged
        }
        var successful: Set<BatterySource> = logitech.permissionDenied ? [] : [.logitech]
        var issues = logitech.permissionDenied ? [String(localized: "Logitech HID++ needs Input Monitoring permission for MacPulse.")] : []
        localResult(.init(devices: devices, successfulSources: successful, issues: issues))
        var connections: [PencilConnection] = []
        if includeMobile && !Task.isCancelled {
            if let mobile = MobileCollector.collect() {
                devices += mobile.devices; connections = mobile.connections
                if mobile.completed { successful.insert(.mobile) }
                else { issues.append(String(localized: "Mobile query partial; the last completed readings are kept.")) }
            } else { issues.append(String(localized: "Mobile battery tools not found; see the connection guide.")) }
        }
        return .init(devices: devices, successfulSources: successful, issues: issues, pencilConnections: connections)
    }
}

enum LogitechCollector {
    static func collect() -> (devices: [BatteryDevice], permissionDenied: Bool) {
        var samples = [PBBattery](repeating: PBBattery(), count: 16)
        var denied: Int32 = 0
        let count = samples.withUnsafeMutableBufferPointer { buffer in
            pb_read_logitech(buffer.baseAddress, Int32(buffer.count), &denied)
        }
        let now = Date()
        let devices = samples.prefix(Int(count)).map { sample in
            var sample = sample
            let name = withUnsafePointer(to: &sample.name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            let id = withUnsafePointer(to: &sample.identifier) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            return BatteryDevice(id: id, name: name, level: sample.level >= 0 ? Int(sample.level) : nil,
                                 isCharging: sample.charging != 0, source: .logitech,
                                 measuredAt: sample.level >= 0 ? now : nil, lastSeenAt: now,
                                 approximate: sample.approximate != 0,
                                 connection: sample.connection == 1 ? .bluetooth : sample.connection == 2 ? .usb : sample.connection == 3 ? .usbReceiver : nil, telemetry: .hidpp)
        }
        return (devices, denied != 0)
    }
}

enum MobileCollector {
    static func collect() -> (devices: [BatteryDevice], connections: [PencilConnection], completed: Bool)? {
        let listTool = DeviceProcessRunner.tool("idevice_id")
        let infoTool = DeviceProcessRunner.tool("ideviceinfo")
        let nativeTool = DeviceProcessRunner.tool("pilbar-mobile-native")
        guard nativeTool != nil || (listTool != nil && infoTool != nil) else { return nil }
        var devices: [BatteryDevice] = []
        var connections: [PencilConnection] = []
        var seen = Set<String>()
        var completed = false
        var completedLists = 0
        if let nativeTool,
           let data = DeviceProcessRunner.run(nativeTool, ["--json"], timeout: 14, keepPartialOutput: true),
           let readings = try? MobileBatteryParser.parse(data) {
            completed = data.split(separator: 10).contains { line in
                (try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])?["complete"] as? Bool == true
            }
            for reading in readings {
                let id = reading.parentID
                guard !seen.contains(id) else { continue }
                var device = reading.device; device.telemetry = .mobileDevice; devices.append(device)
                seen.insert(id)
                if reading.isPhone { devices += companions(id: id, network: reading.network) }
                if reading.isPad {
                    connections.append(.init(id: id, network: reading.network))
                }
            }
        }
        guard let listTool, let infoTool else { return (addingPower(to: devices), connections, completed: completed || completedLists == 2) }
        for network in [false, true] {
            guard let data = DeviceProcessRunner.run(listTool, [network ? "-n" : "-l"]),
                  let text = String(data: data, encoding: .utf8) else { continue }
            completedLists += 1
            for line in text.split(separator: "\n").prefix(16) {
                let id = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !seen.contains(id) else { continue }
                let base = (network ? ["-n"] : []) + ["-u", id]
                guard let batteryData = DeviceProcessRunner.run(infoTool, base + ["-q", "com.apple.mobile.battery", "-x"], timeout: 4),
                      let battery = try? PropertyListSerialization.propertyList(from: batteryData, format: nil) as? [String: Any],
                      let level = battery["BatteryCurrentCapacity"] as? Int, (0...100).contains(level) else { continue }
                seen.insert(id)
                let nameData = DeviceProcessRunner.run(infoTool, base + ["-k", "DeviceName"], timeout: 3)
                let name = nameData.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
                let now = Date()
                let device = BatteryDevice(id: "ios:" + id, name: name ?? "iPhone / iPad", level: level,
                                           isCharging: battery["BatteryIsCharging"] as? Bool ?? false,
                                           source: .mobile, measuredAt: now, lastSeenAt: now, connection: network ? .wifi : .usb, telemetry: .libimobiledevice)
                devices.append(device)
                devices += companions(id: id, network: network)
                if (name ?? "").lowercased().contains("ipad") { connections.append(.init(id: id, network: network)) }
            }
        }
        return (addingPower(to: devices), connections, completed: completed || completedLists == 2)
    }

    private static func addingPower(to devices: [BatteryDevice]) -> [BatteryDevice] {
        guard let tool = DeviceProcessRunner.tool("idevicediagnostics") else { return devices }
        var enriched = devices
        let deadline = Date().addingTimeInterval(7)
        var attempted = 0
        for index in enriched.indices {
            let device = enriched[index]
            guard device.source == .mobile, device.id.hasPrefix("ios:"), device.isConnected,
                  device.level != nil, attempted < 4, Date() < deadline else { continue }
            attempted += 1
            let identifier = String(device.id.dropFirst(4))
            let network = device.connection != .usb
            let args = (network ? ["-n"] : []) + ["-u", identifier, "ioregentry", "AppleSmartBattery"]
            let timeout = min(3, deadline.timeIntervalSinceNow)
            guard timeout > 0,
                  let data = DeviceProcessRunner.run(tool, args, timeout: timeout),
                  let reading = try? BatteryPowerParser.parse(data, expectedLevel: device.level, expectedCharging: device.isCharging) else { continue }
            enriched[index].batteryPower = reading
        }
        return enriched
    }

    private static func companions(id: String, network: Bool) -> [BatteryDevice] {
        guard let tool = DeviceProcessRunner.tool("pilbar-watch"),
              let data = DeviceProcessRunner.run(tool, [id, network ? "network" : "usb"], timeout: 5),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let now = Date()
        return rows.compactMap { row in
            guard let identifier = row["id"] as? String, let level = row["level"] as? Int else { return nil }
            return .init(id: "watch:" + identifier, name: row["name"] as? String ?? "Apple Watch", level: level,
                         isCharging: row["charging"] as? Bool ?? false, source: .mobile,
                         measuredAt: now, lastSeenAt: now, connection: .viaIPhone, telemetry: .libimobiledevice)
        }
    }

}
