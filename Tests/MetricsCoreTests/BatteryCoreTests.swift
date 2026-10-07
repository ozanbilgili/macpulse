import Foundation
import Testing
@testable import MetricsCore

@Test func localizedPercentagesAndInvalidSamples() {
    #expect(BluetoothParser.percentage("%47") == 47)
    #expect(BluetoothParser.percentage("100%") == 100)
    #expect(BluetoothParser.percentage(" 0% ") == 0)
    #expect(BluetoothParser.percentage("unknown") == nil)
    #expect(BluetoothParser.percentage(255) == nil)
}

@Test func airPodsAndCaseAreSeparateAndOfflineTimeIsUnknown() throws {
    let data = Data(#"{"SPBluetoothDataType":[{"device_not_connected":[{"AirPods Pro":{"device_address":"AA:BB","device_batteryLevelLeft":"%100","device_batteryLevelRight":"%95","device_batteryLevelCase":"%47"}}]}]}"#.utf8)
    let devices = try BluetoothParser.parse(data)
    #expect(devices.count == 2)
    #expect(devices[0].level == 95)
    #expect(devices[1].level == 47)
    #expect(devices.allSatisfy { !$0.isConnected && $0.measuredAt == nil })
}

@Test func failedSourcePreservesStateAndFreshnessStillExpires() {
    let old = BatteryDevice(id: "bt:test", name: "Keyboard", level: 62, source: .bluetooth,
                            measuredAt: Date(timeIntervalSince1970: 100), lastSeenAt: Date(timeIntervalSince1970: 100))
    let merged = BatteryLedger.merge([old], snapshot: .init(devices: [], successfulSources: [.mac]))
    #expect(merged == [old])
    #expect(!merged[0].isLive(at: Date(timeIntervalSince1970: 701)))
    let missing = BatteryLedger.merge([old], snapshot: .init(devices: [], successfulSources: [.bluetooth]))
    #expect(!missing[0].isConnected)
    #expect(missing[0].measuredAt == old.measuredAt)
}

@Test func unknownReadingRetainsLastMeasurement() {
    let old = BatteryDevice(id: "a", name: "Mouse", level: 76, source: .bluetooth,
                            measuredAt: Date(timeIntervalSince1970: 100))
    let incoming = BatteryDevice(id: "a", name: "Mouse", level: nil, source: .bluetooth,
                                 lastSeenAt: Date(timeIntervalSince1970: 200))
    let merged = BatteryLedger.merge([old], snapshot: .init(devices: [incoming], successfulSources: [.bluetooth]))
    #expect(merged[0].level == 76)
    #expect(merged[0].measuredAt == old.measuredAt)
}

@Test func connectedDeviceDoesNotDisplayAnOldPercentageAsCurrent() {
    let now = Date(timeIntervalSince1970: 1000)
    let device = BatteryDevice(id: "mouse", name: "MX Master 3", level: 50, source: .logitech,
                               measuredAt: Date(timeIntervalSince1970: 100), lastSeenAt: now)
    #expect(device.isLive(at: now))
    #expect(device.displayLevel(at: now) == nil)
    var offline = device
    offline.isConnected = false
    #expect(offline.displayLevel(at: now) == 50)
}

@Test func logitechGenericBatteryIsIgnored() throws {
    let data = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"MX Master 3":{"device_batteryLevelMain":"100%"}}]}]}"#.utf8)
    let devices = try BluetoothParser.parse(data)
    #expect(devices.count == 1)
    #expect(devices[0].level == nil)
}

@Test func pencilBatteryEventIsBoundedToPencilAndApple() {
    let text = #""Accessory Category" = Pencil; "Current Capacity" = 99; "Is Charging" = 1; "Vendor ID" = 76;"#
    let sample = PencilLogParser.parse(text, parentID: "ipad")
    #expect(sample?.level == 99)
    #expect(sample?.isCharging == true)
    #expect(PencilLogParser.parse(text.replacingOccurrences(of: "Pencil", with: "Keyboard"), parentID: "ipad") == nil)
    #expect(PencilLogParser.parse(text.replacingOccurrences(of: "= 76", with: "= 123"), parentID: "ipad") == nil)
}

@Test func nativeMobileReadingRequiresAnAuthenticatedValidBattery() throws {
    let data = Data(#"[{"id":"pad","name":"Tablet","class":"iPad","level":47,"charging":false,"paired":true,"sessionCode":0,"interface":2},{"id":"untrusted","level":80,"paired":false,"sessionCode":0,"interface":2},{"id":"invalid","level":true,"paired":true,"sessionCode":0,"interface":2},{"id":"failed","level":50,"paired":true,"sessionCode":-1,"interface":1}]"#.utf8)
    let readings = try MobileBatteryParser.parse(data)
    #expect(readings.count == 1)
    #expect(readings[0].network && readings[0].isPad)
    #expect(readings[0].device.level == 47)
    #expect(!readings[0].device.isCharging)
    #expect(readings[0].device.id == "ios:pad")
    #expect(readings[0].device.connection == .wifi)
}

@Test func nativeMobileTransportKeepsTheSameIdentityAndPrefersUSB() throws {
    let data = Data(#"[{"id":"phone","level":73,"charging":false,"paired":true,"sessionCode":0,"interface":2},{"id":"phone","level":74,"charging":true,"paired":true,"sessionCode":0,"interface":1},{"id":"bad","level":256,"paired":true,"sessionCode":0,"interface":2}]"#.utf8)
    let readings = try MobileBatteryParser.parse(data)
    #expect(readings.count == 2)
    #expect(!readings[0].network && readings[0].device.isCharging)
    #expect(readings[0].device.id == readings[1].device.id)
    #expect(readings[0].device.connection == .usb)
}

@Test func nativeRemoteWatchKeepsCompanionIdentity() throws {
    let data = Data(#"[{"id":"watch","name":"Apple Watch","class":"Watch","level":88,"charging":false,"paired":true,"sessionCode":0,"interface":3}]"#.utf8)
    let readings = try MobileBatteryParser.parse(data)
    #expect(readings.count == 1)
    #expect(readings[0].device.id == "watch:watch")
    #expect(readings[0].network && !readings[0].isPhone && !readings[0].isPad)
}

@Test func nativeTimeoutPreservesCompletedBatterySamples() throws {
    let text = """
    {"id":"phone","class":"iPhone","level":73,"charging":false,"paired":true,"sessionCode":0,"interface":2}
    {"id":"slow-watch","level":
    """
    let readings = try MobileBatteryParser.parse(Data(text.utf8))
    #expect(readings.count == 1)
    #expect(readings[0].isPhone && readings[0].device.level == 73)
}
