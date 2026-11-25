import SwiftUI
import MetricsCore

struct AIUsageView: View {
    @Bindable var store: AIUsageStore
    @Bindable var preferences: PreferencesStore
    private enum ProviderFilter: Hashable { case all, claude, codex, openRouter }
    @State private var filter = ProviderFilter.all
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI Usage").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(store.isolated ? String(localized: "Account sources are not read in the isolated acceptance profile") : store.summary + (store.lastCheck.map { " · " + String(localized: "Last checked \(AIUsage.formatClock($0))") } ?? ""))
                        .font(.callout).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button { store.refresh(force: true) } label: {
                    Label(store.checking ? "Checking" : "Refresh", systemImage: "arrow.clockwise")
                }.disabled(store.checking || store.isolated).keyboardShortcut("r")
            }
            HStack {
                Picker("Provider", selection: $filter) {
                    Text("All").tag(ProviderFilter.all)
                    Text(verbatim: "Claude").tag(ProviderFilter.claude)
                    Text(verbatim: "Codex").tag(ProviderFilter.codex)
                    Text(verbatim: "OpenRouter").tag(ProviderFilter.openRouter)
                }.pickerStyle(.segmented).frame(maxWidth: 420)
                Spacer()
                if store.scanning { ProgressView().controlSize(.small); Text("Counting tokens").font(.caption).foregroundStyle(Palette.secondary) }
            }
            if store.states.isEmpty && store.credit == nil {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(Palette.memory)
                    Text(store.checking ? "Reading local accounts" : "No usage data found").font(.headline)
                    Text("Uses your Claude Code and Codex sessions, and your existing OpenRouter key.")
                        .foregroundStyle(Palette.secondary).font(.callout)
                }.frame(maxWidth: .infinity).padding(40).usageCard()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 390), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(store.states.filter { filter == .all || ($0.account.provider == .claude ? filter == .claude : filter == .codex) }, id: \.account.cacheKey) { state in
                    AIAccountCard(state: state, tokens: store.tokens.byAccount[state.account.n], now: store.now,
                                  checking: store.checking, preferences: preferences, rename: { store.rename(state.account, name: $0) })
                }
                if let credit = store.credit, filter == .all || filter == .openRouter {
                    AICreditCard(state: credit, now: store.now)
                }
            }
            if store.tokens.unattributed.total > 0, filter == .all || filter == .claude {
                Label("Sessions with no identified account: \(AIUsage.formatTokens(store.tokens.unattributed.total)) tokens", systemImage: "questionmark.circle")
                    .font(.callout).foregroundStyle(Palette.secondary).help(AIUsage.tokenBreakdown(store.tokens.unattributed))
            }
            Text("Limits come from each provider; every card shows how old its cached reading is. Pace assumes usage continues at the same rate. The token total is the usage found in local Claude transcripts for this billing period; deleted transcripts and hourly account matching can affect it.")
                .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Label("Add accounts to the menu bar", systemImage: "menubar.rectangle")
                Spacer()
                Button("Edit widgets") { openWindow(id: "menu-widgets") }
            }.font(.callout).padding(16).usageCard()
        }
    }
}

struct AIAccountCard: View {
    let state: AIUsage.AccountState
    let tokens: AIUsage.PeriodTokens?
    let now: Date
    let checking: Bool
    @Bindable var preferences: PreferencesStore
    var rename: (String) -> Void
    @State private var editing = false
    @State private var name = ""
    private var claude: Bool { state.account.provider == .claude }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProviderLogoView(logo: claude ? .claude : .codex).frame(width: 22, height: 22)
                    .foregroundStyle(claude ? aiAccountColor(state.account.n) : Color.primary)
                    .frame(width: 38, height: 38).background(Palette.elevated, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(claude ? "Claude · \(state.label)" : "Codex").font(.headline)
                        if state.plan != "?" { Text(state.plan).font(.caption).foregroundStyle(Palette.secondary) }
                    }
                    if !state.email.isEmpty { Text(state.email).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle) }
                }
                Spacer()
                if claude {
                    Button { name = state.label; editing = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain).accessibilityLabel("Rename \(state.label)").disabled(preferences.acceptance != nil)
                        .popover(isPresented: $editing) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Account name").font(.headline)
                                TextField("Account name", text: $name).textFieldStyle(.roundedBorder)
                                HStack { Button("Cancel") { editing = false }; Spacer(); Button("Save") { rename(name); editing = false }.keyboardShortcut(.defaultAction) }
                            }.padding(20).frame(width: 270)
                        }
                }
            }
            if let u = state.usage, u.hasFive || u.hasWeek {
                if u.hasFive { AIUsageMeter(fiveHour: true, window: u.five.effective(at: now), meter: u.meterFive(now: now), length: AIUsage.Cfg.fiveLength, now: now, preferences: preferences) }
                if u.hasWeek { AIUsageMeter(fiveHour: false, window: u.week.effective(at: now), meter: u.meterWeek(now: now), length: AIUsage.Cfg.weekLength, now: now, preferences: preferences) }
            } else {
                Label(checking ? "Checking usage" : state.loggedIn ? "No usage data yet" : "Not signed in to this account", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 8) {
                if let u = state.usage, [(u.hasFive, u.five), (u.hasWeek, u.week)].contains(where: { $0.0 && $0.1.effective(at: now).known && $0.1.effective(at: now).pct >= 100 }) {
                    Label("Full", systemImage: "xmark.octagon.fill").foregroundStyle(Palette.limitCritical)
                }
                if let u = state.usage {
                    Label("\(AIUsage.formatDuration(now.timeIntervalSince(u.fetchedAt))) ago", systemImage: "clock")
                        .foregroundStyle(now.timeIntervalSince(u.fetchedAt) > AIUsage.Cfg.staleSeconds ? Palette.disk : Palette.secondary)
                }
                if state.tokenExpired { Label("Session expired", systemImage: "key").foregroundStyle(Palette.disk) }
                if !state.loggedIn && !checking { Text("Signed out").foregroundStyle(Palette.disk) }
                Spacer()
            }.font(.caption)
            if let blocked = state.blockedUntil {
                Text("Next check in \(AIUsage.formatCountdown(blocked, now: now))").font(.caption).foregroundStyle(Palette.secondary)
            }
            if claude, let tokens {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("This period").font(.callout); Text(AIUsage.formatPeriod(tokens.period)).font(.caption).foregroundStyle(Palette.secondary) }
                    Spacer()
                    Text("\(AIUsage.formatTokens(tokens.counts.total)) tokens").font(.title3.weight(.semibold)).monospacedDigit()
                }
                Text("Output \(AIUsage.formatTokens(tokens.counts.output))").font(.caption).foregroundStyle(Palette.secondary)
                DisclosureGroup("Token details") {
                    VStack(alignment: .leading, spacing: 8) {
                        tokenLine("Input tokens", tokens.counts.input); tokenLine("Output tokens", tokens.counts.output)
                        tokenLine("Cache write", tokens.counts.cacheWrite); tokenLine("Cache read", tokens.counts.cacheRead)
                    }.font(.caption).padding(.top, 8)
                }.font(.caption).foregroundStyle(Palette.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).usageCard()
    }
    private func tokenLine(_ title: LocalizedStringKey, _ count: Int) -> some View { HStack { Text(title); Spacer(); Text(AIUsage.formatTokens(count)).monospacedDigit() } }
}

struct AIUsageMeter: View {
    let fiveHour: Bool
    let window: AIUsage.Window
    let meter: AIUsage.MeterState
    let length: TimeInterval
    let now: Date
    @Bindable var preferences: PreferencesStore
    private var title: String { fiveHour ? String(localized: "5-hour") : String(localized: "Weekly") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                if window.known, let note = AIUsage.meterNote(meter, now: now, relative: preferences.usageResetRelative) {
                    Text(note).font(.caption).foregroundStyle(aiMeterColor(meter.severity))
                }
            }
            if window.known {
                AIUsageBar(percent: window.pct, color: aiMeterColor(meter.severity), tick: AIUsage.paceTick(meter, resetsAt: window.resetsAt, length: length, now: now))
                    .help(AIUsage.meterTooltip(meter) ?? "")
                HStack {
                    Button { preferences.usageShowsLeft.toggle() } label: {
                        Text(preferences.usageShowsLeft ? "\(LocalizedFormat.percent(max(0, 100 - window.pct))) left" : "\(LocalizedFormat.percent(window.pct)) used").monospacedDigit()
                    }.buttonStyle(.plain).help("Switch between used and remaining percentage")
                    Spacer()
                    if let reset = AIUsage.resetLabel(window, now: now, relative: preferences.usageResetRelative, notStarted: fiveHour && window.pct == 0 && window.resetsAt == nil) {
                        Button { preferences.usageResetRelative.toggle() } label: { Text(reset) }
                            .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("Switch between clock time and countdown")
                    }
                }.font(.caption)
            } else {
                Text("— · Waiting for new usage data").font(.caption).foregroundStyle(Palette.secondary)
                AIUsageBar(percent: 0, color: Palette.secondary).accessibilityHidden(true)
            }
        }
    }
}

struct AIUsageBar: View {
    let percent: Int
    let color: Color
    var tick: Double? = nil
    var height: CGFloat = 7
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.elevated)
                Capsule().fill(color).frame(width: g.size.width * CGFloat(min(100, max(0, percent))) / 100)
                if let tick { Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 2).offset(x: max(0, min(g.size.width - 2, g.size.width * tick))) }
            }
        }.frame(height: height).accessibilityElement(children: .ignore).accessibilityLabel("Usage").accessibilityValue(LocalizedFormat.percent(percent))
    }
}

struct AICreditCard: View {
    let state: AIUsage.CreditState
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("OpenRouter", systemImage: "arrow.triangle.branch").font(.headline).foregroundStyle(Palette.network)
            if let c = state.credit {
                if c.remaining < 0.005 { Label("Balance used up", systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(Palette.limitCritical) }
                Text(AIUsage.formatUSD(c.remaining)).font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("Remaining account balance").font(.callout).foregroundStyle(Palette.secondary)
                AIUsageBar(percent: c.usedPct, color: aiMeterColor(AIUsage.levelState(c.usedPct).severity))
                HStack { Text("\(LocalizedFormat.percent(c.usedPct)) used"); Spacer(); Text("\(AIUsage.formatUSD(c.used)) / \(AIUsage.formatUSD(c.total))") }.font(.caption).foregroundStyle(Palette.secondary)
                Label("\(AIUsage.formatDuration(now.timeIntervalSince(c.fetchedAt))) ago", systemImage: "clock").font(.caption)
                    .foregroundStyle(now.timeIntervalSince(c.fetchedAt) > AIUsage.Cfg.staleSeconds ? Palette.disk : Palette.secondary)
            } else { Text("No balance data yet").foregroundStyle(Palette.secondary) }
            if !state.hasKey { Label("Key not found", systemImage: "key").font(.caption).foregroundStyle(Palette.disk) }
            if let t = state.blockedUntil { Text("Next check in \(AIUsage.formatCountdown(t, now: now))").font(.caption).foregroundStyle(Palette.secondary) }
            Text("Account credit; separate from the key's weekly spending limit.").font(.caption).foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).usageCard()
    }
}

func aiMeterColor(_ severity: AIUsage.MeterSeverity) -> Color {
    switch severity { case .normal: Palette.limitNormal; case .warning: Palette.limitWarning; case .critical: Palette.limitCritical }
}
/// Hesap renkleri terminaldeki `claude-pick` ve `statusline.sh` ile aynıdır.
func aiAccountColor(_ n: Int) -> Color {
    switch n {
    case 1: Color(red: 0, green: 175/255, blue: 80/255)
    case 2: Color(red: 1, green: 176/255, blue: 85/255)
    case 4: Color(red: 86/255, green: 182/255, blue: 194/255)
    case 5: Color(red: 1, green: 121/255, blue: 198/255)
    case 6: Color(red: 180/255, green: 220/255, blue: 60/255)
    case 7: Color(red: 210/255, green: 170/255, blue: 120/255)
    case 8: Color(red: 140/255, green: 160/255, blue: 1)
    case 9: Color(red: 1, green: 127/255, blue: 110/255)
    case 10: Color(red: 0, green: 200/255, blue: 170/255)
    case 11: Color(red: 110/255, green: 190/255, blue: 1)
    case 12: Color(red: 1, green: 215/255, blue: 0)
    case 0: Palette.secondary
    default: Color(red: 180/255, green: 140/255, blue: 1)
    }
}
private extension View {
    func usageCard() -> some View { background(Palette.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.035))) }
}

// Shared column widths keep all account percentages and reset times aligned.
private enum AIQuickLayout {
    static let identityWidth: CGFloat = 140
    static let limitWidth: CGFloat = 136
    static let rowHeight: CGFloat = 52
}

struct AIQuickSummary: View {
    let store: MonitorStore
    private var listHeight: CGFloat {
        let rows = store.usage.states.count
        let credit = store.usage.credit == nil ? 0 : 1
        let content = rows + credit == 0 ? 48 : CGFloat(rows) * AIQuickLayout.rowHeight
            + CGFloat(credit) * 49 + CGFloat(max(0, rows + credit - 1))
        return min(content, max(120, MenuPanelLayout.screen.height - 245))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.usage.summary).foregroundStyle(Palette.secondary)
                Spacer()
                Button("All details") { store.showUsage() }.buttonStyle(.link)
                Button { store.usage.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.usage.checking || store.usage.isolated).accessibilityLabel("Refresh usage")
            }.font(.caption)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Account").frame(width: AIQuickLayout.identityWidth, alignment: .leading)
                    Text("5-hour").frame(width: AIQuickLayout.limitWidth, alignment: .leading)
                    Text("Weekly").frame(width: AIQuickLayout.limitWidth, alignment: .leading)
                    Color.clear.frame(width: 18, height: 1)
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 10).frame(height: 26).accessibilityHidden(true)
                Divider().opacity(0.5)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.usage.states.enumerated()), id: \.element.account.cacheKey) { index, state in
                            if index > 0 { Divider().opacity(0.35) }
                            AIQuickAccount(state: state, tokens: store.usage.tokens.byAccount[state.account.n], store: store)
                        }
                        if let c = store.usage.credit {
                            if !store.usage.states.isEmpty { Divider().opacity(0.5) }
                            AIQuickCredit(state: c, now: store.usage.now)
                        }
                        if store.usage.states.isEmpty && store.usage.credit == nil {
                            Text("Waiting for usage data").font(.callout).foregroundStyle(Palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: listHeight)
            }.usageCard()
            if store.usage.tokens.unattributed.total > 0 {
                Text("No identified account: \(AIUsage.formatTokens(store.usage.tokens.unattributed.total)) tokens")
                    .font(.caption2).foregroundStyle(Palette.secondary).help(AIUsage.tokenBreakdown(store.usage.tokens.unattributed))
            }
        }
    }
}

private struct AIQuickAccount: View {
    let state: AIUsage.AccountState
    let tokens: AIUsage.PeriodTokens?
    let store: MonitorStore
    @State private var details = false
    private var claude: Bool { state.account.provider == .claude }
    private var age: String? {
        state.usage.map { String(localized: "\(AIUsage.formatDuration(store.usage.now.timeIntervalSince($0.fetchedAt))) ago") }
    }
    private var stale: Bool {
        state.usage.map { store.usage.now.timeIntervalSince($0.fetchedAt) > AIUsage.Cfg.staleSeconds } ?? true
    }
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    ProviderLogoView(logo: claude ? .claude : .codex).frame(width: 13, height: 13)
                        .foregroundStyle(claude ? aiAccountColor(state.account.n) : Color.primary)
                    Text(state.compactLabel).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .truncationMode(.middle)
                }.help((claude ? "Claude" : "Codex") + " · " + (state.email.isEmpty ? state.label : state.email))
                HStack(spacing: 4) {
                    Text(state.tokenExpired ? String(localized: "Expired") : !state.loggedIn ? String(localized: "Signed out") : state.plan == "?" ? "" : state.plan)
                        .foregroundStyle(state.tokenExpired || !state.loggedIn ? Palette.disk : Palette.secondary)
                    Spacer(minLength: 0)
                    if let age { Text(age).foregroundStyle(stale ? Palette.disk : Palette.secondary) }
                }.font(.system(size: 9)).lineLimit(1)
                if claude, let tokens {
                    Text("\(AIUsage.formatTokens(tokens.counts.total)) tokens").font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(Palette.secondary).lineLimit(1)
                        .help(AIUsage.formatPeriod(tokens.period) + "\n" + AIUsage.tokenBreakdown(tokens.counts))
                } else if let t = state.blockedUntil {
                    Text("Retry in \(AIUsage.formatCountdown(t, now: store.usage.now))").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                }
            }.frame(width: AIQuickLayout.identityWidth, alignment: .leading)
            AIQuickLimit(usage: state.usage, fiveHour: true, store: store)
            AIQuickLimit(usage: state.usage, fiveHour: false, store: store)
            Button { details = true } label: {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .frame(width: 18, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(String(localized: "Open \(claude ? "Claude" : "Codex") · \(state.compactLabel) usage and token details"))
                .popover(isPresented: $details) {
                    AIAccountCard(state: state, tokens: tokens, now: store.usage.now, checking: store.usage.checking,
                        preferences: store.preferences, rename: { store.usage.rename(state.account, name: $0) }).frame(width: 390)
                }
        }.padding(.horizontal, 10).frame(height: AIQuickLayout.rowHeight)
    }
}

private struct AIQuickLimit: View {
    let usage: AIUsage.Usage?
    let fiveHour: Bool
    let store: MonitorStore
    private var title: String { fiveHour ? String(localized: "5-hour") : String(localized: "Weekly") }
    private var window: AIUsage.Window? {
        guard let usage, fiveHour ? usage.hasFive : usage.hasWeek else { return nil }
        return (fiveHour ? usage.five : usage.week).effective(at: store.usage.now)
    }
    private var meter: AIUsage.MeterState {
        guard let usage else { return .level(.normal) }
        return fiveHour ? usage.meterFive(now: store.usage.now) : usage.meterWeek(now: store.usage.now)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let w = window, w.known {
                HStack(spacing: 6) {
                    Button { store.preferences.usageShowsLeft.toggle() } label: {
                        Text(LocalizedFormat.percent(store.preferences.usageShowsLeft ? max(0, 100 - w.pct) : w.pct))
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }.buttonStyle(.plain).frame(width: 34, alignment: .leading)
                        .accessibilityLabel(store.preferences.usageShowsLeft ? String(localized: "\(title) remaining percentage; switch view") : String(localized: "\(title) used percentage; switch view"))
                    AIUsageBar(percent: w.pct, color: aiMeterColor(meter.severity),
                        tick: AIUsage.paceTick(meter, resetsAt: w.resetsAt,
                            length: fiveHour ? AIUsage.Cfg.fiveLength : AIUsage.Cfg.weekLength, now: store.usage.now), height: 5)
                        .accessibilityLabel(String(localized: "\(title) usage"))
                        .help(AIUsage.meterTooltip(meter) ?? "")
                }
                if let reset = AIUsage.resetLabel(w, now: store.usage.now, relative: store.preferences.usageResetRelative,
                    notStarted: fiveHour && w.pct == 0 && w.resetsAt == nil) {
                    Button { store.preferences.usageResetRelative.toggle() } label: {
                        Text(AIUsage.resetLabel(w, now: store.usage.now, relative: store.preferences.usageResetRelative,
                            notStarted: fiveHour && w.pct == 0 && w.resetsAt == nil, compact: true) ?? reset)
                    }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help(reset + " · " + String(localized: "Switch clock / countdown"))
                } else { Text(" ").accessibilityHidden(true) }
                if let note = AIUsage.meterNote(meter, now: store.usage.now, relative: store.preferences.usageResetRelative) {
                    Text(note).foregroundStyle(aiMeterColor(meter.severity)).help(note)
                } else { Text(" ").accessibilityHidden(true) }
            } else {
                Text("—").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                Text(window == nil && usage != nil ? "Not in plan" : "Waiting for data").foregroundStyle(Palette.secondary)
            }
        }.font(.system(size: 9)).lineLimit(1).frame(width: AIQuickLayout.limitWidth, alignment: .leading)
    }
}

private struct AIQuickCredit: View {
    let state: AIUsage.CreditState
    let now: Date
    @State private var details = false
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Label { Text("OpenRouter") } icon: { ProviderLogoView(logo: .openrouter).frame(width: 13, height: 13) }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.network)
                Text(state.credit.map { String(localized: "\(AIUsage.formatDuration(now.timeIntervalSince($0.fetchedAt))) ago") }
                    ?? (state.hasKey ? String(localized: "Waiting for balance") : String(localized: "Key not found")))
                    .font(.system(size: 9)).foregroundStyle(state.credit.map {
                        now.timeIntervalSince($0.fetchedAt) > AIUsage.Cfg.staleSeconds ? Palette.disk : Palette.secondary
                    } ?? Palette.secondary)
            }.frame(width: AIQuickLayout.identityWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.credit.map { AIUsage.formatUSD($0.remaining) } ?? "—").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text("Remaining balance").font(.system(size: 9)).foregroundStyle(Palette.secondary)
            }.frame(width: AIQuickLayout.limitWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if let c = state.credit {
                    HStack(spacing: 6) {
                        Text(LocalizedFormat.percent(c.usedPct)).font(.system(size: 12, weight: .semibold)).monospacedDigit().frame(width: 34, alignment: .leading)
                        AIUsageBar(percent: c.usedPct, color: aiMeterColor(AIUsage.levelState(c.usedPct).severity), height: 5)
                    }
                    Text(AIUsage.formatUSD(c.used) + " / " + AIUsage.formatUSD(c.total)).font(.system(size: 9)).foregroundStyle(Palette.secondary)
                }
            }.frame(width: AIQuickLayout.limitWidth, alignment: .leading)
            Button { details = true } label: {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .frame(width: 18, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open OpenRouter balance details")
                .popover(isPresented: $details) { AICreditCard(state: state, now: now).frame(width: 390).fixedSize(horizontal: false, vertical: true) }
        }.padding(.horizontal, 10).frame(height: 48)
    }
}
