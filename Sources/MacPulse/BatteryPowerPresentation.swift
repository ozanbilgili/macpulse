import Foundation
import MetricsCore

extension BatteryPowerReading {
    var powerText: String {
        let watts = abs(netWatts).formatted(.number.precision(.fractionLength(abs(netWatts) < 0.1 ? 2 : 1))) + " W"
        if netWatts > 0 { return String(localized: "Net charge ≈\(watts)") }
        if netWatts < 0 { return String(localized: "Battery drain ≈\(watts)") }
        return String(localized: "Net battery flow ≈\(watts)")
    }
    var powerHelp: String {
        let volts = (Double(voltageMilliVolts) / 1000).formatted(.number.precision(.fractionLength(3)))
        let measured = measuredAt.formatted(date: .abbreviated, time: .standard)
        return String(localized: "Net power on the battery side: voltage × current. Not the USB input power or the adapter's wattage.\n\(volts) V · \(currentMilliAmps) mA\nMeasured: \(measured)")
    }
}
