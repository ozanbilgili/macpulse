import Foundation

public struct TCPListener: Hashable, Sendable, Identifiable {
    public let port: UInt16
    public let ipv6, loopback, wildcard: Bool
    public var id: String { "\(port):\(ipv6):\(loopback):\(wildcard)" }
    public var label: String {
        let scope = loopback ? String(localized: "local") : wildcard ? String(localized: "all interfaces") : String(localized: "specific interface")
        return "\(port) · \(ipv6 ? "IPv6" : "IPv4") · \(scope)"
    }
}

public struct DeveloperReading: Sendable {
    public let identity: ProcessIdentity
    public let cwd: String?
    public let projectRoot: String?
    public let listeners: [TCPListener]
    public let socketsComplete: Bool
    public let activeConnections: Int
    public let queuedBytes: UInt64
    public let uptime: Double
}

public enum ProjectAttribution: String, Sendable {
    case directory, parent
    public var label: String { switch self { case .directory: String(localized: "Working directory"); case .parent: String(localized: "Parent process") } }
}
public struct ProjectMember: Sendable, Identifiable {
    public let usage: ProcessUsage
    public let attribution: ProjectAttribution
    public let metadata: DeveloperReading?
    public var id: ProcessIdentity { usage.identity }
}
public enum ProjectActivity: String, Sendable {
    case active, observing, idleCandidate, unknown
    public var label: String {
        switch self {
        case .active: String(localized: "Active"); case .observing: String(localized: "Observing")
        case .idleCandidate: String(localized: "Idle candidate"); case .unknown: String(localized: "Missing measurement")
        }
    }
}
public struct DevelopmentProject: Sendable, Identifiable {
    public let root: String
    public var id: String { "project:" + ProcessGrouping.stableKey(root) }
    public var name: String { URL(fileURLWithPath: root).lastPathComponent }
    public let members: [ProjectMember]
    public var activity: ProjectActivity = .unknown
    public var quietSeconds: Double = 0
    public var cpuPercent: Double? {
        let values = members.compactMap { $0.usage.cpuPercent }; return values.isEmpty ? nil : values.reduce(0, +)
    }
    public var footprint: UInt64? {
        let values = members.compactMap { $0.usage.footprint }; return values.isEmpty ? nil : values.reduce(0, +)
    }
    public var cpuPartial: Bool { members.contains { $0.usage.cpuPercent == nil } }
    public var memoryPartial: Bool { members.contains { $0.usage.footprint == nil } }
    public var listeners: [TCPListener] { Array(Set(members.flatMap { $0.metadata?.listeners ?? [] })).sorted { $0.id < $1.id } }
    public var activeConnections: Int? {
        guard members.allSatisfy({ $0.metadata?.socketsComplete == true }) else { return nil }
        return members.reduce(0) { $0 + ($1.metadata?.activeConnections ?? 0) }
    }
    /// Tree edges only exist when both process identities are valid in this snapshot.
    public var tree: [(member: ProjectMember, depth: Int)] {
        let byPID = Dictionary(members.map { ($0.id.pid, $0) }, uniquingKeysWith: { first, _ in first })
        func parent(_ member: ProjectMember) -> ProjectMember? {
            guard let candidate = byPID[member.usage.parentPID], candidate.id != member.id,
                  candidate.id.startMicroseconds <= member.id.startMicroseconds else { return nil }
            return candidate
        }
        var visited = Set<ProcessIdentity>(), result: [(ProjectMember, Int)] = []
        func visit(_ member: ProjectMember, _ depth: Int) {
            guard depth <= 64, visited.insert(member.id).inserted else { return }
            result.append((member, depth))
            for child in members.filter({ parent($0)?.id == member.id }).sorted(by: { $0.id.pid < $1.id.pid }) { visit(child, depth + 1) }
        }
        for member in members.filter({ parent($0) == nil }).sorted(by: { $0.id.pid < $1.id.pid }) { visit(member, 0) }
        for member in members where !visited.contains(member.id) { visit(member, 0) }
        return result
    }
}
public struct DeveloperCoverage: Sendable, Encodable {
    public var scanned = 0, cwdUnavailable = 0, socketsUnavailable = 0, truncated = 0, changed = 0
}
public struct DeveloperSnapshot: Sendable {
    public let projects: [DevelopmentProject]
    public let unmappedListeners: [ProjectMember]
    public let coverage: DeveloperCoverage
    public let scannedAt: Date
    public var listenerProcessCount: Int { projects.flatMap(\.members).filter { !($0.metadata?.listeners.isEmpty ?? true) }.count + unmappedListeners.count }
}

public enum ProjectGrouping {
    public static func group(processes: [ProcessUsage], metadata: [ProcessIdentity: DeveloperReading]) -> (projects: [DevelopmentProject], unmapped: [ProjectMember]) {
        let metadata = metadata.filter { $0.key == $0.value.identity }
        let byPID = Dictionary(processes.map { ($0.identity.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: [ProjectMember]] = [:], unmapped: [ProjectMember] = []
        for process in processes {
            var root = metadata[process.identity]?.projectRoot
            var attribution = ProjectAttribution.directory
            // An explicit cwd outside a project must not borrow an unrelated parent's project.
            let cwd = metadata[process.identity]?.cwd
            if root == nil && (cwd == nil || cwd == "/") {
                var child = process, seen: Set<Int32> = [process.identity.pid]
                for _ in 0..<64 {
                    guard let parent = byPID[child.parentPID], seen.insert(parent.identity.pid).inserted,
                          parent.identity.startMicroseconds <= child.identity.startMicroseconds else { break }
                    if let inherited = metadata[parent.identity]?.projectRoot { root = inherited; attribution = .parent; break }
                    child = parent
                }
            }
            let member = ProjectMember(usage: process, attribution: attribution, metadata: metadata[process.identity])
            if let root { groups[root, default: []].append(member) }
            else if !(member.metadata?.listeners.isEmpty ?? true) { unmapped.append(member) }
        }
        return (groups.map { DevelopmentProject(root: $0.key, members: $0.value) }.sorted { $0.root < $1.root },
                unmapped.sorted { $0.id.pid < $1.id.pid })
    }
}

struct ProjectIdleTracker {
    struct State { let identities: Set<ProcessIdentity>; let since: Double; let last: Double; let topology: Set<String> }
    private var states: [String: State] = [:]
    mutating func reset() { states = [:] }
    mutating func update(_ projects: [DevelopmentProject], uptime: Double) -> [DevelopmentProject] {
        var next: [String: State] = [:]
        let result = projects.map { source -> DevelopmentProject in
            var project = source
            let metadata = project.members.compactMap(\.metadata)
            guard !project.cpuPartial, let cpu = project.cpuPercent, cpu.isFinite,
                  metadata.count == project.members.count,
                  metadata.allSatisfy({ $0.socketsComplete && uptime - $0.uptime >= 0 && uptime - $0.uptime <= 15 }) else { return project }
            let topology = Set(project.members.flatMap { member in (member.metadata?.listeners ?? []).map { member.id.key + ":" + $0.id } })
            let identities = Set(project.members.map(\.id))
            let old = states[project.id]
            let continuous = old.map { $0.identities == identities && $0.topology == topology && uptime - $0.last > 0 && uptime - $0.last <= 20 } ?? false
            let quiet = cpu < 1 && metadata.allSatisfy { $0.activeConnections == 0 && $0.queuedBytes == 0 }
            if quiet {
                let since = continuous ? old!.since : uptime
                project.quietSeconds = max(0, uptime - since)
                project.activity = project.quietSeconds >= 120 && !project.listeners.isEmpty ? .idleCandidate : .observing
                next[project.id] = State(identities: identities, since: since, last: uptime, topology: topology)
            } else { project.activity = .active }
            return project
        }
        states = next; return result
    }
}
