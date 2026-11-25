import SwiftUI
import ServiceManagement
import TelemetryBridge
import MetricsCore

extension PanelTheme {
    var title: String { switch self { case .automatic: String(localized: "System"); case .light: String(localized: "Light"); case .dark: String(localized: "Dark") } }
    var colorScheme: ColorScheme? { switch self { case .automatic: nil; case .light: .light; case .dark: .dark } }
}
extension PanelDensity {
    var title: String { self == .compact ? String(localized: "Compact") : String(localized: "Comfortable") }
}

enum ConnectionSettings {
    static func open(_ device: BatteryDevice? = nil) {
        let connection = device?.connection
        if connection == .usb || connection == .viaIPadUSB {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
            return
        }
        if connection == .usbReceiver {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            return
        }
        let bluetooth = connection == .bluetooth || device?.source == .bluetooth || device?.source == .logitech
        let pane = bluetooth ? "com.apple.BluetoothSettings" : "com.apple.Network-Settings.extension"
        if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) }
    }
    static func notifications() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}

struct DeviceBatterySettingsView: View {
    @Bindable var store: DeviceBatteryStore
    @Bindable var mainPreferences: PreferencesStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TabView(selection: $store.settingsTab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            devices.tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }.tag("devices")
            appearance.tabItem { Label("Appearance", systemImage: "paintpalette") }.tag("appearance")
            notifications.tabItem { Label("Notifications", systemImage: "bell") }.tag("notifications")
        }
        .padding(12)
        .disabled(store.isolated)
        .frame(width: 760, height: 590)
        .background(Palette.background)
    }
    private var general: some View {
        Form {
            Section("MacPulse") {
                Button("MacPulse settings and login item") { openSettings() }
                Toggle("Read iPhone, iPad and connected accessories", isOn: $store.includeMobile)
                Toggle("Group AirPods with their case", isOn: $store.preferences.groupAirPods)
                Toggle("Show low battery first among connected devices", isOn: $store.preferences.lowBatteryFirst)
                Text("Queried every 15 s while the panel is open, every 60 s in the background. Response time may add to this.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Connections") {
                Text("Connect your iPhone/iPad with a cable the first time and choose Trust. With Wi‑Fi sync on, it can be read over the same network. Logitech needs Input Monitoring.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Setup guide") {
                        if let url = Bundle.main.url(forResource: "Setup", withExtension: "html") { NSWorkspace.shared.open(url) }
                    }
                    Button("Bluetooth settings") { ConnectionSettings.open(store.devices.first { $0.source == .bluetooth }) }
                    Button("Input Monitoring") {
                        _ = pb_request_hid_access()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                }
            }
            if !store.issues.isEmpty {
                Section("Connection status") {
                    ForEach(store.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section {
                HStack {
                    Button(store.isRefreshing ? "Refreshing…" : "Refresh now") { store.refresh() }.disabled(store.isRefreshing)
                    Spacer()
                    Button("Clear last readings") { store.forgetOffline() }
                    if store.canUndoForget { Button("Undo") { store.undoForgetOffline() } }
                }
            }
        }.formStyle(.grouped)
    }
    private var appearance: some View {
        Form {
            Section("Panel") {
                Picker("Appearance", selection: $mainPreferences.theme) {
                    ForEach(MonitorTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Layout", selection: $store.preferences.density) {
                    ForEach(PanelDensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menu panel surface density")
                    Slider(value: $store.preferences.glassDensity, in: 0...0.65).accessibilityLabel("Menu panel surface density")
                    HStack { Text("More transparent"); Spacer(); Text("More solid") }.font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Menu bar") {
                Text("Add each device as its own widget and reorder them. Choose a battery icon, a percentage or both.").font(.callout)
                Button("Edit widgets") { MonitorStore.shared.showWidgets() }
                Text("If the selected device is offline, — appears instead of a percentage. An old reading is never shown as current.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Battery history") {
                Text("Click a device row to open its battery history. Pick 6 hours, 24 hours or 7 days; use Focus on data to zoom in on readings. Real readings are stored only on this Mac; ranges without data stay empty in the chart.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }.formStyle(.grouped)
    }
    private var notifications: some View {
        Form {
            Section("Battery alerts") {
                Toggle("Enable notifications", isOn: $store.preferences.notificationsEnabled)
                Picker("Low battery threshold", selection: $store.preferences.lowThreshold) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { Text(LocalizedFormat.percent($0)).tag($0) }
                }.disabled(!store.preferences.notificationsEnabled)
                Picker("Critical battery threshold", selection: $store.preferences.criticalThreshold) {
                    ForEach([5, 10], id: \.self) { Text(LocalizedFormat.percent($0)).tag($0) }
                }.disabled(!store.preferences.notificationsEnabled)
                Toggle("Notify when charging completes", isOn: $store.preferences.notifyFullyCharged)
                Toggle("Notification sound", isOn: $store.preferences.notificationSound)
                Text("Alerts are sent once per device and threshold, and re-arm once the battery has charged enough. Offline, hidden or old readings never trigger alerts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("System permission") {
                LabeledContent("Status", value: store.notificationStatus)
                HStack {
                    Button("Request permission") { store.requestNotifications() }.disabled(!store.preferences.notificationsEnabled)
                    Button("Notification settings") { ConnectionSettings.notifications() }
                    Spacer()
                    Button("Test notification") { store.testNotification() }.disabled(!store.preferences.notificationsEnabled)
                }
                Text("Focus modes and macOS notification settings can affect whether the banner appears. You can turn off alerts for each device separately in the Devices tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { store.refreshNotificationPermission() }
    }
    private var devices: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit your devices").font(.headline).padding(.horizontal, 10)
                List(selection: $store.selectedSettingsDevice) {
                    ForEach(store.managementDevices) { device in
                        HStack(spacing: 6) {
                            Text(store.name(device)).lineLimit(1)
                            Spacer(minLength: 0)
                            if store.preferences.options(for: device.id).favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                            if store.preferences.options(for: device.id).hidden { Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                        }
                        .tag(device.id)
                    }
                    .onMove { source, destination in
                        var order = store.managementDevices.map(\.id)
                        order.move(fromOffsets: source, toOffset: destination)
                        store.preferences.deviceOrder = order
                    }
                }
                Text("Drag to reorder. Favorites and low-battery priority come before this order in the panel.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            }.frame(width: 225)
            Divider().padding(.horizontal, 8)
            if let device = store.devices.first(where: { $0.id == store.selectedSettingsDevice }) {
                deviceEditor(device)
            } else {
                ContentUnavailableView("Select a device", systemImage: "cursorarrow.click", description: Text("Edit its name, order and battery alerts here."))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .onAppear { if store.selectedSettingsDevice == nil { store.selectedSettingsDevice = store.managementDevices.first?.id } }
    }
    private func option<Value>(_ keyPath: WritableKeyPath<DeviceOptions, Value>, for id: String) -> Binding<Value> {
        Binding(get: { store.preferences.options(for: id)[keyPath: keyPath] }, set: { value in store.setOptions(id) { $0[keyPath: keyPath] = value } })
    }
    private func deviceEditor(_ device: BatteryDevice) -> some View {
        Form {
            Section("\(store.name(device))") {
                TextField("Display name", text: option(\.alias, for: device.id), prompt: Text(device.name))
                Text("Original name: \(device.name)").font(.caption).foregroundStyle(.secondary)
                Toggle("Favorite · show at top", isOn: option(\.favorite, for: device.id))
                Toggle("Hide in panel", isOn: option(\.hidden, for: device.id))
                HStack {
                    Button { store.moveDevice(device.id, by: -1) } label: { Label("Up", systemImage: "arrow.up") }
                    Button { store.moveDevice(device.id, by: 1) } label: { Label("Down", systemImage: "arrow.down") }
                }
            }
            Section("Battery alert") {
                Toggle("Notify for this device", isOn: option(\.notifications, for: device.id))
                Picker("Low battery", selection: Binding(get: { store.preferences.options(for: device.id).lowThreshold ?? 0 }, set: { value in store.setOptions(device.id) { $0.lowThreshold = value == 0 ? nil : value } })) {
                    Text("Global threshold").tag(0)
                    ForEach([10, 15, 20, 25, 30], id: \.self) { Text(LocalizedFormat.percent($0)).tag($0) }
                }
            }
            Section("Reading") {
                LabeledContent("Connection", value: device.connection?.label ?? String(localized: "Not verified yet"))
                LabeledContent("Status", value: device.isLive() ? String(localized: "Connected") : String(localized: "Offline"))
                Button("Open battery history") { store.openHistory?(device.id) }
                if device.source != .mac { Button("Connection settings") { ConnectionSettings.open(device) } }
            }
        }.formStyle(.grouped).frame(maxWidth: .infinity)
    }
}
