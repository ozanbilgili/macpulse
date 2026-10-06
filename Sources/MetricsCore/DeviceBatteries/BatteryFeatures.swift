import Foundation

public enum PanelTheme: String, Codable, CaseIterable, Sendable { case automatic, light, dark }
public enum PanelDensity: String, Codable, CaseIterable, Sendable { case compact, comfortable }
public enum BatteryConnection: String, Codable, Sendable {
    case internalBattery, bluetooth, usb, wifi, usbReceiver, appleLink, viaIPhone, viaIPad, viaIPadUSB, viaIPadWiFi
    public var label: String {
        switch self {
        case .internalBattery: "Mac"
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .wifi: "Wi‑Fi"
        case .usbReceiver: "USB alıcısı"
        case .appleLink: "Apple bağlantısı"
        case .viaIPhone: "iPhone üzerinden"
        case .viaIPad: "iPad üzerinden"
        case .viaIPadUSB: "iPad · USB"
        case .viaIPadWiFi: "iPad · Wi‑Fi"
        }
    }
}
public struct DeviceOptions: Codable, Equatable, Sendable {
    public var alias = ""
    public var favorite = false
    public var hidden = false
    public var notifications = true
    public var lowThreshold: Int? = nil
    public init() {}
}
public struct BatteryPreferences: Codable, Equatable, Sendable {
    public var theme: PanelTheme = .automatic
    public var density: PanelDensity = .compact
    public var glassDensity: Double = 0.12
    public var showMenuPercentage = true
    public var menuDeviceID: String? = nil
    public var groupAirPods = true
    public var lowBatteryFirst = true
    public var notificationsEnabled = true
    public var notifyFullyCharged = true
    public var notificationSound = false
    public var lowThreshold = 20
    public var criticalThreshold = 10
    public var deviceOrder: [String] = []
    public var devices: [String: DeviceOptions] = [:]
    public init() {}
    public func options(for id: String) -> DeviceOptions { devices[id] ?? DeviceOptions() }
    public func name(for device: BatteryDevice) -> String {
        let alias = options(for: device.id).alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return alias.isEmpty ? device.name : String(alias.prefix(80))
    }
    public func thresholds(for id: String) -> [Int] {
        Array(Set([options(for: id).lowThreshold ?? lowThreshold, criticalThreshold].filter { (1...50).contains($0) })).sorted(by: >)
    }
}
public struct BatteryDisplayGroup: Identifiable, Sendable {
    public let id: String
    public var devices: [BatteryDevice]
    public var primary: BatteryDevice { devices.first { !$0.id.hasSuffix(":case") } ?? devices[0] }
    public var isAirPods: Bool { devices.contains { $0.name.lowercased().contains("airpods") } }
    public func isLive(at now: Date = Date()) -> Bool { devices.contains { $0.isLive(at: now) } }
}
public enum BatteryPresentation {
    public static func ordered(_ devices: [BatteryDevice], preferences: BatteryPreferences, now: Date = Date(), includeHidden: Bool = false) -> [BatteryDevice] {
        let order = Dictionary(preferences.deviceOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        func low(_ device: BatteryDevice) -> Bool {
            device.isLive(at: now) && !device.isCharging && device.displayLevel(at: now).map { $0 <= (preferences.options(for: device.id).lowThreshold ?? preferences.lowThreshold) } == true
        }
        return devices.filter { includeHidden || !preferences.options(for: $0.id).hidden }.sorted {
            if preferences.lowBatteryFirst && low($0) != low($1) { return low($0) }
            let firstFavorite = preferences.options(for: $0.id).favorite
            let secondFavorite = preferences.options(for: $1.id).favorite
            if firstFavorite != secondFavorite { return firstFavorite }
            let a = order[$0.id] ?? Int.max, b = order[$1.id] ?? Int.max
            if a != b { return a < b }
            if ($0.source == .mac) != ($1.source == .mac) { return $0.source == .mac }
            return preferences.name(for: $0).localizedStandardCompare(preferences.name(for: $1)) == .orderedAscending
        }
    }
    public static func groups(_ devices: [BatteryDevice], preferences: BatteryPreferences, now: Date = Date()) -> [BatteryDisplayGroup] {
        var result: [BatteryDisplayGroup] = []
        for device in ordered(devices, preferences: preferences, now: now) {
            let groupable = preferences.groupAirPods && device.name.lowercased().contains("airpods")
            let id = groupable && device.id.hasSuffix(":case") ? String(device.id.dropLast(5)) : device.id
            if let index = result.firstIndex(where: { $0.id == id }) { result[index].devices.append(device) }
            else { result.append(.init(id: id, devices: [device])) }
        }
        return result
    }
}

public struct BatteryHistoryPoint: Codable, Equatable, Sendable {
    public var date: Date
    public var level: Int? // nil is a real loss of availability, never an invented level
    public var charging: Bool
    public init(date: Date, level: Int?, charging: Bool = false) { self.date = date; self.level = level; self.charging = charging }
}
public struct BatteryHistory: Codable, Sendable {
    public var samples: [String: [BatteryHistoryPoint]] = [:]
    public init() {}
    @discardableResult public mutating func record(_ devices: [BatteryDevice], now: Date = Date()) -> Bool {
        var changed = false
        let cutoff = now.addingTimeInterval(-7 * 86400)
        for device in devices {
            var points = samples[device.id] ?? []
            let last = points.last
            if device.isLive(at: now), let level = device.displayLevel(at: now), let measured = device.measuredAt, measured <= now.addingTimeInterval(5) {
                if last == nil || (measured > last!.date && (last!.level != level || last!.charging != device.isCharging || measured.timeIntervalSince(last!.date) >= 60)) {
                    points.append(.init(date: measured, level: level, charging: device.isCharging))
                }
            } else if let last, last.level != nil {
                points.append(.init(date: now, level: nil))
            }
            points.removeAll { $0.date < cutoff }
            if points.count > 11000 { points = Array(points.suffix(11000)) }
            if points != samples[device.id] && !points.isEmpty { samples[device.id] = points; changed = true }
        }
        for id in Array(samples.keys) {
            let filtered = samples[id]!.filter { $0.date >= cutoff }
            if filtered != samples[id]! { changed = true }
            if filtered.isEmpty { samples.removeValue(forKey: id) } else { samples[id] = filtered }
        }
        return changed
    }
    public func segments(for id: String, since: Date, until: Date = Date(), gap: TimeInterval = 180) -> [[BatteryHistoryPoint]] {
        var result: [[BatteryHistoryPoint]] = []
        var current: [BatteryHistoryPoint] = []
        for point in samples[id] ?? [] where point.date >= since && point.date <= until {
            if point.level == nil || current.last.map({ point.date.timeIntervalSince($0.date) > gap }) == true {
                if !current.isEmpty { result.append(current); current = [] }
            }
            if point.level != nil { current.append(point) }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

public enum BatteryAlertKind: Codable, Equatable, Sendable { case low(Int), full }
public struct BatteryAlert: Sendable, Equatable {
    public let deviceID: String
    public let kind: BatteryAlertKind
    public let level: Int
}
public struct BatteryAlertState: Codable, Sendable {
    public struct DeviceState: Codable, Sendable {
        public var lastMeasurement: Date
        public var sentThresholds: Set<Int> = []
        public var chargeArmed = false
    }
    public var devices: [String: DeviceState] = [:]
    public init() {}
    public mutating func evaluate(_ readings: [BatteryDevice], preferences: BatteryPreferences, now: Date = Date()) -> [BatteryAlert] {
        guard preferences.notificationsEnabled else { return [] }
        var alerts: [BatteryAlert] = []
        for device in readings {
            let options = preferences.options(for: device.id)
            guard options.notifications, !options.hidden, device.isLive(at: now), let level = device.displayLevel(at: now), let measured = device.measuredAt,
                  measured <= now.addingTimeInterval(5), devices[device.id].map({ measured > $0.lastMeasurement }) ?? true else { continue }
            var state = devices[device.id] ?? .init(lastMeasurement: .distantPast)
            state.sentThresholds = state.sentThresholds.filter { level < $0 + 5 }
            if device.isCharging && level < 100 { state.chargeArmed = true }
            if level == 100 {
                if state.chargeArmed && preferences.notifyFullyCharged { alerts.append(.init(deviceID: device.id, kind: .full, level: level)) }
                state.chargeArmed = false
            } else if !device.isCharging {
                // A disconnected charging cable ends the cycle; no full alert from a later unrelated sample.
                state.chargeArmed = false
                let crossed = preferences.thresholds(for: device.id).filter { level <= $0 && !state.sentThresholds.contains($0) }
                if let mostUrgent = crossed.min() { alerts.append(.init(deviceID: device.id, kind: .low(mostUrgent), level: level)) }
                state.sentThresholds.formUnion(crossed)
            }
            state.lastMeasurement = measured
            devices[device.id] = state
        }
        return alerts
    }
}
