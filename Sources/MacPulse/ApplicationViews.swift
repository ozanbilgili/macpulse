import SwiftUI
import AppKit
import MetricsCore

@MainActor private enum ApplicationIcons {
    static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()
    static func image(path: String) -> NSImage {
        if let image = cache.object(forKey: path as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct ApplicationIcon: View {
    let group: ApplicationUsage
    var size: CGFloat = 30
    var body: some View {
        Group {
            if let path = group.bundlePath {
                Image(nsImage: ApplicationIcons.image(path: path)).resizable().scaledToFit()
            } else {
                Image(systemName: "terminal").font(.system(size: size * 0.6)).foregroundStyle(Palette.secondary)
                    .frame(width: size, height: size).background(Palette.elevated, in: RoundedRectangle(cornerRadius: 6))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

enum ApplicationScope: String, CaseIterable, Identifiable {
    case all = "Tümü", applications = "Uygulamalar", independent = "Bağımsız"
    var id: Self { self }
}

struct GroupSelection: Identifiable {
    let id, name: String
}

enum ApplicationFormat {
    static func cpu(_ value: Double?, partial: Bool = false) -> String {
        guard let value else { return "—" }
        return (partial ? "≥ " : "") + MetricFormat.number(value, digits: 1) + "%"
    }
    static func memory(_ value: UInt64?, partial: Bool = false) -> String {
        guard value != nil else { return "—" }
        return (partial ? "≥ " : "") + MetricFormat.bytes(value, binary: true)
    }
}

struct ApplicationListView: View {
    let snapshot: ProcessSnapshot?
    var initialSort: ProcessSort = .memory
    var limit: Int? = nil
    var title = "Uygulamalar ve süreçler"
    let select: (ApplicationUsage) -> Void
    @State private var search = ""
    @State private var scope: ApplicationScope = .all
    @State private var sort: ProcessSort = .memory

    private var rows: [ApplicationUsage] {
        let filtered = (snapshot?.groups ?? []).filter { group in
            let matchesScope = scope == .all || (scope == .applications && group.kind == .application) || (scope == .independent && group.kind == .independent)
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || group.name.localizedCaseInsensitiveContains(query)
                || group.processes.contains { $0.name.localizedCaseInsensitiveContains(query) || String($0.identity.pid) == query }
            return matchesScope && matchesSearch
        }
        let sorted = (limit == nil ? sort : initialSort).sorted(filtered)
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.system(size: 21, weight: .semibold, design: .rounded))
                Spacer()
                if let snapshot {
                    Text("\(snapshot.applicationCount) uygulama · \(snapshot.processCount) süreç")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
            if limit == nil {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                        TextField("Uygulama, süreç veya PID ara", text: $search).textFieldStyle(.plain)
                            .accessibilityLabel("Uygulama veya süreç ara")
                    }.font(.system(size: 13)).padding(10).frame(maxWidth: 360)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                    Picker("Kapsam", selection: $scope) {
                        ForEach(ApplicationScope.allCases) { value in Text(value.rawValue).tag(value) }
                    }.pickerStyle(.segmented).frame(width: 280)
                    Spacer()
                    Picker("Sıralama", selection: $sort) {
                        ForEach(ProcessSort.allCases) { value in Text(value.rawValue).tag(value) }
                    }.frame(width: 150)
                }
            }
            Text("CPU: bir çekirdek %100 · Bellek: uygulamaya yüklenen fiziksel bellek")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            VStack(spacing: 0) {
                HStack {
                    Text("Uygulama / grup")
                    Spacer()
                    Text("Süreç").frame(width: 65, alignment: .trailing)
                    Text("CPU").frame(width: 110, alignment: .trailing)
                    Text("Bellek").frame(width: 125, alignment: .trailing)
                    Color.clear.frame(width: 14)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary).padding(.horizontal, 18).padding(.vertical, 13)
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                if rows.isEmpty {
                    Text(snapshot == nil ? "Süreç listesi alınamıyor" : "Bu filtreye uyan süreç bulunamadı")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity).padding(32)
                }
                LazyVStack(spacing: 0) {
                    ForEach(rows) { group in
                        Button { select(group) } label: {
                            HStack(spacing: 12) {
                                ApplicationIcon(group: group)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(group.kind == .application ? "Yardımcı süreçler dahil" : "Bağımsız süreç grubu")
                                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                }
                                Spacer(minLength: 12)
                                Text("\(group.processes.count)").frame(width: 65, alignment: .trailing)
                                Text(ApplicationFormat.cpu(group.cpuPercent, partial: group.cpuIsPartial)).foregroundStyle(Palette.cpu)
                                    .frame(width: 110, alignment: .trailing)
                                Text(ApplicationFormat.memory(group.footprint, partial: group.memoryIsPartial)).frame(width: 125, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.secondary).frame(width: 14)
                            }.font(.system(size: 12, weight: .medium)).monospacedDigit()
                                .padding(.horizontal, 18).padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(group.name), \(group.processes.count) süreç, CPU \(ApplicationFormat.cpu(group.cpuPercent, partial: group.cpuIsPartial)), bellek \(ApplicationFormat.memory(group.footprint, partial: group.memoryIsPartial)), süreç ayrıntılarını aç")
                        Rectangle().fill(Color.primary.opacity(0.035)).frame(height: 1).padding(.leading, 60)
                    }
                }
            }.background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            if let snapshot {
                coverage(snapshot)
            }
            Text("Bellek yükü ve RSS farklı ölçümlerdir. Paylaşılan ve sıkıştırılmış bellek nedeniyle süreç toplamı, sistemin kullanılan RAM değeriyle birebir örtüşmez. ≥ işareti yalnız ölçülebilen süreçlerin ara toplamını gösterir.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }.onAppear { sort = initialSort }
    }

    private func coverage(_ snapshot: ProcessSnapshot) -> some View {
        let inaccessible = snapshot.coverage.otherUsers + snapshot.coverage.metadataUnavailable
        return HStack(spacing: 20) {
            Label("\(snapshot.memoryMeasuredCount)/\(snapshot.processCount) süreç ölçüldü", systemImage: "checkmark.circle")
            Text("\(inaccessible) süreç kapsam dışında")
            Text("\(snapshot.independentCount) süreç bağımsız")
            if snapshot.coverage.truncated { Text("Liste kısmi").foregroundStyle(Palette.disk) }
        }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
    }
}

struct TopApplicationsView: View {
    let snapshot: ProcessSnapshot
    let sort: ProcessSort
    let select: (ApplicationUsage) -> Void
    let showAll: () -> Void
    private var rows: [ApplicationUsage] { Array(sort.sorted(snapshot.groups).prefix(5)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(sort == .cpu ? "CPU kullananlar" : "Bellek kullananlar", systemImage: sort == .cpu ? "cpu" : "memorychip")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(sort == .cpu ? Palette.cpu : Palette.memory)
                Spacer()
                Button("Tümü", action: showAll).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            ForEach(rows) { group in
                Button { select(group) } label: {
                    HStack(spacing: 10) {
                        ApplicationIcon(group: group, size: 24)
                        Text(group.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(group.processes.count)").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Text(sort == .cpu ? ApplicationFormat.cpu(group.cpuPercent, partial: group.cpuIsPartial) : ApplicationFormat.memory(group.footprint, partial: group.memoryIsPartial))
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(group.name), süreç ayrıntılarını aç")
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ProcessDetailSheet: View {
    let selection: GroupSelection
    let group: ApplicationUsage?
    @Environment(\.dismiss) private var dismiss
    private var members: [ProcessUsage] {
        (group?.processes ?? []).sorted { left, right in
            if left.footprint != right.footprint { return (left.footprint ?? 0) > (right.footprint ?? 0) }
            return left.identity.pid < right.identity.pid
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                if let group { ApplicationIcon(group: group, size: 40) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(selection.name).font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(group.map { "\($0.processes.count) süreç · canlı ölçümler" } ?? "Bu grup artık çalışmıyor")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let group {
                FactRow(facts: [StatFact(title: "CPU · bir çekirdek %100", value: ApplicationFormat.cpu(group.cpuPercent, partial: group.cpuIsPartial)),
                    StatFact(title: "Bellek yükü", value: ApplicationFormat.memory(group.footprint, partial: group.memoryIsPartial)),
                    StatFact(title: "RSS toplamı", value: ApplicationFormat.memory(group.resident, partial: group.memoryIsPartial)),
                    StatFact(title: "Ölçülen süreç", value: "\(group.memoryMeasuredCount)/\(group.processes.count)")])
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(members) { process in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(process.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Spacer()
                                Text(ApplicationFormat.cpu(process.cpuPercent)).foregroundStyle(Palette.cpu).frame(width: 100, alignment: .trailing)
                                Text(ApplicationFormat.memory(process.footprint)).frame(width: 115, alignment: .trailing)
                                Text("RSS \(ApplicationFormat.memory(process.resident))").foregroundStyle(Palette.secondary).frame(width: 145, alignment: .trailing)
                            }.font(.system(size: 12)).monospacedDigit()
                            HStack(spacing: 14) {
                                Text("PID \(process.identity.pid)")
                                Text("Ebeveyn \(process.parentPID)")
                                Text(process.attribution.label)
                                Spacer()
                                Text("Başlangıç \(process.identity.startDate.formatted(date: .abbreviated, time: .shortened))")
                            }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            if process.footprint == nil {
                                Text("Bu sürecin kaynak ölçümüne erişilemiyor.").font(.system(size: 10)).foregroundStyle(Palette.disk)
                            } else if process.cpuPercent == nil {
                                Text("CPU hızı için yeni bir başlangıç ölçümü alınıyor.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }
                        }.padding(.vertical, 14)
                        Divider().overlay(Color.primary.opacity(0.04))
                    }
                }
            }
            Text("Bellek yükü sıkıştırılmış bellek dahil uygulamanın yükünü; RSS ise o anda RAM'de bulunan sayfaları gösterir. Süreç kimliği PID ve başlangıç zamanı ile takip edilir.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(26).frame(width: 900, height: 620).background(Palette.background).foregroundStyle(.primary)
    }
}
