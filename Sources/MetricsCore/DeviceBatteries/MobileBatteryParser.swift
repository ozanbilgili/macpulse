import Foundation
import CoreFoundation

public struct MobileReading: Sendable {
    public let device: BatteryDevice
    public let parentID: String
    public let network: Bool
    public let isPad: Bool
    public let isPhone: Bool
}

public enum MobileBatteryParser {
    public static func parse(_ data: Data, now: Date = Date()) throws -> [MobileReading] {
        let rows: [[String: Any]]
        if data.first == UInt8(ascii: "[") {
            rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        } else {
            rows = data.split(separator: UInt8(ascii: "\n")).compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any]
            }
        }
        return rows.compactMap { row -> MobileReading? in
            guard let id = row["id"] as? String, !id.isEmpty,
                  row["paired"] as? Bool == true, row["sessionCode"] as? Int == 0,
                  let level = row["level"] as? NSNumber, CFGetTypeID(level) != CFBooleanGetTypeID(),
                  (0...100).contains(level.intValue), level.doubleValue == Double(level.intValue),
                  let interface = row["interface"] as? Int, (1...3).contains(interface) else { return nil }
            let name = row["name"] as? String ?? "iPhone / iPad"
            let deviceClass = row["class"] as? String ?? ""
            let isWatch = deviceClass.lowercased().contains("watch") || name.lowercased().contains("apple watch")
            let charging = (row["charging"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
            return .init(device: .init(id: (isWatch ? "watch:" : "ios:") + id, name: name, level: level.intValue,
                                      isCharging: charging, source: .mobile, measuredAt: now, lastSeenAt: now,
                                      connection: interface == 1 ? .usb : interface == 2 ? .wifi : .appleLink),
                         parentID: id, network: interface != 1,
                         isPad: deviceClass == "iPad" || name.lowercased().contains("ipad"),
                         isPhone: deviceClass == "iPhone" || name.lowercased().contains("iphone"))
        }.sorted { !$0.network && $1.network }
    }
}
