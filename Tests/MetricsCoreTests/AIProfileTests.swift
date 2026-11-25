import Foundation
import Testing
@testable import MetricsCore

struct AIProfileTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let first = AIUsage.AccountProfile(email: "first@example.test", subscriptionAnchor: nil)
    private let second = AIUsage.AccountProfile(email: "second@example.test", subscriptionAnchor: nil)

    @Test func profileParserRequiresAnAccountEmailAndUsesTheMatchingSubscription() throws {
        let data = Data(#"{"account":{"email":" first@example.test ","full_name":"ignored"},"organization":{"subscription_created_at":"2026-07-25T10:00:00Z"},"unrelated":"ignored"}"#.utf8)
        let profile = try #require(AIUsage.parseProfile(data))
        #expect(profile.email == first.email)
        #expect(profile.subscriptionAnchor == AIUsage.parseDate("2026-07-25T10:00:00Z"))
        #expect(AIUsage.parseProfile(Data(#"{"account":{"email":"missing-at"}}"#.utf8)) == nil)
        #expect(AIUsage.parseProfile(Data(#"{"account":{"email":"first@"}}"#.utf8)) == nil)
        #expect(AIUsage.parseProfile(Data(#"{"account":{"email":"first@exa mple.test"}}"#.utf8)) == nil)
        #expect(AIUsage.parseProfile(Data(#"{"email":"first@example.test"}"#.utf8)) == nil)
        #expect(AIUsage.parseProfile(Data(repeating: 32, count: (256 << 10) + 1)) == nil)
    }

    @Test func staleConfigurationDoesNotOverrideTheActiveProfileOrInventAnIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("account.json")
        let original = Data(#"{"oauthAccount":{"emailAddress":"wrong@example.test","subscriptionCreatedAt":"2025-06-23T00:00:00Z"}}"#.utf8)
        try original.write(to: path)
        let account = AIUsage.Account(n: 9901, dir: directory.path, config: path.path, service: "fixture")
        let credentials = AIUsage.Credentials(token: "fixture", expiresAt: now.addingTimeInterval(3600), plan: "Max 5x")
        let anchor = try #require(AIUsage.parseDate("2026-07-25T00:00:00Z"))
        let state = AIUsage.loadState(account, creds: credentials, now: now, names: [:],
                                     profile: .init(email: first.email, subscriptionAnchor: anchor))
        #expect(state.email == first.email && state.compactLabel == "first@e")
        #expect(state.subscriptionAnchor == anchor)
        let unavailable = AIUsage.loadState(account, creds: credentials, now: now, names: [:])
        #expect(unavailable.email.isEmpty && unavailable.compactLabel == "Account 9901")
        #expect(unavailable.subscriptionAnchor == nil)
        let report = AIUsage.scanTokens(accounts: [account], now: now, projectsDir: directory.path,
            indexPath: directory.appendingPathComponent("index.json").path, subscriptionAnchors: [9901: anchor])
        #expect(report.byAccount[9901]?.period == AIUsage.billingPeriod(anchor: anchor, now: now))
        let unknown = AIUsage.scanTokens(accounts: [account], now: now, projectsDir: directory.path,
            indexPath: directory.appendingPathComponent("index.json").path, subscriptionAnchors: [:])
        #expect(unknown.byAccount.isEmpty)
        #expect(try Data(contentsOf: path) == original)
    }

    @Test func profileCacheIsBoundToTheCredentialAndTheSource() async {
        let cache = AIUsage.ProfileCache()
        let calls = Counter()
        let a = await cache.resolve(source: "one", credential: "credential-a", now: now, allowsFetch: true) {
            await calls.increment(); return .init(profile: first)
        }
        let reuse = await cache.resolve(source: "one", credential: "credential-a", now: now.addingTimeInterval(60), allowsFetch: true) {
            await calls.increment(); return .init(profile: second)
        }
        #expect(a == first && reuse == first)
        #expect(await calls.value == 1)
        let changed = await cache.resolve(source: "one", credential: "credential-b", now: now, allowsFetch: false) {
            await calls.increment(); return .init(profile: second)
        }
        #expect(changed == nil)
        let otherSource = await cache.resolve(source: "two", credential: "credential-a", now: now, allowsFetch: false) {
            await calls.increment(); return .init(profile: first)
        }
        #expect(otherSource == nil)
        #expect(await calls.value == 1)
        let refreshed = await cache.resolve(source: "one", credential: "credential-b", now: now, allowsFetch: true) {
            await calls.increment(); return .init(profile: second)
        }
        #expect(refreshed == second)
        #expect(await calls.value == 2)
    }

    @Test func unavailableProfileHonorsBackoffAndKeepsOnlyTheSameCredentialIdentity() async {
        let cache = AIUsage.ProfileCache()
        let calls = Counter()
        _ = await cache.resolve(source: "one", credential: "credential-a", now: now, allowsFetch: true) { .init(profile: first) }
        let retryTime = now.addingTimeInterval(3601)
        let failed = await cache.resolve(source: "one", credential: "credential-a", now: retryTime, allowsFetch: true) {
            await calls.increment(); return .init(retrySeconds: 600)
        }
        let blocked = await cache.resolve(source: "one", credential: "credential-a", now: retryTime.addingTimeInterval(599), allowsFetch: true) {
            await calls.increment(); return .init(profile: second)
        }
        #expect(failed == first && blocked == first)
        #expect(await calls.value == 1)
        let fresh = await cache.resolve(source: "one", credential: "credential-a", now: retryTime.addingTimeInterval(601), allowsFetch: true) {
            await calls.increment(); return .init(profile: second)
        }
        #expect(fresh == second)
        let changed = await cache.resolve(source: "one", credential: "credential-b", now: retryTime, allowsFetch: true) { .init() }
        #expect(changed == nil)
    }

    @Test func aLateResponseFromTheFormerCredentialCannotRestoreTheWrongIdentity() async {
        let cache = AIUsage.ProfileCache()
        let gate = Gate()
        let old = Task {
            await cache.resolve(source: "one", credential: "credential-a", now: now, allowsFetch: true) {
                await gate.wait(); return .init(profile: first)
            }
        }
        await gate.started()
        let current = await cache.resolve(source: "one", credential: "credential-b", now: now, allowsFetch: true) { .init(profile: second) }
        await gate.release()
        #expect(await old.value == nil)
        #expect(current == second)
        let saved = await cache.resolve(source: "one", credential: "credential-b", now: now, allowsFetch: false) { .init() }
        #expect(saved == second)
    }

    private actor Counter {
        var value = 0
        func increment() { value += 1 }
    }
    private actor Gate {
        private var waiting: CheckedContinuation<Void, Never>?
        private var onStart: CheckedContinuation<Void, Never>?
        func wait() async {
            await withCheckedContinuation { continuation in
                waiting = continuation; onStart?.resume(); onStart = nil
            }
        }
        func started() async {
            if waiting != nil { return }
            await withCheckedContinuation { onStart = $0 }
        }
        func release() { waiting?.resume(); waiting = nil }
    }
}
