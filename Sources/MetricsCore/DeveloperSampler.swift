import Foundation
import TelemetryBridge

struct ProjectRootResolver {
    private var cache: [String: (root: String?, time: Double)] = [:]
    static let markers = [".git", "Package.swift", "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts", "composer.json", "CMakeLists.txt"]
    mutating func root(for path: String, uptime: Double) -> String? {
        if let value = cache[path], uptime - value.time < 30 { return value.root }
        let root = Self.resolve(path)
        if cache.count >= 1024 { cache = [:] }
        cache[path] = (root, uptime); return root
    }
    static func resolve(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var directory = URL(fileURLWithPath: path).standardizedFileURL
        // Presence checks only: never open manifests or walk the repository contents.
        for _ in 0..<24 {
            if directory.path == "/" || directory.path == FileManager.default.homeDirectoryForCurrentUser.path { return nil }
            let components = directory.pathComponents
            if !components.contains(where: { ["node_modules", ".build", ".venv", "vendor"].contains($0) }) {
                for marker in markers where !marker.hasPrefix("*") {
                    if FileManager.default.fileExists(atPath: directory.appendingPathComponent(marker).path) { return directory.path }
                }
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }
}

struct DeveloperSampler {
    private var readings: [ProcessIdentity: DeveloperReading] = [:]
    private var lastScan: Double?
    private var scannedAt = Date()
    private var resolver = ProjectRootResolver()
    private var coverage = DeveloperCoverage()
    private var idle = ProjectIdleTracker()
    mutating func reset() { lastScan = nil; readings = [:]; idle.reset() }
    mutating func sample(_ snapshot: ProcessSnapshot?, uptime: Double) -> DeveloperSnapshot? {
        guard let snapshot else { reset(); return nil }
        let processes = snapshot.groups.flatMap(\.processes)
        if lastScan == nil || uptime - lastScan! >= 10 || uptime - lastScan! < 0 {
            var next: [ProcessIdentity: DeveloperReading] = [:], scope = DeveloperCoverage()
            for process in processes {
                var raw = mp_developer_info(), ports = [mp_tcp_listener](repeating: mp_tcp_listener(), count: 64), count: Int32 = 0
                let status = ports.withUnsafeMutableBufferPointer {
                    mp_read_developer(process.identity.pid, process.identity.startMicroseconds, &raw, $0.baseAddress, Int32($0.count), &count)
                }
                scope.scanned += 1
                guard status == 0 else { scope.changed += 1; continue }
                let cwd = raw.cwd_status == 0 ? withUnsafePointer(to: &raw.cwd) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) }
                } : nil
                if cwd == nil || cwd!.isEmpty { scope.cwdUnavailable += 1 }
                if raw.sockets_status != 0 || raw.failed_sockets != 0 { scope.socketsUnavailable += 1 }
                if raw.truncated != 0 { scope.truncated += 1 }
                let path = cwd.flatMap { $0.isEmpty ? nil : $0 }
                let listeners = Array(Set(ports.prefix(Int(count)).map {
                    TCPListener(port: $0.port, ipv6: $0.family == AF_INET6, loopback: $0.loopback != 0, wildcard: $0.wildcard != 0)
                }))
                next[process.identity] = DeveloperReading(identity: process.identity, cwd: path,
                    projectRoot: path.flatMap { resolver.root(for: $0, uptime: uptime) }, listeners: listeners,
                    socketsComplete: raw.sockets_status == 0 && raw.failed_sockets == 0 && raw.truncated == 0,
                    activeConnections: Int(raw.active_connections), queuedBytes: raw.queued_bytes, uptime: uptime)
            }
            readings = next; coverage = scope; lastScan = uptime; scannedAt = Date()
        }
        let live = Set(processes.map(\.identity))
        readings = readings.filter { live.contains($0.key) }
        let grouped = ProjectGrouping.group(processes: processes, metadata: readings)
        return DeveloperSnapshot(projects: idle.update(grouped.projects, uptime: uptime), unmappedListeners: grouped.unmapped,
                                 coverage: coverage, scannedAt: scannedAt)
    }
}
