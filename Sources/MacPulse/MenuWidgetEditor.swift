import SwiftUI
import MetricsCore

struct MenuWidgetEditor: View {
    @Bindable var store: MonitorStore
    @State private var catalogScope = "Tümü"
    private var selected: [MenuWidget] { store.preferences.manualWidgets(for: store.usage) }
    private var displayed: [MenuWidget] { store.preferences.widgets(for: store.usage) }
    private var automatic: Bool { store.preferences.menuWidgetSelection == .topFourFiveHour }
    private var catalog: [MenuWidget] {
        let system = MenuMetric.allCases.compactMap { MenuWidgetKind(rawValue: $0.rawValue).map { MenuWidget($0) } }
        let accounts = Set(store.usage.states.filter { $0.account.provider == .claude }.map(\.account.n) + selected.filter { $0.kind == .claude }.map(\.account) + [1]).sorted()
        return system + accounts.map { MenuWidget(.claude, account: $0) } + [MenuWidget(.codex), MenuWidget(.openRouter)]
            + store.deviceBatteries.managementDevices.filter { $0.source != .mac }.map { MenuWidget(.deviceBattery, deviceID: $0.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Menü çubuğu widget'ları", systemImage: "menubar.rectangle").font(.title2.weight(.semibold))
                    Text("Görmek istediklerini seç. Sırayı ve her hesabın görünümünü ayrı düzenle.").font(.callout).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("Kullanım ayrıntıları") { store.showUsage() }
            }
            Picker("Menü çubuğunda göster", selection: Binding(get: { store.preferences.menuWidgetSelection }, set: { store.preferences.menuWidgetSelection = $0 })) {
                ForEach(MenuWidgetSelection.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            preview
            if automatic {
                automaticAccounts
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Seçili widget'lar · \(selected.count)").font(.headline)
                            Spacer()
                            Button("Widget ekle") { withAnimation { proxy.scrollTo("widget-catalog", anchor: .top) } }.buttonStyle(.link)
                            Button("Yalnız simge") { store.preferences.setWidgets([]) }.buttonStyle(.link).disabled(selected.isEmpty)
                        }
                        if selected.isEmpty {
                            Text("Menü çubuğunda MacPulse simgesi görünür. Aşağıdan widget ekleyebilirsin.")
                                .font(.callout).foregroundStyle(Palette.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading).widgetCard()
                        }
                        ForEach(Array(selected.enumerated()), id: \.element.id) { index, widget in
                            selectedRow(widget, index: index)
                        }
                        Text("Widget ekle").font(.headline).padding(.top, 8).id("widget-catalog")
                        Picker("Widget türü", selection: $catalogScope) {
                            ForEach(["Tümü", "Sistem", "AI", "Cihaz pilleri"], id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.segmented)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(catalog.filter { widget in
                                catalogScope == "Tümü" || (catalogScope == "AI" && [MenuWidgetKind.claude, .codex, .openRouter].contains(widget.kind))
                                    || (catalogScope == "Cihaz pilleri" && widget.kind == .deviceBattery)
                                    || (catalogScope == "Sistem" && MenuMetric(rawValue: widget.kind.rawValue) != nil)
                            }) { widget in
                                HStack(spacing: 10) {
                                    MenuWidgetIcon(kind: widget.kind).foregroundStyle(widgetColor(widget.kind)).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(title(widget)).font(.callout.weight(.medium))
                                        Text(subtitle(widget)).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    let on = selected.contains { $0.id == widget.id }
                                    Button(on ? "Eklendi" : "Ekle") { store.preferences.setWidgets(selected + [widget]) }
                                        .disabled(on).accessibilityLabel("\(widget.label) \(on ? "eklendi" : "ekle")")
                                }.padding(14).widgetCard()
                            }
                        }
                        Text("Yeni Claude hesapları listede görünür; kaydettiğin düzene kendiliğinden eklenmez. Veri olmayan seçili widget — gösterir. Tüm kullanım ayrıntıları AI Kullanımı ekranında ve hızlı panelde bulunur.")
                            .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 8)
                }
                }
            }
            Text("Değişiklikler anında uygulanır ve bu Mac'te saklanır.").font(.caption).foregroundStyle(Palette.secondary)
        }.padding(24).frame(minWidth: 660, minHeight: 560).background(Palette.background)
    }
    private var automaticAccounts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Şu an üst çubukta").font(.headline)
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, widget in
                HStack(spacing: 10) {
                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary).frame(width: 18)
                    MenuWidgetIcon(kind: widget.kind).frame(width: 18).foregroundStyle(widgetColor(widget.kind))
                    Text(title(widget)).font(.callout.weight(.medium))
                    Spacer()
                    if let pct = state(widget)?.usage?.five.effective(at: store.usage.now).pct {
                        Text("5 saat · %\(pct)").font(.callout.monospacedDigit())
                    }
                }.padding(12).widgetCard()
            }
            if displayed.isEmpty {
                Text("Güncel 5 saatlik kullanım verisi bekleniyor.").foregroundStyle(Palette.secondary)
            }
            Text("Yalnız güncel, bilinen 5 saatlik limitler sıralanır. Sadece haftalık limiti olan planlar, oturumu kapalı hesaplar ve eski/verisiz okumalar bu dörde dahil edilmez. Tüm hesaplar açılan AI panelinde görünür.")
                .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Elle seçtiğin widget düzeni saklıdır; üstteki seçenekten geri dönebilirsin.")
                .font(.caption).foregroundStyle(Palette.secondary)
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Canlı önizleme").font(.caption.weight(.semibold)); Spacer(); Text(automatic ? "5 saat · yüksekten düşüğe" : "Soldan sağa menü sırası").font(.caption).foregroundStyle(Palette.secondary) }
            HStack {
                if let image = MenuWidgetRenderer.image(widgets: displayed, store: store) {
                    Image(nsImage: image).frame(height: 28).accessibilityLabel(MenuWidgetRenderer.description(widgets: displayed, store: store))
                } else { Image(systemName: "waveform.path.ecg").font(.title3).foregroundStyle(Palette.accent).frame(height: 28).accessibilityLabel("MacPulse simgesi") }
                Spacer(minLength: 0)
            }
            Text(automatic ? "5 saatlik kullanımı en yüksek dört hesap; tek satırda hesap numarası ve kullanılan yüzde. Sıra yeni ölçüm ve sıfırlanmalarda otomatik değişir." : "Üst çubukta tek satır. AI sayıları yüzdeyi gösterir: üstte 5 saat, altta haftalık; tek limit ortalanır. Alan daraldığında etiket ve boşluklar kısalır.").font(.caption).foregroundStyle(Palette.secondary)
        }.padding(16).background(Palette.elevated, in: RoundedRectangle(cornerRadius: 14))
    }
    private func selectedRow(_ widget: MenuWidget, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary).frame(width: 20)
                Label { Text(title(widget)) } icon: { MenuWidgetIcon(kind: widget.kind) }
                    .font(.callout.weight(.semibold)).foregroundStyle(widgetColor(widget.kind))
                Spacer()
                Button { move(widget.id, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0).accessibilityLabel("\(widget.label) sola taşı")
                Button { move(widget.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index == selected.count - 1).accessibilityLabel("\(widget.label) sağa taşı")
                Button { store.preferences.setWidgets(selected.filter { $0.id != widget.id }) } label: { Image(systemName: "minus.circle") }
                    .accessibilityLabel("\(widget.label) kaldır")
            }
            if widget.kind.isLimit {
                HStack(spacing: 14) {
                    Picker("Limit", selection: binding(widget, \.window)) { ForEach(MenuWidgetWindow.allCases, id: \.self) { Text($0.label).tag($0) } }.frame(maxWidth: 220)
                    Picker("Görünüm", selection: binding(widget, \.style)) { ForEach(AIUsageMenuStyle.allCases, id: \.self) { Text($0.label).tag($0) } }.frame(maxWidth: 180)
                    Toggle("Kalan", isOn: binding(widget, \.showsLeft)).toggleStyle(.switch).controlSize(.small)
                        .help("Kapalı: kullanılan yüzde. Açık: kalan yüzde ve doluluk.")
                }.font(.caption)
                if let state = state(widget), let u = state.usage, widget.windows(in: u, now: store.usage.now).isEmpty {
                    Text("Bu planda seçilen limit bulunmuyor; widget — gösterir.").font(.caption).foregroundStyle(Palette.disk)
                }
            } else if widget.kind.isBattery {
                Picker("Görünüm", selection: binding(widget, \.style)) {
                    Text("Pil simgesi").tag(AIUsageMenuStyle.bars)
                    Text("Yüzde").tag(AIUsageMenuStyle.percent)
                    Text("İkisi").tag(AIUsageMenuStyle.both)
                }.pickerStyle(.segmented)
                Text(subtitle(widget)).font(.caption).foregroundStyle(Palette.secondary)
            } else {
                Text(widget.kind == .openRouter ? "Kalan hesap bakiyesi · USD" : subtitle(widget)).font(.caption).foregroundStyle(Palette.secondary)
            }
        }.padding(16).widgetCard()
    }
    private func binding<T>(_ widget: MenuWidget, _ key: WritableKeyPath<MenuWidget, T>) -> Binding<T> {
        Binding(get: { (selected.first { $0.id == widget.id } ?? widget)[keyPath: key] }, set: { value in
            var list = selected
            guard let i = list.firstIndex(where: { $0.id == widget.id }) else { return }
            list[i][keyPath: key] = value; store.preferences.setWidgets(list)
        })
    }
    private func move(_ id: String, by distance: Int) {
        var list = selected
        guard let i = list.firstIndex(where: { $0.id == id }), list.indices.contains(i + distance) else { return }
        list.swapAt(i, i + distance); store.preferences.setWidgets(list)
    }
    private func state(_ widget: MenuWidget) -> AIUsage.AccountState? {
        store.usage.states.first { widget.kind == .claude ? $0.account.provider == .claude && $0.account.n == widget.account : widget.kind == .codex && $0.account.provider == .codex }
    }
    private func title(_ widget: MenuWidget) -> String {
        if widget.kind == .deviceBattery { return store.deviceBatteries.devices.first { $0.id == widget.deviceID }.map { store.deviceBatteries.name($0) } ?? "Cihaz pili" }
        if let state = state(widget) { return "\(widget.label) · \(state.compactLabel)" }
        return widget.label
    }
    private func subtitle(_ widget: MenuWidget) -> String {
        switch widget.kind {
        case .claude, .codex: return state(widget)?.plan ?? "Hesap verisi bekleniyor"
        case .openRouter: return store.usage.credit?.credit == nil ? "Bakiye verisi bekleniyor" : "Kalan hesap kredisi"
        case .cpu: return "Tüm çekirdekler · yüzde"
        case .gpu: return "Sürücü kullanımı · yüzde"
        case .memory: return "Kullanılan bellek · yüzde"
        case .network: return "Fiziksel arayüzler · saniyelik indirme"
        case .disk: return "Başlangıç diski · kullanılan yüzde"
        case .battery: return "Mac pili · kalan yüzde"
        case .deviceBattery:
            guard let d = store.deviceBatteries.devices.first(where: { $0.id == widget.deviceID }) else { return "Cihaz verisi bekleniyor" }
            return d.isLive(at: store.deviceBatteries.now) ? (d.connection?.label ?? "Bağlı") : "Çevrimdışı · menüde —"
        }
    }
}
private func widgetColor(_ kind: MenuWidgetKind) -> Color {
    switch kind {
    case .cpu: Palette.cpu; case .gpu: Palette.gpu; case .memory, .claude, .codex: Palette.memory
    case .network, .openRouter: Palette.network; case .disk: Palette.disk; case .battery, .deviceBattery: Palette.battery
    }
}
private extension View {
    func widgetCard() -> some View { background(Palette.card, in: RoundedRectangle(cornerRadius: 14)) }
}
