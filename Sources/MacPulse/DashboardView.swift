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
                        Label(tab.rawValue + (tab == .alerts ? " · \(store.alerts.filter(\.active).count)" : ""), systemImage: tab.icon)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(selected == tab ? tab.color : Palette.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(selected == tab ? Palette.elevated : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut(tab == .usage ? nil : KeyboardShortcut(tab == .history ? "8" : tab == .alerts ? "9" : tab == .hardware ? "g" : tab == .bluetooth ? "b" : tab == .audio ? "s" : "0", modifiers: [.containers, .hardware, .bluetooth, .audio].contains(tab) ? [.command, .shift] : .command))
                        .accessibilityAddTraits(selected == tab ? [.isSelected] : [])
                }
                }
                }
                Text(selected == .usage ? "Hesap limitleri ve kredi" : selected == .hardware ? "Bu oturum · son 90 örnek" : selected == .bluetooth || selected == .audio ? "Cihazlar · salt okunur" : store.historyError == nil ? "Geçmiş bu Mac'te · 30 gün" : "Geçmiş kaydı alınamıyor")
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
                                    limit: 10, title: selected == .cpu ? "CPU kullanan uygulamalar" : "Bellek kullanan uygulamalar", select: selectGroup)
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
                VStack(spacing: 14) { ProgressView(); Text("Mac'in ölçümleri alınıyor").foregroundStyle(Palette.secondary) }
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
                    Text(store.snapshot.map { "\($0.system.chip) · \($0.system.cores) çekirdek" } ?? "Sistem izleme")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 3) {
                ForEach(Array(MonitorTab.allCases.prefix(7).enumerated()), id: \.element.id) { index, tab in
                    Button { selected = tab } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
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
            }.buttonStyle(.plain).help(store.paused ? "İzlemeyi sürdür" : "İzlemeyi duraklat")
                .accessibilityLabel(store.paused ? "İzlemeyi sürdür" : "İzlemeyi duraklat")
            Button { openSettings() } label: {
                Image(systemName: "gearshape").foregroundStyle(Palette.secondary)
                    .frame(width: 30, height: 34)
            }.buttonStyle(.plain).help("Tercihler · Cmd+,").accessibilityLabel("Tercihleri aç")
        }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
    }

    private func overview(_ snapshot: MetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mac'in şu anki durumu").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(store.paused ? Palette.disk : Palette.accent).frame(width: 6, height: 6)
                    Text(store.paused ? "Duraklatıldı" : "Canlı izleme").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
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
                    Label("AI Kullanımı", systemImage: "chart.bar.xaxis").foregroundStyle(Palette.memory)
                    Text(store.usage.summary).foregroundStyle(Palette.secondary)
                    Spacer()
                    if let c = store.usage.credit?.credit { Text("OpenRouter \(AIUsage.formatUSD(c.remaining))").monospacedDigit() }
                    Image(systemName: "chevron.right").foregroundStyle(Palette.secondary)
                }.font(.callout).padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack {
                Text("Dikkat gerektiren durumlar").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Uyarıları gör") { selected = .alerts }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.accent)
            }.padding(.top, 4)
            AlertListView(alerts: store.alerts, limit: 3)
            Text("Şu anda").font(.system(size: 17, weight: .semibold)).padding(.top, 2)
            HStack(alignment: .top, spacing: 14) {
                if let memory = snapshot.memory {
                    BreakdownCard(title: "Bellek dağılımı", icon: "memorychip", center: MetricFormat.percent(memory.usedPercent), subtitle: "kullanılıyor", color: Palette.memory,
                        slices: [
                            RingSlice(title: "Uygulamalar", value: Double(memory.app), color: Palette.memory),
                            RingSlice(title: "Sabit", value: Double(memory.wired), color: Palette.disk),
                            RingSlice(title: "Sıkıştırılmış", value: Double(memory.compressed), color: Palette.network),
                            RingSlice(title: "Kullanılabilir", value: Double(memory.total - memory.used), color: Palette.elevated)
                        ], binary: true)
                }
                if let cpu = snapshot.cpu {
                    BreakdownCard(title: "CPU dağılımı", icon: "cpu", center: MetricFormat.percent(cpu.used), subtitle: "kullanılıyor", color: Palette.cpu,
                        slices: [
                            RingSlice(title: "Kullanıcı", value: cpu.user, color: Palette.cpu),
                            RingSlice(title: "Sistem", value: cpu.system, color: Palette.memory),
                            RingSlice(title: "Boşta", value: cpu.idle, color: Palette.elevated)
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
                    DeveloperSummary(title: "Geliştirme projeleri", icon: "hammer", color: Palette.disk,
                        value: snapshot.developer.map { "\($0.projects.count) proje · \($0.listenerProcessCount) TCP dinleyicisi" } ?? "Ölçüm alınamıyor",
                        detail: snapshot.developer.map { "\($0.projects.filter { $0.activity == .idleCandidate }.count) boşta adayı · salt okunur" } ?? "")
                }.buttonStyle(.plain)
                Button { selected = .containers } label: {
                    DeveloperSummary(title: "Containerlar", icon: "shippingbox", color: Palette.accent,
                        value: snapshot.containers.map { "\($0.runningCount) çalışıyor · \($0.containerCount) container" } ?? "Ölçüm alınamıyor",
                        detail: "Yalnız çalışan yerel runtime'lar")
                }.buttonStyle(.plain)
            }
        }
    }

    private func cpuCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: "CPU", icon: "cpu", eyebrow: "Tüm çekirdeklerde kullanım", value: MetricFormat.percent(s.cpu?.used), color: Palette.cpu,
            facts: [StatFact(title: "Kullanıcı", value: MetricFormat.percent(s.cpu?.user)), StatFact(title: "Sistem", value: MetricFormat.percent(s.cpu?.system)), StatFact(title: "Boşta", value: MetricFormat.percent(s.cpu?.idle))],
            points: plotPoints(store.history) { $0.cpu?.used }, ceiling: 100) { selected = .cpu }
    }

    private func memoryCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: "Bellek", icon: "memorychip", eyebrow: "\(MetricFormat.bytes(s.memory?.total, binary: true)) içinde kullanılan", value: MetricFormat.bytes(s.memory?.used, binary: true), color: Palette.memory,
            facts: [StatFact(title: "Uygulamalar", value: MetricFormat.bytes(s.memory?.app, binary: true)), StatFact(title: "Sabit", value: MetricFormat.bytes(s.memory?.wired, binary: true)), StatFact(title: "Sıkıştırılmış", value: MetricFormat.bytes(s.memory?.compressed, binary: true))],
            points: plotPoints(store.history) { $0.memory?.usedPercent }, ceiling: 100, badge: s.memory?.pressure.label) { selected = .memory }
    }

    private func diskCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: "Disk", icon: "internaldrive", eyebrow: "Başlangıç diskinde boş alan", value: MetricFormat.bytes(s.disk?.available), color: Palette.disk,
            facts: [StatFact(title: "Okuma", value: MetricFormat.rate(s.disk?.io?.incomingRate)), StatFact(title: "Yazma", value: MetricFormat.rate(s.disk?.io?.outgoingRate)), StatFact(title: "Kullanılan", value: MetricFormat.percent(s.disk?.usedPercent))],
            points: plotPoints(store.history) { $0.disk?.io.map { $0.incomingRate + $0.outgoingRate } },
            emptyLabel: s.issues.contains { $0.id == "diskIO" } ? "Okuma/yazma ölçümü alınamıyor" : "Grafik için ölçümler birikiyor") { selected = .disk }
    }

    private func networkCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: "Ağ", icon: "network", eyebrow: "İndirme hızı · fiziksel arayüzler", value: MetricFormat.rate(s.network?.incomingRate), color: Palette.network,
            facts: [StatFact(title: "Yükleme", value: MetricFormat.rate(s.network?.outgoingRate)), StatFact(title: "Oturumda alınan", value: MetricFormat.bytes(s.network?.sessionReceived)), StatFact(title: "Oturumda gönderilen", value: MetricFormat.bytes(s.network?.sessionSent))],
            points: plotPoints(store.history) { $0.network?.incomingRate }) { selected = .network }
    }

    private func batteryCard(_ s: MetricSnapshot) -> some View {
        MetricCard(title: "Pil", icon: "battery.100percent", eyebrow: s.battery?.stateLabel ?? "Güç kaynağı", value: s.battery?.present == false ? "Pil yok" : s.battery?.percent.map { "\($0)%" } ?? "—", color: Palette.battery,
            facts: [StatFact(title: "Kalan süre", value: s.battery?.minutesRemaining.map { MetricFormat.duration(Double($0 * 60)) } ?? "—"), StatFact(title: "Kaynak", value: s.battery.map { $0.onAC ? "Adaptör" : ($0.present ? "Pil" : "Şebeke") } ?? "—"), StatFact(title: "Düşük güç", value: s.battery.map { $0.lowPowerMode ? "Açık" : "Kapalı" } ?? "—")],
            points: plotPoints(store.history) { $0.battery?.percent.map(Double.init) }, ceiling: 100,
            emptyLabel: s.battery?.present == false ? "Bu Mac'te dahili pil bulunmuyor" : "Grafik için ölçümler birikiyor") { selected = .battery }
    }

    private func gpuCard(_ s: MetricSnapshot) -> some View {
        let gpu = s.hardware?.gpus.count == 1 ? s.hardware?.gpus.first : nil
        return MetricCard(title: "GPU", icon: "square.3.layers.3d", eyebrow: "Sürücü kullanım sayacı", value: MetricFormat.percent(gpu?.devicePercent), color: Palette.gpu,
            facts: [StatFact(title: "Renderer", value: MetricFormat.percent(gpu?.rendererPercent)), StatFact(title: "Tiler", value: MetricFormat.percent(gpu?.tilerPercent)), StatFact(title: "Sürücü belleği", value: MetricFormat.bytes(gpu?.memoryInUse, binary: true))],
            points: plotPoints(store.history) { $0.hardware?.singleGPUPercent }, ceiling: 100) { selected = .hardware }
    }

    private func systemCard(_ s: MetricSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sistem", systemImage: "desktopcomputer").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Kesintisiz çalışma").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text(MetricFormat.duration(s.system.uptime)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            }
            FactRow(facts: [StatFact(title: "İşlemci", value: s.system.chip), StatFact(title: "Çekirdek", value: "\(s.system.cores)"), StatFact(title: "RAM", value: MetricFormat.bytes(s.system.physicalMemory, binary: true))])
            HStack(spacing: 7) {
                Image(systemName: "thermometer.medium").foregroundStyle(Palette.accent)
                Text("Termal durum: \(s.system.thermalState)")
                Spacer()
                Text(s.system.operatingSystem)
            }.font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(height: 38, alignment: .bottom)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.035)))
    }

    private func footer(_ s: MetricSnapshot) -> some View {
        HStack {
            Text("Ölçümler bu Mac'te · \(store.history.count) örnek · \(s.processes?.applicationCount ?? 0) uygulama · \(s.processes?.processCount ?? 0) süreç")
            Spacer()
            Text(store.paused ? "Duraklatıldı" : "Son ölçüm \(s.date.formatted(date: .omitted, time: .standard))")
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
            Label("Ağ arayüzleri", systemImage: "network").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.network)
            VStack(alignment: .leading, spacing: 10) {
                if let network {
                    if network.interfaces.isEmpty {
                        Text("Bağlı fiziksel arayüz yok").font(.system(size: 12)).foregroundStyle(Palette.secondary)
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
                        Text("\(network.interfaces.count) arayüz · tümü Ağ sekmesinde").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                } else { Text("Ağ ölçümü alınamıyor").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                Spacer(minLength: 0)
                Text("Fiziksel bağlantılar ölçülür. VPN ve yerel trafik ayrıca toplanmaz.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 112, alignment: .top)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
