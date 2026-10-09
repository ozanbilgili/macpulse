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
                    Text("Pil").font(.title2.weight(.semibold))
                    Text(batteries.isPaused ? "İzleme duraklatıldı · son ölçümler" : "Mac’in ve bağlı cihazların pil durumu")
                        .font(.callout).foregroundStyle(Palette.secondary)
                }
                Spacer()
                BatteryRefreshButton(store: store)
                Button("Cihaz ayarları") { store.showBatterySettings() }
                Button("Widget’lar") { store.showWidgets() }
            }

            if let mac { MacBatteryOverview(store: store, device: mac) }

            VStack(alignment: .leading, spacing: 12) {
                BatterySectionHeading(title: "Bağlı cihazlar", count: deviceCount(liveGroups))
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
                    BatteryDisclosure(title: "Son görülen cihazlar", count: deviceCount(offlineGroups), expanded: $showOffline)
                    if showOffline {
                        Text(batteries.isPaused ? "İzleme sürdürülene kadar bu değerler güncellenmez." : "Bu cihazlar şu an bağlı değil. Yüzdeler son kayıtlı ölçüme aittir.")
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
                    BatteryDisclosure(title: "Mac pil ayrıntıları ve grafik", expanded: $showDetails)
                    if showDetails { DetailView(tab: .battery, snapshot: snapshot, history: store.history) }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    BatteryRefreshStatus(store: store)
                    Spacer()
                    Button { showConnections.toggle() } label: {
                        Label("Bağlantı bilgileri", systemImage: showConnections ? "chevron.up" : "info.circle")
                    }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                }.font(.caption)
                if showConnections {
                    Text("Bluetooth pil seviyesi macOS kaydından gelir; cihazın sensör zamanı doğrulanamaz. Logitech pili HID++ ile okunur. Mobil güç değeri bataryanın net akışıdır.")
                    if let migration = batteries.migration, !migration.files.isEmpty {
                        Label("PilBar’dan \(migration.deviceCount) cihaz ve \(migration.historyPointCount) ölçüm aktarıldı", systemImage: "checkmark.circle")
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
                    Text("Bu Mac").font(.headline)
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
                }.buttonStyle(.plain).help(status.tooltip).accessibilityLabel("Bu Mac, pil geçmişini aç").accessibilityValue(status.accessibilityStatus)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 102)
            VStack(alignment: .leading, spacing: 18) {
                BatteryFact(title: "Güç kaynağı", value: metrics.map { $0.onAC ? "Adaptör" : "Pil" } ?? "—", symbol: "powerplug")
                BatteryFact(title: metrics?.charging == true ? "Tam doluma kalan" : "Tahmini kalan süre",
                            value: metrics?.minutesRemaining.flatMap { $0 >= 0 ? MetricFormat.duration(Double($0) * 60) : nil } ?? "Hesaplanmıyor", symbol: "clock")
            }.frame(width: 175, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                BatteryFact(title: "Düşük güç modu", value: metrics.map { $0.lowPowerMode ? "Açık" : "Kapalı" } ?? "—", symbol: "leaf")
                BatteryFact(title: "Son ölçüm", value: device.measuredAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—", symbol: "waveform.path")
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
                        if status.charging { Label("Şarj oluyor", systemImage: "bolt.fill").font(.caption).foregroundStyle(Palette.battery) }
                    }
                    BatteryLevelBar(level: status.level, charging: status.charging, live: status.live).frame(height: 5)
                    Text(status.charging ? group.primary.connection?.label ?? "Bağlı" : status.subtitle)
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
                    if let power = status.power { Text(power.powerText).font(.caption).foregroundStyle(Palette.secondary).help(power.powerHelp) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help(status.tooltip)
                .accessibilityLabel(store.deviceBatteries.name(group.primary) + ", pil geçmişini aç").accessibilityValue(status.accessibilityStatus)
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
                    Text(device.id.hasSuffix(":case") ? "Şarj kutusu" : store.deviceBatteries.name(device))
                    Text(status.subtitle).font(.caption).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(status.percentage).fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain).help(status.tooltip)
            .accessibilityLabel(store.deviceBatteries.name(device) + ", pil geçmişini aç").accessibilityValue(status.accessibilityStatus)
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
                Text(batteries.isPaused ? "Son pil ölçümleri" : "Güncel piller").font(.callout.weight(.semibold))
                Spacer()
                BatteryRefreshButton(store: store)
                Button { store.showBatterySettings() } label: { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Cihaz ayarları").accessibilityLabel("Cihaz ayarları").accessibilityIdentifier("panel-settings")
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(batteries.liveGroups) { group in menuGroup(group) }
                    if batteries.displayedDevices.isEmpty { BatteryEmptyState(store: store).padding(.vertical, 16) }
                    if !batteries.offlineGroups.isEmpty {
                        if !batteries.liveGroups.isEmpty { Divider().padding(.vertical, 8) }
                        BatteryDisclosure(title: "Son görülen cihazlar", count: deviceCount(batteries.offlineGroups), expanded: $showOffline)
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
                        .accessibilityLabel(batteries.name(group.primary) + " kutu ayrıntıları")
                        .accessibilityValue(batteries.expandedGroups.contains(group.id) ? "Açık" : "Kapalı")
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
                    Text(companionStatus.map { status.subtitle + " · Kutu " + $0.percentage + ($0.live ? "" : " (son ölçüm)") } ?? status.power?.powerText ?? status.subtitle)
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
        .accessibilityLabel(store.deviceBatteries.name(device) + ", pil geçmişini aç")
        .accessibilityValue(status.accessibilityStatus + (companionStatus.map { ", kutu " + $0.accessibilityStatus } ?? ""))
        .contextMenu {
            batteryContextMenu(device, store: store)
            if let companion { Button("Kutu pil geçmişi") { store.showBatteryHistory(companion.id) } }
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
    var percentage: String { level.map { (device.approximate == true ? "≈" : "") + "\($0)%" } ?? "—" }
    var subtitle: String {
        if !live {
            return device.measuredAt.map { "Son ölçüm " + $0.formatted(date: Calendar.current.isDateInToday($0) ? .omitted : .abbreviated, time: .shortened) } ?? "Ölçüm zamanı bilinmiyor"
        }
        if level == nil { return "Pil bilgisi bekleniyor" }
        if let macMetrics { return macMetrics.stateLabel }
        if charging { return "Şarj oluyor" }
        if let level, level <= (store.deviceBatteries.preferences.options(for: device.id).lowThreshold ?? store.deviceBatteries.preferences.lowThreshold) { return "Düşük pil" }
        return device.connection == .internalBattery ? "Pille çalışıyor" : device.connection?.label ?? "Bağlı"
    }
    var accessibilityStatus: String {
        (level.map { "Yüzde \($0)" } ?? "Pil bilinmiyor") + ", " + subtitle
        + (live ? ", bağlı" : store.deviceBatteries.isPaused ? ", duraklatıldı" : ", çevrimdışı")
        + (power.map { ", " + $0.powerText } ?? "")
    }
    var tooltip: String {
        store.deviceBatteries.name(device) + "\n" + accessibilityStatus + "\n"
        + (device.connection?.label ?? "Bağlantı henüz doğrulanmadı") + (device.telemetry.map { " · " + $0.label } ?? "")
        + "\nSon ölçüm: " + (device.measuredAt?.formatted(date: .abbreviated, time: .shortened) ?? "Bilinmiyor")
        + (device.approximate == true ? "\nYaklaşık pil seviyesi" : "")
        + (power.map { "\n" + $0.powerHelp } ?? "") + "\nPil geçmişi için tıkla"
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
            .accessibilityLabel(store.deviceBatteries.name(device) + ", cihaz işlemleri")
    }
}

private struct BatteryRefreshButton: View {
    let store: MonitorStore
    var body: some View {
        Button { store.refreshBatteryDevices() } label: { Image(systemName: "arrow.clockwise").frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(store.deviceBatteries.isRefreshing || store.deviceBatteries.isolated || store.paused)
            .help("Pilleri şimdi yenile").accessibilityLabel(store.deviceBatteries.isRefreshing ? "Piller yenileniyor" : "Pilleri yenile").accessibilityIdentifier("panel-refresh")
    }
}

private struct BatteryRefreshStatus: View {
    let store: MonitorStore
    private var batteries: DeviceBatteryStore { store.deviceBatteries }
    var body: some View {
        HStack(spacing: 6) {
            if !batteries.issues.isEmpty {
                Button { store.showBatterySettings() } label: { Label("Bağlantıyı kontrol et", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.disk) }
                    .buttonStyle(.plain).help(batteries.issues.joined(separator: "\n"))
            } else {
                Text(batteries.isPaused ? "İzleme duraklatıldı" : batteries.isRefreshing ? "Piller yenileniyor…" : batteries.lastRefresh.map { "Son kontrol " + $0.formatted(date: .omitted, time: .shortened) } ?? "İlk ölçüm bekleniyor")
            }
        }.help("Panel açıkken 15, arka planda 60 saniyede bir sorgulanır. Cihazın yanıt süresi eklenebilir.")
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
        }.buttonStyle(.plain).accessibilityValue(expanded ? "Açık" : "Kapalı")
    }
}

private struct BatteryEmptyState: View {
    let store: MonitorStore
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 23)).foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.deviceBatteries.isPaused ? "İzleme duraklatıldı" : store.deviceBatteries.isRefreshing ? "Cihazlar kontrol ediliyor…" : "Bağlı cihaz pili görünmüyor").font(.callout.weight(.medium))
                Text("Cihazları ve bağlantıları ayarlardan kontrol edebilirsin.").font(.caption).foregroundStyle(Palette.secondary)
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
    Button("Pil geçmişi") { store.showBatteryHistory(device.id) }
    Button("Menü çubuğunda göster") { addBatteryWidget(device, store: store) }
    Button(store.deviceBatteries.preferences.options(for: device.id).favorite ? "Favorilerden çıkar" : "Favorilere ekle") { store.deviceBatteries.setOptions(device.id) { $0.favorite.toggle() } }
    Button("Cihazı düzenle") { store.deviceBatteries.selectedSettingsDevice = device.id; store.deviceBatteries.settingsTab = "devices"; store.showBatterySettings() }
    if device.source != .mac { Button("Bağlantı ayarları") { ConnectionSettings.open(device) } }
    Button("Panelde gizle") { store.deviceBatteries.setOptions(device.id) { $0.hidden = true } }
}
