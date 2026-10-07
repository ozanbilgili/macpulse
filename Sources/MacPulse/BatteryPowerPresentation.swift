import Foundation
import MetricsCore

extension BatteryPowerReading {
    var powerText: String {
        let watts = abs(netWatts).formatted(.number.precision(.fractionLength(abs(netWatts) < 0.1 ? 2 : 1))) + " W"
        if netWatts > 0 { return "Net şarj ≈" + watts }
        if netWatts < 0 { return "Batarya tüketimi ≈" + watts }
        return "Net batarya akışı ≈" + watts
    }
    var powerHelp: String {
        "Batarya tarafındaki net güç: voltaj × akım. USB giriş gücü veya adaptörün watt değeri değildir.\n"
        + (Double(voltageMilliVolts) / 1000).formatted(.number.precision(.fractionLength(3))) + " V · "
        + "\(currentMilliAmps) mA\nÖlçüm: " + measuredAt.formatted(date: .abbreviated, time: .standard)
    }
}
