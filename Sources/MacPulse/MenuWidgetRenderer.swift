import AppKit
import MetricsCore

/// One renderer for the actual status item and the editor's live preview.
@MainActor enum MenuWidgetRenderer {
    private struct Segment {
        var badge: String
        var compactBadge: String = ""
        var text: String
        var color: NSColor
        var logo: ProviderLogo?
        var lead: ProviderLogo?
        var isLimit = false
        var values: [Int?] = []
        var barColors: [NSColor] = []
        var showBars = false
        var showPercent = false
        var stale = false
        var danger = false
        var battery = false
        var batteryLevel: Int?
        var charging = false
        var description: String
    }
    private static func segments(widgets: [MenuWidget], store: MonitorStore) -> [Segment] {
        let s = store.snapshot
        return widgets.enumerated().map { index, widget in
            let label = widget.label
            if widget.kind.isLimit {
                let state = store.usage.states.first { widget.kind == .claude ? $0.account.provider == .claude && $0.account.n == widget.account : $0.account.provider == .codex }
                let windows = widget.windows(in: state?.usage, now: store.usage.now)
                let stale = state?.usage.map { store.usage.now.timeIntervalSince($0.fetchedAt) > AIUsage.Cfg.staleSeconds } ?? true
                let bars = windows.isEmpty ? [(pct: nil as Int?, color: NSColor.secondaryLabelColor)] : windows.map { w in
                    (pct: w.value.known ? (widget.showsLeft ? 100 - w.value.pct : w.value.pct) : nil,
                     color: stale ? .secondaryLabelColor : w.value.pct >= 90 ? .systemRed : w.value.pct >= 70 ? .systemOrange : .systemGreen)
                }
                let danger = !stale && windows.contains { w in if case .runningOut = w.meter { return w.value.known }; return false }
                let details = windows.isEmpty ? "Seçilen limit için veri yok" : windows.map { w in
                    "\(w.label): \(w.value.known ? "%\(widget.showsLeft ? 100 - w.value.pct : w.value.pct) \(widget.showsLeft ? "kaldı" : "kullanıldı")" : "veri bekleniyor")"
                }.joined(separator: ", ")
                // A lead mark identifies each contiguous Claude group; account numbers stay colored.
                return Segment(badge: widget.kind == .claude ? "\(widget.account)" : "", text: "",
                               color: widget.kind == .claude ? NSColor(aiAccountColor(widget.account)) : .labelColor,
                               logo: widget.kind == .codex ? .codex : nil,
                               lead: widget.kind == .claude && (index == 0 || widgets[index - 1].kind != .claude) ? .claude : nil,
                               isLimit: true, values: bars.map(\.pct), barColors: bars.map(\.color),
                               showBars: widget.style != .percent, showPercent: widget.style != .bars,
                               stale: stale, danger: danger, description: label + " · " + details + (stale ? " · Eski/veri yok" : ""))
            }
            if widget.kind.isBattery {
                let device = store.deviceBatteries.devices.first { $0.id == (widget.kind == .battery ? "mac:internal" : widget.deviceID) }
                let live = !store.paused && !store.deviceBatteries.isPaused && device?.isLive(at: store.deviceBatteries.now) == true
                let level = live ? device?.displayLevel(at: store.deviceBatteries.now) : nil
                let value = level.map { (device?.approximate == true ? "≈" : "") + "\($0)%" } ?? "—"
                let name = widget.kind == .battery ? "Pil" : device.map { store.deviceBatteries.name($0) } ?? "Cihaz pili"
                let charging = live && level != nil && device?.isCharging == true
                return Segment(badge: widget.kind == .battery ? "B" : String(name.prefix(10)), compactBadge: widget.kind == .battery ? "B" : String(name.prefix(3)), text: widget.style == .bars ? "" : value,
                               color: level == nil ? .secondaryLabelColor : charging ? .systemGreen : (level! <= 20 ? .systemRed : level! <= 40 ? .systemOrange : .systemGreen),
                               battery: widget.style != .percent, batteryLevel: level, charging: charging,
                               description: name + " · " + value + (live ? charging ? " · Şarj oluyor" : "" : " · Son ölçüm/çevrimdışı"))
            }
            let badge: String, value: String, color: NSColor
            switch widget.kind {
            case .cpu: badge = "CPU"; value = MetricFormat.percent(s?.cpu?.used); color = .systemBlue
            case .gpu: badge = "GPU"; value = MetricFormat.percent(s?.hardware?.singleGPUPercent); color = .systemPink
            case .memory: badge = "RAM"; value = MetricFormat.percent(s?.memory?.usedPercent); color = .systemPurple
            case .network: badge = "↓"; value = MetricFormat.rate(s?.network?.incomingRate); color = .systemTeal
            case .disk: badge = "D"; value = MetricFormat.percent(s?.disk?.usedPercent); color = .systemOrange
            case .battery: badge = "B"; value = s?.battery?.present == false ? "—" : s?.battery?.percent.map { "\($0)%" } ?? "—"; color = .systemGreen
            case .openRouter:
                badge = "OR"; value = store.usage.credit?.credit.map { AIUsage.formatUSD($0.remaining) } ?? "—"; color = .systemTeal
            case .claude, .codex, .deviceBattery: badge = ""; value = "—"; color = .secondaryLabelColor
            }
            return Segment(badge: badge, compactBadge: widget.kind == .cpu ? "C" : widget.kind == .gpu ? "G" : widget.kind == .memory ? "R" : badge, text: value, color: color,
                           logo: widget.kind == .openRouter ? .openrouter : nil, description: label + " · " + value)
        }
    }
    static func description(widgets: [MenuWidget], store: MonitorStore) -> String {
        let result = segments(widgets: widgets, store: store).map(\.description).joined(separator: " · ")
        return result.isEmpty ? "MacPulse simgesi" : result
    }
    static var widthBudget: CGFloat {
        let screen = NSScreen.main
        let rightArea = screen?.auxiliaryTopRightArea?.width ?? 0
        return max(220, min(440, rightArea > 0 ? rightArea - 150 : (screen?.frame.width ?? 1280) * 0.4))
    }
    static func image(widgets: [MenuWidget], store: MonitorStore) -> NSImage? {
        var items = segments(widgets: widgets, store: store)
        guard !items.isEmpty else { return nil }
        var font = NSFont.monospacedDigitSystemFont(ofSize: store.preferences.menuWidgetSelection == .topFourFiveHour ? 11 : 10, weight: .semibold)
        let height: CGFloat = 22, logoWidth: CGFloat = 12, leadGap: CGFloat = 4, dotSpace: CGFloat = 5
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        func labelWidth(_ item: Segment) -> CGFloat { item.logo != nil ? logoWidth : max(item.isLimit ? width("8") : 0, width(item.badge)) }
        func leadWidth(_ item: Segment) -> CGFloat { item.lead != nil ? logoWidth + leadGap : 0 }
        func percentWidth(_ item: Segment) -> CGFloat { max(width("88"), item.values.map { width($0.map(String.init) ?? "—") }.max() ?? 0) }
        func itemWidth(_ item: Segment, bar: CGFloat, battery: CGFloat, gap: CGFloat) -> CGFloat {
            leadWidth(item) + labelWidth(item) + gap
                + (item.isLimit ? (item.showBars ? bar + gap : 0) + (item.showPercent ? percentWidth(item) : 0) + dotSpace
                   : (item.battery ? battery : 0) + width(item.text)) + gap * 2
        }
        func totalWidth(bar: CGFloat, battery: CGFloat, gap: CGFloat) -> CGFloat {
            items.reduce(0) { $0 + itemWidth($1, bar: bar, battery: battery, gap: gap) }
        }
        let compact = totalWidth(bar: 14, battery: 27, gap: 3) > widthBudget
        if compact {
            font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            for i in items.indices {
                if !items[i].compactBadge.isEmpty { items[i].badge = items[i].compactBadge }
            }
        }
        let gap: CGFloat = compact ? 2 : 3, barWidth: CGFloat = compact ? 10 : 14
        let batteryWidth: CGFloat = compact ? 22 : 27
        let total = totalWidth(bar: barWidth, battery: batteryWidth, gap: gap)
        let scale = min(1, widthBudget / max(1, total))
        let result = NSImage(size: NSSize(width: total * scale, height: height), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: height / 2 * (1 - scale)); transform.scale(by: scale); transform.concat()
            var x: CGFloat = 0
            func draw(_ text: String, color: NSColor) {
                let textHeight = (text as NSString).size(withAttributes: [.font: font]).height
                (text as NSString).draw(at: NSPoint(x: x, y: (height - textHeight) / 2), withAttributes: [.font: font, .foregroundColor: color])
                x += (text as NSString).size(withAttributes: [.font: font]).width
            }
            func drawLogo(_ logo: ProviderLogo, at x: CGFloat) {
                NSColor.labelColor.setFill()
                NSBezierPath(cgPath: providerLogoPath(logo, in: NSRect(x: x, y: (height - logoWidth) / 2, width: logoWidth, height: logoWidth), flipped: true)).fill()
            }
            for item in items {
                let start = x, label = labelWidth(item)
                if let lead = item.lead { drawLogo(lead, at: x); x += leadWidth(item) }
                if let logo = item.logo { drawLogo(logo, at: x) }
                else { draw(item.badge, color: item.color); x -= width(item.badge) }
                x += label + gap
                if item.isLimit {
                    let valueX = x + (item.showBars ? barWidth + gap : 0), valueWidth = percentWidth(item)
                    for (i, pct) in item.values.enumerated() {
                        let center: CGFloat = item.values.count == 1 ? height / 2 : i == 0 ? 16 : 5
                        if item.showBars {
                            NSColor.tertiaryLabelColor.setFill()
                            let rect = NSRect(x: x, y: center - 2, width: barWidth, height: 4)
                            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
                            if let pct {
                                item.barColors[i].setFill()
                                NSBezierPath(roundedRect: NSRect(x: x, y: rect.minY, width: barWidth * CGFloat(max(0, min(100, pct))) / 100, height: 4), xRadius: 2, yRadius: 2).fill()
                            } else {
                                NSColor.secondaryLabelColor.setFill(); NSRect(x: x + (barWidth - 4) / 2, y: center - 0.5, width: 4, height: 1).fill()
                            }
                        }
                        if item.showPercent {
                            let text = (pct.map(String.init) ?? "—") as NSString
                            let size = text.size(withAttributes: [.font: font])
                            let y = item.values.count == 1 ? (height - size.height) / 2 : i == 0 ? height - size.height : 0
                            let color: NSColor = pct == nil || item.stale ? .secondaryLabelColor : item.barColors[i] == .systemRed ? .systemRed : .labelColor
                            text.draw(at: NSPoint(x: valueX + valueWidth - size.width, y: y), withAttributes: [.font: font, .foregroundColor: color])
                        }
                    }
                    if item.danger {
                        NSColor.systemRed.setFill()
                        let dotX = valueX + (item.showPercent ? valueWidth : 0) + 2
                        NSBezierPath(ovalIn: NSRect(x: dotX, y: (height - 3) / 2, width: 3, height: 3)).fill()
                    }
                    x = start + itemWidth(item, bar: barWidth, battery: batteryWidth, gap: gap)
                    continue
                }
                if item.battery {
                    NSGraphicsContext.saveGraphicsState()
                    let batteryTransform = NSAffineTransform(); batteryTransform.translateX(by: x, yBy: 0); batteryTransform.scaleX(by: batteryWidth / 27, yBy: 1); batteryTransform.translateX(by: -x, yBy: 0); batteryTransform.concat()
                    item.color.withAlphaComponent(0.6).setStroke()
                    NSBezierPath(roundedRect: NSRect(x: x, y: 5, width: 22, height: 11), xRadius: 2, yRadius: 2).stroke()
                    item.color.setFill(); NSRect(x: x + 23, y: 8, width: 2, height: 5).fill()
                    if let level = item.batteryLevel {
                        NSBezierPath(roundedRect: NSRect(x: x + 2, y: 7, width: 18 * CGFloat(level) / 100, height: 7), xRadius: 1, yRadius: 1).fill()
                    } else { NSRect(x: x + 8, y: 10, width: 6, height: 1).fill() }
                    if item.charging {
                        let bolt = NSBezierPath(); bolt.move(to: NSPoint(x: x + 13, y: 15)); bolt.line(to: NSPoint(x: x + 8, y: 9)); bolt.line(to: NSPoint(x: x + 11, y: 9)); bolt.line(to: NSPoint(x: x + 9, y: 5)); bolt.line(to: NSPoint(x: x + 15, y: 11)); bolt.line(to: NSPoint(x: x + 12, y: 11)); bolt.close()
                        NSColor.white.setFill(); bolt.fill()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    x += batteryWidth
                }
                draw(item.text, color: .labelColor)
                x = start + itemWidth(item, bar: barWidth, battery: batteryWidth, gap: gap)
            }
            return true
        }
        result.isTemplate = false
        return result
    }
}
