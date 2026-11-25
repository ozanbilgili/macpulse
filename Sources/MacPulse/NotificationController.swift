import Foundation
import UserNotifications
import Observation
import MetricsCore

@MainActor @Observable final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    @ObservationIgnored var onBatteryDevice: ((String) -> Void)?
    var enabled = false
    var requesting = false
    var status = String(localized: "Off · alerts appear in the app")
    private let preference = "MacPulse.localAlertNotifications"
    private let systemNotificationsAllowed: Bool
    init(systemNotificationsAllowed: Bool = true) {
        self.systemNotificationsAllowed = systemNotificationsAllowed
        super.init()
    }
    func restorePreference() async {
        guard systemNotificationsAllowed else { return }
        UNUserNotificationCenter.current().delegate = self
        guard UserDefaults.standard.bool(forKey: preference) else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        enabled = settings.authorizationStatus == .authorized
        status = enabled ? String(localized: "System notifications on") : String(localized: "System permission off · alerts appear in the app")
        UNUserNotificationCenter.current().delegate = self
    }
    func toggle() async {
        guard systemNotificationsAllowed, !requesting else { return }
        if enabled {
            enabled = false; UserDefaults.standard.set(false, forKey: preference)
            status = String(localized: "Off · alerts appear in the app"); return
        }
        requesting = true
        defer { requesting = false }
        do {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            enabled = try await center.requestAuthorization(options: [.alert])
            UserDefaults.standard.set(enabled, forKey: preference)
            status = enabled ? String(localized: "System notifications on") : String(localized: "Permission denied · alerts appear in the app")
        } catch { enabled = false; status = String(localized: "Notification permission couldn't be obtained · alerts appear in the app") }
    }
    func deliver(_ alert: MonitorAlert) async {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.kind.title
        content.body = "\(alert.displayTarget) · \(AlertFormat.value(alert))"
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)) }
        catch { status = String(localized: "System notification couldn't be sent · alert saved in the app") }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["deviceID"] as? String else { return }
        await MainActor.run { self.onBatteryDevice?(id) }
    }

}
