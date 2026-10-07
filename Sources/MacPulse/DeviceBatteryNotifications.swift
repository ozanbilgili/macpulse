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
                onStatus?("macOS izni bekleniyor")
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch { onStatus?("Bildirim izni alınamadı."); return }
                settings = await center.notificationSettings()
            }
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            onStatus?(!enabled ? "Kapalı" : authorized ? "İzin verildi" : settings.authorizationStatus == .denied ? "Sistem izni kapalı" : "İzin gerekiyor")
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
            case .low: content.body = "Pil azaldı: %\(alert.level). Şarj zamanı."
            case .full: content.body = "Şarj tamamlandı: %100."
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
                    onStatus?("Sistem izni kapalı")
                    return
                }
                do { try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
                catch {
                    if state.devices[device.id]?.lastMeasurement == measurement { state.devices[device.id] = previous.devices[device.id] }
                    try? storage.write(state, file: "alerts.json")
                    onStatus?("Bildirim gönderilemedi; sistem bildirim ayarını kontrol et.")
                }
            }
        }
    }
    func sendTest(sound: Bool) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { onStatus?("Önce bildirim iznini aç."); return }
            let content = UNMutableNotificationContent()
            content.title = "MacPulse"
            content.body = "Bildirimler hazır. Düşük pil ve tamamlanan şarj burada görünecek."
            if sound { content.sound = .default }
            do {
                try await center.add(.init(identifier: "macpulse-battery-test", content: content, trigger: nil))
                try await Task.sleep(for: .seconds(1))
                let delivered = await center.deliveredNotifications()
                onStatus?(delivered.contains { $0.request.identifier == "macpulse-battery-test" } ? "Test Bildirim Merkezi’ne ulaştı" : "Test gönderildi; görünümü macOS yönetir")
            }
            catch { onStatus?("Test bildirimi gönderilemedi.") }
        }
    }
}
