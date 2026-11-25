import Testing
import Foundation
import TelemetryBridge
@testable import MetricsCore

private let accessoryNow = Date(timeIntervalSince1970: 1_000)
private func profile(connected: [[String: Any]] = [], offline: [[String: Any]] = [], power: String = "attrib_on") throws -> BluetoothSnapshot {
    let root: [String: Any] = ["SPBluetoothDataType": [["controller_properties": ["controller_state": power], "device_connected": connected, "device_not_connected": offline]]]
    return try BluetoothProfileParser.parse(JSONSerialization.data(withJSONObject: root), date: accessoryNow)
}
private func device(_ name: String = "Test headset", address: String = "00-11-22-33-44-55", extra: [String: Any] = [:]) -> [String: Any] {
    [name: ["device_address": address, "device_minorType": "Headphones"].merging(extra) { _, new in new }]
}
@Test func accessoryPercentageAcceptsOnlyWholeRangeAndRejectsBoolean() {
    #expect(BluetoothProfileParser.percent("%40") == 40)
    #expect(BluetoothProfileParser.percent("100%") == 100)
    #expect(BluetoothProfileParser.percent(0) == 0)
    for value: Any in [-1, 101, 1.5, true, "unknown", "%100%", "12.5%"] { #expect(BluetoothProfileParser.percent(value) == nil) }
}
@Test func accessoryZeroBatteryIsReportedWithoutInventingCharging() throws {
    let s = try profile(connected: [device(extra: ["device_batteryLevel": "0%"])] )
    #expect(s.accessories.first?.reportedBatteries == [AccessoryBattery(component: "main", percent: 0)])
}
@Test func accessoryOfflineCachedAirPodsLevelsAreDiscarded() throws {
    let s = try profile(offline: [device(extra: ["device_batteryLevelLeft": "%100", "device_batteryLevelRight": "%100", "device_batteryLevelCase": "%40"])])
    #expect(s.discardedOfflineBatteryCount == 3)
    #expect(s.accessories.count == 1)
    #expect(s.accessories[0].connection == .disconnected)
    #expect(s.accessories[0].reportedBatteries.isEmpty)
}
@Test func accessoryComponentsStaySeparateAndMainHasPriority() throws {
    let s = try profile(connected: [device(extra: ["device_batteryLevelMain": 30, "device_batteryLevel": 80, "device_batteryLevelLeft": 90, "device_batteryLevelRight": 70, "device_batteryLevelCase": 10])])
    #expect(s.accessories[0].reportedBatteries.map(\.percent) == [30, 90, 70, 10])
}
@Test func accessoryLogitechGenericBatteryIsNotTrusted() throws {
    let s = try profile(connected: [device("MX Keys", extra: ["device_batteryLevel": 100]), device("Keyboard", address: "00:11:22:33:44:66", extra: ["device_vendorID": "0x046D", "device_batteryLevel": 100]), device("Keyboard", address: "00:11:22:33:44:77", extra: ["device_vendorID": 1133, "device_batteryLevel": 100])])
    #expect(s.accessories.allSatisfy { $0.reportedBatteries.isEmpty && $0.batteryLimitation != nil })
}
@Test func accessoryNativeReaderRejectsInvalidCapacityBeforeSpawning() {
    var byte: CChar = 0, length: UInt32 = 99
    #expect(mp_read_bluetooth_profile(&byte, 1, &length) == 3)
    #expect(mp_read_bluetooth_profile(&byte, 1_048_577, &length) == 3)
}
@Test func audioNativeReaderRejectsInvalidCapacityWithoutTouchingHAL() {
    var entry = mp_audio_device(), count: Int32 = 99, info = mp_audio_info()
    #expect(mp_read_audio(&entry, 0, &count, &info) == -1)
    #expect(mp_read_audio(&entry, 129, &count, &info) == -1)
}
@Test func accessoryConflictingConnectionFailsClosedAcrossDuplicateRows() throws {
    let s = try profile(connected: [device(extra: ["device_batteryLevel": 90])], offline: [device(address: "00:11:22:33:44:55", extra: ["device_batteryLevel": 100])])
    #expect(s.accessories.count == 1)
    #expect(s.accessories[0].connection == .disconnected)
    #expect(s.accessories[0].reportedBatteries.isEmpty)
}
@Test func accessoryDuplicateConnectedRowDoesNotDuplicateDevice() throws {
    let s = try profile(connected: [device(), device("Renamed", address: "00:11:22:33:44:55")])
    #expect(s.accessories.count == 1)
}
@Test func accessoryEqualNamesDifferentAddressesRemainDistinct() throws {
    let s = try profile(connected: [device(), device(address: "00:11:22:33:44:66")])
    #expect(s.accessories.count == 2)
}
@Test func accessoryMissingAddressDoesNotMergeSameNames() throws {
    let s = try profile(connected: [["Headset": [:]], ["Headset": [:]]])
    #expect(s.accessories.count == 2)
}
@Test func accessoryAddressRequiresSixHexOctets() {
    #expect(BluetoothProfileParser.identity("00-11-22-AA-bb-FF") == "00:11:22:aa:bb:ff")
    for value in ["0:11:22:33:44:55", "00:11:22:33:44:gg", "secret"] { #expect(BluetoothProfileParser.identity(value) == nil) }
}
@Test func accessoryControllerOffOverridesConnectedCachedBattery() throws {
    let s = try profile(connected: [device(extra: ["device_batteryLevel": 90])], power: "attrib_off")
    #expect(s.power == .off)
    #expect(s.accessories[0].connection == .disconnected)
    #expect(s.accessories[0].reportedBatteries.isEmpty)
}
@Test func accessoryUnknownPowerDoesNotBecomeOff() throws {
    #expect(try profile(power: "unsupported").power == .unknown)
}
@Test func accessoryFreshnessUsesPollTimeWithoutClaimingSensorTime() throws {
    let s = try profile(connected: [device(extra: ["device_batteryLevel": 70])]); let d = s.accessories[0]
    #expect(s.batteries(d, at: accessoryNow.addingTimeInterval(45)).count == 1)
    #expect(s.batteries(d, at: accessoryNow.addingTimeInterval(45.1)).isEmpty)
    #expect(s.connection(d, at: accessoryNow.addingTimeInterval(46)) == .unknown)
    #expect(s.batteries(d, at: accessoryNow.addingTimeInterval(-3)).isEmpty)
}
@Test func accessoryPauseHidesReportedBattery() throws {
    let s = try profile(connected: [device(extra: ["device_batteryLevel": 70])]); let d = s.accessories[0]
    #expect(s.batteries(d, at: accessoryNow, paused: true).isEmpty)
}
@Test func accessoryEmptyInventoryIsValidAndNotAnError() throws {
    let s = try profile(); #expect(s.available); #expect(s.accessories.isEmpty)
}
@Test func accessoryMalformedControllerOrEntriesAreErrors() throws {
    for root: [String: Any] in [[:], ["SPBluetoothDataType": []], ["SPBluetoothDataType": [[:]]], ["SPBluetoothDataType": [["controller_properties": ["controller_state": "attrib_on"], "device_connected": "bad"]]]] {
        let data = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: (any Error).self) { try BluetoothProfileParser.parse(data, date: accessoryNow) }
    }
}
@Test func accessoryInventoryHasBoundedRowsAndSize() throws {
    let entries = (0..<70).map { ["Device \($0)": ["device_address": String(format: "00:11:22:33:44:%02x", $0)]] }
    let s = try profile(connected: entries)
    #expect(s.accessories.count == 64); #expect(s.truncated)
    #expect(throws: (any Error).self) { try BluetoothProfileParser.parse(Data(repeating: 32, count: 1_048_577), date: accessoryNow) }
}
@Test func accessoryNamesStripControlCharactersAndBoundLength() {
    #expect(AccessoryMath.safeName("a\nb\tc", fallback: "Empty") == "abc")
    #expect(AccessoryMath.safeName("\n\t", fallback: "Empty") == "Empty")
    #expect(AccessoryMath.safeName(String(repeating: "x", count: 300), fallback: "Empty").count == 120)
}
@Test func audioScalarKeepsTrueZeroAndMissingOutOfRange() {
    #expect(AccessoryMath.scalar(0) == 0); #expect(AccessoryMath.scalar(1) == 100)
    #expect(AccessoryMath.scalar(0.42) == 42)
    for value in [-0.1, 1.1, .nan, .infinity] { #expect(AccessoryMath.scalar(value) == nil) }
}
@Test func audioSampleRateRejectsInvalidDriverValues() {
    #expect(AccessoryMath.sampleRate(48_000) == 48_000)
    for value in [0, -1, .nan, .infinity, 1_000_000] { #expect(AccessoryMath.sampleRate(value) == nil) }
}
@Test func audioDefaultsOnlyResolveToCurrentInventoryAndKeepUnknownMute() {
    let d = AudioDeviceReading(id: 42, name: "Speaker", transport: "USB", inputChannels: 0, outputChannels: 2, running: false, sampleRate: 48_000, inputVolume: nil, outputVolume: nil, inputMuted: nil, outputMuted: nil)
    let s = AudioSnapshot(date: accessoryNow, devices: [d], defaultInput: 99, defaultOutput: 42, defaultSystemOutput: nil, available: true, failures: 0, truncated: false, collectionMilliseconds: 0)
    #expect(s.input == nil); #expect(s.output?.id == 42); #expect(s.output?.outputMuted == nil); #expect(s.output?.outputVolume == nil)
}
@Test func accessoryInventoriesNeverEnterEncodedSnapshotOrChartHistory() throws {
    var snapshot = MetricSnapshot(date: accessoryNow, cpu: nil, memory: nil, disk: nil, network: nil, battery: nil,
        system: SystemMetrics(chip: "Test", cores: 1, physicalMemory: 1, operatingSystem: "Test", uptime: 1, thermalState: "Normal"), issues: [], collectionMilliseconds: 0)
    snapshot.bluetooth = try profile(offline: [device("Private accessory")])
    snapshot.audio = AudioSnapshot(date: accessoryNow, devices: [], defaultInput: nil, defaultOutput: nil, defaultSystemOutput: nil, available: true, failures: 0, truncated: false, collectionMilliseconds: 0)
    let data = try JSONEncoder().encode(snapshot)
    #expect(!String(decoding: data, as: UTF8.self).contains("Private accessory"))
    let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(root["bluetooth"] == nil && root["audio"] == nil)
    #expect(snapshot.historySample.bluetooth == nil && snapshot.historySample.audio == nil)
    let decoded = try JSONDecoder().decode(MetricSnapshot.self, from: data)
    #expect(decoded.bluetooth == nil && decoded.audio == nil)
}
