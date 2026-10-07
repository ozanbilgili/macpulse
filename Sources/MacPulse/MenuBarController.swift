import AppKit
import SwiftUI
import Observation
import MetricsCore

@MainActor final class MenuBarController: NSObject, NSPopoverDelegate {
    private let store: MonitorStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    init(store: MonitorStore) {
        self.store = store
        super.init()
        if let button = item.button {
            button.target = self; button.action = #selector(toggle)
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("MacPulse hızlı panel")
        }
        popover.behavior = .transient; popover.animates = false; popover.delegate = self
        let host = NSHostingController(rootView: MenuPanelRoot(store: store))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        store.togglePanelAction = { [weak self] in self?.toggle() }
        store.closePanelAction = { [weak self] in self?.popover.performClose(nil) }
        observeLabel()
    }
    @objc func toggle() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.panelVisible = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func popoverDidClose(_ notification: Notification) { store.panelVisible = false }
    private func observeLabel() {
        withObservationTracking {
            let paused = store.paused || store.lifecycle.sleeping
            let widgets = store.preferences.widgets(for: store.usage)
            _ = store.preferences.theme // Redraw dynamic label colors after a theme change.
            let description = MenuWidgetRenderer.description(widgets: widgets, store: store)
            item.button?.title = ""
            item.button?.setAccessibilityValue(paused ? "Duraklatıldı" : description)
            let image = !paused ? MenuWidgetRenderer.image(widgets: widgets, store: store) : nil
            item.button?.image = image ?? NSImage(systemSymbolName: paused ? "pause.circle" : "waveform.path.ecg", accessibilityDescription: "MacPulse")
            store.menuWidgetCount = widgets.count
            store.menuWidgetImageWidth = image?.size.width ?? 18
            store.menuWidgetBudget = MenuWidgetRenderer.widthBudget
            item.button?.image?.isTemplate = image == nil
            item.button?.toolTip = paused ? "MacPulse · Duraklatıldı" : "MacPulse · " + description
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeLabel() }
        }
    }
}

private struct MenuPanelRoot: View {
    let store: MonitorStore
    var body: some View {
        Group {
            if store.panelVisible { QuickPanel(store: store) }
            else { Color.clear.frame(width: 520, height: 180) }
        }.fixedSize(horizontal: true, vertical: true)
            .background(Palette.background).preferredColorScheme(store.preferences.colorScheme)
    }
}
