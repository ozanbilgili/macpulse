import SwiftUI
import ServiceManagement
import TelemetryBridge
import MetricsCore

extension PanelTheme {
    var title: String { switch self { case .automatic: "Sistem"; case .light: "Açık"; case .dark: "Koyu" } }
    var colorScheme: ColorScheme? { switch self { case .automatic: nil; case .light: .light; case .dark: .dark } }
}
extension PanelDensity {
    var title: String { self == .compact ? "Kompakt" : "Rahat" }
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
            general.tabItem { Label("Genel", systemImage: "gearshape") }.tag("general")
            devices.tabItem { Label("Cihazlar", systemImage: "laptopcomputer.and.iphone") }.tag("devices")
            appearance.tabItem { Label("Görünüm", systemImage: "paintpalette") }.tag("appearance")
            notifications.tabItem { Label("Bildirimler", systemImage: "bell") }.tag("notifications")
        }
        .padding(12)
        .disabled(store.isolated)
        .frame(width: 760, height: 590)
        .background(Palette.background)
    }
    private var general: some View {
        Form {
            Section("MacPulse") {
                Button("MacPulse tercihleri ve giriş öğesi") { openSettings() }
                Toggle("iPhone, iPad ve bağlı aksesuarları oku", isOn: $store.includeMobile)
                Toggle("AirPods ve kutusunu grupla", isOn: $store.preferences.groupAirPods)
                Toggle("Düşük pili bağlı cihazlarda üstte göster", isOn: $store.preferences.lowBatteryFirst)
                Text("Panel açıkken 15 sn, arka planda 60 sn arayla sorgulanır. Yanıt süresi eklenebilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Bağlantılar") {
                Text("iPhone/iPad’i ilk kullanımda kabloyla bağlayıp Güven’i seç. Wi‑Fi eşzamanlama açıkken aynı ağdan okunabilir. Logitech için Giriş İzleme gerekir.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Kurulum rehberi") {
                        if let url = Bundle.main.url(forResource: "Kurulum", withExtension: "html") { NSWorkspace.shared.open(url) }
                    }
                    Button("Bluetooth ayarları") { ConnectionSettings.open(store.devices.first { $0.source == .bluetooth }) }
                    Button("Giriş İzleme") {
                        _ = pb_request_hid_access()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                }
            }
            if !store.issues.isEmpty {
                Section("Bağlantı durumu") {
                    ForEach(store.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section {
                HStack {
                    Button(store.isRefreshing ? "Yenileniyor…" : "Şimdi yenile") { store.refresh() }.disabled(store.isRefreshing)
                    Spacer()
                    Button("Son ölçümleri temizle") { store.forgetOffline() }
                    if store.canUndoForget { Button("Geri al") { store.undoForgetOffline() } }
                }
            }
        }.formStyle(.grouped)
    }
    private var appearance: some View {
        Form {
            Section("Panel") {
                Picker("Görünüm", selection: $mainPreferences.theme) {
                    ForEach(MonitorTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Yerleşim", selection: $store.preferences.density) {
                    ForEach(PanelDensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menü panelinin yüzey yoğunluğu")
                    Slider(value: $store.preferences.glassDensity, in: 0...0.65).accessibilityLabel("Menü panelinin yüzey yoğunluğu")
                    HStack { Text("Daha saydam"); Spacer(); Text("Daha yoğun") }.font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Menü çubuğu") {
                Text("Her cihazı ayrı widget olarak ekleyip sıralayabilirsin. Pil simgesi, yüzde veya ikisini seç.").font(.callout)
                Button("Widget'ları düzenle") { MonitorStore.shared.showWidgets() }
                Text("Seçilen cihaz çevrimdışıysa yüzde yerine — görünür. Eski ölçüm güncelmiş gibi gösterilmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Pil geçmişi") {
                Text("Cihaz satırına tıklayarak pil geçmişini aç. 6 saat, 24 saat veya 7 gün seç; Veriye odaklan ile ölçümlere yakınlaş. Gerçek ölçümler yalnızca bu Mac’te saklanır; veri alınamayan aralıklar grafikte boş bırakılır.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }.formStyle(.grouped)
    }
    private var notifications: some View {
        Form {
            Section("Pil uyarıları") {
                Toggle("Bildirimleri etkinleştir", isOn: $store.preferences.notificationsEnabled)
                Picker("Düşük pil eşiği", selection: $store.preferences.lowThreshold) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { Text("%\($0)").tag($0) }
                }.disabled(!store.preferences.notificationsEnabled)
                Picker("Kritik pil eşiği", selection: $store.preferences.criticalThreshold) {
                    ForEach([5, 10], id: \.self) { Text("%\($0)").tag($0) }
                }.disabled(!store.preferences.notificationsEnabled)
                Toggle("Şarj tamamlandığında bildir", isOn: $store.preferences.notifyFullyCharged)
                Toggle("Bildirim sesi", isOn: $store.preferences.notificationSound)
                Text("Uyarılar cihaz ve eşik başına bir kez gönderilir; pil yeterince yükselince yeniden hazır olur. Çevrimdışı, gizli veya eski ölçümler uyarı oluşturmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sistem izni") {
                LabeledContent("Durum", value: store.notificationStatus)
                HStack {
                    Button("İzin iste") { store.requestNotifications() }.disabled(!store.preferences.notificationsEnabled)
                    Button("Bildirim ayarları") { ConnectionSettings.notifications() }
                    Spacer()
                    Button("Test bildirimi") { store.testNotification() }.disabled(!store.preferences.notificationsEnabled)
                }
                Text("Odak modu ve macOS bildirim ayarları banner’ın görünmesini etkileyebilir. Cihazlar sekmesinde her cihazın uyarısını ayrıca kapatabilirsin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { store.refreshNotificationPermission() }
    }
    private var devices: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cihazlarını düzenle").font(.headline).padding(.horizontal, 10)
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
                Text("Sıralamak için sürükle. Favoriler ve düşük pil önceliği panelde bu sıranın önüne geçer.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            }.frame(width: 225)
            Divider().padding(.horizontal, 8)
            if let device = store.devices.first(where: { $0.id == store.selectedSettingsDevice }) {
                deviceEditor(device)
            } else {
                ContentUnavailableView("Bir cihaz seç", systemImage: "cursorarrow.click", description: Text("Adını, sırasını ve pil uyarılarını burada düzenle."))
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
                TextField("Görünen ad", text: option(\.alias, for: device.id), prompt: Text(device.name))
                Text("Asıl ad: \(device.name)").font(.caption).foregroundStyle(.secondary)
                Toggle("Favori · üstte göster", isOn: option(\.favorite, for: device.id))
                Toggle("Panelde gizle", isOn: option(\.hidden, for: device.id))
                HStack {
                    Button { store.moveDevice(device.id, by: -1) } label: { Label("Yukarı", systemImage: "arrow.up") }
                    Button { store.moveDevice(device.id, by: 1) } label: { Label("Aşağı", systemImage: "arrow.down") }
                }
            }
            Section("Pil uyarısı") {
                Toggle("Bu cihaz için bildir", isOn: option(\.notifications, for: device.id))
                Picker("Düşük pil", selection: Binding(get: { store.preferences.options(for: device.id).lowThreshold ?? 0 }, set: { value in store.setOptions(device.id) { $0.lowThreshold = value == 0 ? nil : value } })) {
                    Text("Genel eşik").tag(0)
                    ForEach([10, 15, 20, 25, 30], id: \.self) { Text("%\($0)").tag($0) }
                }
            }
            Section("Ölçüm") {
                LabeledContent("Bağlantı", value: device.connection?.label ?? "Henüz doğrulanmadı")
                LabeledContent("Durum", value: device.isLive() ? "Bağlı" : "Çevrimdışı")
                Button("Pil geçmişini aç") { store.openHistory?(device.id) }
                if device.source != .mac { Button("Bağlantı ayarları") { ConnectionSettings.open(device) } }
            }
        }.formStyle(.grouped).frame(maxWidth: .infinity)
    }
}
