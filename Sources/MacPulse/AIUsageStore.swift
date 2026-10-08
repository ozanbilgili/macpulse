import Foundation
import Observation
import MetricsCore

/// Uses the monitor's existing tick. Network/cache and token jobs have one in-flight
/// task each; no independent timer, credential refresh or login side effect.
@MainActor @Observable final class AIUsageStore {
    var states: [AIUsage.AccountState] = []
    var credit: AIUsage.CreditState?
    var tokens = AIUsage.TokenReport()
    var now = Date()
    var checking = false
    var scanning = false
    var lastCheck: Date?
    let isolated: Bool
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var nextCheck = Date.distantPast
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var tokenIdentityGeneration = 0
    init(isolated: Bool) { self.isolated = isolated }

    var availableClaude: Int {
        states.filter { s in
            guard s.account.provider == .claude, s.loggedIn, !s.tokenExpired, let u = s.usage,
                  now.timeIntervalSince(u.fetchedAt) <= AIUsage.Cfg.staleSeconds else { return false }
            let windows = [(u.hasFive, u.five), (u.hasWeek, u.week)].filter(\.0).map { $0.1.effective(at: now) }
            return !windows.isEmpty && windows.allSatisfy { $0.known && $0.pct < 100 }
        }.count
    }
    var claudeCount: Int { states.filter { $0.account.provider == .claude }.count }
    var summary: String { "Claude \(availableClaude)/\(claudeCount) kullanılabilir" }

    func tick() {
        now = Date()
        guard !isolated, !stopped, now >= nextCheck else { return }
        refresh(force: false)
    }
    func refresh(force: Bool) {
        guard !isolated, !stopped, refreshTask == nil else { return }
        checking = true
        nextCheck = Date().addingTimeInterval(60)
        refreshTask = Task { [weak self] in
            // A cold UI can immediately display the shared cache while OAuth fetch runs.
            let cached = await Task.detached(priority: .utility) {
                let names = AIUsage.loadNames()
                let states = AIUsage.discoverAccounts().map { AIUsage.loadState($0, creds: nil, names: names) }
                let credit = AIUsage.loadCreditState(hasKey: false)
                return (states, credit)
            }.value
            if let self, self.states.isEmpty, !Task.isCancelled { self.states = cached.0; self.credit = cached.1.visible ? cached.1 : nil }
            let job = Task.detached(priority: .utility) {
                async let accounts = AIUsage.refreshAll(fetch: true, force: force)
                async let credit = AIUsage.refreshCredit(fetch: true, force: force)
                return await (accounts, credit)
            }
            let result = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            guard let self else { return }
            if !Task.isCancelled, !self.stopped {
                let oldProfiles = Dictionary(uniqueKeysWithValues: self.states.filter { $0.account.provider == .claude }.map {
                    ($0.account.cacheKey, AIUsage.AccountProfile(email: $0.email, subscriptionAnchor: $0.subscriptionAnchor))
                })
                let newProfiles = Dictionary(uniqueKeysWithValues: result.0.filter { $0.account.provider == .claude }.map {
                    ($0.account.cacheKey, AIUsage.AccountProfile(email: $0.email, subscriptionAnchor: $0.subscriptionAnchor))
                })
                if oldProfiles != newProfiles {
                    self.tokenIdentityGeneration += 1
                    self.scanTask?.cancel()
                    self.tokens = AIUsage.TokenReport()
                }
                self.states = result.0; self.credit = result.1.visible ? result.1 : nil
                self.now = Date(); self.lastCheck = self.now
                self.scanIfDue()
            }
            self.checking = false; self.refreshTask = nil
        }
    }
    func scanIfDue() {
        guard !isolated, !stopped, scanTask == nil, Date().timeIntervalSince(tokens.scannedAt) >= 120 else { return }
        scanning = true
        let accounts = states.map(\.account)
        let anchors = Dictionary(uniqueKeysWithValues: states.filter { $0.account.provider == .claude }.compactMap { state in
            state.subscriptionAnchor.map { (state.account.n, $0) }
        })
        let generation = tokenIdentityGeneration
        scanTask = Task { [weak self] in
            let job = Task.detached(priority: .utility) { AIUsage.scanTokens(accounts: accounts, subscriptionAnchors: anchors) }
            let report = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            guard let self else { return }
            if !Task.isCancelled, !self.stopped, generation == self.tokenIdentityGeneration { self.tokens = report }
            self.scanning = false; self.scanTask = nil
            if generation != self.tokenIdentityGeneration, !self.stopped { self.scanIfDue() }
        }
    }
    func rename(_ account: AIUsage.Account, name: String) {
        guard !isolated, account.provider == .claude else { return }
        Task {
            await Task.detached(priority: .utility) { AIUsage.saveName(account.n, name) }.value
            let names = await Task.detached(priority: .utility) { AIUsage.loadNames() }.value
            for i in states.indices where states[i].account.provider == .claude { states[i].label = AIUsage.accountLabel(states[i].account.n, names: names) }
        }
    }
    func finish() async {
        stopped = true; refreshTask?.cancel(); scanTask?.cancel()
        await refreshTask?.value; await scanTask?.value
    }
}
