import Testing
import Foundation
@testable import MetricsCore

@Test func hardwareFloatUsesLittleEndianAndRejectsNonFinite() {
    #expect(HardwareMath.decodeSensor(type: "flt ", bytes: [0, 0, 72, 66]) == 50)
    #expect(HardwareMath.decodeSensor(type: "flt ", bytes: [0, 0, 128, 127]) == nil)
    #expect(HardwareMath.decodeSensor(type: "flt ", bytes: [0, 0, 192, 127]) == nil)
}
@Test func hardwareFixedPointFormatsAreDistinct() {
    #expect(HardwareMath.decodeSensor(type: "sp78", bytes: [50, 128]) == 50.5)
    #expect(HardwareMath.decodeSensor(type: "sp78", bytes: [255, 128]) == -0.5)
    #expect(HardwareMath.decodeSensor(type: "fpe2", bytes: [0x17, 0x70]) == 1500)
}
@Test func hardwareUnknownSensorTypesAndSizesAreUnknown() {
    #expect(HardwareMath.decodeSensor(type: "flt ", bytes: [0, 0]) == nil)
    #expect(HardwareMath.decodeSensor(type: "ui32", bytes: [0, 0, 0, 0]) == nil)
}
@Test func sensorBoundsDoNotTurnSentinelsIntoTemperatures() {
    for value in [-4.0, 0, 3.4, 9.9, 131, .infinity, .nan] { #expect(!HardwareMath.validSensor(value, kind: .cpu)) }
    #expect(HardwareMath.validSensor(0, kind: .fan))
    #expect(!HardwareMath.validSensor(0, kind: .systemPower))
}
@Test func temperaturesRequireTwoValidPollsAndRecoverAfterMissing() {
    var validator = SensorValidator()
    let valid = SensorReading(id: "Te05", kind: .cpu, value: 50)
    #expect(validator.validate([valid]).isEmpty)
    #expect(validator.validate([valid]).count == 1)
    #expect(validator.validate([]).isEmpty)
    #expect(validator.validate([valid]).isEmpty)
}
@Test func startupPlaceholderThenInvalidTemperatureNeverDisplays() {
    var validator = SensorValidator()
    #expect(validator.validate([SensorReading(id: "Tp01", kind: .cpu, value: 40)]).isEmpty)
    #expect(validator.validate([SensorReading(id: "Tp01", kind: .cpu, value: 3.4)]).isEmpty)
    #expect(validator.validate([SensorReading(id: "Tp01", kind: .cpu, value: 40)]).isEmpty)
}
@Test func sensorWakeResetsConfirmationButKeepsValidIdleFan() {
    var validator = SensorValidator()
    let sensor = SensorReading(id: "Tg05", kind: .gpu, value: 50)
    _ = validator.validate([sensor]); _ = validator.validate([sensor]); validator.reset()
    #expect(validator.validate([sensor]).isEmpty)
    #expect(validator.validate([SensorReading(id: "F0Ac", kind: .fan, value: 0)]).count == 1)
}
@Test func energyUnitsUseActualWindow() {
    #expect(HardwareMath.energyWatts(previous: 10, current: 2010, unit: "mJ", seconds: 2) == 1)
    #expect(HardwareMath.energyWatts(previous: 0, current: 1_000_000, unit: "uJ", seconds: 0.25) == 4)
    #expect(HardwareMath.energyWatts(previous: 0, current: 2_000_000_000, unit: "nJ", seconds: 2) == 1)
}
@Test func invalidEnergyWindowResetAndUnitStayUnknown() {
    for seconds in [0.0, -1, 21, .nan, .infinity] { #expect(HardwareMath.energyWatts(previous: 0, current: 1, unit: "mJ", seconds: seconds) == nil) }
    #expect(HardwareMath.energyWatts(previous: 10, current: 1, unit: "mJ", seconds: 2) == nil)
    #expect(HardwareMath.energyWatts(previous: -1, current: 1, unit: "mJ", seconds: 2) == nil)
    #expect(HardwareMath.energyWatts(previous: 0, current: 1, unit: "ticks", seconds: 2) == nil)
}
@Test func frozenCounterNeverBecomesZeroWatts() {
    var tracker = GPUModelTracker()
    #expect(tracker.observe(driver: 1, channel: 2, counter: 100, unit: "mJ", uptime: 1, busy: false) == nil)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 100, unit: "mJ", uptime: 3, busy: false) == nil)
}
@Test func confirmedIdleZeroIsDifferentFromFrozenBusyCounter() {
    var tracker = GPUModelTracker()
    _ = tracker.observe(driver: 1, channel: 2, counter: 100, unit: "mJ", uptime: 1, busy: true)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 2100, unit: "mJ", uptime: 3, busy: true) == 1)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 2100, unit: "mJ", uptime: 5, busy: false) == 0)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 2100, unit: "mJ", uptime: 7, busy: true) == nil)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 2100, unit: "mJ", uptime: 9, busy: false) == nil)
}
@Test func unknownGPUActivityCannotConfirmZero() {
    var tracker = GPUModelTracker()
    _ = tracker.observe(driver: 1, channel: 2, counter: 0, unit: "mJ", uptime: 1, busy: true)
    _ = tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 3, busy: true)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 5, busy: nil) == nil)
}
@Test func energyIdentityAndUnitChangesRequireNewBaseline() {
    var tracker = GPUModelTracker()
    _ = tracker.observe(driver: 1, channel: 2, counter: 1, unit: "mJ", uptime: 1, busy: true)
    #expect(tracker.observe(driver: 2, channel: 2, counter: 2001, unit: "mJ", uptime: 3, busy: true) == nil)
    #expect(tracker.observe(driver: 2, channel: 3, counter: 4001, unit: "mJ", uptime: 5, busy: true) == nil)
    #expect(tracker.observe(driver: 2, channel: 3, counter: 6001, unit: "nJ", uptime: 7, busy: true) == nil)
}
@Test func energySleepAndCounterResetDiscardConfidence() {
    var tracker = GPUModelTracker()
    _ = tracker.observe(driver: 1, channel: 2, counter: 0, unit: "mJ", uptime: 1, busy: true)
    _ = tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 3, busy: true)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 2000, unit: "mJ", uptime: 30, busy: true) == nil)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 0, unit: "mJ", uptime: 32, busy: true) == nil)
    tracker.reset()
    #expect(tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 34, busy: true) == nil)
}
@Test func idleEnergyLivenessExpires() {
    var tracker = GPUModelTracker()
    _ = tracker.observe(driver: 1, channel: 2, counter: 0, unit: "mJ", uptime: 0, busy: true)
    _ = tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 1, busy: true)
    _ = tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 15, busy: false)
    _ = tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 30, busy: false)
    #expect(tracker.observe(driver: 1, channel: 2, counter: 1000, unit: "mJ", uptime: 32, busy: false) == nil)
}
@Test func batteryNetFlowKeepsSignAndAllowsZeroOnAC() {
    let now = Date()
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: -1000, installed: true, onAC: false, charging: false, updated: now, now: now) == -12)
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: 1000, installed: true, onAC: true, charging: true, updated: now, now: now) == 12)
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: 0, installed: true, onAC: true, charging: false, updated: now, now: now) == 0)
}
@Test func batteryMissingOldFutureOrContradictoryFlowIsUnknown() {
    let now = Date()
    for updated in [nil, now.addingTimeInterval(-61), now.addingTimeInterval(3)] {
        #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: 0, installed: true, onAC: true, charging: false, updated: updated, now: now) == nil)
    }
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: 1000, installed: true, onAC: false, charging: true, updated: now, now: now) == nil)
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: -1000, installed: true, onAC: true, charging: true, updated: now, now: now) == nil)
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: 1000, installed: true, onAC: true, charging: false, updated: now, now: now) == nil)
}
@Test func batteryAbsentAndImplausibleVoltageAreUnknown() {
    let now = Date()
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: 0, installed: false, onAC: true, charging: false, updated: now, now: now) == nil)
    #expect(HardwareMath.batteryWatts(millivolts: 0, milliamps: 0, installed: true, onAC: true, charging: false, updated: now, now: now) == nil)
}
@Test func hardwarePercentRejectsInvalidInsteadOfClamping() {
    for number in [-1.0, 101, .nan, .infinity] { #expect(HardwareMath.percentage(number) == nil) }
    #expect(HardwareMath.percentage(0) == 0)
}
@Test func batteryZeroWhileRunningOffBatteryIsNotConfirmedFlow() {
    let now = Date()
    #expect(HardwareMath.batteryWatts(millivolts: 12000, milliamps: 0, installed: true, onAC: false, charging: false, updated: now, now: now) == nil)
}
@Test func hardwareChartSampleDropsDetailedSensorInventory() {
    let frame = HardwareSnapshot(date: Date(), gpus: [], sensors: [SensorReading(id: "Te05", kind: .cpu, value: 50)],
        cpuTemperatureAverage: 50, gpuTemperatureAverage: nil, systemWatts: 25, gpuModelWatts: 1, batteryNetWatts: 0,
        batteryUpdatedAt: Date(), sensorFailures: 0, invalidSensors: 0, sensorsTruncated: false, gpuStatus: "test", sensorStatus: "test", energyStatus: "test", batteryFlowStatus: "test", collectionMilliseconds: 1)
    #expect(frame.chartSample.sensors.isEmpty)
    #expect(frame.chartSample.cpuTemperatureAverage == 50)
    #expect(frame.chartSample.gpuModelWatts == 1)
}
@Test func legacyMetricSnapshotWithoutHardwareStillDecodes() throws {
    let data = Data(#"{"date":0,"system":{"chip":"test","cores":1,"physicalMemory":1,"operatingSystem":"test","uptime":1,"thermalState":"Normal"},"issues":[],"collectionMilliseconds":1}"#.utf8)
    let old = try JSONDecoder().decode(MetricSnapshot.self, from: data)
    #expect(old.hardware == nil)
}
@Test func plausibleTpPlaceholderIsExcludedOnMacOS27() {
    #expect(!HardwareMath.trustedTemperatureKey("Tp01", kind: .cpu, osMajor: 27))
    #expect(HardwareMath.trustedTemperatureKey("Te05", kind: .cpu, osMajor: 27))
    #expect(HardwareMath.trustedTemperatureKey("Tg05", kind: .gpu, osMajor: 27))
    #expect(HardwareMath.trustedTemperatureKey("Tp01", kind: .cpu, osMajor: 26))
}
