import Foundation

public enum ProcessGrouping {
    public static func bundleRoot(_ executable: String) -> String? {
        let parts = executable.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + parts[...index].joined(separator: "/")
    }
    // A stable UI key, not a security hash. Paths stay out of encoded reports.
    public static func stableKey(_ text: String) -> String {
        let value = text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(value, radix: 16)
    }

    public static func group(current: [RawProcessReading], previous: [ProcessIdentity: RawProcessReading],
                             applications: [ApplicationDescriptor], coverage: ProcessCoverage) -> ProcessSnapshot {
        let byPID = Dictionary(current.map { ($0.identity.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let byPath = Dictionary(applications.map { ($0.bundlePath, $0) }, uniquingKeysWith: { first, _ in first })
        var direct: [ProcessIdentity: ApplicationDescriptor] = [:]
        var coalitionOwners: [UInt64: [String: ApplicationDescriptor]] = [:]
        for process in current {
            guard let path = process.executablePath, let root = bundleRoot(path), let app = byPath[root] else { continue }
            direct[process.identity] = app
            if let coalition = process.coalition, coalition > 0 { coalitionOwners[coalition, default: [:]][app.key] = app }
        }
        func owner(_ process: RawProcessReading) -> (ApplicationDescriptor, Attribution)? {
            if let app = direct[process.identity] { return (app, .bundle) }
            var node = process
            var visited: Set<ProcessIdentity> = [node.identity]
            for _ in 0..<64 {
                guard let parent = byPID[node.parentPID], parent.identity.startMicroseconds <= node.identity.startMicroseconds,
                      !visited.contains(parent.identity) else { break }
                visited.insert(parent.identity)
                if let app = direct[parent.identity] { return (app, .parent) }
                node = parent
            }
            // Detached XPC/WebKit helpers can have launchd as their parent.
            // Attribute only when exactly one verified app owns this resource coalition.
            if let coalition = process.coalition, coalition > 0,
               let owners = coalitionOwners[coalition], owners.count == 1, let app = owners.values.first {
                return (app, .coalition)
            }
            return nil
        }
        var members: [String: [ProcessUsage]] = [:]
        var descriptors: [String: ApplicationDescriptor] = [:]
        var names: [String: String] = [:]
        for process in current {
            let attribution = owner(process)
            let key: String
            if let (app, _) = attribution { key = app.key; descriptors[key] = app; names[key] = app.name }
            else {
                key = process.executablePath.map { "independent:" + stableKey($0) } ?? "process:" + process.identity.key
                names[key] = process.name
            }
            let cpu = previous[process.identity].flatMap { ProcessCPU.percent(previous: $0, current: process) }
            members[key, default: []].append(ProcessUsage(identity: process.identity, parentPID: process.parentPID,
                name: process.name, cpuPercent: cpu, footprint: process.footprint, resident: process.resident,
                attribution: attribution?.1 ?? .independent))
        }
        let groups = members.map { key, rows in
            ApplicationUsage(id: key, name: names[key] ?? "Süreç", kind: descriptors[key] == nil ? .independent : .application,
                bundleIdentifier: descriptors[key]?.bundleIdentifier, bundlePath: descriptors[key]?.bundlePath,
                processes: rows.sorted { $0.identity.pid < $1.identity.pid })
        }
        return ProcessSnapshot(groups: ProcessSort.memory.sorted(groups), coverage: coverage)
    }
}
