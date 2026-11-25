import SwiftUI
import AppKit
import Observation
import ServiceManagement
import MetricsCore

@MainActor @Observable final class PreferencesStore {
    private(set) var value: MonitorPreferences
    @ObservationIgnored var onIntervalChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let acceptance: AcceptanceProfile?
    private static let key = "monitor.preferences.v1"
    init(defaults: UserDefaults = .standard, acceptance: AcceptanceProfile? = nil) {
        self.defaults = defaults
        self.acceptance = acceptance
        if let acceptance { value = acceptance.preferences() }
        else { value = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(MonitorPreferences.self, from: $0) } ?? MonitorPreferences() }
    }
    var theme: MonitorTheme {
        get { value.theme }
        set { value.theme = newValue; save(); applyAppearance() }
    }
    var interval: Int {
        get { value.interval }
        set {
            guard MonitorPreferences.intervals.contains(newValue), newValue != value.interval else { return }
            value.interval = newValue; save(); onIntervalChange?()
        }
    }
    var colorScheme: ColorScheme? {
        switch theme { case .system: nil; case .dark: .dark; case .light: .light }
    }
    var usageMenu: Bool {
        get { value.usageMenu }
        set { value.usageMenu = newValue; save() }
    }
    var usageMenuStyle: AIUsageMenuStyle {
        get { value.usageMenuStyle }
        set { value.usageMenuStyle = newValue; save() }
    }
    var usageShowsLeft: Bool {
        get { value.usageShowsLeft }
        set { value.usageShowsLeft = newValue; save() }
    }
    var usageResetRelative: Bool {
        get { value.usageResetRelative }
        set { value.usageResetRelative = newValue; save() }
    }
    var menuWidgetSelection: MenuWidgetSelection {
        get { value.menuWidgetSelection }
        set { value.menuWidgetSelection = newValue; save() }
    }
    func widgets(for usage: AIUsageStore) -> [MenuWidget] {
        if menuWidgetSelection == .topFourFiveHour {
            return MenuWidget.topFiveHourWidgets(states: usage.states, now: usage.now)
        }
        return manualWidgets(for: usage)
    }
    func manualWidgets(for usage: AIUsageStore) -> [MenuWidget] {
        value.resolvedWidgets(claudeAccounts: usage.states.filter { $0.account.provider == .claude }.map(\.account.n),
                              codex: usage.states.contains { $0.account.provider == .codex }, openRouter: usage.credit != nil)
    }
    func setWidgets(_ widgets: [MenuWidget]) {
        value.menuWidgets = MenuWidget.normalized(widgets); value.menuWidgetSelection = .manual; save()
    }
    func contains(_ metric: MenuMetric) -> Bool { value.menuMetrics.contains(metric) }
    func select(_ metric: MenuMetric, enabled: Bool) {
        var selected = value.menuMetrics
        if enabled {
            guard selected.count < 3 || selected.contains(metric) else { return }
            selected.append(metric)
        } else { selected.removeAll { $0 == metric } }
        value.menuMetrics = MonitorPreferences.normalized(selected); save()
    }
    func applyAppearance() {
        NSApp.appearance = theme == .system ? nil : NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
    }
    private func save() {
        if let acceptance { try? acceptance.save(value); return }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

@MainActor @Observable final class LoginItemController {
    private(set) var status = SMAppService.mainApp.status
    private(set) var error: String?
    var requested: Bool { status == .enabled || status == .requiresApproval }
    var message: String {
        if let error { return error }
        switch status {
        case .enabled: return String(localized: "This app will open when you log in.")
        case .requiresApproval: return String(localized: "Waiting for macOS approval. Open Login Items and allow MacPulse.")
        case .notRegistered: return String(localized: "Off. Nothing is registered automatically at launch.")
        case .notFound: return String(localized: "Login item not found. Run the app from the Applications folder and try enabling it.")
        @unknown default: return String(localized: "Login item status can't be read.")
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    // Called only by the preference toggle; initialization never changes OS registration.
    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = String(localized: "Login item couldn't be changed. Run the app from the Applications folder and try again.")
        }
        refresh()
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct PreferencesView: View {
    @Bindable var preferences: PreferencesStore
    @Environment(\.openWindow) private var openWindow
    @State private var login = LoginItemController()
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? String(localized: "Development") }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Palette.accent).font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacPulse Settings").font(.title2.weight(.semibold))
                    Text("Appearance, sampling rate and menu bar").font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(MonitorTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Refresh while visible", selection: $preferences.interval) {
                        ForEach(MonitorPreferences.intervals, id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Text("This interval is used while the main window or quick panel is visible. In the background, sampling happens every 10 seconds.")
                        .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(10)
            }
            GroupBox("Menu Bar Widgets") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Choose, order and style system data and AI accounts separately.")
                        .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Edit menu bar") { openWindow(id: "menu-widgets") }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("Open MacPulse when I log in", isOn: Binding(get: { login.requested }, set: { login.setEnabled($0) }))
                        .disabled(preferences.acceptance != nil)
                    Text(login.message).font(.caption).foregroundStyle(login.error == nil ? Palette.secondary : Palette.disk)
                        .fixedSize(horizontal: false, vertical: true)
                    if login.status == .requiresApproval {
                        Button("Open Login Items") { login.openSystemSettings() }
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("About MacPulse \(version)") { openWindow(id: "about") }
                    .buttonStyle(.link)
                Spacer()
                Text("Settings are stored on this Mac")
            }.font(.caption).foregroundStyle(Palette.secondary)
        }.padding(24).frame(width: 490).background(Palette.background).foregroundStyle(.primary)
            .onAppear { login.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }
}
