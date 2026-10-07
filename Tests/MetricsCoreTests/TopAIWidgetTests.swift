import Foundation
import Testing
@testable import MetricsCore

struct TopAIWidgetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func state(_ n: Int, _ pct: Int, provider: AIUsage.Provider = .claude) -> AIUsage.AccountState {
        .init(account: .init(n: n, dir: "", config: "", service: "", provider: provider), email: "", label: "Hesap \(n)", plan: "Test",
              loggedIn: true, tokenExpired: false,
              usage: .init(five: .init(pct: pct, resetsAt: now.addingTimeInterval(3600)),
                           week: .init(pct: 100 - pct, resetsAt: now.addingTimeInterval(86400)), fetchedAt: now), blockedUntil: nil)
    }
    @Test func highestFourComeFromFiveHourUsageAcrossAllAccounts() {
        let states = [34, 78, 25, 95, 60, 10, 66, 12].enumerated().map { state($0.offset + 1, $0.element) }
        let widgets = MenuWidget.topFiveHourWidgets(states: states, now: now)
        #expect(widgets.map(\.account) == [4, 2, 7, 5])
        #expect(widgets.allSatisfy { $0.window == .five && $0.style == .percent && !$0.showsLeft })
    }
    @Test func unavailableReadingsDoNotBecomeZerosOrWeeklyFallbacks() {
        var states = (1...9).map { state($0, 90) }
        states[0].usage?.five.pct = 0
        states[1].usage?.five.known = false
        states[2].usage?.fetchedAt = now.addingTimeInterval(-AIUsage.Cfg.staleSeconds - 1)
        states[3].usage?.five.resetsAt = now
        states[4].usage?.hasFive = false
        states[5].tokenExpired = true
        states[6].loggedIn = false
        states[7].usage?.fetchedAt = now.addingTimeInterval(10)
        states[8].usage?.five.pct = 101
        #expect(MenuWidget.topFiveHourWidgets(states: states, now: now).map(\.account) == [1])
        #expect(MenuWidget.topFiveHourWidgets(states: [], now: now).isEmpty)
    }
    @Test func equalPercentagesHaveStableOrderAndDuplicateSourcesDoNotTakeSlots() {
        let states = [state(5, 50), state(4, 50), state(3, 50), state(2, 50), state(1, 50), state(1, 50), state(0, 92, provider: .codex)]
        let expected = ["codex", "claude:1", "claude:2", "claude:3"]
        #expect(MenuWidget.topFiveHourWidgets(states: states, now: now).map(\.id) == expected)
        #expect(MenuWidget.topFiveHourWidgets(states: Array(states.reversed()), now: now).map(\.id) == expected)
    }
    @Test func currentResetAndRefreshCanReplaceAnAccountInTheTopFour() {
        var states = [state(1, 100), state(2, 90), state(3, 80), state(4, 70), state(5, 60)]
        states[0].usage?.five.resetsAt = now.addingTimeInterval(1)
        #expect(MenuWidget.topFiveHourWidgets(states: states, now: now).map(\.account) == [1, 2, 3, 4])
        #expect(MenuWidget.topFiveHourWidgets(states: states, now: now.addingTimeInterval(2)).map(\.account) == [2, 3, 4, 5])
        states[4].usage?.five.pct = 99
        #expect(MenuWidget.topFiveHourWidgets(states: states, now: now.addingTimeInterval(2)).map(\.account) == [5, 2, 3, 4])
    }
    @Test func automaticSelectionPersistsWithoutOverwritingManualWidgets() throws {
        let original = MonitorPreferences(theme: .light, interval: 5,
            menuWidgets: [MenuWidget(.battery), MenuWidget(.codex, window: .week)], menuWidgetSelection: .topFourFiveHour)
        let decoded = try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.resolvedWidgets(claudeAccounts: [1, 2], codex: true, openRouter: true) == original.menuWidgets)
        let old = try JSONDecoder().decode(MonitorPreferences.self, from: Data(#"{"theme":"dark","menuWidgets":[{"kind":"cpu"}]}"#.utf8))
        #expect(old.menuWidgetSelection == .manual && old.menuWidgets == [MenuWidget(.cpu)])
        let future = try JSONDecoder().decode(MonitorPreferences.self, from: Data(#"{"menuWidgetSelection":"future"}"#.utf8))
        #expect(future.menuWidgetSelection == .manual)
    }
}
