import Foundation
import Testing
@testable import MetricsCore

/// Numbers follow the given locale; words come from the app's catalog, which tests do not load (English keys).
@Suite struct LocalizedFormatTests {
    private let en = Locale(identifier: "en_US")
    private let tr = Locale(identifier: "tr_TR")

    @Test func percentFollowsLocale() {
        #expect(LocalizedFormat.percent(32, locale: en) == "32%")
        #expect(LocalizedFormat.percent(32, locale: tr) == "%32")
        #expect(LocalizedFormat.percent(92.34, digits: 1, locale: en) == "92.3%")
        #expect(LocalizedFormat.percent(92.34, digits: 1, locale: tr) == "%92,3")
    }

    @Test func tokenTotalsKeepCompactUnitsAndLocaleDigits() {
        #expect(AIUsage.formatTokens(1_234_567_890, locale: en) == "1.23B")
        #expect(AIUsage.formatTokens(345_600_000, locale: en) == "346M")
        #expect(AIUsage.formatTokens(12_340, locale: tr) == "12,3K")
        #expect(AIUsage.formatTokens(850, locale: en) == "850")
    }

    @Test func datesUseLocaleNamesAndClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 14)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 14)))
        let period = AIUsage.BillingPeriod(start: start, end: end)
        #expect(AIUsage.formatPeriod(period, locale: en) == "Sep 25 – Oct 25")
        #expect(AIUsage.formatPeriod(period, locale: tr) == "25 Eyl – 25 Eki")
        let sameDay = start.addingTimeInterval(-3600)
        #expect(AIUsage.formatReset(start, now: sameDay, locale: tr) == "14:00")
        #expect(AIUsage.formatReset(start, now: sameDay, locale: en).replacingOccurrences(of: "\u{202F}", with: " ") == "2:00 PM")
        #expect(AIUsage.formatReset(start, now: start.addingTimeInterval(-86_400), locale: tr) == "Cum 14:00")
    }

    @Test func meterAndResetTextReadAsSentences() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AIUsage.Window(pct: 40, resetsAt: now.addingTimeInterval(7200))
        #expect(AIUsage.resetLabel(window, now: now, relative: true, notStarted: false) == "Resets in 2h 0m")
        #expect(AIUsage.resetLabel(window, now: now, relative: true, notStarted: false, compact: true) == "↻ 2h 0m")
        #expect(AIUsage.resetLabel(window, now: now, relative: true, notStarted: true, compact: true) == "Not started")
        #expect(AIUsage.meterNote(.spent, now: now, relative: false) == "Limit reached")
        #expect(AIUsage.meterNote(.runningOut(eta: now.addingTimeInterval(3600), projected: 140), now: now, relative: true) == "Runs out in 1h 0m")
        #expect(AIUsage.meterNote(.runningOut(eta: now.addingTimeInterval(60), projected: 140), now: now, relative: true) == "Runs out soon")
        #expect(AIUsage.meterNote(.healthy(projected: 64), now: now, relative: false)?.hasSuffix(" left at reset") == true)
        let when = try #require(AIUsage.formatWhen(now.addingTimeInterval(60), now: now, relative: false, locale: tr))
        #expect(when.hasPrefix("today ") || when.hasPrefix("tomorrow "))
    }

    @Test func englishSourceStringsAndDurations() {
        #expect(AIUsage.formatDuration(90 * 60) == "1h 30m")
        #expect(AIUsage.formatDuration(26 * 3600) == "1d 2h")
        #expect(AIUsage.accountLabel(12345, names: [:]) == "Account 12345")
        #expect(MenuWidgetWindow.five.label == "5-hour")
        #expect(HistoryRange.week.label == "7 days")
    }
}
