import SwiftUI
import AppKit
import MetricsCore

struct QuickPanel: View {
    let store: MonitorStore
    // The quick panel is recreated when reopened, so temporary tab choices never replace its default.
    @State private var panel = "AI Kullanımı"
    private var s: MetricSnapshot? { store.snapshot }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MacPulse", systemImage: "waveform.path.ecg").font(.headline).foregroundStyle(Palette.accent)
                Spacer()
                Button("Widget'lar") { store.showWidgets() }.buttonStyle(.link).font(.caption)
                Button { store.showSettings() } label: {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain).accessibilityLabel("Tercihleri aç")
            }
            HStack(spacing: 6) {
                Circle().fill(store.paused ? Palette.disk : Palette.accent).frame(width: 6, height: 6)
                Text(store.paused ? "Duraklatıldı · son ölçüm gösteriliyor" : "Canlı · \(store.effectiveInterval) saniyede bir")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Picker("Panel", selection: $panel) {
                Text("Mac").tag("Mac")
                Text("AI Kullanımı").tag("AI Kullanımı")
                Text("Piller").tag("Piller")
            }.pickerStyle(.segmented)
            if panel == "AI Kullanımı" {
                AIQuickSummary(store: store)
            } else if panel == "Piller" {
                DeviceBatteryQuickView(store: store)
            } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PanelMetric(title: "CPU", value: MetricFormat.percent(s?.cpu?.used), detail: "Tüm çekirdekler", icon: "cpu", color: Palette.cpu)
                PanelMetric(title: "Bellek", value: MetricFormat.bytes(s?.memory?.used, binary: true), detail: s?.memory?.pressure.label ?? "—", icon: "memorychip", color: Palette.memory)
                PanelMetric(title: "Disk", value: MetricFormat.bytes(s?.disk?.available), detail: "Başlangıç diskinde boş", icon: "internaldrive", color: Palette.disk)
                PanelMetric(title: "Ağ", value: MetricFormat.rate(s?.network?.incomingRate), detail: "↓ Fiziksel arayüzler", icon: "network", color: Palette.network)
                PanelMetric(title: "Pil", value: s?.battery?.present == false ? "Pil yok" : s?.battery?.percent.map { "\($0)%" } ?? "—", detail: s?.battery?.stateLabel ?? "—", icon: "battery.100percent", color: Palette.battery)
                PanelMetric(title: "GPU", value: MetricFormat.percent(s?.hardware?.singleGPUPercent), detail: "Sürücü kullanım sayacı", icon: "square.3.layers.3d", color: Palette.gpu)
            }
            if let date = s?.date {
                Text("Son ölçüm \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).monospacedDigit().foregroundStyle(Palette.secondary)
            }
            }
            if store.historyError != nil {
                Label("Geçmiş kaydı alınamıyor", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(Palette.disk)
            }
            HStack {
                Button("Ana pencereyi aç") { store.showMain() }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                Spacer()
                Button { store.paused.toggle() } label: {
                    Image(systemName: store.paused ? "play.fill" : "pause.fill")
                }.accessibilityLabel(store.paused ? "İzlemeyi sürdür" : "İzlemeyi duraklat")
            }
            Divider()
            HStack {
                Text("Pencereyi kapatmak izlemeyi durdurmaz.").font(.caption2).foregroundStyle(Palette.secondary)
                Spacer()
                Button("Çıkış") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption)
            }
        }.padding(16).frame(width: panel == "AI Kullanımı" ? 520 : panel == "Piller" ? DeviceBatteryPanelLayout.width(store.deviceBatteries.preferences.density) + 32 : MenuPanelLayout.width).background(Palette.background).foregroundStyle(.primary)
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
