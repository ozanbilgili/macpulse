import Foundation

public enum MenuWidgetKind: String, CaseIterable, Codable, Sendable {
    case cpu, gpu, memory, network, disk, battery, claude, codex, openRouter, deviceBattery
    public var label: String {
        switch self {
        case .cpu: "CPU"; case .gpu: "GPU"; case .memory: String(localized: "Memory"); case .network: String(localized: "Network download")
        case .disk: String(localized: "Disk usage"); case .battery: String(localized: "Battery"); case .claude: "Claude"; case .codex: "Codex"; case .openRouter: "OpenRouter"; case .deviceBattery: String(localized: "Device battery")
        }
    }
    public var isLimit: Bool { self == .claude || self == .codex }
    public var isBattery: Bool { self == .battery || self == .deviceBattery }
    public var icon: String {
        switch self {
        case .cpu: "cpu"; case .gpu: "square.3.layers.3d"; case .memory: "memorychip"; case .network: "network"
        case .disk: "internaldrive"; case .battery, .deviceBattery: "battery.100percent"; case .claude, .codex: "chart.bar.xaxis"; case .openRouter: "arrow.triangle.branch"
        }
    }
}

public enum MenuWidgetWindow: String, CaseIterable, Codable, Sendable {
    case both, five, week
    public var label: String { switch self { case .both: String(localized: "Both limits"); case .five: String(localized: "5-hour"); case .week: String(localized: "Weekly") } }
}

/// Identity depends on the source, never its mutable display name or login state.
public struct MenuWidget: Codable, Equatable, Sendable, Identifiable {
    public var kind: MenuWidgetKind
    public var account: Int
    public var style: AIUsageMenuStyle
    public var window: MenuWidgetWindow
    public var showsLeft: Bool
    public var deviceID: String
    public var id: String { kind == .claude ? "claude:\(account)" : kind == .deviceBattery ? "battery:\(deviceID)" : kind.rawValue }
    public var label: String { kind == .claude ? "Claude \(account)" : kind.label }
    public init(_ kind: MenuWidgetKind, account: Int = 0, style: AIUsageMenuStyle = .both,
                window: MenuWidgetWindow = .both, showsLeft: Bool = false, deviceID: String = "") {
        self.kind = kind; self.account = kind == .claude ? account : 0
        self.style = style; self.window = window; self.showsLeft = showsLeft
        self.deviceID = kind == .deviceBattery ? deviceID : ""
    }
    public static func normalized(_ widgets: [Self]) -> [Self] {
        var seen = Set<String>()
        return widgets.compactMap { widget in
            guard widget.kind != .claude || widget.account > 0 else { return nil }
            guard widget.kind != .deviceBattery || (!widget.deviceID.isEmpty && widget.deviceID.count <= 512) else { return nil }
            let canonical = Self(widget.kind, account: widget.account, style: widget.style, window: widget.window, showsLeft: widget.showsLeft, deviceID: widget.deviceID)
            guard seen.insert(canonical.id).inserted else { return nil }
            return canonical
        }
    }
    public func windows(in usage: AIUsage.Usage?, now: Date) -> [(label: String, value: AIUsage.Window, meter: AIUsage.MeterState)] {
        guard let usage else { return [] }
        var result: [(String, AIUsage.Window, AIUsage.MeterState)] = []
        if window != .week && usage.hasFive { result.append((String(localized: "5-hour"), usage.five.effective(at: now), usage.meterFive(now: now))) }
        if window != .five && usage.hasWeek { result.append((String(localized: "Weekly"), usage.week.effective(at: now), usage.meterWeek(now: now))) }
        return result
    }
    /// Highest current five-hour usage first. Weekly-only plans and unavailable readings
    /// never stand in for five-hour usage. Stable source order resolves equal percentages.
    public static func topFiveHourWidgets(states: [AIUsage.AccountState], now: Date) -> [Self] {
        let ranked = states.compactMap { state -> (widget: Self, pct: Int)? in
            guard state.loggedIn, !state.tokenExpired, let usage = state.usage, usage.hasFive,
                  now.timeIntervalSince(usage.fetchedAt) >= -5,
                  now.timeIntervalSince(usage.fetchedAt) <= AIUsage.Cfg.staleSeconds else { return nil }
            let window = usage.five.effective(at: now)
            guard window.known, (0...100).contains(window.pct) else { return nil }
            let widget = Self(state.account.provider == .claude ? .claude : .codex,
                              account: state.account.n, style: .percent, window: .five)
            return (widget, window.pct)
        }.sorted { a, b in
            if a.pct != b.pct { return a.pct > b.pct }
            if a.widget.kind != b.widget.kind { return a.widget.kind == .claude }
            return a.widget.account < b.widget.account
        }
        return Array(normalized(ranked.map(\.widget)).prefix(4))
    }
    enum CodingKeys: String, CodingKey { case kind, account, style, window, showsLeft, deviceID }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(MenuWidgetKind.self, forKey: .kind)
        self.init(kind, account: try c.decodeIfPresent(Int.self, forKey: .account) ?? 0,
                  style: try c.decodeIfPresent(String.self, forKey: .style).flatMap(AIUsageMenuStyle.init(rawValue:)) ?? .both,
                  window: try c.decodeIfPresent(String.self, forKey: .window).flatMap(MenuWidgetWindow.init(rawValue:)) ?? .both,
                  showsLeft: try c.decodeIfPresent(Bool.self, forKey: .showsLeft) ?? false, deviceID: try c.decodeIfPresent(String.self, forKey: .deviceID) ?? "")
    }
}

extension MonitorPreferences {
    /// A nil list means legacy preferences have not yet been edited. An empty list
    /// deliberately means icon only; unavailable configured sources stay selected.
    public func resolvedWidgets(claudeAccounts: [Int], codex: Bool, openRouter: Bool) -> [MenuWidget] {
        if let menuWidgets { return MenuWidget.normalized(menuWidgets) }
        var result = menuMetrics.compactMap { MenuWidgetKind(rawValue: $0.rawValue).map { MenuWidget($0) } }
        if usageMenu {
            result += claudeAccounts.sorted().map { MenuWidget(.claude, account: $0, style: usageMenuStyle) }
            if codex { result.append(MenuWidget(.codex, style: usageMenuStyle)) }
            if openRouter { result.append(MenuWidget(.openRouter)) }
        }
        return MenuWidget.normalized(result)
    }
}
