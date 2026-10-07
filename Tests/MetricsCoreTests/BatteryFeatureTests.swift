import Foundation
import Testing
@testable import MetricsCore

private let instant = Date(timeIntervalSince1970: 5000)
private func sample(_ id: String = "mouse", _ level: Int = 15, charging: Bool = false, at date: Date = instant) -> BatteryDevice {
    .init(id: id, name: id, level: level, isCharging: charging, source: .bluetooth, measuredAt: date, lastSeenAt: date)
}
@Test func preferencesRoundTripAndAliasesDoNotChangeIdentity() throws {
    var preferences = BatteryPreferences()
    var options = DeviceOptions(); options.alias = "  Masa faresi  "; options.favorite = true
    preferences.devices["mouse"] = options
    let restored = try JSONDecoder().decode(BatteryPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored == preferences)
    #expect(restored.name(for: sample()) == "Masa faresi")
    #expect(sample().id == "mouse")
    let legacy = Data(#"{"id":"old","name":"Mouse","level":50,"isCharging":false,"isConnected":true,"source":"bluetooth"}"#.utf8)
    #expect(try JSONDecoder().decode(BatteryDevice.self, from: legacy).connection == nil)
}
@Test func presentationHonorsHiddenLowFavoritesAndManualOrder() {
    var preferences = BatteryPreferences()
    var hidden = DeviceOptions(); hidden.hidden = true
    var favorite = DeviceOptions(); favorite.favorite = true
    preferences.devices["hidden"] = hidden; preferences.devices["favorite"] = favorite
    preferences.deviceOrder = ["b", "a"]
    let devices = [sample("a", 70), sample("hidden", 5), sample("favorite", 80), sample("low", 9), sample("b", 80)]
    #expect(BatteryPresentation.ordered(devices, preferences: preferences, now: instant).map(\.id) == ["low", "favorite", "b", "a"])
    preferences.lowBatteryFirst = false
    #expect(BatteryPresentation.ordered(devices, preferences: preferences, now: instant).first?.id == "favorite")
}
@Test func airPodsGroupingUsesIdentityInsteadOfSimilarNames() {
    let devices = [BatteryDevice(id: "bt:one", name: "AirPods", level: 80, source: .bluetooth),
                   BatteryDevice(id: "bt:one:case", name: "AirPods Case", level: 30, source: .bluetooth),
                   BatteryDevice(id: "bt:two", name: "AirPods", level: 70, source: .bluetooth)]
    let groups = BatteryPresentation.groups(devices, preferences: BatteryPreferences(), now: instant)
    #expect(groups.count == 2)
    #expect(groups.first { $0.id == "bt:one" }?.devices.count == 2)
    var ungrouped = BatteryPreferences(); ungrouped.groupAirPods = false
    #expect(BatteryPresentation.groups(devices, preferences: ungrouped).count == 3)
}
@Test func historyDoesNotRepeatSamplesOrInventOfflineValuesAndLeavesGaps() {
    var history = BatteryHistory()
    let initial = history.record([sample()], now: instant)
    #expect(initial)
    let repeated = history.record([sample()], now: instant.addingTimeInterval(30))
    #expect(!repeated)
    var offline = sample(); offline.isConnected = false
    let disconnected = history.record([offline], now: instant.addingTimeInterval(60))
    #expect(disconnected)
    #expect(history.samples["mouse"]?.last?.level == nil)
    let stillOffline = history.record([offline], now: instant.addingTimeInterval(90))
    #expect(!stillOffline)
    history.record([sample("mouse", 14, at: instant.addingTimeInterval(100))], now: instant.addingTimeInterval(100))
    let pieces = history.segments(for: "mouse", since: instant, until: instant.addingTimeInterval(100))
    #expect(pieces.count == 2)
    #expect(pieces.flatMap { $0 }.map(\.level) == [15, 14])
    let expired = history.record([], now: instant.addingTimeInterval(8 * 86400))
    #expect(expired)
    #expect(history.samples.isEmpty)
}
@Test func historyNeverBridgesMissingPollingIntervals() {
    var history = BatteryHistory()
    history.record([sample()], now: instant)
    history.record([sample("mouse", 12, at: instant.addingTimeInterval(300))], now: instant.addingTimeInterval(300))
    #expect(history.segments(for: "mouse", since: instant, until: instant.addingTimeInterval(300)).count == 2)
}
@Test func batteryAlertsDeduplicateAcrossPollingAndRelaunchAndResetAfterRecovery() throws {
    var policy = BatteryAlertState(); let preferences = BatteryPreferences()
    #expect(policy.evaluate([sample()], preferences: preferences, now: instant).map(\.kind) == [.low(20)])
    policy = try JSONDecoder().decode(BatteryAlertState.self, from: JSONEncoder().encode(policy))
    let later = instant.addingTimeInterval(60)
    #expect(policy.evaluate([sample(at: later)], preferences: preferences, now: later).isEmpty)
    let critical = instant.addingTimeInterval(120)
    #expect(policy.evaluate([sample("mouse", 9, at: critical)], preferences: preferences, now: critical).map(\.kind) == [.low(10)])
    let recovered = instant.addingTimeInterval(180)
    _ = policy.evaluate([sample("mouse", 30, at: recovered)], preferences: preferences, now: recovered)
    let down = instant.addingTimeInterval(240)
    #expect(policy.evaluate([sample(at: down)], preferences: preferences, now: down).map(\.kind) == [.low(20)])
}
@Test func alertsIgnoreOfflineStaleHiddenAndDisabledDevices() {
    var policy = BatteryAlertState(); var preferences = BatteryPreferences()
    var offline = sample(); offline.isConnected = false
    #expect(policy.evaluate([offline], preferences: preferences, now: instant).isEmpty)
    #expect(policy.evaluate([sample()], preferences: preferences, now: instant.addingTimeInterval(700)).isEmpty)
    var hidden = DeviceOptions(); hidden.hidden = true; preferences.devices["mouse"] = hidden
    #expect(policy.evaluate([sample()], preferences: preferences, now: instant).isEmpty)
    hidden.hidden = false; hidden.notifications = false; preferences.devices["mouse"] = hidden
    #expect(policy.evaluate([sample()], preferences: preferences, now: instant).isEmpty)
}
@Test func fullyChargedAlertRequiresARealChargingCycleAndOnlyFiresOnce() {
    var policy = BatteryAlertState(); let preferences = BatteryPreferences()
    #expect(policy.evaluate([sample("mouse", 100)], preferences: preferences, now: instant).isEmpty)
    let charging = instant.addingTimeInterval(60)
    #expect(policy.evaluate([sample("mouse", 99, charging: true, at: charging)], preferences: preferences, now: charging).isEmpty)
    let full = instant.addingTimeInterval(120)
    #expect(policy.evaluate([sample("mouse", 100, at: full)], preferences: preferences, now: full).map(\.kind) == [.full])
    let later = instant.addingTimeInterval(180)
    #expect(policy.evaluate([sample("mouse", 100, at: later)], preferences: preferences, now: later).isEmpty)
}
