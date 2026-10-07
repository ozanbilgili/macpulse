import Foundation
import Testing
@testable import MetricsCore

@Suite struct AIUsageTests {
    typealias U = AIUsage
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func temp(_ action: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try action(dir)
    }
    private func write(_ dir: URL, _ file: String, _ value: String) throws -> String {
        let p = dir.appendingPathComponent(file); try Data(value.utf8).write(to: p); return p.path
    }
    @Test func claudeNullIsNotStartedButAbsentAndMalformedAreUnknown() throws {
        try temp { dir in
            let path = try write(dir, "usage.json", #"{"five_hour":null,"seven_day":{"utilization":16.4,"resets_at":"2026-10-07T02:00:00.123456Z"}}"#)
            let usage = try #require(U.loadUsage(path: path))
            #expect(usage.hasFive && usage.five.known && usage.five.pct == 0 && usage.five.resetsAt == nil)
            #expect(usage.week.pct == 16 && usage.week.resetsAt != nil)
            let onlyWeek = try write(dir, "week.json", #"{"seven_day":{"utilization":0}}"#)
            #expect(U.loadUsage(path: onlyWeek)?.hasFive == false)
            #expect(!U.parseWindow(["utilization": -1]).known)
            #expect(!U.parseWindow(["utilization": Double.nan]).known)
            #expect(!U.parseWindow(["utilization": "25"]).known)
            #expect(!U.parseWindow(nil).known)
        }
    }
    @Test func resetWithoutNewReadingDoesNotInventZero() {
        let window = U.Window(pct: 80, resetsAt: now.addingTimeInterval(-60)).effective(at: now)
        #expect(!window.known)
    }
    @Test func codexWindowsAreClassifiedByDuration() throws {
        try temp { dir in
            let path = try write(dir, "codex.json", #"{"rate_limit":{"primary_window":{"used_percent":14,"limit_window_seconds":604800,"reset_at":1800000100},"secondary_window":null}}"#)
            let u = try #require(U.loadCodexUsage(path: path))
            #expect(!u.hasFive && u.hasWeek && u.week.pct == 14)
            let reversed = try write(dir, "reverse.json", #"{"rate_limit":{"secondary_window":{"used_percent":30.6,"limit_window_seconds":18000},"primary_window":{"used_percent":9,"limit_window_seconds":604800}}}"#)
            #expect(U.loadCodexUsage(path: reversed)?.five.pct == 31)
            #expect(U.loadCodexUsage(path: reversed)?.week.pct == 9)
        }
    }
    @Test func creditIsAccountBalanceAndRejectsBadNumbers() throws {
        try temp { dir in
            let path = try write(dir, "credit.json", #"{"data":{"total_credits":20,"total_usage":10.52839552}}"#)
            let credit = try #require(U.loadCredit(path: path))
            #expect(abs(credit.remaining - 9.47160448) < 1e-9 && credit.usedPct == 53)
            #expect(U.formatUSD(credit.remaining) == "$9,47")
            let bad = try write(dir, "bad.json", #"{"data":{"total_credits":-1,"total_usage":4}}"#)
            #expect(U.loadCredit(path: bad) == nil)
            #expect(U.Credit(total: 5, used: 6.2, fetchedAt: now).remaining == 0)
            #expect(!U.CreditState(hasKey: false, credit: nil, blockedUntil: nil).visible)
        }
    }
    @Test func paceMatchesUsageThresholds() {
        let length = U.Cfg.weekLength
        let reset = now.addingTimeInterval(length / 2)
        #expect(U.projectPace(pct: 44, resetsAt: reset, length: length, now: now) == .ok(88))
        #expect(U.projectPace(pct: 46, resetsAt: reset, length: length, now: now) == .tight(92))
        #expect(U.projectPace(pct: 50, resetsAt: reset, length: length, now: now) == .tight(100))
        if case .runsOut(let at, _)? = U.projectPace(pct: 60, resetsAt: reset, length: length, now: now) {
            #expect(at < reset)
        } else { Issue.record("Limit should run out before reset") }
        #expect(U.paceStatus(pct: 100, resetsAt: reset, length: length, now: now) == .full)
    }
    @Test func earlyAndTinyUsageDoNotCreateFalseAlarms() {
        let reset = now.addingTimeInterval(U.Cfg.fiveLength - 120)
        #expect(U.projectPace(pct: 10, resetsAt: reset, length: U.Cfg.fiveLength, now: now) == nil)
        let status = U.paceStatus(pct: 4, resetsAt: now.addingTimeInterval(U.Cfg.fiveLength - 300), length: U.Cfg.fiveLength, now: now)
        #expect(U.meterState(pct: 4, status: status) == .level(.normal))
        #expect(U.paceStatus(pct: 5, resetsAt: reset, length: 0, now: now) == .idle)
    }
    @Test func meterAndPaceNotchMatchSourceApp() {
        #expect(U.meterState(pct: 46, status: .projected(.tight(92), 92)) == .closeToLimit(spare: 8, projected: 92))
        #expect(U.meterState(pct: 50, status: .projected(.tight(100), 100)) == .runningOut(eta: nil, projected: 100))
        let reset = now.addingTimeInterval(U.Cfg.weekLength / 2)
        #expect(U.paceTick(.closeToLimit(spare: 8, projected: 92), resetsAt: reset, length: U.Cfg.weekLength, now: now) == 0.5)
        #expect(U.paceTick(.healthy(projected: 60), resetsAt: reset, length: U.Cfg.weekLength, now: now) == nil)
    }
    @Test func resetTimeRoundsToNearestMinute() {
        let date = Date(timeIntervalSince1970: 1_800_000_059.57)
        #expect(U.roundedToMinute(date) == Date(timeIntervalSince1970: 1_800_000_060))
        #expect(U.resetLabel(U.Window(pct: 0, resetsAt: nil), now: now, relative: false, notStarted: true) == "Başlamadı")
    }
    @Test func manualRefreshCannotBypassExpiredCredentialsOrBackoff() {
        #expect(!U.canFetch(valid: false, cacheDate: nil, blockedUntil: nil, force: true, now: now))
        #expect(!U.canFetch(valid: true, cacheDate: nil, blockedUntil: now.addingTimeInterval(60), force: true, now: now))
        #expect(!U.canFetch(valid: true, cacheDate: now, blockedUntil: nil, force: false, now: now))
        #expect(U.canFetch(valid: true, cacheDate: now, blockedUntil: nil, force: true, now: now))
        #expect(U.canFetch(valid: true, cacheDate: now.addingTimeInterval(-301), blockedUntil: nil, force: false, now: now))
    }
    @Test func numericAndLegacyMarkersUseSameCooldown() throws {
        try temp { dir in
            let p = try write(dir, "attempt", String(now.addingTimeInterval(120).timeIntervalSince1970))
            #expect(U.markerBlockedUntil(path: p, now: now) == now.addingTimeInterval(120))
            try Data().write(to: URL(fileURLWithPath: p))
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: p)
            #expect(U.markerBlockedUntil(path: p, now: now) == now.addingTimeInterval(300))
        }
    }
    @Test func billingAnniversaryDoesNotDriftAfterShortMonth() throws {
        let f = ISO8601DateFormatter()
        let anchor = try #require(f.date(from: "2026-01-31T10:00:00Z"))
        let march = U.billingPeriod(anchor: anchor, now: try #require(f.date(from: "2026-03-05T00:00:00Z")))
        #expect(march.start == f.date(from: "2026-02-28T10:00:00Z"))
        #expect(march.end == f.date(from: "2026-03-31T10:00:00Z"))
    }
    private func assistant(_ id: String, tokens: Int) -> String {
        #"{"type":"assistant","timestamp":"2026-10-01T10:05:00Z","requestId":"r","message":{"id":"\#(id)","usage":{"input_tokens":\#(tokens),"output_tokens":5,"cache_creation_input_tokens":3,"cache_read_input_tokens":4}}}"#
    }
    @Test func tokensDeduplicateAndResumeAfterPartialLastLine() throws {
        try temp { dir in
            let line = assistant("m1", tokens: 10)
            let next = assistant("m2", tokens: 20)
            let prefix = String(next.prefix(80)), suffix = String(next.dropFirst(80))
            let path = try write(dir, "transcript.jsonl", line + "\n" + line + "\n" + prefix)
            let first = U.tallyFile(path: path, previous: nil, size: try Data(contentsOf: URL(fileURLWithPath: path)).count, mtime: 1)
            #expect(first.buckets.values.first == [10, 5, 3, 4])
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path)); try handle.seekToEnd(); try handle.write(contentsOf: Data((suffix + "\n").utf8)); try handle.close()
            let second = U.tallyFile(path: path, previous: first, size: try Data(contentsOf: URL(fileURLWithPath: path)).count, mtime: 2)
            #expect(second.buckets.values.first == [30, 10, 6, 8])
            #expect(second.offset == second.size)
        }
    }
    @Test func malformedIndexAndUserLinesDoNotBecomeTokenUsage() throws {
        try temp { dir in
            let path = try write(dir, "transcript.jsonl", assistant("m", tokens: 1) + "\n")
            let broken = U.FileTally(size: 1, mtime: 1, offset: -1, keys: [], buckets: [0: [1]])
            let result = U.tallyFile(path: path, previous: broken, size: try Data(contentsOf: URL(fileURLWithPath: path)).count, mtime: 2)
            #expect(result.buckets.values.first == [1, 5, 3, 4])
            #expect(U.parseUsageLine(#"{"type":"user","message":{"usage":{"input_tokens":10}}}"#) == nil)
            #expect(U.parseUsageLine(Substring(assistant("m", tokens: -1))) == nil)
        }
    }
    @Test func transcriptGrowthAfterInventoryKeepsConsumedPrefixAndCountsNextAppendOnce() throws {
        try temp { dir in
            let line = assistant("m1", tokens: 10) + "\n"
            let path = try write(dir, "growing.jsonl", line)
            // Inventory observed a smaller file just before the producer appended.
            let first = U.tallyFile(path: path, previous: nil, size: 1, mtime: 1)
            #expect(first.size == line.utf8.count && first.offset == first.size)
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path)); try handle.seekToEnd()
            try handle.write(contentsOf: Data((assistant("m2", tokens: 20) + "\n").utf8)); try handle.close()
            let second = U.tallyFile(path: path, previous: first, size: try Data(contentsOf: URL(fileURLWithPath: path)).count, mtime: 2)
            #expect(second.buckets.values.first == [30, 10, 6, 8])
            #expect(second.offset == second.size)
        }
    }
    @Test func sessionOwnersAndSubagentsRetainAttribution() {
        #expect(U.sessionId(ofTranscript: "/tmp/proj/session/subagents/agent.jsonl") == "session")
        #expect(U.sessionId(ofTranscript: "/tmp/proj/session.jsonl") == "session")
        #expect(U.owner(of: 7200, in: [(born: 0, n: 1), (born: 8000, n: 2)]) == 2)
        #expect(U.owner(of: 0, in: []) == nil)
    }
    @Test func credentialParsingIsReadOnlyAndRedactsDescription() throws {
        try temp { dir in
            let claims = #"{"exp":1800000000,"https://api.openai.com/auth":{"chatgpt_plan_type":"prolite"}}"#
            let jwt = "e30." + Data(claims.utf8).base64EncodedString() + ".fixture"
            let p = try write(dir, "auth.json", "{\"tokens\":{\"access_token\":\"\(jwt)\"}}")
            let before = try Data(contentsOf: URL(fileURLWithPath: p))
            let c = try #require(U.readCodexCredentials(path: p))
            #expect(c.plan == "Pro Lite" && !c.isValid(at: now))
            #expect(c.description == "Credentials(<redacted>)")
            #expect(try Data(contentsOf: URL(fileURLWithPath: p)) == before)
        }
    }
    @Test func privateAtomicFilesAndNamesDoNotContainCredentials() throws {
        try temp { dir in
            let p = dir.appendingPathComponent("names.json").path
            U.saveName(2, "  Test hesabı  ", path: p)
            #expect(U.loadNames(path: p)[2] == "Test hesabı")
            let attrs = try FileManager.default.attributesOfItem(atPath: p)
            #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            U.saveName(2, "", path: p); #expect(U.loadNames(path: p).isEmpty)
        }
    }
    @Test func existingPreferencesKeepThemeIntervalAndMetrics() throws {
        let p = try JSONDecoder().decode(MonitorPreferences.self, from: Data(#"{"theme":"light","interval":5,"menuMetrics":["cpu","gpu","memory"]}"#.utf8))
        #expect(p.theme == .light && p.interval == 5 && p.menuMetrics == [.cpu, .gpu, .memory])
        #expect(p.usageMenu && p.usageMenuStyle == .both && !p.usageShowsLeft && !p.usageResetRelative)
        #expect(try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(p)) == p)
    }
}
