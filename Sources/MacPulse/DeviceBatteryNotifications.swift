import Foundation
import UserNotifications
import MetricsCore

@MainActor final class DeviceBatteryNotifications: NSObject {
    private let center = UNUserNotificationCenter.current()
    private let storage: DeviceBatteryStorage
    private var state: BatteryAlertState
    private var authorized = false
    private var requesting = false
    var onStatus: ((String) -> Void)?
    var onOpenDevice: ((String) -> Void)?
    init(storage: DeviceBatteryStorage) { self.storage = storage; state = storage.read(BatteryAlertState.self, file: "alerts.json") ?? BatteryAlertState(); super.init() }

    func configure(enabled: Bool, requestPermission: Bool = false) {
        guard !requesting else { return }
        requesting = true
        Task {
            defer { requesting = false }
            var settings = await center.notificationSettings()
            if enabled && requestPermission && settings.authorizationStatus == .notDetermined {
                onStatus?(String(localized: "Waiting for macOS permission"))
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch { onStatus?(String(localized: "Notification permission could not be obtained.")); return }
                settings = await center.notificationSettings()
            }
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            onStatus?(!enabled ? String(localized: "Off") : authorized ? String(localized: "Allowed") : settings.authorizationStatus == .denied ? String(localized: "System permission off") : String(localized: "Permission needed"))
        }
    }
    func process(_ devices: [BatteryDevice], preferences: BatteryPreferences) {
        guard authorized && preferences.notificationsEnabled else { return }
        let previous = state
        let alerts = state.evaluate(devices, preferences: preferences)
        try? storage.write(state, file: "alerts.json")
        for alert in alerts {
            guard let device = devices.first(where: { $0.id == alert.deviceID }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = preferences.name(for: device)
            switch alert.kind {
            case .low: content.body = String(localized: "Battery low: \(LocalizedFormat.percent(alert.level)). Time to charge.")
            case .full: content.body = String(localized: "Charging complete: \(LocalizedFormat.percent(100)).")
            }
            content.userInfo = ["deviceID": device.id]
            if preferences.notificationSound { content.sound = .default }
            let measurement = state.devices[device.id]?.lastMeasurement
            Task {
                let settings = await center.notificationSettings()
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    authorized = false
                    if state.devices[device.id]?.lastMeasurement == measurement { state.devices[device.id] = previous.devices[device.id] }
                    try? storage.write(state, file: "alerts.json")
                    onStatus?(String(localized: "System permission off"))
                    return
                }
                do { try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
                catch {
                    if state.devices[device.id]?.lastMeasurement == measurement { state.devices[device.id] = previous.devices[device.id] }
                    try? storage.write(state, file: "alerts.json")
                    onStatus?(String(localized: "Notification couldn't be sent; check the system notification settings."))
                }
            }
        }
    }
    func sendTest(sound: Bool) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { onStatus?(String(localized: "Turn on notification permission first.")); return }
            let content = UNMutableNotificationContent()
            content.title = "MacPulse"
            content.body = String(localized: "Notifications are ready. Low battery and finished charging will show up here.")
            if sound { content.sound = .default }
            do {
                try await center.add(.init(identifier: "macpulse-battery-test", content: content, trigger: nil))
                try await Task.sleep(for: .seconds(1))
                let delivered = await center.deliveredNotifications()
                onStatus?(delivered.contains { $0.request.identifier == "macpulse-battery-test" } ? String(localized: "Test reached Notification Center") : String(localized: "Test sent; macOS controls how it appears"))
            }
            catch { onStatus?(String(localized: "Test notification couldn't be sent.")) }
        }
    }
}
