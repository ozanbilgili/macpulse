import SwiftUI
import MetricsCore

struct DeviceBatteryDashboard: View {
    let store: MonitorStore
    @State private var showOffline = false
    @State private var showDetails = false
    @State private var showConnections = false
    private var batteries: DeviceBatteryStore { store.deviceBatteries }
    private var mac: BatteryDevice? { batteries.displayedDevices.first { $0.source == .mac } }
    private var liveGroups: [BatteryDisplayGroup] { batteries.liveGroups.filter { $0.primary.source != .mac } }
    private var offlineGroups: [BatteryDisplayGroup] { batteries.offlineGroups.filter { $0.primary.source != .mac } }
    private let columns = [GridItem(.adaptive(minimum: 270), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Battery").font(.title2.weight(.semibold))
                    Text(batteries.isPaused ? "Monitoring paused · last readings" : "Battery status of your Mac and connected devices")
                        .font(.callout).foregroundStyle(Palette.secondary)
                }
                Spacer()
                BatteryRefreshButton(store: store)
                Button("Device settings") { store.showBatterySettings() }
                Button("Widgets") { store.showWidgets() }
            }

            if let mac { MacBatteryOverview(store: store, device: mac) }

            VStack(alignment: .leading, spacing: 12) {
                BatterySectionHeading(title: String(localized: "Connected devices"), count: deviceCount(liveGroups))
                if liveGroups.isEmpty {
                    BatteryEmptyState(store: store)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(liveGroups) { group in BatteryDeviceCard(store: store, group: group) }
                    }
                }
            }

            if !offlineGroups.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    BatteryDisclosure(title: String(localized: "Recently seen devices"), count: deviceCount(offlineGroups), expanded: $showOffline)
                    if showOffline {
                        Text(batteries.isPaused ? "These values won't update until monitoring resumes." : "These devices aren't connected right now. Percentages are from the last recorded reading.")
                            .font(.callout).foregroundStyle(Palette.secondary)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(offlineGroups) { group in BatteryDeviceCard(store: store, group: group) }
                        }
                    }
                }
                .padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            }

            if mac != nil, let snapshot = store.snapshot {
                VStack(alignment: .leading, spacing: 14) {
                    BatteryDisclosure(title: String(localized: "Mac battery details and chart"), expanded: $showDetails)
                    if showDetails { DetailView(tab: .battery, snapshot: snapshot, history: store.history) }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    BatteryRefreshStatus(store: store)
                    Spacer()
                    Button { showConnections.toggle() } label: {
                        Label("Connection details", systemImage: showConnections ? "chevron.up" : "info.circle")
                    }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                }.font(.caption)
                if showConnections {
                    Text("Bluetooth battery levels come from the macOS record; the device's sensor time can't be verified. Logitech batteries are read over HID++. Mobile power is the battery's net flow.")
                    if let migration = batteries.migration, !migration.files.isEmpty {
                        Label("Imported \(migration.deviceCount) devices and \(migration.historyPointCount) readings from PilBar", systemImage: "checkmark.circle")
                    }
                    ForEach(batteries.issues, id: \.self) { Label($0, systemImage: "info.circle") }
                }
            }.font(.caption).foregroundStyle(Palette.secondary)
        }
    }
}

private struct MacBatteryOverview: View {
    let store: MonitorStore
    let device: BatteryDevice
    private var status: BatteryDeviceStatus { .init(device: device, store: store) }
    private var metrics: BatteryMetrics? { status.macMetrics }

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    Image(systemName: "laptopcomputer").foregroundStyle(Palette.secondary)
                    Text("This Mac").font(.headline)
                    Text(store.deviceBatteries.name(device)).font(.callout).foregroundStyle(Palette.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    BatteryDeviceMenu(store: store, device: device)
                }
                Button { store.showBatteryHistory(device.id) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(status.percentage).font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(status.live ? metrics?.stateLabel ?? status.subtitle : status.subtitle)
                                .font(.callout).foregroundStyle(Palette.secondary)
                        }
                        BatteryLevelBar(level: status.level, charging: status.charging, live: status.live).frame(height: 7)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help(status.tooltip).accessibilityLabel("This Mac, open battery history").accessibilityValue(status.accessibilityStatus)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 102)
            VStack(alignment: .leading, spacing: 18) {
                BatteryFact(title: String(localized: "Power source"), value: metrics.map { $0.onAC ? String(localized: "Adapter") : String(localized: "Battery") } ?? "—", symbol: "powerplug")
                BatteryFact(title: metrics?.charging == true ? String(localized: "Until full") : String(localized: "Estimated time remaining"),
                            value: metrics?.minutesRemaining.flatMap { $0 >= 0 ? MetricFormat.duration(Double($0) * 60) : nil } ?? String(localized: "Not calculated"), symbol: "clock")
            }.frame(width: 175, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                BatteryFact(title: String(localized: "Low Power Mode"), value: metrics.map { $0.lowPowerMode ? String(localized: "On") : String(localized: "Off") } ?? "—", symbol: "leaf")
                BatteryFact(title: String(localized: "Last measured"), value: device.measuredAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—", symbol: "waveform.path")
            }.frame(width: 160, alignment: .leading)
        }
        .padding(24).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct BatteryFact: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(Palette.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }.accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(value)
    }
}

private struct BatteryDeviceCard: View {
    let store: MonitorStore
    let group: BatteryDisplayGroup
    private var status: BatteryDeviceStatus { .init(device: group.primary, store: store) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                DeviceBatteryGlyph(device: group.primary, live: status.live, size: 34)
                Text(store.deviceBatteries.name(group.primary)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
                BatteryDeviceMenu(store: store, device: group.primary)
            }
            Button { store.showBatteryHistory(group.primary.id) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(status.percentage).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                        Spacer()
                        if status.charging { Label("Charging", systemImage: "bolt.fill").font(.caption).foregroundStyle(Palette.battery) }
                    }
                    BatteryLevelBar(level: status.level, charging: status.charging, live: status.live).frame(height: 5)
                    Text(status.charging ? group.primary.connection?.label ?? String(localized: "Connected") : status.subtitle)
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
                    if let power = status.power { Text(power.powerText).font(.caption).foregroundStyle(Palette.secondary).help(power.powerHelp) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help(status.tooltip)
                .accessibilityLabel(String(localized: "\(store.deviceBatteries.name(group.primary)), open battery history")).accessibilityValue(status.accessibilityStatus)
            ForEach(group.devices.filter { $0.id != group.primary.id }) { device in
                Divider().opacity(0.5)
                BatteryCompanionRow(store: store, device: device)
            }
        }
        .foregroundStyle(.primary.opacity(status.live ? 1 : 0.7))
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BatteryCompanionRow: View {
    let store: MonitorStore
    let device: BatteryDevice
    private var status: BatteryDeviceStatus { .init(device: device, store: store) }
    var body: some View {
        Button { store.showBatteryHistory(device.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: batteryGlyph(device)).foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.id.hasSuffix(":case") ? String(localized: "Charging case") : store.deviceBatteries.name(device))
                    Text(status.subtitle).font(.caption).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(status.percentage).fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain).help(status.tooltip)
            .accessibilityLabel(String(localized: "\(store.deviceBatteries.name(device)), open battery history")).accessibilityValue(status.accessibilityStatus)
            .contextMenu { batteryContextMenu(device, store: store) }
    }
}

enum DeviceBatteryPanelLayout {
    static func width(_ density: PanelDensity) -> CGFloat { density == .compact ? 400 : 424 }
    static func rowHeight(_ density: PanelDensity) -> CGFloat { density == .compact ? 50 : 58 }
}

struct DeviceBatteryQuickView: View {
    let store: MonitorStore
    @State private var showOffline = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var batteries: DeviceBatteryStore { store.deviceBatteries }
    private var listHeight: CGFloat {
        let groups = batteries.liveGroups + (showOffline ? batteries.offlineGroups : [])
        let rows = groups.reduce(0) { count, group in
            count + 1 + (batteries.expandedGroups.contains(group.id) ? group.devices.count - 1 : 0)
        }
        return CGFloat(rows) * DeviceBatteryPanelLayout.rowHeight(batteries.preferences.density)
            + (batteries.offlineGroups.isEmpty ? 0 : 52 + (batteries.liveGroups.isEmpty ? 0 : 17))
            + (batteries.displayedDevices.isEmpty ? 100 : 0) + 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(batteries.isPaused ? "Last battery readings" : "Current batteries").font(.callout.weight(.semibold))
                Spacer()
                BatteryRefreshButton(store: store)
                Button { store.showBatterySettings() } label: { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Device settings").accessibilityLabel("Device settings").accessibilityIdentifier("panel-settings")
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(batteries.liveGroups) { group in menuGroup(group) }
                    if batteries.displayedDevices.isEmpty { BatteryEmptyState(store: store).padding(.vertical, 16) }
                    if !batteries.offlineGroups.isEmpty {
                        if !batteries.liveGroups.isEmpty { Divider().padding(.vertical, 8) }
                        BatteryDisclosure(title: String(localized: "Recently seen devices"), count: deviceCount(batteries.offlineGroups), expanded: $showOffline)
                            .padding(.horizontal, 12).padding(.vertical, 12)
                        if showOffline {
                            ForEach(batteries.offlineGroups) { group in menuGroup(group) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
            .frame(height: min(listHeight, max(100, MenuPanelLayout.screen.height - 340)))
            .background(Palette.card.opacity(reduceTransparency ? 1 : 0.55 + batteries.preferences.glassDensity * 0.65), in: RoundedRectangle(cornerRadius: 12))
            BatteryRefreshStatus(store: store).font(.caption).foregroundStyle(Palette.secondary)
        }
        .frame(width: DeviceBatteryPanelLayout.width(batteries.preferences.density))
    }

    private func menuGroup(_ group: BatteryDisplayGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                DeviceBatteryRow(store: store, device: group.primary, companion: group.devices.first { $0.id != group.primary.id })
                if group.devices.count > 1 {
                    Button { batteries.toggleGroup(group.id) } label: {
                        Image(systemName: batteries.expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium)).frame(width: 28, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                        .accessibilityLabel(String(localized: "\(batteries.name(group.primary)) case details"))
                        .accessibilityValue(batteries.expandedGroups.contains(group.id) ? "Expanded" : "Collapsed")
                } else {
                    Color.clear.frame(width: 28).accessibilityHidden(true)
                }
            }
            if batteries.expandedGroups.contains(group.id) {
                ForEach(group.devices.filter { $0.id != group.primary.id }) { device in
                    HStack(spacing: 0) {
                        DeviceBatteryRow(store: store, device: device, companion: nil).padding(.leading, 18)
                        Color.clear.frame(width: 28).accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

private struct DeviceBatteryRow: View {
    let store: MonitorStore
    let device: BatteryDevice
    let companion: BatteryDevice?
    @State private var hovered = false
    private var status: BatteryDeviceStatus { .init(device: device, store: store) }
    private var companionStatus: BatteryDeviceStatus? { companion.map { .init(device: $0, store: store) } }

    var body: some View {
        Button { store.showBatteryHistory(device.id) } label: {
            HStack(spacing: 10) {
                DeviceBatteryGlyph(device: device, live: status.live)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.deviceBatteries.name(device)).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(companionStatus.map { $0.live ? String(localized: "\(status.subtitle) · Case \($0.percentage)") : String(localized: "\(status.subtitle) · Case \($0.percentage) (last reading)") } ?? status.power?.powerText ?? status.subtitle)
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.tail)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        if status.charging { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(Palette.battery) }
                        Text(status.percentage).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    }
                    BatteryLevelBar(level: status.level, charging: status.charging, live: status.live).frame(width: 48, height: 4)
                }.frame(minWidth: 50, alignment: .trailing)
            }
            .foregroundStyle(.primary.opacity(status.live ? 1 : 0.65))
            .padding(.horizontal, 12).frame(height: DeviceBatteryPanelLayout.rowHeight(store.deviceBatteries.preferences.density))
            .contentShape(Rectangle()).background(.primary.opacity(hovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.help(status.tooltip)
        .accessibilityLabel(String(localized: "\(store.deviceBatteries.name(device)), open battery history"))
        .accessibilityValue(status.accessibilityStatus + (companionStatus.map { ", " + String(localized: "case \($0.accessibilityStatus)") } ?? ""))
        .contextMenu {
            batteryContextMenu(device, store: store)
            if let companion { Button("Case battery history") { store.showBatteryHistory(companion.id) } }
        }
    }
}

/// Uses the existing freshness rules for every surface; cached values never imply a live charge or power reading.
@MainActor private struct BatteryDeviceStatus {
    let device: BatteryDevice
    let store: MonitorStore
    var live: Bool { !store.deviceBatteries.isPaused && device.isLive(at: store.deviceBatteries.now) }
    var level: Int? { device.displayLevel(at: store.deviceBatteries.now) }
    var charging: Bool { live && level != nil && device.isCharging }
    var power: BatteryPowerReading? { live ? device.displayPower(at: store.deviceBatteries.now) : nil }
    var macMetrics: BatteryMetrics? {
        guard device.source == .mac, live, let snapshot = store.snapshot,
              (-2..<Double(max(20, store.effectiveInterval * 3))).contains(store.deviceBatteries.now.timeIntervalSince(snapshot.date)) else { return nil }
        return snapshot.battery
    }
    var percentage: String { level.map { (device.approximate == true ? "≈" : "") + LocalizedFormat.percent($0) } ?? "—" }
    var subtitle: String {
        if !live {
            return device.measuredAt.map { String(localized: "Last measured \($0.formatted(date: Calendar.current.isDateInToday($0) ? .omitted : .abbreviated, time: .shortened))") } ?? String(localized: "Measurement time unknown")
        }
        if level == nil { return String(localized: "Waiting for battery info") }
        if let macMetrics { return macMetrics.stateLabel }
        if charging { return String(localized: "Charging") }
        if let level, level <= (store.deviceBatteries.preferences.options(for: device.id).lowThreshold ?? store.deviceBatteries.preferences.lowThreshold) { return String(localized: "Low battery") }
        return device.connection == .internalBattery ? String(localized: "On battery") : device.connection?.label ?? String(localized: "Connected")
    }
    var accessibilityStatus: String {
        let state = live ? String(localized: "connected") : store.deviceBatteries.isPaused ? String(localized: "paused") : String(localized: "offline")
        return ([level.map { LocalizedFormat.percent($0) } ?? String(localized: "Battery unknown"), subtitle, state] + (power.map { [$0.powerText] } ?? []))
            .joined(separator: ", ")
    }
    var tooltip: String {
        let measured = device.measuredAt?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Unknown")
        var lines = [store.deviceBatteries.name(device), accessibilityStatus,
                     (device.connection?.label ?? String(localized: "Connection not verified yet")) + (device.telemetry.map { " · " + $0.label } ?? ""),
                     String(localized: "Last measured: \(measured)")]
        if device.approximate == true { lines.append(String(localized: "Approximate battery level")) }
        if let power { lines.append(power.powerHelp) }
        lines.append(String(localized: "Click for battery history"))
        return lines.joined(separator: "\n")
    }
}

private struct BatteryLevelBar: View {
    let level: Int?
    let charging: Bool
    let live: Bool
    private var tint: Color {
        guard live, let level else { return Palette.secondary.opacity(0.45) }
        if charging { return Palette.battery }
        return level <= 20 ? Palette.limitCritical : level <= 40 ? Palette.limitWarning : Palette.battery
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.07))
                if let level { Capsule().fill(tint).frame(width: geometry.size.width * CGFloat(level) / 100) }
            }
        }.accessibilityHidden(true)
    }
}

private struct DeviceBatteryGlyph: View {
    let device: BatteryDevice
    let live: Bool
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: batteryGlyph(device)).font(.system(size: size * 0.55)).symbolRenderingMode(.hierarchical)
            .foregroundStyle(Palette.secondary.opacity(live ? 1 : 0.7))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct BatteryDeviceMenu: View {
    let store: MonitorStore
    let device: BatteryDevice
    var body: some View {
        Menu { batteryContextMenu(device, store: store) } label: { Image(systemName: "ellipsis").frame(width: 20, height: 24).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Palette.secondary)
            .accessibilityLabel(String(localized: "\(store.deviceBatteries.name(device)), device actions"))
    }
}

private struct BatteryRefreshButton: View {
    let store: MonitorStore
    var body: some View {
        Button { store.refreshBatteryDevices() } label: { Image(systemName: "arrow.clockwise").frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(store.deviceBatteries.isRefreshing || store.deviceBatteries.isolated || store.paused)
            .help("Refresh batteries now").accessibilityLabel(store.deviceBatteries.isRefreshing ? "Refreshing batteries" : "Refresh batteries").accessibilityIdentifier("panel-refresh")
    }
}

private struct BatteryRefreshStatus: View {
    let store: MonitorStore
    private var batteries: DeviceBatteryStore { store.deviceBatteries }
    var body: some View {
        HStack(spacing: 6) {
            if !batteries.issues.isEmpty {
                Button { store.showBatterySettings() } label: { Label("Check connection", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.disk) }
                    .buttonStyle(.plain).help(batteries.issues.joined(separator: "\n"))
            } else {
                Text(batteries.isPaused ? String(localized: "Monitoring paused") : batteries.isRefreshing ? String(localized: "Refreshing batteries…") : batteries.lastRefresh.map { String(localized: "Last checked \($0.formatted(date: .omitted, time: .shortened))") } ?? String(localized: "Waiting for first reading"))
            }
        }.help("Queried every 15 seconds while the panel is open, every 60 seconds in the background. The device's response time may add to this.")
    }
}

private struct BatterySectionHeading: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            Text("\(count)").font(.callout).monospacedDigit().foregroundStyle(Palette.secondary)
        }
    }
}

private struct BatteryDisclosure: View {
    let title: String
    var count: Int? = nil
    @Binding var expanded: Bool
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let count { Text("\(count)").font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.secondary) }
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.secondary)
            }.frame(minHeight: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}

private struct BatteryEmptyState: View {
    let store: MonitorStore
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 23)).foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.deviceBatteries.isPaused ? "Monitoring paused" : store.deviceBatteries.isRefreshing ? "Checking devices…" : "No connected device batteries").font(.callout.weight(.medium))
                Text("You can check devices and connections in settings.").font(.caption).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

private func deviceCount(_ groups: [BatteryDisplayGroup]) -> Int { groups.reduce(0) { $0 + $1.devices.count } }

func batteryGlyph(_ device: BatteryDevice) -> String {
    let name = device.name.lowercased()
    if device.source == .mac { return "laptopcomputer" }
    if device.id.hasPrefix("watch:") || name.contains("watch") { return "applewatch" }
    if device.source == .pencil || name.contains("pencil") { return "applepencil" }
    if name.contains("airpods") { return device.id.hasSuffix(":case") ? "airpods.chargingcase" : "airpods" }
    if name.contains("ipad") { return "ipad" }
    if device.id.hasPrefix("ios:") || name.contains("iphone") { return "iphone" }
    if name.contains("keys") || name.contains("keyboard") { return "keyboard" }
    if name.contains("master") || name.contains("mouse") { return "computermouse" }
    return "battery.100percent"
}
@MainActor func addBatteryWidget(_ device: BatteryDevice, store: MonitorStore) {
    let widget = device.source == .mac ? MenuWidget(.battery) : MenuWidget(.deviceBattery, deviceID: device.id)
    store.preferences.setWidgets(store.preferences.manualWidgets(for: store.usage) + [widget])
}
@MainActor @ViewBuilder private func batteryContextMenu(_ device: BatteryDevice, store: MonitorStore) -> some View {
    Button("Battery history") { store.showBatteryHistory(device.id) }
    Button("Show in menu bar") { addBatteryWidget(device, store: store) }
    Button(store.deviceBatteries.preferences.options(for: device.id).favorite ? "Remove from favorites" : "Add to favorites") { store.deviceBatteries.setOptions(device.id) { $0.favorite.toggle() } }
    Button("Edit device") { store.deviceBatteries.selectedSettingsDevice = device.id; store.deviceBatteries.settingsTab = "devices"; store.showBatterySettings() }
    if device.source != .mac { Button("Connection settings") { ConnectionSettings.open(device) } }
    Button("Hide in panel") { store.deviceBatteries.setOptions(device.id) { $0.hidden = true } }
}
