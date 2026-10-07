import Foundation
import Testing
@testable import MetricsCore

struct DeviceBatteryIntegrationTests {
    private let now = Date(timeIntervalSince1970: 1800000000)
    @Test func migrationIsPrivateIdempotentAndPreservesSourceBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = DeviceBatteryStorage(directory: root.appendingPathComponent("source"))
        let target = DeviceBatteryStorage(directory: root.appendingPathComponent("target"))
        let device = BatteryDevice(id: "fixture", name: "Tablet", level: 60, source: .mobile, measuredAt: now, lastSeenAt: now)
        var history = BatteryHistory(); history.record([device], now: now)
        var preferences = BatteryPreferences(); preferences.devices["fixture"] = DeviceOptions(); preferences.devices["fixture"]?.alias = "Work tablet"
        try source.write([device], file: "devices.json"); try source.write(history, file: "history.json")
        try source.write(preferences, file: "preferences.json"); try source.write(BatteryAlertState(), file: "alerts.json")
        let before = try ["devices.json", "history.json", "preferences.json", "alerts.json"].map { try Data(contentsOf: source.directory.appendingPathComponent($0)) }
        let report = try target.migrate(from: source.directory)
        #expect(report.files.count == 4 && report.deviceCount == 1 && report.historyPointCount == 1)
        for (i, file) in ["devices.json", "history.json", "preferences.json", "alerts.json"].enumerated() {
            #expect(try Data(contentsOf: source.directory.appendingPathComponent(file)) == before[i])
            #expect(try Data(contentsOf: target.directory.appendingPathComponent(file)) == before[i])
            #expect((try FileManager.default.attributesOfItem(atPath: target.directory.appendingPathComponent(file).path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        #expect((try FileManager.default.attributesOfItem(atPath: target.directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try target.write([BatteryDevice](), file: "devices.json")
        #expect(try target.migrate(from: source.directory).sourceHashes == report.sourceHashes)
        #expect(target.read([BatteryDevice].self, file: "devices.json")?.isEmpty == true)
    }
    @Test func malformedMigrationValidatesAllFilesBeforeWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = DeviceBatteryStorage(directory: root.appendingPathComponent("source"))
        let target = DeviceBatteryStorage(directory: root.appendingPathComponent("target"))
        try source.write([BatteryDevice](), file: "devices.json")
        try Data("invalid".utf8).write(to: source.directory.appendingPathComponent("history.json"))
        #expect(throws: (any Error).self) { try target.migrate(from: source.directory) }
        #expect(!FileManager.default.fileExists(atPath: target.directory.path))
    }
    @Test func migrationDoesNotReplaceAnExistingTargetFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = DeviceBatteryStorage(directory: root.appendingPathComponent("source"))
        let target = DeviceBatteryStorage(directory: root.appendingPathComponent("target"))
        var p = BatteryPreferences(); p.lowThreshold = 25
        try target.write(p, file: "preferences.json")
        try source.write(BatteryPreferences(), file: "preferences.json")
        #expect(try target.migrate(from: source.directory).files.isEmpty)
        #expect(target.read(BatteryPreferences.self, file: "preferences.json")?.lowThreshold == 25)
    }
    @Test func deviceWidgetIdentityOptionsAndOrderPersistWithoutFabricatingADevice() throws {
        let order = [MenuWidget(.deviceBattery, style: .percent, deviceID: "a"), MenuWidget(.claude, account: 2), MenuWidget(.deviceBattery, style: .bars, deviceID: "b"), MenuWidget(.battery)]
        let decoded = try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(MonitorPreferences(menuWidgets: order)))
        #expect(decoded.resolvedWidgets(claudeAccounts: [], codex: false, openRouter: false) == order)
        #expect(MenuWidget.normalized(order + [.init(.deviceBattery), .init(.deviceBattery, deviceID: "a"), .init(.deviceBattery, deviceID: String(repeating: "a", count: 513))]) == order)
        #expect(try JSONDecoder().decode(MenuWidget.self, from: Data(#"{"kind":"cpu"}"#.utf8)).deviceID.isEmpty)
    }
    @Test func oldWidgetJSONWithoutDeviceIDsKeepsAllSourcesWhenBatteryIsAdded() throws {
        let data = Data(#"{"theme":"dark","interval":2,"menuWidgets":[{"kind":"cpu","account":0,"window":"both","style":"both","showsLeft":false},{"kind":"memory"},{"kind":"claude","account":1},{"kind":"claude","account":2},{"kind":"claude","account":3},{"kind":"claude","account":4},{"kind":"codex"},{"kind":"openRouter"}]}"#.utf8)
        let p = try JSONDecoder().decode(MonitorPreferences.self, from: data)
        let old = p.resolvedWidgets(claudeAccounts: [], codex: false, openRouter: false)
        #expect(old.count == 8)
        #expect(MenuWidget.normalized(old + [.init(.battery)]).map(\.id) == ["cpu", "memory", "claude:1", "claude:2", "claude:3", "claude:4", "codex", "openRouter", "battery"])
    }
    @Test func unmeasuredOfflineInventoryDoesNotCreateAFalseLastMeasurement() throws {
        let data = Data(#"{"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},"device_not_connected":[{"Unmeasured keyboard":{"device_address":"00:11:22:33:44:55"}}]}]}"#.utf8)
        let s = try BluetoothProfileParser.parse(data, date: now)
        let result = DeviceBatteryAdapter.bluetooth(s, now: now)
        #expect(result.devices.isEmpty && result.successfulSources == [.bluetooth])
    }
    @Test func sharedBluetoothAdapterPreservesDateCaseAndCharging() throws {
        let json = Data(#"{"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},"device_connected":[{"AirPods Pro":{"device_address":"00:11:22:33:44:55","device_batteryLevelLeft":"70%","device_batteryLevelRight":"60%","device_batteryLevelCase":"30%","device_isCharging":true,"device_batteryIsChargingCase":true}}]}]}"#.utf8)
        let s = try BluetoothProfileParser.parse(json, date: now)
        let result = DeviceBatteryAdapter.bluetooth(s, now: now.addingTimeInterval(10))
        #expect(result.devices.map(\.level) == [60, 30])
        #expect(result.devices.allSatisfy { $0.measuredAt == now && $0.lastSeenAt == now })
        #expect(result.devices[0].isCharging)
        #expect(DeviceBatteryAdapter.bluetooth(s, now: now.addingTimeInterval(46)).successfulSources.isEmpty)
        #expect(DeviceBatteryAdapter.bluetooth(nil, now: now).devices.isEmpty)
    }
    @Test func unknownGenericReadingDoesNotReplaceHIDMeasurementOrStampItFresh() {
        let hid = BatteryDevice(id: "mouse", name: "MX", level: 64, isCharging: true, source: .bluetooth, measuredAt: now, lastSeenAt: now, approximate: true, telemetry: .hidpp)
        let generic = BatteryDevice(id: "mouse", name: "MX", level: nil, source: .bluetooth, lastSeenAt: now.addingTimeInterval(700), telemetry: .macOSBluetooth)
        let result = BatteryLedger.merge([hid], snapshot: .init(devices: [generic], successfulSources: [.bluetooth]))[0]
        #expect(result.level == 64 && result.isCharging && result.approximate == true && result.telemetry == .hidpp)
        #expect(result.measuredAt == now && result.displayLevel(at: now.addingTimeInterval(700)) == nil)
    }
    @Test func futureMeasurementsAndBooleanPercentagesAreUnknown() {
        let device = BatteryDevice(id: "bad", name: "Bad clock", level: 40, source: .mobile, measuredAt: now.addingTimeInterval(5), lastSeenAt: now.addingTimeInterval(5))
        #expect(!device.isLive(at: now))
        #expect(BluetoothParser.percentage(true) == nil)
        #expect(BluetoothParser.percentage(1.5) == nil)
    }
}
