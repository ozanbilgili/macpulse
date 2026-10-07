import SwiftUI
import AppKit
import Observation
import MetricsCore

@MainActor @Observable final class MonitorStore {
    static let shared = MonitorStore()
    var snapshot: MetricSnapshot?
    var history: [MetricSnapshot] = []
    let preferences: PreferencesStore
    let notifications: NotificationController
    let usage: AIUsageStore
    let deviceBatteries: DeviceBatteryStore
    @ObservationIgnored private let acceptance: AcceptanceProfile?
    var lifecycle = SamplingLifecycle()
    var paused: Bool {
        get { lifecycle.paused }
        set {
            guard lifecycle.setPaused(newValue) else { return }
            boundaryChanged()
        }
    }
    var mainVisible = false { didSet { visibilityChanged(oldValue != mainVisible) } }
    var mainWindowOpen = false
    var panelVisible = false { didSet { visibilityChanged(oldValue != panelVisible) } }
    var foreground: Bool { mainVisible || panelVisible }
    var effectiveInterval: Int { preferences.value.pollingInterval(visible: foreground) }
    @ObservationIgnored private let sampler = MetricSampler()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var waitTask: Task<Void, any Error>?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var repository: HistoryRepository?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var starts = 0
    @ObservationIgnored private var sampleCount = 0
    @ObservationIgnored private var diagnosticURL: URL?
    @ObservationIgnored var menuWidgetImageWidth: CGFloat = 0
    @ObservationIgnored var menuWidgetBudget: CGFloat = 0
    @ObservationIgnored var menuWidgetCount = 0
    @ObservationIgnored var showMainAction: (() -> Void)?
    @ObservationIgnored var showAboutAction: (() -> Void)?
    @ObservationIgnored var showUsageAction: (() -> Void)?
    @ObservationIgnored var showWidgetsAction: (() -> Void)?
    @ObservationIgnored var showBatterySettingsAction: (() -> Void)?
    @ObservationIgnored var showBatteryHistoryAction: ((String) -> Void)?
    @ObservationIgnored var showSettingsAction: (() -> Void)?
    @ObservationIgnored var togglePanelAction: (() -> Void)?
    @ObservationIgnored var closePanelAction: (() -> Void)?
    var historyReport: HistoryReport?
    var historyError: String?
    var historyLoading = false
    var historyRange: HistoryRange = .hour {
        didSet { Task { await refreshHistory() } }
    }
    var alerts: [MonitorAlert] = []
    @ObservationIgnored private var lastHistoryRefresh = 0.0
    @ObservationIgnored private var queryID = UUID()

    init() {
        do {
            acceptance = try AcceptanceProfile.parse(CommandLine.arguments)
            try acceptance?.prepare()
        } catch { fatalError("Geçersiz kabul profili; canlı kullanıcı verisi açılmadı.") }
        preferences = PreferencesStore(acceptance: acceptance)
        notifications = NotificationController(systemNotificationsAllowed: acceptance == nil)
        usage = AIUsageStore(isolated: acceptance != nil)
        deviceBatteries = DeviceBatteryStore(acceptance: acceptance)
        notifications.onBatteryDevice = { [weak self] in self?.showBatteryHistory($0) }
        deviceBatteries.openHistory = { [weak self] in self?.showBatteryHistory($0) }
        // Opt-in local acceptance diagnostics contain counts/timing only, never the inventory.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--diagnostics-file"), args.indices.contains(index + 1) {
            diagnosticURL = URL(fileURLWithPath: args[index + 1])
        }
        preferences.onIntervalChange = { [weak self] in self?.waitTask?.cancel() }
    }
    func start() {
        guard runTask == nil, !stopping else { return }
        starts += 1
        runTask = Task { await run() }
    }
    func showMain() { closePanelAction?(); showMainAction?() }
    func showUsage() { showMain(); showUsageAction?() }
    func showWidgets() { closePanelAction?(); showWidgetsAction?() }
    func showBatterySettings() { closePanelAction?(); showBatterySettingsAction?() }
    func showBatteryHistory(_ id: String) { closePanelAction?(); showBatteryHistoryAction?(id) }
    func showSettings() { closePanelAction?(); showSettingsAction?() }
    func setSleeping(_ sleeping: Bool) {
        guard lifecycle.setSleeping(sleeping) else { return }
        boundaryChanged()
    }
    private func boundaryChanged() {
        deviceBatteries.setActive(lifecycle.canSample)
        waitTask?.cancel()
        writeDiagnostics()
        let previous = boundaryTask
        boundaryTask = Task { await previous?.value; await interruptHistory() }
    }
    private func visibilityChanged(_ changed: Bool) {
        guard changed else { return }
        waitTask?.cancel()
        writeDiagnostics()
    }
    func refreshBatteryDevices() {
        deviceBatteries.refresh()
        Task { await sampler.refreshBluetooth(); waitTask?.cancel() }
    }
    func refreshHistory() async {
        guard let repository else { return }
        let id = UUID(); queryID = id
        let range = historyRange
        historyLoading = true
        do {
            let report = try await repository.report(range: range)
            guard queryID == id else { return }
            historyReport = report; alerts = report.alerts; historyError = nil
        } catch {
            guard queryID == id else { return }
            historyError = "Geçmiş kaydı okunamıyor. Canlı ölçümler devam ediyor."
        }
        historyLoading = false
    }
    private func interruptHistory() async {
        do { try await repository?.interrupt(); await refreshHistory() }
        catch { historyError = "Geçmiş kaydı tamamlanamadı. Canlı ölçümler devam ediyor." }
    }
    func finish() async {
        guard !stopping else { await runTask?.value; return }
        stopping = true; lifecycle.stop()
        runTask?.cancel(); waitTask?.cancel()
        await runTask?.value
        runTask = nil
        await boundaryTask?.value
        await interruptHistory()
        await usage.finish()
        await deviceBatteries.finish()
        writeDiagnostics()
    }
    private func run() async {
        do {
            let url = try acceptance?.historyURL ?? HistoryRepository.defaultURL()
            repository = try await Task.detached { try HistoryRepository(url: url) }.value
            await refreshHistory()
        } catch { historyError = "Yerel geçmiş açılamadı; mevcut kayıt korundu. Canlı ölçümler devam ediyor." }
        await notifications.restorePreference()
        while !Task.isCancelled && !stopping {
            if lifecycle.canSample {
                usage.tick()
                await boundaryTask?.value
                let token = lifecycle.generation
                if lifecycle.resetRequired {
                    await sampler.resetBaselines()
                    lifecycle.didReset(for: token)
                }
                guard lifecycle.accepts(token) else { continue }
                let next = await sampler.sample(applications: RunningApplicationCatalog.read())
                await boundaryTask?.value
                guard !Task.isCancelled && !stopping else { break }
                guard lifecycle.accepts(token) else { continue }
                snapshot = next
                deviceBatteries.tick(snapshot: next, visible: foreground)
                sampleCount += 1
                history.append(next.historySample)
                if history.count > 90 { history.removeFirst(history.count - 90) }
                if let repository {
                    do {
                        let newAlerts = try await repository.ingest(next)
                        if lifecycle.accepts(token) {
                            for alert in newAlerts { await notifications.deliver(alert) }
                        }
                        if next.system.uptime - lastHistoryRefresh >= 10 || !newAlerts.isEmpty {
                            lastHistoryRefresh = next.system.uptime
                            await refreshHistory()
                        }
                    } catch { historyError = "Yerel geçmiş yazılamıyor. Canlı ölçümler devam ediyor." }
                }
                writeDiagnostics()
            }
            guard !Task.isCancelled && !stopping else { break }
            let delay = lifecycle.canSample ? effectiveInterval : 3600
            let waiter = Task { try await Task.sleep(for: .seconds(delay)) }
            waitTask = waiter
            _ = await waiter.result
            waitTask = nil
        }
    }
    private func writeDiagnostics() {
        guard let diagnosticURL else { return }
        let payload: [String: Any] = [
            "at": Date().timeIntervalSince1970, "starts": starts, "samples": sampleCount,
            "paused": paused, "sleeping": lifecycle.sleeping, "stopped": stopping,
            "generation": lifecycle.generation, "mainVisible": mainVisible, "mainWindowOpen": mainWindowOpen, "panelVisible": panelVisible,
            "interval": effectiveInterval, "theme": preferences.value.theme.rawValue,
            "acceptanceProfile": acceptance != nil,
            "lastSample": snapshot?.date.timeIntervalSince1970 as Any? ?? NSNull(),
            "cpuAvailable": snapshot?.cpu != nil, "networkRateAvailable": snapshot?.network?.incomingRate != nil,
            "collectionMilliseconds": snapshot?.collectionMilliseconds as Any? ?? NSNull(),
            "hardwareMilliseconds": snapshot?.hardware?.collectionMilliseconds as Any? ?? NSNull(),
            "hardwareDate": snapshot?.hardware?.date.timeIntervalSince1970 as Any? ?? NSNull(),
            "gpuPercent": snapshot?.hardware?.singleGPUPercent as Any? ?? NSNull(),
            "gpuEnergyAvailable": snapshot?.hardware?.gpuModelWatts != nil,
            "sensorCount": snapshot?.hardware?.sensors.count ?? 0,
            "bluetoothDate": snapshot?.bluetooth?.date.timeIntervalSince1970 as Any? ?? NSNull(),
            "bluetoothAvailable": snapshot?.bluetooth?.available ?? false,
            "bluetoothCount": snapshot?.bluetooth?.accessories.count ?? 0,
            "bluetoothMilliseconds": snapshot?.bluetooth?.collectionMilliseconds as Any? ?? NSNull(),
            "audioDate": snapshot?.audio?.date.timeIntervalSince1970 as Any? ?? NSNull(),
            "audioCount": snapshot?.audio?.devices.count ?? 0,
            "audioMilliseconds": snapshot?.audio?.collectionMilliseconds as Any? ?? NSNull(),
            "usageChecking": usage.checking, "usageScanning": usage.scanning,
            "usageAccounts": usage.states.count, "usageAccountsWithData": usage.states.filter { $0.usage != nil }.count,
            "usageCreditAvailable": usage.credit?.credit != nil, "usageTokenAccounts": usage.tokens.byAccount.count,
            "usageLastCheck": usage.lastCheck?.timeIntervalSince1970 as Any? ?? NSNull(),
            "deviceBatteryCount": deviceBatteries.devices.count,
            "deviceBatteryLive": deviceBatteries.devices.filter { $0.isLive(at: deviceBatteries.now) }.count,
            "deviceBatteryMobileLive": deviceBatteries.devices.filter { $0.source == .mobile && $0.isLive(at: deviceBatteries.now) }.count,
            "deviceBatteryPowerCount": deviceBatteries.devices.filter { $0.displayPower(at: deviceBatteries.now) != nil }.count,
            "deviceBatteryRefreshing": deviceBatteries.isRefreshing,
            "deviceBatteryHistoryPoints": deviceBatteries.history.samples.values.reduce(0) { $0 + $1.count },
            "deviceBatteryImportedPoints": deviceBatteries.migration?.historyPointCount ?? 0,
            "menuWidgetCount": menuWidgetCount, "menuWidgetWidth": menuWidgetImageWidth, "menuWidgetBudget": menuWidgetBudget,
            "menuAutomaticAI": preferences.menuWidgetSelection == .topFourFiveHour,
            "historyError": historyError != nil
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: diagnosticURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: diagnosticURL.path)
    }
}

enum MonitorTab: String, CaseIterable, Identifiable {
    case overview = "Genel bakış", cpu = "CPU", memory = "Bellek", disk = "Disk", network = "Ağ", battery = "Pil", applications = "Uygulamalar", history = "Geçmiş", alerts = "Uyarılar", projects = "Projeler", containers = "Containerlar", hardware = "GPU ve enerji", bluetooth = "Bluetooth", audio = "Ses", usage = "AI Kullanımı"
    var id: Self { self }
    var icon: String {
        switch self { case .overview: "square.grid.2x2.fill"; case .cpu: "cpu"; case .memory: "memorychip"; case .disk: "internaldrive"; case .network: "network"; case .battery: "battery.100percent"; case .applications: "app.badge"; case .history: "clock.arrow.circlepath"; case .alerts: "bell"; case .projects: "hammer"; case .containers: "shippingbox"; case .hardware: "square.3.layers.3d"; case .bluetooth: "antenna.radiowaves.left.and.right"; case .audio: "speaker.wave.2"; case .usage: "chart.bar.xaxis" }
    }
    var color: Color {
        switch self { case .overview, .applications, .history, .containers: Palette.accent; case .alerts, .projects: Palette.disk; case .cpu: Palette.cpu; case .memory: Palette.memory; case .disk: Palette.disk; case .network: Palette.network; case .battery: Palette.battery; case .hardware: Palette.gpu; case .bluetooth: Palette.memory; case .audio: Palette.network; case .usage: Palette.memory }
    }
}


@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = MonitorStore.shared
    private var terminating = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var menuBar: MenuBarController?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task { await monitor.finish(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.preferences.applyAppearance()
        NSApp.setActivationPolicy(.regular)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MonitorStore.shared.setSleeping(true) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MonitorStore.shared.setSleeping(false) }
            }
        ]
        monitor.start()
        menuBar = MenuBarController(store: monitor)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        monitor.showMain()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = MonitorStore.shared
    var body: some Scene {
        Window("MacPulse", id: "main") {
            DashboardView(store: store)
                .preferredColorScheme(store.preferences.colorScheme)
                .background(WindowActivityObserver(store: store))
        }
        .defaultSize(width: 1320, height: 920)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { MonitorCommands(store: store) }
        Settings {
            PreferencesView(preferences: store.preferences)
                .preferredColorScheme(store.preferences.colorScheme)
        }
        Window("Menü çubuğu widget'ları", id: "menu-widgets") {
            MenuWidgetEditor(store: store).preferredColorScheme(store.preferences.colorScheme)
        }.defaultSize(width: 760, height: 720).windowResizability(.contentMinSize)
        Window("Pil ve cihaz ayarları", id: "battery-settings") {
            DeviceBatterySettingsView(store: store.deviceBatteries, mainPreferences: store.preferences)
                .preferredColorScheme(store.preferences.colorScheme)
        }.windowResizability(.contentSize)
        WindowGroup("Cihaz pil geçmişi", id: "battery-history", for: String.self) { $deviceID in
            if let deviceID { DeviceBatteryHistoryView(store: store.deviceBatteries, deviceID: deviceID).preferredColorScheme(store.preferences.colorScheme) }
        }.windowResizability(.contentSize)
        Window("MacPulse Hakkında", id: "about") {
            AboutView().preferredColorScheme(store.preferences.colorScheme)
        }.windowResizability(.contentSize)
    }
}

struct MonitorCommands: Commands {
    let store: MonitorStore
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("MacPulse Hakkında") { store.showAboutAction?() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .newItem) {
            Button("Ana pencereyi aç") { store.showMain() }.keyboardShortcut("o")
        }
        CommandMenu("İzleme") {
            Button("Menü çubuğu widget'larını düzenle") { store.showWidgets() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("AI Kullanımını aç") { store.showUsage() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Hızlı paneli aç") { store.togglePanelAction?() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button(store.paused ? "İzlemeyi sürdür" : "İzlemeyi duraklat") { store.paused.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}
