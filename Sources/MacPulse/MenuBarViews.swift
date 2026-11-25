import SwiftUI
import AppKit
import MetricsCore

struct QuickPanel: View {
    let store: MonitorStore
    // The quick panel is recreated when reopened, so temporary tab choices never replace its default.
    private enum Tab: Hashable { case mac, usage, batteries }
    @State private var panel = Tab.usage
    private var s: MetricSnapshot? { store.snapshot }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MacPulse", systemImage: "waveform.path.ecg").font(.headline).foregroundStyle(Palette.accent)
                Spacer()
                Button("Widgets") { store.showWidgets() }.buttonStyle(.link).font(.caption)
                Button { store.showSettings() } label: {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain).accessibilityLabel("Open Settings")
            }
            HStack(spacing: 6) {
                Circle().fill(store.paused ? Palette.disk : Palette.accent).frame(width: 6, height: 6)
                Text(store.paused ? "Paused · showing last reading" : "Live · every \(store.effectiveInterval) seconds")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Picker("Panel", selection: $panel) {
                Text("Mac").tag(Tab.mac)
                Text("AI Usage").tag(Tab.usage)
                Text("Batteries").tag(Tab.batteries)
            }.pickerStyle(.segmented)
            if panel == .usage {
                AIQuickSummary(store: store)
            } else if panel == .batteries {
                DeviceBatteryQuickView(store: store)
            } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PanelMetric(title: "CPU", value: MetricFormat.percent(s?.cpu?.used), detail: String(localized: "All cores"), icon: "cpu", color: Palette.cpu)
                PanelMetric(title: String(localized: "Memory"), value: MetricFormat.bytes(s?.memory?.used, binary: true), detail: s?.memory?.pressure.label ?? "—", icon: "memorychip", color: Palette.memory)
                PanelMetric(title: "Disk", value: MetricFormat.bytes(s?.disk?.available), detail: String(localized: "Free on startup disk"), icon: "internaldrive", color: Palette.disk)
                PanelMetric(title: String(localized: "Network"), value: MetricFormat.rate(s?.network?.incomingRate), detail: String(localized: "↓ Physical interfaces"), icon: "network", color: Palette.network)
                PanelMetric(title: String(localized: "Battery"), value: s?.battery?.present == false ? String(localized: "No battery") : MetricFormat.percent(s?.battery?.percent), detail: s?.battery?.stateLabel ?? "—", icon: "battery.100percent", color: Palette.battery)
                PanelMetric(title: "GPU", value: MetricFormat.percent(s?.hardware?.singleGPUPercent), detail: String(localized: "Driver utilization counter"), icon: "square.3.layers.3d", color: Palette.gpu)
            }
            if let date = s?.date {
                Text("Last measured \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).monospacedDigit().foregroundStyle(Palette.secondary)
            }
            }
            if store.historyError != nil {
                Label("History unavailable", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(Palette.disk)
            }
            HStack {
                Button("Open Main Window") { store.showMain() }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                Spacer()
                Button { store.paused.toggle() } label: {
                    Image(systemName: store.paused ? "play.fill" : "pause.fill")
                }.accessibilityLabel(store.paused ? "Resume monitoring" : "Pause monitoring")
            }
            Divider()
            HStack {
                Text("Closing the window doesn't stop monitoring.").font(.caption2).foregroundStyle(Palette.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption)
            }
        }.padding(16).frame(width: panel == .usage ? 520 : panel == .batteries ? DeviceBatteryPanelLayout.width(store.deviceBatteries.preferences.density) + 32 : MenuPanelLayout.width).background(Palette.background).foregroundStyle(.primary)
    }
}

private struct PanelMetric: View {
    let title, value, detail, icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(color)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(Palette.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue("\(value), \(detail)")
    }
}

/// Tracks the actual NSWindow, including closing/minimizing, rather than a retained SwiftUI view.
struct WindowActivityObserver: NSViewRepresentable {
    let store: MonitorStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.attached = { [weak coordinator = context.coordinator] window in coordinator?.bind(window) }
        return view
    }
    func updateNSView(_ nsView: TrackingView, context: Context) { }
    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) { coordinator.unbind() }
    final class TrackingView: NSView {
        var attached: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attached?(window) }
    }
    @MainActor final class Coordinator {
        let store: MonitorStore
        weak var window: NSWindow?
        private var tokens: [NSObjectProtocol] = []
        init(store: MonitorStore) { self.store = store }
        func bind(_ window: NSWindow?) {
            guard self.window !== window else { return }
            unbind(); self.window = window
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    Task { @MainActor in
                        if closing { self?.store.mainVisible = false; self?.store.mainWindowOpen = false }
                        else { self?.update() }
                    }
                })
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                tokens.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.update() }
                })
            }
            Task { @MainActor [weak self] in self?.update() }
        }
        func unbind() {
            tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll()
            window = nil
            Task { @MainActor [weak store] in store?.mainVisible = false; store?.mainWindowOpen = false }
        }
        private func update() {
            store.mainWindowOpen = window.map { $0.isVisible && !$0.isMiniaturized } ?? false
            store.mainVisible = store.mainWindowOpen && NSApp.isActive
        }
    }
}

/// Screen bounds keep vertical AI/device lists inside the menu popup.
@MainActor enum MenuPanelLayout {
    static var screen: NSRect { NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800) }
    static var width: CGFloat { min(screen.width - 40, 740) }
}
