import Foundation
import Observation
import MetricsCore

@MainActor @Observable final class DeviceBatteryStore {
    private(set) var devices: [BatteryDevice] = []
    private(set) var issues: [String] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    var now = Date()
    private(set) var isPaused = false
    var history = BatteryHistory()
    var migration: BatteryMigration?
    var notificationStatus = String(localized: "Off")
    var expandedGroups: Set<String> = []
    var settingsTab = "general"
    var selectedSettingsDevice: String?
    var preferences = BatteryPreferences() {
        didSet {
            guard ready else { return }
            persist(preferences, file: "preferences.json")
            if !isolated, oldValue.notificationsEnabled != preferences.notificationsEnabled {
                notifications.configure(enabled: preferences.notificationsEnabled)
            }
        }
    }
    var includeMobile = true {
        didSet {
            guard ready else { return }
            persist(includeMobile, file: "include-mobile.json")
            if !includeMobile { mobileDiscovery.stop(); pencilMonitor.stopAll(); markMobileOffline() }
            refresh()
        }
    }
    let isolated: Bool
    @ObservationIgnored var openHistory: ((String) -> Void)?
    @ObservationIgnored private let storage: DeviceBatteryStorage
    @ObservationIgnored private var notifications: DeviceBatteryNotifications!
    @ObservationIgnored private let mobileDiscovery = MobileDiscovery()
    @ObservationIgnored private let pencilMonitor = PencilMonitor()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var active = true
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var nextRefresh = Date.distantPast
    @ObservationIgnored private var nextPermissionCheck = Date.distantPast
    @ObservationIgnored private var lastBluetoothDate: Date?
    @ObservationIgnored private var connections: [PencilConnection] = []

    init(acceptance: AcceptanceProfile?) {
        isolated = acceptance != nil
        storage = acceptance.map { DeviceBatteryStorage(directory: $0.directory.appendingPathComponent("DeviceBatteries")) } ?? .local
        if acceptance == nil {
            let source = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PilBar")
            do { migration = try storage.migrate(from: source) }
            catch { issues = [String(localized: "PilBar import couldn't be completed; the source records are kept.")] }
        }
        history = storage.read(BatteryHistory.self, file: "history.json") ?? BatteryHistory()
        if let saved = storage.read(BatteryPreferences.self, file: "preferences.json") { preferences = saved }
        else { preferences.notificationsEnabled = false }
        includeMobile = storage.read(Bool.self, file: "include-mobile.json")
            ?? (acceptance == nil ? UserDefaults(suiteName: "dev.homedev.PilBar")?.object(forKey: "includeMobile") as? Bool : nil) ?? true
        devices = (storage.read([BatteryDevice].self, file: "devices.json") ?? []).filter {
            !($0.source == .mobile && $0.id.hasPrefix("ios:") && $0.name.lowercased().contains("watch"))
        }.map { var d = $0; d.isConnected = false; return d }
        notifications = DeviceBatteryNotifications(storage: storage)
        notifications.onStatus = { [weak self] in self?.notificationStatus = $0 }
        pencilMonitor.onSample = { [weak self] sample in
            guard let self, self.active, !self.stopped, !self.isolated else { return }
            self.devices = BatteryLedger.merge(self.devices, snapshot: .init(devices: [sample], successfulSources: []))
            self.record(); self.saveDevices()
        }
        pencilMonitor.onDisconnected = { [weak self] id in
            guard let self, let i = self.devices.firstIndex(where: { $0.id == id }) else { return }
            self.devices[i].isConnected = false; self.record(); self.saveDevices()
        }
        mobileDiscovery.onChange = { [weak self] in self?.refresh() }
        ready = true
        if !isolated { notifications.configure(enabled: preferences.notificationsEnabled) }
    }
    var displayedDevices: [BatteryDevice] { BatteryPresentation.ordered(devices, preferences: preferences, now: now) }
    var groups: [BatteryDisplayGroup] { BatteryPresentation.groups(devices, preferences: preferences, now: now) }
    var liveGroups: [BatteryDisplayGroup] { isPaused ? [] : groups.filter { $0.isLive(at: now) } }
    var offlineGroups: [BatteryDisplayGroup] { isPaused ? groups : groups.filter { !$0.isLive(at: now) } }
    func name(_ device: BatteryDevice) -> String { preferences.name(for: device) }
    func setOptions(_ id: String, _ update: (inout DeviceOptions) -> Void) {
        var options = preferences.options(for: id); update(&options); preferences.devices[id] = options
    }
    func toggleGroup(_ id: String) {
        if expandedGroups.contains(id) { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
    }
    var managementDevices: [BatteryDevice] {
        var manual = preferences; manual.lowBatteryFirst = false
        for id in manual.devices.keys { manual.devices[id]?.favorite = false }
        return BatteryPresentation.ordered(devices, preferences: manual, now: now, includeHidden: true)
    }
    func moveDevice(_ id: String, by distance: Int) {
        var order = managementDevices.map(\.id)
        guard let i = order.firstIndex(of: id), order.indices.contains(i + distance) else { return }
        order.swapAt(i, i + distance); preferences.deviceOrder = order
    }
    func requestNotifications() { if !isolated { notifications.configure(enabled: preferences.notificationsEnabled, requestPermission: true) } }
    func refreshNotificationPermission() { if !isolated { notifications.configure(enabled: preferences.notificationsEnabled) } }
    func testNotification() { if !isolated { notifications.sendTest(sound: preferences.notificationSound) } }

    /// Called by the one existing system sampler; no timer or second Mac/BT poll.
    func tick(snapshot: MetricSnapshot, visible: Bool) {
        now = snapshot.date
        var mac: [BatteryDevice] = []
        if let b = snapshot.battery, b.present, let level = b.percent {
            mac = [.init(id: "mac:internal", name: String(localized: "This Mac"), level: level, isCharging: b.charging, source: .mac,
                         measuredAt: snapshot.date, lastSeenAt: snapshot.date, connection: .internalBattery, telemetry: .iokit)]
        }
        if snapshot.battery != nil { devices = BatteryLedger.merge(devices, snapshot: .init(devices: mac, successfulSources: [.mac])) }
        if let bluetooth = snapshot.bluetooth, bluetooth.date != lastBluetoothDate {
            lastBluetoothDate = bluetooth.date
            devices = BatteryLedger.merge(devices, snapshot: DeviceBatteryAdapter.bluetooth(bluetooth, now: now))
        }
        record()
        if !isolated, now >= nextPermissionCheck {
            nextPermissionCheck = now.addingTimeInterval(60); refreshNotificationPermission()
        }
        if now >= nextRefresh { refresh(visible: visible) }
    }
    func setActive(_ value: Bool) {
        active = value; isPaused = !value; now = Date()
        if !value {
            let unavailable = devices.map { var d = $0; d.isConnected = false; return d }
            if history.record(unavailable, now: now) { persist(history, file: "history.json") }
            generation += 1; refreshTask?.cancel(); mobileDiscovery.stop(); pencilMonitor.stopAll()
        } else { nextRefresh = .distantPast }
    }
    func refresh(visible: Bool = true) {
        guard !isolated, active, !stopped, refreshTask == nil else { return }
        isRefreshing = true
        nextRefresh = Date().addingTimeInterval(visible ? 15 : 60)
        if includeMobile { mobileDiscovery.start() }
        generation += 1
        let token = generation, includeMobile = includeMobile
        let bluetooth = devices.filter { $0.source == .bluetooth }
        refreshTask = Task { [weak self] in
            guard let owner = self else { return }
            let job = Task.detached(priority: .utility) {
                DeviceBatteryCollector.collect(includeMobile: includeMobile, bluetooth: bluetooth) { partial in
                    Task { @MainActor [weak owner] in
                        guard let owner, owner.active, !owner.stopped, owner.generation == token, owner.isRefreshing else { return }
                        owner.apply(partial)
                    }
                }
            }
            let snapshot = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            guard let self else { return }
            if !Task.isCancelled, self.active, !self.stopped, self.generation == token {
                self.apply(snapshot)
                if snapshot.successfulSources.contains(.mobile) { self.connections = snapshot.pencilConnections }
                else {
                    for c in snapshot.pencilConnections { self.connections.removeAll { $0.id == c.id }; self.connections.append(c) }
                }
                if self.includeMobile { self.pencilMonitor.reconcile(self.connections) }
                self.lastRefresh = Date()
            }
            self.isRefreshing = false; self.refreshTask = nil
        }
    }
    private func apply(_ snapshot: BatterySnapshot) {
        devices = BatteryLedger.merge(devices, snapshot: snapshot); issues = snapshot.issues
        now = Date(); saveDevices(); record()
    }
    private func record() {
        if history.record(devices, now: now) { persist(history, file: "history.json") }
        if !isolated, active, !stopped { notifications.process(devices, preferences: preferences) }
    }
    private func saveDevices() { persist(devices, file: "devices.json") }
    private func markMobileOffline() {
        for i in devices.indices where [.mobile, .pencil].contains(devices[i].source) { devices[i].isConnected = false }
        record(); saveDevices()
    }
    private func persist<T: Encodable>(_ value: T, file: String) {
        do { try storage.write(value, file: file) }
        catch { if !issues.contains(String(localized: "Battery data couldn't be saved.")) { issues.append(String(localized: "Battery data couldn't be saved.")) } }
    }
    func forgetOffline() {
        let removed = devices.filter { !$0.isLive(at: now) }
        persist(removed, file: "removed-devices.json")
        devices.removeAll { !$0.isLive(at: now) }; saveDevices()
    }
    func undoForgetOffline() {
        let removed = storage.read([BatteryDevice].self, file: "removed-devices.json") ?? []
        devices = BatteryLedger.merge(devices, snapshot: .init(devices: removed, successfulSources: [])); saveDevices()
    }
    var canUndoForget: Bool { !(storage.read([BatteryDevice].self, file: "removed-devices.json") ?? []).isEmpty }
    func finish() async {
        stopped = true; active = false; isPaused = true; now = Date(); generation += 1
        refreshTask?.cancel(); mobileDiscovery.stop(); pencilMonitor.stopAll()
        await refreshTask?.value
        await mobileDiscovery.finish()
        await pencilMonitor.finish()
        saveDevices()
    }
}
