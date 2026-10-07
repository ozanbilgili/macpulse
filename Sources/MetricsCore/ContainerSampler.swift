import Foundation
import CoreFoundation
import Darwin
import TelemetryBridge

struct ContainerSampler {
    private var lastScan: Double?
    private var latest: ContainerSnapshot?
    private var previousCPU: [String: ContainerCPUReading] = [:]
    mutating func reset() { lastScan = nil; latest = nil; previousCPU = [:] }
    struct Endpoint { let name, path: String; let running: Bool }
    static func endpoints(readings: [RawProcessReading], home: URL = FileManager.default.homeDirectoryForCurrentUser, temporary: URL = FileManager.default.temporaryDirectory) -> [Endpoint] {
        let paths = readings.compactMap(\.executablePath)
        let dockerBackend = paths.contains { $0.contains("/Docker.app/") && $0.hasSuffix("/com.docker.backend") }
        let dockerVM = paths.contains { path in path.contains("/Docker.app/") && ["com.docker.virtualization", "com.docker.hyperkit", "qemu-system-aarch64", "qemu-system-x86_64"].contains(URL(fileURLWithPath: path).lastPathComponent) }
        // A desktop backend/socket can survive Resource Saver after its Linux VM stops.
        let dockerRunning = dockerBackend && dockerVM
        let orbRunning = paths.contains { $0.contains("/OrbStack.app/") && $0.hasSuffix("/Contents/MacOS/OrbStack") }
        let podmanRunning = paths.contains { ["gvproxy", "vfkit"].contains(URL(fileURLWithPath: $0).lastPathComponent) && $0.lowercased().contains("podman") }
        let docker = home.appendingPathComponent(".docker/run/docker.sock").path
        let orb = home.appendingPathComponent(".orbstack/run/docker.sock").path
        var result = [Endpoint(name: "Docker Desktop", path: docker, running: dockerRunning), Endpoint(name: "OrbStack", path: orb, running: orbRunning)]
        if dockerRunning && !isSocket(docker) { result[0] = Endpoint(name: "Docker Desktop", path: "/var/run/docker.sock", running: true) }
        // Bounded metadata discovery; no configuration/credential files or remote contexts.
        let directory = temporary.appendingPathComponent("podman")
        let sockets = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("-api.sock") }.sorted { $0.path < $1.path }.prefix(4)
        if sockets.isEmpty { result.append(Endpoint(name: "Podman", path: directory.appendingPathComponent("podman-machine-default-api.sock").path, running: podmanRunning)) }
        else { result += sockets.map { Endpoint(name: "Podman", path: $0.path, running: podmanRunning) } }
        return result
    }
    // Request only type and identity; no file timestamp fields are accessed.
    static func isSocket(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        return (try? url.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType) == .socket
    }
    static func socketKey(_ path: String) -> AnyHashable? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard let value = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject else { return nil }
        return AnyHashable(value)
    }
    mutating func sample(readings: [RawProcessReading]?, uptime: Double) -> ContainerSnapshot? {
        guard let readings else { reset(); return nil }
        if let lastScan, let latest, uptime - lastScan >= 0 && uptime - lastScan < 10 { return latest }
        var runtimes: [ContainerRuntimeSnapshot] = [], seen = Set<AnyHashable>()
        var nextCPU: [String: ContainerCPUReading] = [:]
        for endpoint in Self.endpoints(readings: readings) {
            let id = endpoint.name + ":" + ProcessGrouping.stableKey(endpoint.path)
            let exists = Self.isSocket(endpoint.path)
            if let key = Self.socketKey(endpoint.path), endpoint.running, exists, !seen.insert(key).inserted { continue }
            // Presence alone does not prove an engine is active. Never connect to a stopped runtime.
            guard endpoint.running, exists else {
                runtimes.append(ContainerRuntimeSnapshot(id: id, name: endpoint.name,
                    state: endpoint.running ? .noSocket : .notRunning, containers: [], inventoryTruncated: false, resourcesUnavailable: 0)); continue
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 1.5
            do {
                let response = try Self.get(endpoint.path, "/containers/json?all=1", timeout: 500)
                var inventory = try ContainerAPI.inventory(ContainerAPI.body(response))
                var missing = 0, queried = 0
                for index in inventory.entries.indices where inventory.entries[index].running {
                    let remaining = Int((deadline - ProcessInfo.processInfo.systemUptime) * 1000)
                    guard remaining > 0, queried < 64 else { missing += 1; continue }
                    queried += 1
                    do {
                        let data = try Self.get(endpoint.path, "/containers/" + inventory.entries[index].id + "/stats?stream=false&one-shot=true", timeout: min(400, remaining))
                        let body = try ContainerAPI.body(data)
                        let resources = try ContainerAPI.resources(body)
                        let key = id + ":" + inventory.entries[index].id
                        let reading = try ContainerAPI.cpuReading(body, uptime: ProcessInfo.processInfo.systemUptime)
                        let cpu = resources.cpuPercent ?? reading.flatMap { ContainerCPUReading.percent(previous: previousCPU[key], current: $0) }
                        if let reading { nextCPU[key] = reading }
                        inventory.entries[index].resources = ContainerResourceUsage(cpuPercent: cpu, memoryBytes: resources.memoryBytes,
                            memoryLimitBytes: resources.memoryLimitBytes, receivedBytes: resources.receivedBytes, sentBytes: resources.sentBytes)
                    } catch { missing += 1 }
                }
                runtimes.append(ContainerRuntimeSnapshot(id: id, name: endpoint.name, state: .available,
                    containers: inventory.entries, inventoryTruncated: inventory.truncated, resourcesUnavailable: missing))
            } catch {
                runtimes.append(ContainerRuntimeSnapshot(id: id, name: endpoint.name, state: .unavailable, containers: [], inventoryTruncated: false, resourcesUnavailable: 0))
            }
        }
        let result = ContainerSnapshot(runtimes: runtimes, scannedAt: Date())
        previousCPU = nextCPU; latest = result; lastScan = uptime; return result
    }
    static func get(_ socket: String, _ endpoint: String, timeout: Int) throws -> Data {
        var buffer = [CChar](repeating: 0, count: 2_097_152), count: Int32 = 0
        let status = buffer.withUnsafeMutableBufferPointer { mp_container_get(socket, endpoint, Int32(timeout), $0.baseAddress, Int32($0.count), &count) }
        guard status == 0 else { throw ContainerAPIError.response }
        return buffer.withUnsafeBufferPointer { Data(bytes: $0.baseAddress!, count: Int(count)) }
    }
}
