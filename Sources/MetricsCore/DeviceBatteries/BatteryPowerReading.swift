import Foundation
import CoreFoundation

/// Signed net energy flow at the battery, not USB input power or adapter rating.
public struct BatteryPowerReading: Codable, Equatable, Sendable {
    public let voltageMilliVolts: Int
    public let currentMilliAmps: Int
    public let isCharging: Bool
    public let externalConnected: Bool
    public let measuredAt: Date

    public init(voltageMilliVolts: Int, currentMilliAmps: Int, isCharging: Bool,
                externalConnected: Bool, measuredAt: Date) {
        self.voltageMilliVolts = voltageMilliVolts
        self.currentMilliAmps = currentMilliAmps
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.measuredAt = measuredAt
    }

    public var netWatts: Double { Double(voltageMilliVolts) * Double(currentMilliAmps) / 1_000_000 }
    public var isValid: Bool {
        (2000...12000).contains(voltageMilliVolts) && (-20000...20000).contains(currentMilliAmps)
            && abs(netWatts) <= 100
            && (!isCharging || externalConnected)
            && (currentMilliAmps <= 0 || (isCharging && externalConnected))
    }
}

public enum BatteryPowerParser {
    public static func parse(_ data: Data, expectedLevel: Int?, expectedCharging: Bool,
                             now: Date = Date()) throws -> BatteryPowerReading? {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let registry = root["IORegistry"] as? [String: Any],
              root["Status"].map({ ($0 as? String) == "Success" }) ?? true,
              let voltage = integer(registry["Voltage"]),
              let current = integer(registry["InstantAmperage"] ?? registry["Amperage"]),
              let charging = boolean(registry["IsCharging"]),
              let external = boolean(registry["ExternalConnected"]),
              charging == expectedCharging else { return nil }
        // Compare against the authenticated percentage query to reject conflicting
        // diagnostics. No percentage, serial, or adapter metadata is substituted.
        if let expectedLevel, let rawLevel = registry["CurrentCapacity"] {
            guard let level = integer(rawLevel), (0...100).contains(level), level == expectedLevel else { return nil }
        }
        let reading = BatteryPowerReading(voltageMilliVolts: voltage, currentMilliAmps: current,
                                          isCharging: charging, externalConnected: external, measuredAt: now)
        return reading.isValid ? reading : nil
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue else { return nil }
        // IORegistry can encode signed currents as unsigned two's-complement
        // integers. int64Value restores the sign without converting through Double.
        return Int(exactly: number.int64Value)
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
