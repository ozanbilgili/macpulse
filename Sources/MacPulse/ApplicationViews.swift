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
    case all, applications, independent
    var id: Self { self }
    var label: String {
        switch self { case .all: String(localized: "All"); case .applications: String(localized: "Apps"); case .independent: String(localized: "Standalone") }
    }
}

struct GroupSelection: Identifiable {
    let id, name: String
}

enum ApplicationFormat {
    static func cpu(_ value: Double?, partial: Bool = false) -> String {
        guard let value else { return "—" }
        return (partial ? "≥ " : "") + LocalizedFormat.percent(value, digits: 1)
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
    var title = String(localized: "Apps and processes")
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
                    Text("\(snapshot.applicationCount) apps · \(snapshot.processCount) processes")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
            if limit == nil {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                        TextField("Search apps, processes or PID", text: $search).textFieldStyle(.plain)
                            .accessibilityLabel("Search apps or processes")
                    }.font(.system(size: 13)).padding(10).frame(maxWidth: 360)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                    Picker("Scope", selection: $scope) {
                        ForEach(ApplicationScope.allCases) { value in Text(value.label).tag(value) }
                    }.pickerStyle(.segmented).frame(width: 280)
                    Spacer()
                    Picker("Sort", selection: $sort) {
                        ForEach(ProcessSort.allCases) { value in Text(value.label).tag(value) }
                    }.frame(width: 150)
                }
            }
            Text("CPU: 100% = one core · Memory: physical memory charged to the app")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            VStack(spacing: 0) {
                HStack {
                    Text("App / group")
                    Spacer()
                    Text("Process").frame(width: 65, alignment: .trailing)
                    Text("CPU").frame(width: 110, alignment: .trailing)
                    Text("Memory").frame(width: 125, alignment: .trailing)
                    Color.clear.frame(width: 14)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary).padding(.horizontal, 18).padding(.vertical, 13)
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                if rows.isEmpty {
                    Text(snapshot == nil ? "Process list unavailable" : "No processes match this filter")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity).padding(32)
                }
                LazyVStack(spacing: 0) {
                    ForEach(rows) { group in
                        Button { select(group) } label: {
                            HStack(spacing: 12) {
                                ApplicationIcon(group: group)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(group.kind == .application ? "Including helper processes" : "Standalone process group")
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
                        }.buttonStyle(.plain).accessibilityLabel("\(group.name), \(group.processes.count) processes, CPU \(ApplicationFormat.cpu(group.cpuPercent, partial: group.cpuIsPartial)), memory \(ApplicationFormat.memory(group.footprint, partial: group.memoryIsPartial)), open process details")
                        Rectangle().fill(Color.primary.opacity(0.035)).frame(height: 1).padding(.leading, 60)
                    }
                }
            }.background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            if let snapshot {
                coverage(snapshot)
            }
            Text("Memory footprint and RSS are different measurements. Because of shared and compressed memory, the process total doesn't match the system's used RAM exactly. The ≥ sign marks a subtotal of only the processes that could be measured.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }.onAppear { sort = initialSort }
    }

    private func coverage(_ snapshot: ProcessSnapshot) -> some View {
        let inaccessible = snapshot.coverage.otherUsers + snapshot.coverage.metadataUnavailable
        return HStack(spacing: 20) {
            Label("\(snapshot.memoryMeasuredCount)/\(snapshot.processCount) processes measured", systemImage: "checkmark.circle")
            Text("\(inaccessible) processes out of scope")
            Text("\(snapshot.independentCount) standalone processes")
            if snapshot.coverage.truncated { Text("Partial list").foregroundStyle(Palette.disk) }
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
                Label(sort == .cpu ? "Top CPU" : "Top memory", systemImage: sort == .cpu ? "cpu" : "memorychip")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(sort == .cpu ? Palette.cpu : Palette.memory)
                Spacer()
                Button("All", action: showAll).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent)
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
                }.buttonStyle(.plain).accessibilityLabel("\(group.name), open process details")
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
                    Text(group.map { "\($0.processes.count) processes · live measurements" } ?? "This group is no longer running")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let group {
                FactRow(facts: [StatFact(title: String(localized: "CPU · one core = \(LocalizedFormat.percent(100))"), value: ApplicationFormat.cpu(group.cpuPercent, partial: group.cpuIsPartial)),
                    StatFact(title: String(localized: "Memory footprint"), value: ApplicationFormat.memory(group.footprint, partial: group.memoryIsPartial)),
                    StatFact(title: String(localized: "RSS total"), value: ApplicationFormat.memory(group.resident, partial: group.memoryIsPartial)),
                    StatFact(title: String(localized: "Measured processes"), value: "\(group.memoryMeasuredCount)/\(group.processes.count)")])
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
                                Text("Parent \(process.parentPID)")
                                Text(process.attribution.label)
                                Spacer()
                                Text("Started \(process.identity.startDate.formatted(date: .abbreviated, time: .shortened))")
                            }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            if process.footprint == nil {
                                Text("This process's resource usage can't be read.").font(.system(size: 10)).foregroundStyle(Palette.disk)
                            } else if process.cpuPercent == nil {
                                Text("Taking a new baseline sample for CPU rate.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }
                        }.padding(.vertical, 14)
                        Divider().overlay(Color.primary.opacity(0.04))
                    }
                }
            }
            Text("Memory footprint is the app's load including compressed memory; RSS shows the pages in RAM right now. Processes are tracked by PID and start time.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(26).frame(width: 900, height: 620).background(Palette.background).foregroundStyle(.primary)
    }
}
