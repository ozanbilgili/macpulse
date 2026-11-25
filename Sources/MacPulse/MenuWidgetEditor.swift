import SwiftUI
import MetricsCore

struct MenuWidgetEditor: View {
    @Bindable var store: MonitorStore
    private enum Scope: Hashable { case all, system, ai, batteries }
    @State private var catalogScope = Scope.all
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
                    Label("Menu Bar Widgets", systemImage: "menubar.rectangle").font(.title2.weight(.semibold))
                    Text("Choose what you want to see. Edit the order and each account's display separately.").font(.callout).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("Usage details") { store.showUsage() }
            }
            Picker("Show in menu bar", selection: Binding(get: { store.preferences.menuWidgetSelection }, set: { store.preferences.menuWidgetSelection = $0 })) {
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
                            Text("Selected widgets · \(selected.count)").font(.headline)
                            Spacer()
                            Button("Add widget") { withAnimation { proxy.scrollTo("widget-catalog", anchor: .top) } }.buttonStyle(.link)
                            Button("Icon only") { store.preferences.setWidgets([]) }.buttonStyle(.link).disabled(selected.isEmpty)
                        }
                        if selected.isEmpty {
                            Text("The MacPulse icon appears in the menu bar. You can add widgets below.")
                                .font(.callout).foregroundStyle(Palette.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading).widgetCard()
                        }
                        ForEach(Array(selected.enumerated()), id: \.element.id) { index, widget in
                            selectedRow(widget, index: index)
                        }
                        Text("Add widget").font(.headline).padding(.top, 8).id("widget-catalog")
                        Picker("Widget type", selection: $catalogScope) {
                            Text("All").tag(Scope.all)
                            Text("System").tag(Scope.system)
                            Text(verbatim: "AI").tag(Scope.ai)
                            Text("Device batteries").tag(Scope.batteries)
                        }.pickerStyle(.segmented)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(catalog.filter { widget in
                                catalogScope == .all || (catalogScope == .ai && [MenuWidgetKind.claude, .codex, .openRouter].contains(widget.kind))
                                    || (catalogScope == .batteries && widget.kind == .deviceBattery)
                                    || (catalogScope == .system && MenuMetric(rawValue: widget.kind.rawValue) != nil)
                            }) { widget in
                                HStack(spacing: 10) {
                                    MenuWidgetIcon(kind: widget.kind).foregroundStyle(widgetColor(widget.kind)).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(title(widget)).font(.callout.weight(.medium))
                                        Text(subtitle(widget)).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    let on = selected.contains { $0.id == widget.id }
                                    Button(on ? "Added" : "Add") { store.preferences.setWidgets(selected + [widget]) }
                                        .disabled(on).accessibilityLabel(on ? "\(widget.label) added" : "Add \(widget.label)")
                                }.padding(14).widgetCard()
                            }
                        }
                        Text("New Claude accounts appear in the list; they aren't added to your saved layout automatically. A selected widget without data shows —. All usage details are on the AI Usage screen and in the quick panel.")
                            .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 8)
                }
                }
            }
            Text("Changes apply immediately and are stored on this Mac.").font(.caption).foregroundStyle(Palette.secondary)
        }.padding(24).frame(minWidth: 660, minHeight: 560).background(Palette.background)
    }
    private var automaticAccounts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In the menu bar now").font(.headline)
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, widget in
                HStack(spacing: 10) {
                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary).frame(width: 18)
                    MenuWidgetIcon(kind: widget.kind).frame(width: 18).foregroundStyle(widgetColor(widget.kind))
                    Text(title(widget)).font(.callout.weight(.medium))
                    Spacer()
                    if let pct = state(widget)?.usage?.five.effective(at: store.usage.now).pct {
                        Text("5-hour · \(LocalizedFormat.percent(pct))").font(.callout.monospacedDigit())
                    }
                }.padding(12).widgetCard()
            }
            if displayed.isEmpty {
                Text("Waiting for current 5-hour usage data.").foregroundStyle(Palette.secondary)
            }
            Text("Only current, known 5-hour limits are ranked. Weekly-only plans, signed-out accounts and stale or empty readings aren't included in these four. All accounts appear in the AI panel.")
                .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Your manually chosen widget layout is saved; you can switch back with the option above.")
                .font(.caption).foregroundStyle(Palette.secondary)
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Live preview").font(.caption.weight(.semibold)); Spacer(); Text(automatic ? "5-hour · highest to lowest" : "Menu order, left to right").font(.caption).foregroundStyle(Palette.secondary) }
            HStack {
                if let image = MenuWidgetRenderer.image(widgets: displayed, store: store) {
                    Image(nsImage: image).frame(height: 28).accessibilityLabel(MenuWidgetRenderer.description(widgets: displayed, store: store))
                } else { Image(systemName: "waveform.path.ecg").font(.title3).foregroundStyle(Palette.accent).frame(height: 28).accessibilityLabel("MacPulse icon") }
                Spacer(minLength: 0)
            }
            Text(automatic ? "The four accounts with the highest 5-hour usage; one line with account number and percentage used. The order updates automatically with new readings and resets." : "One line in the menu bar. AI numbers show percentages: 5-hour on top, weekly below; a single limit is centered. Labels and spacing shrink when space is tight.").font(.caption).foregroundStyle(Palette.secondary)
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
                    .disabled(index == 0).accessibilityLabel("Move \(widget.label) left")
                Button { move(widget.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index == selected.count - 1).accessibilityLabel("Move \(widget.label) right")
                Button { store.preferences.setWidgets(selected.filter { $0.id != widget.id }) } label: { Image(systemName: "minus.circle") }
                    .accessibilityLabel("Remove \(widget.label)")
            }
            if widget.kind.isLimit {
                HStack(spacing: 14) {
                    Picker("Limit", selection: binding(widget, \.window)) { ForEach(MenuWidgetWindow.allCases, id: \.self) { Text($0.label).tag($0) } }.frame(maxWidth: 220)
                    Picker("Appearance", selection: binding(widget, \.style)) { ForEach(AIUsageMenuStyle.allCases, id: \.self) { Text($0.label).tag($0) } }.frame(maxWidth: 180)
                    Toggle("Remaining", isOn: binding(widget, \.showsLeft)).toggleStyle(.switch).controlSize(.small)
                        .help("Off: percentage used. On: percentage remaining and fill.")
                }.font(.caption)
                if let state = state(widget), let u = state.usage, widget.windows(in: u, now: store.usage.now).isEmpty {
                    Text("The selected limit isn't in this plan; the widget shows —.").font(.caption).foregroundStyle(Palette.disk)
                }
            } else if widget.kind.isBattery {
                Picker("Appearance", selection: binding(widget, \.style)) {
                    Text("Battery icon").tag(AIUsageMenuStyle.bars)
                    Text("Percentage").tag(AIUsageMenuStyle.percent)
                    Text("Both").tag(AIUsageMenuStyle.both)
                }.pickerStyle(.segmented)
                Text(subtitle(widget)).font(.caption).foregroundStyle(Palette.secondary)
            } else {
                Text(widget.kind == .openRouter ? String(localized: "Remaining account balance · USD") : subtitle(widget)).font(.caption).foregroundStyle(Palette.secondary)
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
        if widget.kind == .deviceBattery { return store.deviceBatteries.devices.first { $0.id == widget.deviceID }.map { store.deviceBatteries.name($0) } ?? String(localized: "Device battery") }
        if let state = state(widget) { return "\(widget.label) · \(state.compactLabel)" }
        return widget.label
    }
    private func subtitle(_ widget: MenuWidget) -> String {
        switch widget.kind {
        case .claude, .codex: return state(widget)?.plan ?? String(localized: "Waiting for account data")
        case .openRouter: return store.usage.credit?.credit == nil ? String(localized: "Waiting for balance data") : String(localized: "Remaining account credit")
        case .cpu: return String(localized: "All cores · percentage")
        case .gpu: return String(localized: "Driver utilization · percentage")
        case .memory: return String(localized: "Memory used · percentage")
        case .network: return String(localized: "Physical interfaces · download per second")
        case .disk: return String(localized: "Startup disk · percentage used")
        case .battery: return String(localized: "Mac battery · percentage left")
        case .deviceBattery:
            guard let d = store.deviceBatteries.devices.first(where: { $0.id == widget.deviceID }) else { return String(localized: "Waiting for device data") }
            return d.isLive(at: store.deviceBatteries.now) ? (d.connection?.label ?? String(localized: "Connected")) : String(localized: "Offline · shows — in menu")
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
