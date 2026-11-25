import SwiftUI
import MetricsCore

struct DashboardView: View {
    @Bindable var store: MonitorStore
    @State private var selected: MonitorTab = .overview
    @State private var selectedGroup: GroupSelection?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.mainWindowOpen { content }
            else { Color.clear.frame(minWidth: 1100, minHeight: 780) }
        }.onAppear {
            store.showMainAction = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            store.showAboutAction = { openWindow(id: "about"); NSApp.activate(ignoringOtherApps: true) }
            store.showSettingsAction = { openSettings(); NSApp.activate(ignoringOtherApps: true) }
            store.showUsageAction = { selected = .usage }
            store.showWidgetsAction = { openWindow(id: "menu-widgets"); NSApp.activate(ignoringOtherApps: true) }
            store.showBatterySettingsAction = { openWindow(id: "battery-settings"); NSApp.activate(ignoringOtherApps: true) }
            store.showBatteryHistoryAction = { openWindow(id: "battery-history", value: $0); NSApp.activate(ignoringOtherApps: true) }
        }
    }
    private var content: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                ForEach([MonitorTab.usage, .history, .alerts, .projects, .containers, .hardware, .bluetooth, .audio]) { tab in
                    Button { selected = tab } label: {
                        Label(tab.label + (tab == .alerts ? " · \(store.alerts.filter(\.active).count)" : ""), systemImage: tab.icon)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(selected == tab ? tab.color : Palette.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(selected == tab ? Palette.elevated : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut(tab == .usage ? nil : KeyboardShortcut(tab == .history ? "8" : tab == .alerts ? "9" : tab == .hardware ? "g" : tab == .bluetooth ? "b" : tab == .audio ? "s" : "0", modifiers: [.containers, .hardware, .bluetooth, .audio].contains(tab) ? [.command, .shift] : .command))
                        .accessibilityAddTraits(selected == tab ? [.isSelected] : [])
                }
                }
                }
                Text(selected == .usage ? "Account limits and credit" : selected == .hardware ? "This session · last 90 samples" : selected == .bluetooth || selected == .audio ? "Devices · read-only" : store.historyError == nil ? "History on this Mac · 30 days" : "History unavailable")
                    .font(.system(size: 10)).foregroundStyle(store.historyError == nil ? Palette.secondary : Palette.disk)
            }.padding(.horizontal, 24).padding(.bottom, 10)
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            if let snapshot = store.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if selected == .overview {
                            overview(snapshot)
                        } else if selected == .usage {
                            AIUsageView(store: store.usage, preferences: store.preferences)
                        } else if selected == .applications {
                            ApplicationListView(snapshot: snapshot.processes, select: selectGroup)
                        } else if selected == .battery {
                            DeviceBatteryDashboard(store: store)
                        } else if selected == .history {
                            HistoryView(store: store)
                        } else if selected == .alerts {
                            AlertsView(store: store)
                        } else if selected == .projects {
                            ProjectsView(snapshot: snapshot.developer)
                        } else if selected == .containers {
                            ContainersView(snapshot: snapshot.containers)
                        } else if selected == .hardware {
                            HardwareView(snapshot: snapshot.hardware, system: snapshot.system, history: store.history)
                        } else if selected == .bluetooth {
                            BluetoothView(snapshot: snapshot.bluetooth, paused: store.paused)
                        } else if selected == .audio {
                            AudioDevicesView(snapshot: snapshot.audio)
                        } else {
                            DetailView(tab: selected, snapshot: snapshot, history: store.history)
                            if selected == .cpu || selected == .memory {
                                ApplicationListView(snapshot: snapshot.processes, initialSort: selected == .cpu ? .cpu : .memory,
                                    limit: 10, title: selected == .cpu ? String(localized: "Apps using CPU") : String(localized: "Apps using memory"), select: selectGroup)
                            }
                        }
                        if let error = store.historyError {
                            Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Palette.disk)
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                        if !snapshot.issues.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(snapshot.issues) { issue in
                                    Label(issue.message, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Palette.disk)
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding(24)
                }
                footer(snapshot)
            } else {
                VStack(spacing: 14) { ProgressView(); Text("Getting your Mac's measurements").foregroundStyle(Palette.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.primary)
        .background(Palette.background)
        .frame(minWidth: 1100, minHeight: 780)
        .sheet(item: $selectedGroup) { selection in
            ProcessDetailSheet(selection: selection, group: store.snapshot?.processes?.groups.first { $0.id == selection.id })
        }
    }

    private func selectGroup(_ group: ApplicationUsage) { selectedGroup = GroupSelection(id: group.id, name: group.name) }

    private var header: some View {
        HStack(spacing: 24) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 25, weight: .semibold)).foregroundStyle(Palette.accent)
                    .frame(width: 43, height: 43).background(Palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacPulse").font(.system(size: 17, weight: .semibold))
                    Text(store.snapshot.map { "\($0.system.chip) · \($0.system.cores) cores" } ?? "System monitoring")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 3) {
                ForEach(Array(MonitorTab.allCases.prefix(7).enumerated()), id: \.element.id) { index, tab in
                    Button { selected = tab } label: {
                        Label(tab.label, systemImage: tab.icon)
                            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 9)
                            .foregroundStyle(selected == tab ? tab.color : Palette.secondary)
                            .background(selected == tab ? Palette.elevated : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .accessibilityAddTraits(selected == tab ? [.isSelected] : [])
                }
            }.padding(4).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            Button { store.paused.toggle() } label: {
                Image(systemName: store.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .frame(width: 34, height: 34).background(Color.primary.opacity(0.04), in: Circle())
            }.buttonStyle(.plain).help(store.paused ? "Resume monitoring" : "Pause monitoring")
                .accessibilityLabel(store.paused ? "Resume monitoring" : "Pause monitoring")
            Button { openSettings() } label: {
                Image(systemName: "gearshape").foregroundStyle(Palette.secondary)
                    .frame(width: 30, height: 34)
            }.buttonStyle(.plain).help("Settings · Cmd+,").accessibilityLabel("Open Settings")
        }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
    }

    private func overview(_ snapshot: MetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Mac right now").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(store.paused ? Palette.disk : Palette.accent).frame(width: 6, height: 6)
                    Text(store.paused ? "Paused" : "Live monitoring").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                cpuCard(snapshot)
                memoryCard(snapshot)
                gpuCard(snapshot)
                diskCard(snapshot)
                networkCard(snapshot)
                batteryCard(snapshot)
            }
            Button { selected = .usage } label: {
                HStack(spacing: 12) {
                    Label("AI Usage", systemImage: "chart.bar.xaxis").foregroundStyle(Palette.memory)
                    Text(store.usage.summary).foregroundStyle(Palette.secondary)
                    Spacer()
                    if let c = store.usage.credit?.credit { Text("OpenRouter \(AIUsage.formatUSD(c.remaining))").monospacedDigit() }
                    Image(systemName: "chevron.right").foregroundStyle(Palette.secondary)
                }.font(.callout).padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack {
                Text("Needs attention").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("See alerts") { selected = .alerts }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accent)
            }.padding(.top, 4)
            AlertListView(alerts: store.alerts, limit: 3)
            Text("Right now").font(.system(size: 17, weight: .semibold)).padding(.top, 2)
            HStack(alignment: .top, spacing: 14) {
                if let memory = snapshot.memory {
                    BreakdownCard(title: String(localized: "Memory breakdown"), icon: "memorychip", center: MetricFormat.percent(memory.usedPercent), subtitle: String(localized: "in use"), color: Palette.memory,
                        slices: [
                            RingSlice(title: String(localized: "Apps"), value: Double(memory.app), color: Palette.memory),
                            RingSlice(title: String(localized: "Wired"), value: Double(memory.wired), color: Palette.disk),
                            RingSlice(title: String(localized: "Compressed"), value: Double(memory.compressed), color: Palette.network),
                            RingSlice(title: String(localized: "Available"), value: Double(memory.total - memory.used), color: Palette.elevated)
                        ], binary: true)
                }
                if let cpu = snapshot.cpu {
                    BreakdownCard(title: String(localized: "CPU breakdown"), icon: "cpu", center: MetricFormat.percent(cpu.used), subtitle: String(localized: "in use"), color: Palette.cpu,
                        slices: [
                            RingSlice(title: String(localized: "User"), value: cpu.user, color: Palette.cpu),
                            RingSlice(title: String(localized: "System"), value: cpu.system, color: Palette.memory),
                            RingSlice(title: String(localized: "Idle"), value: cpu.idle, color: Palette.elevated)
                        ], percentages: true)
                }
                NetworkSummary(network: snapshot.network, limit: 2)
            }
            if let processes = snapshot.processes {
                HStack(alignment: .top, spacing: 14) {
                    TopApplicationsView(snapshot: processes, sort: .memory, select: selectGroup) { selected = .applications }
                    TopApplicationsView(snapshot: processes, sort: .cpu, select: selectGroup) { selected = .applications }
                }
            }
            HStack(spacing: 14) {
                Button { selected = .projects } label: {
                    DeveloperSummary(title: String(localized: "Development projects"), icon: "hammer", color: Palette.disk,
                        value: snapshot.developer.map { String(localized: "\($0.projects.count) projects · \($0.listenerProcessCount) TCP listeners") } ?? String(localized: "Measurement unavailable"),
                        detail: snapshot.developer.map { String(localized: "\($0.projects.filter { $0.activity == .idleCandidate }.count) idle candidates · read-only") } ?? "")
                }.buttonStyle(.plain)
                Button { selected = .containers } label: {
                    DeveloperSummary(title: String(localized: "Containers"), icon: "shippingbox", color: Palette.accent,
                        value: snapshot.containers.map { String(localized: "\($0.runningCount) running · \($0.containerCount) containers") } ?? String(localized: "Measurement unavailable"),
                        detail: String(localized: "Local running runtimes only"))
                }.buttonStyle(.plain)
            }
        }
    }

    private func cpuCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: "CPU", icon: "cpu", eyebrow: String(localized: "Usage across all cores"), value: MetricFormat.percent(s.cpu?.used), color: Palette.cpu,
            facts: [StatFact(title: String(localized: "User"), value: MetricFormat.percent(s.cpu?.user)), StatFact(title: String(localized: "System"), value: MetricFormat.percent(s.cpu?.system)), StatFact(title: String(localized: "Idle"), value: MetricFormat.percent(s.cpu?.idle))],
            points: plotPoints(store.history) { $0.cpu?.used }, ceiling: 100) { selected = .cpu }
    }

    private func memoryCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: String(localized: "Memory"), icon: "memorychip", eyebrow: String(localized: "used of \(MetricFormat.bytes(s.memory?.total, binary: true))"), value: MetricFormat.bytes(s.memory?.used, binary: true), color: Palette.memory,
            facts: [StatFact(title: String(localized: "Apps"), value: MetricFormat.bytes(s.memory?.app, binary: true)), StatFact(title: String(localized: "Wired"), value: MetricFormat.bytes(s.memory?.wired, binary: true)), StatFact(title: String(localized: "Compressed"), value: MetricFormat.bytes(s.memory?.compressed, binary: true))],
            points: plotPoints(store.history) { $0.memory?.usedPercent }, ceiling: 100, badge: s.memory?.pressure.label) { selected = .memory }
    }

    private func diskCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: "Disk", icon: "internaldrive", eyebrow: String(localized: "Free space on startup disk"), value: MetricFormat.bytes(s.disk?.available), color: Palette.disk,
            facts: [StatFact(title: String(localized: "Read"), value: MetricFormat.rate(s.disk?.io?.incomingRate)), StatFact(title: String(localized: "Write"), value: MetricFormat.rate(s.disk?.io?.outgoingRate)), StatFact(title: String(localized: "Used"), value: MetricFormat.percent(s.disk?.usedPercent))],
            points: plotPoints(store.history) { $0.disk?.io.map { $0.incomingRate + $0.outgoingRate } },
            emptyLabel: s.issues.contains { $0.id == "diskIO" } ? String(localized: "Read/write measurement unavailable") : String(localized: "Collecting samples for the chart")) { selected = .disk }
    }

    private func networkCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: String(localized: "Network"), icon: "network", eyebrow: String(localized: "Download speed · physical interfaces"), value: MetricFormat.rate(s.network?.incomingRate), color: Palette.network,
            facts: [StatFact(title: String(localized: "Upload"), value: MetricFormat.rate(s.network?.outgoingRate)), StatFact(title: String(localized: "Received this session"), value: MetricFormat.bytes(s.network?.sessionReceived)), StatFact(title: String(localized: "Sent this session"), value: MetricFormat.bytes(s.network?.sessionSent))],
            points: plotPoints(store.history) { $0.network?.incomingRate }) { selected = .network }
    }

    private func batteryCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: String(localized: "Battery"), icon: "battery.100percent", eyebrow: s.battery?.stateLabel ?? String(localized: "Power source"), value: s.battery?.present == false ? String(localized: "No battery") : MetricFormat.percent(s.battery?.percent), color: Palette.battery,
            facts: [StatFact(title: String(localized: "Time remaining"), value: s.battery?.minutesRemaining.map { MetricFormat.duration(Double($0 * 60)) } ?? "—"), StatFact(title: String(localized: "Source"), value: s.battery.map { $0.onAC ? String(localized: "Adapter") : ($0.present ? String(localized: "Battery") : String(localized: "AC power")) } ?? "—"), StatFact(title: String(localized: "Low Power"), value: s.battery.map { $0.lowPowerMode ? String(localized: "On") : String(localized: "Off") } ?? "—")],
            points: plotPoints(store.history) { $0.battery?.percent.map(Double.init) }, ceiling: 100,
            emptyLabel: s.battery?.present == false ? String(localized: "This Mac has no internal battery") : String(localized: "Collecting samples for the chart")) { selected = .battery }
    }

    private func gpuCard(_ s: MetricSnapshot) -> some View {
        let gpu = s.hardware?.gpus.count == 1 ? s.hardware?.gpus.first : nil
        return MetricCard(title: "GPU", icon: "square.3.layers.3d", eyebrow: String(localized: "Driver utilization counter"), value: MetricFormat.percent(gpu?.devicePercent), color: Palette.gpu,
            facts: [StatFact(title: "Renderer", value: MetricFormat.percent(gpu?.rendererPercent)), StatFact(title: "Tiler", value: MetricFormat.percent(gpu?.tilerPercent)), StatFact(title: String(localized: "Driver memory"), value: MetricFormat.bytes(gpu?.memoryInUse, binary: true))],
            points: plotPoints(store.history) { $0.hardware?.singleGPUPercent }, ceiling: 100) { selected = .hardware }
    }

    private func systemCard(_ s: MetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System", systemImage: "desktopcomputer").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Uptime").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text(MetricFormat.duration(s.system.uptime)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            }
            FactRow(facts: [StatFact(title: String(localized: "Processor"), value: s.system.chip), StatFact(title: String(localized: "Cores"), value: "\(s.system.cores)"), StatFact(title: "RAM", value: MetricFormat.bytes(s.system.physicalMemory, binary: true))])
            HStack(spacing: 7) {
                Image(systemName: "thermometer.medium").foregroundStyle(Palette.accent)
                Text("Thermal state: \(s.system.thermalState)")
                Spacer()
                Text(s.system.operatingSystem)
            }.font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(height: 38, alignment: .bottom)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.035)))
    }

    private func footer(_ s: MetricSnapshot) -> some View {
        HStack {
            Text("Measured on this Mac · \(store.history.count) samples · \(s.processes?.applicationCount ?? 0) apps · \(s.processes?.processCount ?? 0) processes")
            Spacer()
            Text(store.paused ? "Paused" : "Last measured \(s.date.formatted(date: .omitted, time: .standard))")
        }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 24).padding(.vertical, 10).background(Color.primary.opacity(0.015))
    }
}

struct NetworkSummary: View {
    let network: NetworkMetrics?
    var limit: Int? = nil
    private var displayed: [NetworkInterface] {
        let sorted = (network?.interfaces ?? []).sorted {
            let lhs = ($0.transfer?.incomingRate ?? 0) + ($0.transfer?.outgoingRate ?? 0)
            let rhs = ($1.transfer?.incomingRate ?? 0) + ($1.transfer?.outgoingRate ?? 0)
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Network interfaces", systemImage: "network").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.network)
            VStack(alignment: .leading, spacing: 10) {
                if let network {
                    if network.interfaces.isEmpty {
                        Text("No connected physical interfaces").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    ForEach(displayed) { interface in
                        HStack {
                            Label(interface.id, systemImage: "point.3.connected.trianglepath.dotted").font(.system(size: 12, weight: .medium))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("↓ \(MetricFormat.rate(interface.transfer?.incomingRate))")
                                Text("↑ \(MetricFormat.rate(interface.transfer?.outgoingRate))").foregroundStyle(Palette.secondary)
                            }.font(.system(size: 11)).monospacedDigit()
                        }
                    }
                    if let limit, network.interfaces.count > limit {
                        Text("\(network.interfaces.count) interfaces · all in the Network tab").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                } else { Text("Network measurement unavailable").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                Spacer(minLength: 0)
                Text("Physical connections are measured. VPN and local traffic aren't counted separately.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 112, alignment: .top)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
