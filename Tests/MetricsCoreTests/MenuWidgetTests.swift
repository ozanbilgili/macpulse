import Foundation
import Testing
@testable import MetricsCore

struct MenuWidgetTests {
    @Test func legacyPreferencesResolveIntoOrderedSourcesWithoutChangingBaseSettings() throws {
        let p = try JSONDecoder().decode(MonitorPreferences.self, from: Data(#"{"theme":"light","interval":5,"menuMetrics":["cpu","memory"],"usageMenuStyle":"percent"}"#.utf8))
        let widgets = p.resolvedWidgets(claudeAccounts: [4, 1, 2, 1], codex: true, openRouter: true)
        #expect(widgets.map(\.id) == ["cpu", "memory", "claude:1", "claude:2", "claude:4", "codex", "openRouter"])
        #expect(widgets[2].style == .percent)
        #expect(p.menuWidgets == nil && p.theme == .light && p.interval == 5)
    }
    @Test func explicitIconOnlyIsDifferentFromAnUneditedLegacyList() throws {
        let p = MonitorPreferences(menuWidgets: [])
        let decoded = try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(p))
        #expect(decoded.menuWidgets == [])
        #expect(decoded.resolvedWidgets(claudeAccounts: [1, 2], codex: true, openRouter: true).isEmpty)
        #expect(!MonitorPreferences().resolvedWidgets(claudeAccounts: [1], codex: false, openRouter: false).isEmpty)
    }
    @Test func explicitOrderAndOptionsSurviveRestartAndMissingSources() throws {
        let order = [MenuWidget(.codex, style: .bars, window: .week, showsLeft: true), MenuWidget(.battery), MenuWidget(.claude, account: 4, style: .percent, window: .five), MenuWidget(.cpu)]
        let p = MonitorPreferences(menuWidgets: order)
        let decoded = try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(p))
        #expect(decoded.resolvedWidgets(claudeAccounts: [], codex: false, openRouter: false) == order)
        // A newly discovered account never changes an explicit user's layout.
        #expect(decoded.resolvedWidgets(claudeAccounts: [1, 4, 5], codex: true, openRouter: true) == order)
    }
    @Test func normalizationKeepsFirstIdentityAndDoesNotImposeOldThreeMetricLimit() {
        let system = MenuMetric.allCases.map { MenuWidget(MenuWidgetKind(rawValue: $0.rawValue)!) }
        let widgets = MenuWidget.normalized([MenuWidget(.claude, account: -1)] + system + [MenuWidget(.cpu), MenuWidget(.claude, account: 2), MenuWidget(.claude, account: 2, style: .bars)])
        #expect(widgets.count == 7 && widgets.last?.style == .both)
        #expect(widgets.map(\.id).prefix(6) == system.map(\.id)[...])
    }
    @Test func unknownWidgetIsSkippedWithoutDiscardingOtherPreferences() throws {
        let p = try JSONDecoder().decode(MonitorPreferences.self, from: Data(#"{"theme":"light","interval":10,"menuWidgets":[{"kind":"future"},{"kind":"claude","account":2,"style":"future","window":"future"},{"kind":"cpu"},{"kind":"claude","account":0}]}"#.utf8))
        #expect(p.theme == .light && p.interval == 10)
        #expect(p.menuWidgets == [MenuWidget(.claude, account: 2), MenuWidget(.cpu)])
    }
    @Test func legacyDisabledAIStaysDisabledUntilExplicitlyAdded() {
        let p = MonitorPreferences(usageMenu: false)
        #expect(p.resolvedWidgets(claudeAccounts: [1, 2], codex: true, openRouter: true).map(\.id) == ["cpu", "memory"])
    }
    @Test func windowSelectionRespectsPlanAndDoesNotFabricateUnavailableLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lite = AIUsage.Usage(five: .init(pct: 0, resetsAt: nil, known: false), week: .init(pct: 20, resetsAt: now.addingTimeInterval(1000)), fetchedAt: now, hasFive: false, hasWeek: true)
        #expect(MenuWidget(.codex, window: .both).windows(in: lite, now: now).map(\.label) == ["Weekly"])
        #expect(MenuWidget(.codex, window: .five).windows(in: lite, now: now).isEmpty)
        #expect(MenuWidget(.codex, window: .week).windows(in: lite, now: now).first?.value.pct == 20)
        #expect(MenuWidget(.codex).windows(in: nil, now: now).isEmpty)
        #expect(MenuWidget(.codex).windows(in: lite, now: now.addingTimeInterval(1001)).first?.value.known == false)
    }
}
