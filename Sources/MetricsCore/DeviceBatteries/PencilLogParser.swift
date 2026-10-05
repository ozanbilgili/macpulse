import Foundation

public enum PencilLogParser {
    public static func parse(_ text: String, parentID: String, now: Date = Date()) -> BatteryDevice? {
        guard text.contains("Pencil") else { return nil }
        func capture(_ pattern: String) -> String? {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        let capacity = capture(#""Current Capacity"\s*=\s*(\d+)"#)
            ?? capture(#"percentCharge\s*=\s*(\d+)"#)
        let charging = capture(#""Is Charging"\s*=\s*(\d+)"#)
            ?? capture(#"charging\s*=\s*(YES|NO|true|false|0|1)"#)
        if let vendor = capture(#""Vendor ID"\s*=\s*(\d+)"#), vendor != "76" { return nil }
        guard let capacity, let level = Int(capacity), (0...100).contains(level), let charging else { return nil }
        return .init(id: "pencil:" + parentID, name: "Apple Pencil", level: level,
                     isCharging: ["1", "YES", "true"].contains(charging), source: .pencil,
                     measuredAt: now, lastSeenAt: now)
    }
}
