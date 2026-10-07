import Foundation

public enum MonitorTheme: String, CaseIterable, Codable, Sendable {
    case system, dark, light
    public var label: String {
        switch self { case .system: "Sistem"; case .dark: "Koyu"; case .light: "Açık" }
    }
}

public enum MenuMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, gpu, memory, network, disk, battery
    public var id: Self { self }
    public var label: String {
        switch self { case .cpu: "CPU"; case .gpu: "GPU"; case .memory: "Bellek"; case .network: "Ağ indirme"; case .disk: "Disk doluluğu"; case .battery: "Pil" }
    }
}

public enum AIUsageMenuStyle: String, CaseIterable, Codable, Sendable {
    case bars, percent, both
    public var label: String { switch self { case .bars: "Çubuk"; case .percent: "Yüzde"; case .both: "İkisi" } }
}

public enum MenuWidgetSelection: String, CaseIterable, Codable, Sendable {
    case manual, topFourFiveHour
    public var label: String {
        switch self { case .manual: "Seçtiğim widget'lar"; case .topFourFiveHour: "AI · En yüksek 4 (5 saat)" }
    }
}

public struct MonitorPreferences: Codable, Sendable, Equatable {
    public static let intervals = [2, 5, 10]
    public var theme: MonitorTheme
    public var interval: Int
    public var menuMetrics: [MenuMetric]
    public var usageMenu: Bool
    public var usageMenuStyle: AIUsageMenuStyle
    public var usageShowsLeft: Bool
    public var usageResetRelative: Bool
    public var menuWidgets: [MenuWidget]?
    public var menuWidgetSelection: MenuWidgetSelection
    public init(theme: MonitorTheme = .dark, interval: Int = 2, menuMetrics: [MenuMetric] = [.cpu, .memory], usageMenu: Bool = true,
                usageMenuStyle: AIUsageMenuStyle = .both, usageShowsLeft: Bool = false, usageResetRelative: Bool = false,
                menuWidgets: [MenuWidget]? = nil, menuWidgetSelection: MenuWidgetSelection = .manual) {
        self.theme = theme
        self.interval = Self.intervals.contains(interval) ? interval : 2
        self.menuMetrics = Self.normalized(menuMetrics)
        self.usageMenu = usageMenu; self.usageMenuStyle = usageMenuStyle
        self.usageShowsLeft = usageShowsLeft; self.usageResetRelative = usageResetRelative
        self.menuWidgets = menuWidgets.map(MenuWidget.normalized)
        self.menuWidgetSelection = menuWidgetSelection
    }
    public var backgroundInterval: Int { max(10, interval) }
    public func pollingInterval(visible: Bool) -> Int { visible ? interval : backgroundInterval }
    public static func normalized(_ values: [MenuMetric]) -> [MenuMetric] {
        Array(MenuMetric.allCases.filter { values.contains($0) }.prefix(3))
    }
    enum CodingKeys: String, CodingKey { case theme, interval, menuMetrics, usageMenu, usageMenuStyle, usageShowsLeft, usageResetRelative, menuWidgets, menuWidgetSelection }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let theme = try c.decodeIfPresent(String.self, forKey: .theme).flatMap(MonitorTheme.init(rawValue:)) ?? .dark
        let interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? 2
        let metrics = try c.decodeIfPresent([String].self, forKey: .menuMetrics)?.compactMap(MenuMetric.init(rawValue:)) ?? [.cpu, .memory]
        self.init(theme: theme, interval: interval, menuMetrics: metrics)
        usageMenu = try c.decodeIfPresent(Bool.self, forKey: .usageMenu) ?? true
        usageMenuStyle = try c.decodeIfPresent(String.self, forKey: .usageMenuStyle).flatMap(AIUsageMenuStyle.init(rawValue:)) ?? .both
        usageShowsLeft = try c.decodeIfPresent(Bool.self, forKey: .usageShowsLeft) ?? false
        usageResetRelative = try c.decodeIfPresent(Bool.self, forKey: .usageResetRelative) ?? false
        menuWidgetSelection = try c.decodeIfPresent(String.self, forKey: .menuWidgetSelection).flatMap(MenuWidgetSelection.init(rawValue:)) ?? .manual
        if c.contains(.menuWidgets), !(try c.decodeNil(forKey: .menuWidgets)) {
            var list = try c.nestedUnkeyedContainer(forKey: .menuWidgets)
            var widgets: [MenuWidget] = []
            while !list.isAtEnd {
                let item = try list.superDecoder()
                if let widget = try? MenuWidget(from: item) { widgets.append(widget) }
            }
            menuWidgets = MenuWidget.normalized(widgets)
        }
    }
}

/// Invalidates in-flight reads at lifecycle boundaries. A gap never becomes a rate sample.
public struct SamplingLifecycle: Sendable {
    public private(set) var paused = false
    public private(set) var sleeping = false
    public private(set) var stopped = false
    public private(set) var generation: UInt64 = 0
    public private(set) var resetRequired = true
    public init() { }
    public var canSample: Bool { !paused && !sleeping && !stopped }
    public func accepts(_ token: UInt64) -> Bool { canSample && generation == token }
    @discardableResult public mutating func setPaused(_ value: Bool) -> Bool {
        guard paused != value else { return false }
        paused = value; invalidate(); return true
    }
    @discardableResult public mutating func setSleeping(_ value: Bool) -> Bool {
        guard sleeping != value else { return false }
        sleeping = value; invalidate(); return true
    }
    public mutating func stop() { stopped = true; invalidate() }
    public mutating func didReset(for token: UInt64) {
        if accepts(token) { resetRequired = false }
    }
    private mutating func invalidate() { generation &+= 1; resetRequired = true }
}
