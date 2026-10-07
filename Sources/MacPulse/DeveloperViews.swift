import SwiftUI
import MetricsCore

struct DeveloperSummary: View {
    let title, icon: String
    let color: Color
    let value, detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded))
            HStack { Text(detail).foregroundStyle(Palette.secondary); Spacer(); Image(systemName: "chevron.right").foregroundStyle(color) }
                .font(.system(size: 11))
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
private enum ProjectFilter: String, CaseIterable, Identifiable {
    case all = "Tümü", listening = "TCP dinleyen", idle = "Boşta adayı"
    var id: Self { self }
}
private struct ProjectSelection: Identifiable { let id, name: String }
private func activityColor(_ state: ProjectActivity) -> Color {
    switch state { case .active: Palette.accent; case .idleCandidate: Palette.disk; case .unknown, .observing: Palette.secondary }
}
private func displayPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

struct ProjectsView: View {
    let snapshot: DeveloperSnapshot?
    @State private var search = ""
    @State private var filter = ProjectFilter.all
    @State private var selection: ProjectSelection?
    private var unmapped: [ProjectMember] {
        guard filter != .idle else { return [] }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (snapshot?.unmappedListeners ?? []).filter { member in
            term.isEmpty || member.usage.name.localizedCaseInsensitiveContains(term) || String(member.id.pid).contains(term)
                || (member.metadata?.listeners.contains { String($0.port).contains(term) } ?? false)
        }
    }
    private var projects: [DevelopmentProject] {
        (snapshot?.projects ?? []).filter { project in
            let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = term.isEmpty || project.root.localizedCaseInsensitiveContains(term) || project.members.contains {
                $0.usage.name.localizedCaseInsensitiveContains(term) || String($0.id.pid).contains(term) || ($0.metadata?.listeners.contains { String($0.port).contains(term) } ?? false)
            }
            return matches && (filter == .all || (filter == .listening && !project.listeners.isEmpty) || (filter == .idle && project.activity == .idleCandidate))
        }.sorted { left, right in
            if left.listeners.isEmpty != right.listeners.isEmpty { return !left.listeners.isEmpty }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Geliştirme projeleri", systemImage: "hammer").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                if let snapshot { Text("Port taraması \(snapshot.scannedAt.formatted(date: .omitted, time: .standard))").font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            }
            Text("Çalışma dizini ve proje işaretinden eşlenen süreçler · CPU: bir çekirdek %100")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            HStack {
                TextField("Proje, süreç, PID veya port ara", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                Picker("Proje kapsamı", selection: $filter) { ForEach(ProjectFilter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 360)
                Spacer(); Text("\(projects.count) proje").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            VStack(spacing: 0) {
                if projects.isEmpty { Text(snapshot == nil ? "Proje ölçümü alınamıyor" : "Bu filtreye uyan proje bulunamadı").foregroundStyle(Palette.secondary).padding(36) }
                LazyVStack(spacing: 0) {
                    ForEach(projects) { project in
                        Button { selection = ProjectSelection(id: project.id, name: project.name) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: project.listeners.isEmpty ? "folder" : "server.rack").font(.system(size: 22)).foregroundStyle(Palette.disk).frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(project.name).font(.system(size: 14, weight: .semibold))
                                    Text(displayPath(project.root)).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1)
                                    Text(project.listeners.isEmpty ? "TCP dinleyicisi gözlenmedi" : project.listeners.map { String($0.port) }.uniqued().joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(Palette.disk)
                                }
                                Spacer()
                                Text(project.activity.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(activityColor(project.activity)).frame(width: 110)
                                Text("\(project.members.count) süreç").font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(width: 75)
                                Text(ApplicationFormat.cpu(project.cpuPercent, partial: project.cpuPartial)).foregroundStyle(Palette.cpu).frame(width: 95, alignment: .trailing)
                                Text(ApplicationFormat.memory(project.footprint, partial: project.memoryPartial)).frame(width: 110, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }.font(.system(size: 12)).monospacedDigit().padding(18).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(project.name), \(project.members.count) süreç, \(project.activity.rawValue), proje ağacını aç")
                        Divider().opacity(0.25).padding(.leading, 65)
                    }
                }
            }.frame(maxWidth: .infinity).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            if let snapshot {
                let scope = snapshot.coverage
                Text("\(scope.scanned) süreç tarandı · \(scope.cwdUnavailable) dizin erişimi yok · \(scope.socketsUnavailable) eksik socket ölçümü · \(scope.truncated) kısmi liste · \(scope.changed) çıkan/değişen süreç")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                if !unmapped.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Projeye eşlenemeyen TCP dinleyicileri").font(.system(size: 16, weight: .semibold))
                        ForEach(unmapped) { member in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(member.usage.name).font(.system(size: 12, weight: .medium))
                                    Text("PID \(member.id.pid)").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                }
                                Text((member.metadata?.listeners ?? []).map(\.label).joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Palette.disk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            Text("Boşta adayı: iki dakika boyunca CPU %1'in altında; taranan TCP bağlantısı ve bekleyen veri gözlenmedi; en az bir dinleyen port var. TCP byte sayacı, UDP ve taramalar arasında açılıp kapanan bağlantılar ölçülmez. Bu gösterge sunucunun kullanılmadığını kanıtlamaz. Eksik ölçümde aday oluşmaz.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }.sheet(item: $selection) { item in
            ProjectDetailSheet(name: item.name, project: snapshot?.projects.first { $0.id == item.id })
        }
    }
}

private struct ProjectDetailSheet: View {
    let name: String
    let project: DevelopmentProject?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(name).font(.system(size: 24, weight: .semibold, design: .rounded)); Spacer(); Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction) }
            if let project {
                Text(displayPath(project.root)).font(.system(size: 12)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                FactRow(facts: [StatFact(title: "CPU", value: ApplicationFormat.cpu(project.cpuPercent, partial: project.cpuPartial)),
                    StatFact(title: "Bellek yükü", value: ApplicationFormat.memory(project.footprint, partial: project.memoryPartial)),
                    StatFact(title: "Gözlenen TCP bağlantısı", value: project.activeConnections.map(String.init) ?? "—"),
                    StatFact(title: "Etkinlik", value: project.activity.rawValue)])
                Text("Süreç ağacı · PID + başlangıç zamanı ile doğrulanır").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.disk)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(project.tree, id: \.member.id) { row in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: row.depth == 0 ? "circle.fill" : "arrow.turn.down.right").font(.system(size: 8)).foregroundStyle(Palette.disk)
                                    Text(row.member.usage.name).font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(ApplicationFormat.cpu(row.member.usage.cpuPercent)).foregroundStyle(Palette.cpu).frame(width: 85, alignment: .trailing)
                                    Text(ApplicationFormat.memory(row.member.usage.footprint)).frame(width: 110, alignment: .trailing)
                                }.font(.system(size: 12)).monospacedDigit()
                                Text("PID \(row.member.id.pid) · Ebeveyn \(row.member.usage.parentPID) · \(row.member.attribution.rawValue)")
                                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                if let metadata = row.member.metadata {
                                    Text(metadata.listeners.isEmpty ? "TCP dinleyicisi gözlenmedi" : metadata.listeners.map(\.label).joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(Palette.disk)
                                    if !metadata.socketsComplete { Text("Socket ölçümü kısmi").font(.system(size: 10)).foregroundStyle(Palette.disk) }
                                } else { Text("Port/dizin taraması bekleniyor").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                            }.padding(.leading, CGFloat(min(row.depth, 12)) * 14).padding(.vertical, 13)
                            Divider().opacity(0.3)
                        }
                    }
                }
            } else { Text("Bu proje artık çalışan süreçlere eşlenmiyor").foregroundStyle(Palette.secondary).frame(maxHeight: .infinity) }
            Text("Dizin ve port metadata'sı 10 saniyede bir yenilenir. Başka kullanıcılar ve korumalı süreçler kapsam dışındadır. Liste salt okunurdur.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }.padding(26).frame(width: 900, height: 650).background(Palette.background).foregroundStyle(.primary)
    }
}

struct ContainersView: View {
    let snapshot: ContainerSnapshot?
    @State private var search = ""
    @State private var onlyRunning = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Containerlar", systemImage: "shippingbox").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                if let snapshot { Text("Yerel sorgu \(snapshot.scannedAt.formatted(date: .omitted, time: .standard))").font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            }
            Text(snapshot.map { "Gözlenen: \($0.runningCount) çalışıyor · \($0.containerCount) container · salt okunur yerel bağlantı" } ?? "Container ölçümü alınamıyor")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            HStack {
                TextField("Container, image veya Compose projesi ara", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                Toggle("Yalnız çalışanlar", isOn: $onlyRunning).toggleStyle(.switch).font(.system(size: 12))
                Spacer()
            }
            ForEach(snapshot?.runtimes ?? []) { runtime in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(runtime.name, systemImage: "shippingbox.fill").font(.system(size: 15, weight: .semibold))
                        Spacer(); Text(runtime.state.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(runtime.state == .available ? Palette.accent : Palette.secondary)
                    }
                    if runtime.state == .available {
                        let rows = runtime.containers.filter { container in
                            (!onlyRunning || container.running) && (search.isEmpty || [container.name, container.image, container.composeProject ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
                        }
                        if rows.isEmpty { Text("Bu filtreye uyan container bulunamadı").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.vertical, 15) }
                        LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { container in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(alignment: .top) {
                                    Circle().fill(container.running ? Palette.accent : Palette.secondary).frame(width: 7, height: 7).padding(.top, 4)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(container.name).font(.system(size: 14, weight: .semibold))
                                        Text(container.image).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1)
                                        if let compose = container.composeProject { Text("Compose · \(compose)").font(.system(size: 10)).foregroundStyle(Palette.accent) }
                                    }
                                    Spacer()
                                    Text(container.state).font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(width: 90)
                                    VStack(alignment: .trailing, spacing: 5) {
                                        Text(ApplicationFormat.cpu(container.resources?.cpuPercent)).foregroundStyle(Palette.cpu)
                                        Text("CPU · bir çekirdek %100").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                                    }.frame(width: 125)
                                    VStack(alignment: .trailing, spacing: 5) {
                                        Text(MetricFormat.bytes(container.resources?.memoryBytes, binary: true))
                                        Text("Bellek · cache dahil").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                                    }.frame(width: 145)
                                }.font(.system(size: 12)).monospacedDigit()
                                Text(container.ports.isEmpty ? "Port eşlemesi bildirilmedi" : container.ports.map(\.label).joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(Palette.disk)
                                HStack {
                                    Text(container.status).lineLimit(1)
                                    Spacer()
                                    if let resources = container.resources {
                                        Text("Ağ sayacı ↓ \(MetricFormat.bytes(resources.receivedBytes)) ↑ \(MetricFormat.bytes(resources.sentBytes))")
                                    } else if container.running { Text("Kaynak ölçümü alınamadı") }
                                }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }.padding(.vertical, 12)
                            Divider().opacity(0.25)
                        }
                        }
                        if runtime.inventoryTruncated || runtime.resourcesUnavailable > 0 {
                            Text("\(runtime.resourcesUnavailable) çalışan container'da kaynak ölçümü eksik\(runtime.inventoryTruncated ? " · envanter kısmi" : "")")
                                .font(.system(size: 11)).foregroundStyle(Palette.disk)
                        }
                    } else {
                        Text(runtime.state == .notRunning ? "Çalışan runtime süreci bulunamadı; bağlantı kurulmadı." : runtime.state == .noSocket ? "Çalışan runtime'ın standart yerel socketi bulunamadı." : "Yerel API yanıt vermedi veya erişim kısıtlı; envanter bilinmiyor.")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.vertical, 12)
                    }
                }.padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            }
            Text("Docker Desktop, OrbStack ve Podman'ın standart yerel Unix socketleri sorgulanır. Kapalı runtime başlatılmaz; uzak context kullanılmaz. Bilgiler 10 saniyede bir alınır. CPU ve bellek container kapsamındadır; Mac süreçlerine eklenip toplanmaz. Ağ değeri hız değil, runtime'ın bildirdiği yaşam boyu sayacıdır. Duran container için kaynak ölçümü yoktur.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
private extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
