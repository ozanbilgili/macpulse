import Foundation
import Testing
@testable import MetricsCore

private let powerNow = Date(timeIntervalSince1970: 10_000)
private func powerData(_ changes: [String: Any] = [:]) throws -> Data {
    var registry: [String: Any] = ["Voltage": 4200, "InstantAmperage": 2000, "Amperage": 1700,
                                  "IsCharging": true, "ExternalConnected": true, "CurrentCapacity": 47,
                                  "AdapterDetails": ["Watts": 20]]
    registry.merge(changes) { _, new in new }
    return try PropertyListSerialization.data(fromPropertyList: ["IORegistry": registry], format: .xml, options: 0)
}

@Test func powerUsesSignedBatteryVoltageAndCurrentInsteadOfAdapterRating() throws {
    let reading = try #require(try BatteryPowerParser.parse(try powerData(), expectedLevel: 47, expectedCharging: true, now: powerNow))
    #expect(reading.netWatts == 8.4)
    #expect(reading.measuredAt == powerNow)
    let discharging = try #require(try BatteryPowerParser.parse(try powerData(["InstantAmperage": -50, "IsCharging": false, "ExternalConnected": false]), expectedLevel: 47, expectedCharging: false, now: powerNow))
    #expect(discharging.netWatts == -0.21)
    // AdapterDetails remains populated while unplugged; it must not become 20 W.
    #expect(!discharging.externalConnected)
    let encodedNegative = NSNumber(value: UInt64(bitPattern: Int64(-50)))
    let unsigned = try #require(try BatteryPowerParser.parse(try powerData(["InstantAmperage": encodedNegative, "IsCharging": false, "ExternalConnected": false]), expectedLevel: 47, expectedCharging: false))
    #expect(unsigned.currentMilliAmps == -50)
}

@Test func powerRejectsConflictingUnavailableAndInvalidMeasurements() throws {
    for fields: [String: Any] in [
        ["Voltage": true], ["Voltage": 4.2], ["Voltage": 20000], ["InstantAmperage": 50000],
        ["CurrentCapacity": 20], ["CurrentCapacity": true], ["ExternalConnected": false], ["IsCharging": false],
        ["InstantAmperage": "2000"], ["IsCharging": 1]
    ] {
        #expect(try BatteryPowerParser.parse(try powerData(fields), expectedLevel: 47, expectedCharging: true) == nil)
    }
    let adapterOnly = try PropertyListSerialization.data(fromPropertyList: ["IORegistry": ["AdapterDetails": ["Watts": 20]]], format: .xml, options: 0)
    #expect(try BatteryPowerParser.parse(adapterOnly, expectedLevel: 47, expectedCharging: true) == nil)
    #expect(try BatteryPowerParser.parse(try powerData(["InstantAmperage": 1000, "IsCharging": false, "ExternalConnected": false]), expectedLevel: 47, expectedCharging: false) == nil)
}

@Test func powerFallsBackToAmperageOnlyWhenInstantFieldIsAbsent() throws {
    let registry: [String: Any] = ["Voltage": 8000, "Amperage": 1000, "IsCharging": true, "ExternalConnected": true]
    let data = try PropertyListSerialization.data(fromPropertyList: ["IORegistry": registry], format: .binary, options: 0)
    let reading = try #require(try BatteryPowerParser.parse(data, expectedLevel: 47, expectedCharging: true))
    #expect(reading.netWatts == 8)
}

@Test func powerExpiresIndependentlyAndIsHiddenWhenOfflineOrChargingChanges() throws {
    let reading = try #require(try BatteryPowerParser.parse(try powerData(), expectedLevel: 47, expectedCharging: true, now: powerNow))
    var device = BatteryDevice(id: "ios:phone", name: "Phone", level: 47, isCharging: true, source: .mobile,
                               measuredAt: powerNow, lastSeenAt: powerNow, batteryPower: reading)
    #expect(device.displayPower(at: powerNow.addingTimeInterval(119)) == reading)
    #expect(device.displayPower(at: powerNow.addingTimeInterval(120)) == nil)
    #expect(device.displayPower(at: powerNow.addingTimeInterval(-1)) == nil)
    device.isCharging = false
    #expect(device.displayPower(at: powerNow) == nil)
    device.isCharging = true; device.isConnected = false
    #expect(device.displayPower(at: powerNow) == nil)
    var watch = device; watch.isConnected = true
    watch = .init(id: "watch:watch", name: "Watch", level: 47, isCharging: true, source: .mobile, lastSeenAt: powerNow, batteryPower: reading)
    #expect(watch.displayPower(at: powerNow) == nil)
}

@Test func powerCacheIsCompatibleAndFailedFreshQueryDoesNotRenewOldPower() throws {
    let legacy = Data(#"{"id":"ios:phone","name":"Phone","level":47,"isCharging":true,"isConnected":true,"source":"mobile"}"#.utf8)
    #expect(try JSONDecoder().decode(BatteryDevice.self, from: legacy).batteryPower == nil)
    let reading = try #require(try BatteryPowerParser.parse(try powerData(), expectedLevel: 47, expectedCharging: true, now: powerNow))
    let old = BatteryDevice(id: "ios:phone", name: "Phone", level: 47, isCharging: true, source: .mobile,
                            measuredAt: powerNow, lastSeenAt: powerNow, batteryPower: reading)
    #expect(try JSONDecoder().decode(BatteryDevice.self, from: JSONEncoder().encode(old)).batteryPower == reading)
    let new = BatteryDevice(id: old.id, name: old.name, level: 48, isCharging: true, source: .mobile,
                            measuredAt: powerNow.addingTimeInterval(60), lastSeenAt: powerNow.addingTimeInterval(60))
    let merged = BatteryLedger.merge([old], snapshot: .init(devices: [new], successfulSources: [.mobile]))
    #expect(merged[0].level == 48)
    #expect(merged[0].batteryPower == nil)
    let disconnected = BatteryLedger.merge([old], snapshot: .init(devices: [], successfulSources: [.mobile]))
    #expect(disconnected[0].displayPower(at: powerNow) == nil)
}
