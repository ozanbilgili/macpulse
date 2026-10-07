import Foundation

public struct GPUReading: Codable, Sendable, Identifiable {
    public let id: UInt64
    public let devicePercent, rendererPercent, tilerPercent: Double?
    public let memoryInUse, memoryAllocated: UInt64?
}

public enum SensorKind: String, Codable, Sendable { case cpu, gpu, fan, systemPower }
public struct SensorReading: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: SensorKind
    public let value: Double
}
public struct HardwareSnapshot: Codable, Sendable {
    public let date: Date
    public let gpus: [GPUReading]
    public var sensors: [SensorReading]
    public let cpuTemperatureAverage, gpuTemperatureAverage: Double?
    public let systemWatts, gpuModelWatts, batteryNetWatts: Double?
    public let batteryUpdatedAt: Date?
    public let sensorFailures, invalidSensors: Int
    public let sensorsTruncated: Bool
    public let gpuStatus, sensorStatus, energyStatus, batteryFlowStatus: String
    public let collectionMilliseconds: Double
    public var singleGPUPercent: Double? { gpus.count == 1 ? gpus[0].devicePercent : nil }
    public var fans: [SensorReading] { sensors.filter { $0.kind == .fan } }
    public var chartSample: Self { var copy = self; copy.sensors = []; return copy }
}

public enum HardwareMath {
    public static func percentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
    public static func decodeSensor(type: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch (type, bytes.count) {
        case ("flt ", 4):
            let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * $1.offset)) }
            value = Double(Float(bitPattern: bits))
        case ("sp78", 2): value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case ("fpe2", 2): value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        default: return nil
        }
        return value.isFinite ? value : nil
    }
    public static func validSensor(_ value: Double, kind: SensorKind) -> Bool {
        guard value.isFinite else { return false }
        switch kind {
        case .cpu, .gpu: return (10...130).contains(value)
        case .fan: return (0...20000).contains(value)
        case .systemPower: return value > 0 && value <= 500
        }
    }
    public static func trustedTemperatureKey(_ key: String, kind: SensorKind, osMajor: Int) -> Bool {
        // On the accepted macOS 27 device, Tp keys alternate between placeholders
        // and invalid values. A plausible number alone does not confirm this source.
        !(kind == .cpu && key.hasPrefix("Tp") && osMajor >= 27)
    }
    public static func energyWatts(previous: Int64, current: Int64, unit: String, seconds: Double) -> Double? {
        guard previous >= 0, current >= previous, seconds.isFinite, seconds > 0, seconds <= 20 else { return nil }
        let scale: Double
        switch unit { case "J": scale = 1; case "mJ": scale = 1e3; case "uJ": scale = 1e6; case "nJ": scale = 1e9; default: return nil }
        let watts = Double(current - previous) / scale / seconds
        return watts.isFinite && (0...500).contains(watts) ? watts : nil
    }
    public static func batteryWatts(millivolts: Int64, milliamps: Int64, installed: Bool, onAC: Bool, charging: Bool, updated: Date?, now: Date) -> Double? {
        guard installed, (6000...20000).contains(millivolts), (-20000...20000).contains(milliamps), let updated else { return nil }
        let age = now.timeIntervalSince(updated)
        guard age >= -2 && age <= 60 else { return nil }
        if !onAC && milliamps == 0 { return nil }
        if charging && (!onAC || milliamps < 0) { return nil }
        if !charging && milliamps > 0 { return nil }
        return Double(millivolts) * Double(milliamps) / 1e6
    }
}

/// Temperatures need two valid polls; a driver startup placeholder is not displayed.
struct SensorValidator {
    private var previousValid: Set<String> = []
    mutating func reset() { previousValid = [] }
    mutating func validate(_ candidates: [SensorReading]) -> [SensorReading] {
        var valid: Set<String> = []
        let result = candidates.filter { sensor in
            guard HardwareMath.validSensor(sensor.value, kind: sensor.kind) else { return false }
            valid.insert(sensor.id)
            return sensor.kind == .fan || sensor.kind == .systemPower || previousValid.contains(sensor.id)
        }
        previousValid = valid
        return result
    }
}

struct GPUModelTracker {
    private struct Baseline { let driver, channel: UInt64; let counter: Int64; let unit: String; let time: Double }
    private var previous: Baseline?
    private var lastAdvance: Double?
    private(set) var status = "GPU enerji başlangıç örneği"
    mutating func reset() { previous = nil; lastAdvance = nil; status = "GPU enerji başlangıç örneği" }
    mutating func observe(driver: UInt64, channel: UInt64, counter: Int64, unit: String, uptime: Double, busy: Bool?) -> Double? {
        guard counter >= 0 && uptime.isFinite else { reset(); status = "GPU enerji sayacı geçersiz"; return nil }
        let current = Baseline(driver: driver, channel: channel, counter: counter, unit: unit, time: uptime)
        defer { previous = current }
        guard let previous, previous.driver == driver, previous.channel == channel, previous.unit == unit else {
            lastAdvance = nil; status = "GPU enerji başlangıç örneği"; return nil
        }
        guard let watts = HardwareMath.energyWatts(previous: previous.counter, current: counter, unit: unit, seconds: uptime - previous.time) else {
            lastAdvance = nil; status = "GPU enerji aralığı geçersiz; yeni sayaç alınıyor"; return nil
        }
        if watts > 0 { lastAdvance = uptime }
        else if busy != false { lastAdvance = nil }
        guard let lastAdvance, uptime - lastAdvance <= 30 else {
            status = "GPU enerji sayacı canlılığı doğrulanamıyor"; return nil
        }
        status = "GPU: IOReport enerji modeli"
        return watts
    }
}
