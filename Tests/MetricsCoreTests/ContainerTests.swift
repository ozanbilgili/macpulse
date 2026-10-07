import Foundation
import Darwin
import Testing
import TelemetryBridge
@testable import MetricsCore

private let containerID = String(repeating: "a", count: 64)
private func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
private func inventoryRow() -> [String: Any] {
    ["Id": containerID, "Names": ["/test"], "State": "running", "Image": "test:1", "Status": "Up",
     "Labels": ["com.docker.compose.project": "fixture", "private-label": "sensitive"],
     "Env": ["SHOULD_NOT_BE_INCLUDED"], "Ports": [["PrivatePort": 80, "PublicPort": 8080, "Type": "tcp", "IP": "127.0.0.1"]]]
}
@Test func containerInventoryKeepsOnlySelectedMetadata() throws {
    let result = try ContainerAPI.inventory(data([inventoryRow()]))
    #expect(result.entries.count == 1 && !result.truncated)
    #expect(result.entries[0].name == "test" && result.entries[0].composeProject == "fixture")
    #expect(result.entries[0].ports[0].label == "8080 → 80/tcp · IPv4 · yerel")
    let encoded = String(decoding: try JSONEncoder().encode(result.entries), as: UTF8.self)
    #expect(!encoded.contains("sensitive") && !encoded.contains("SHOULD_NOT") && !encoded.contains("127.0.0.1"))
}
@Test func inventoryRejectsUnsafeIDsAndBoundsRows() throws {
    #expect(!ContainerAPI.validID("../start")); #expect(!ContainerAPI.validID("a"))
    var malformed = inventoryRow(); malformed["Id"] = "../start"
    #expect(throws: (any Error).self) { try ContainerAPI.inventory(data([malformed])) }
    let rows = (0..<130).map { index -> [String: Any] in var row = inventoryRow(); row["Id"] = String(format: "%064x", index); return row }
    let result = try ContainerAPI.inventory(data(rows))
    #expect(result.entries.count == 128 && result.truncated)
}
@Test func containerPortFamiliesStayDistinctAndMissingBindingScopeStaysUnknown() throws {
    var row = inventoryRow()
    row["Ports"] = [["PrivatePort": 80, "PublicPort": 8080, "IP": "0.0.0.0"],
                    ["PrivatePort": 80, "PublicPort": 8080, "IP": "::"], ["PrivatePort": 81, "PublicPort": 8081]]
    let entries = try ContainerAPI.inventory(data([row])).entries
    #expect(entries[0].ports[0].family == "IPv4" && entries[0].ports[1].family == "IPv6")
    #expect(entries[0].ports[2].scope == "arayüz bilinmiyor")
    #expect(throws: (any Error).self) { try ContainerAPI.inventory(data([row, row])) }
}
@Test func HTTPParserVerifiesLengthStatusAndChunkFraming() throws {
    #expect(try ContainerAPI.body(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n[]".utf8)) == Data("[]".utf8))
    #expect(try ContainerAPI.body(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2;foo=bar\r\n[]\r\n0\r\n\r\n".utf8)) == Data("[]".utf8))
    for response in ["HTTP/1.1 403 Forbidden\r\n\r\n[]", "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n[]", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\n[]", "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n[]"] {
        #expect(throws: (any Error).self) { try ContainerAPI.body(Data(response.utf8)) }
    }
}
@Test func containerCPUUsesEngineIntervalAndNumericMemoryScale() throws {
    let row: [String: Any] = ["cpu_stats": ["cpu_usage": ["total_usage": 300], "system_cpu_usage": 2000, "online_cpus": 4],
        "precpu_stats": ["cpu_usage": ["total_usage": 100], "system_cpu_usage": 1000],
        "memory_stats": ["usage": 1_073_741_824, "limit": 2_147_483_648],
        "networks": ["eth0": ["rx_bytes": 500, "tx_bytes": 100], "eth1": ["rx_bytes": 100, "tx_bytes": 50]]]
    let result = try ContainerAPI.resources(data(row))
    #expect(result.cpuPercent == 80); #expect(result.memoryBytes == 1_073_741_824)
    #expect(result.receivedBytes == 600 && result.sentBytes == 150)
}
@Test func missingResetAndFirstContainerCPUCountersStayUnknown() throws {
    for system in [0, 1000, 3000] {
        let row: [String: Any] = ["cpu_stats": ["cpu_usage": ["total_usage": 100], "system_cpu_usage": 2000, "online_cpus": 4],
            "precpu_stats": ["cpu_usage": ["total_usage": system == 1000 ? 101 : 0], "system_cpu_usage": system]]
        #expect(try ContainerAPI.resources(data(row)).cpuPercent == nil)
    }
    let missing = try ContainerAPI.resources(data(["memory_stats": ["usage": true], "networks": ["eth0": ["rx_bytes": 1]]]))
    #expect(missing.memoryBytes == nil && missing.cpuPercent == nil && missing.sentBytes == nil)
}
@Test func emptyOrPartialContainerNetworksDoNotFabricateZero() throws {
    #expect(try ContainerAPI.resources(data(["networks": [:]])).receivedBytes == nil)
    #expect(try ContainerAPI.resources(data(["networks": ["a": ["rx_bytes": 0], "b": [:]]])).receivedBytes == nil)
    #expect(try ContainerAPI.resources(data(["networks": ["a": ["rx_bytes": 0, "tx_bytes": 0]]])).receivedBytes == 0)
}
@Test func runtimeDetectionRequiresActiveBackendRatherThanSocketPresence() {
    let empty = ContainerSampler.endpoints(readings: [])
    #expect(empty.allSatisfy { !$0.running })
    let backend = RawProcessReading(identity: .init(pid: 100, startMicroseconds: 1), parentPID: 1, name: "com.docker.backend",
        executablePath: "/Applications/Docker.app/Contents/MacOS/com.docker.backend", cpuNanoseconds: nil, footprint: nil, resident: nil, uptime: 0)
    #expect(ContainerSampler.endpoints(readings: [backend]).first { $0.name == "Docker Desktop" }?.running == false)
    let vm = RawProcessReading(identity: .init(pid: 101, startMicroseconds: 1), parentPID: 100, name: "FixtureVM",
        executablePath: "/Applications/Docker.app/Contents/MacOS/com.docker.virtualization", cpuNanoseconds: nil, footprint: nil, resident: nil, uptime: 0)
    #expect(ContainerSampler.endpoints(readings: [backend,vm]).first { $0.name == "Docker Desktop" }?.running == true)
    #expect(ContainerSampler.endpoints(readings: [backend]).first { $0.name == "Podman" }?.running == false)
}
@Test func CContainerBridgeRejectsMutatingEndpointsBeforeConnecting() {
    var response = [CChar](repeating: 0, count: 128), count: Int32 = 0
    for endpoint in ["/containers/json?all=0", "/containers/" + containerID + "/stop", "/containers/../../delete/stats?stream=false&one-shot=true"] {
        let status = response.withUnsafeMutableBufferPointer { mp_container_get("/nonexistent", endpoint, 100, $0.baseAddress, 128, &count) }
        #expect(status == EINVAL && count == 0)
    }
}
@Test func successiveContainerCPUReadingsWarmUpAndMeasureSingleCoreScale() {
    let first = ContainerCPUReading(total: 100, system: 1000, cores: 4, uptime: 0)
    let next = ContainerCPUReading(total: 350, system: 2000, cores: 4, uptime: 10)
    #expect(ContainerCPUReading.percent(previous: nil, current: first) == nil)
    #expect(ContainerCPUReading.percent(previous: first, current: next) == 100)
}
@Test func successiveContainerCPURejectsResetCoreChangeLongGapAndInvalidScale() {
    let first = ContainerCPUReading(total: 100, system: 1000, cores: 4, uptime: 0)
    for next in [ContainerCPUReading(total: 50, system: 2000, cores: 4, uptime: 10),
                 ContainerCPUReading(total: 200, system: 1000, cores: 4, uptime: 10),
                 ContainerCPUReading(total: 200, system: 2000, cores: 8, uptime: 10),
                 ContainerCPUReading(total: 200, system: 2000, cores: 4, uptime: 31),
                 ContainerCPUReading(total: 200, system: 1001, cores: 4, uptime: 10)] {
        #expect(ContainerCPUReading.percent(previous: first, current: next) == nil)
    }
}
@Test func unavailableProcessInventoryCannotReportStoppedRuntimes() {
    var sampler = ContainerSampler()
    #expect(sampler.sample(readings: nil, uptime: 0) == nil)
}
private func localStub(response: String?, delay: useconds_t = 0) throws -> (folder: URL, path: String, server: Int32) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MP-" + UUID().uuidString.prefix(8))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let path = folder.appendingPathComponent("s.sock").path
    let server = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard server >= 0 else { throw ContainerAPIError.response }
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(server); throw ContainerAPIError.limit }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: UInt8.self, capacity: bytes.count) { buffer in
            for index in bytes.indices { buffer[index] = bytes[index] }
        }
    }
    let status = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard status == 0, Darwin.listen(server, 1) == 0 else { Darwin.close(server); throw ContainerAPIError.response }
    DispatchQueue.global().async {
        let client = Darwin.accept(server, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var buffer = [UInt8](repeating: 0, count: 256)
        _ = buffer.withUnsafeMutableBytes { Darwin.read(client, $0.baseAddress, $0.count) }
        if delay > 0 { usleep(delay) }
        if let response { _ = Data(response.utf8).withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) } }
    }
    return (folder, path, server)
}
@Test func localUnixTransportReadsValidHTTPWithoutCLIOrRemoteContext() throws {
    let stub = try localStub(response: "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n[]")
    defer { Darwin.close(stub.server); try? FileManager.default.removeItem(at: stub.folder) }
    let response = try ContainerSampler.get(stub.path, "/containers/json?all=1", timeout: 200)
    #expect(try ContainerAPI.body(response) == Data("[]".utf8))
}
@Test func localUnixTransportHasBoundedTimeoutAndResponseSize() throws {
    let stub = try localStub(response: nil, delay: 250_000)
    defer { Darwin.close(stub.server); try? FileManager.default.removeItem(at: stub.folder) }
    let start = ProcessInfo.processInfo.systemUptime
    #expect(throws: (any Error).self) { try ContainerSampler.get(stub.path, "/containers/json?all=1", timeout: 50) }
    #expect(ProcessInfo.processInfo.systemUptime - start < 1)
    let large = try localStub(response: String(repeating: "a", count: 512))
    defer { Darwin.close(large.server); try? FileManager.default.removeItem(at: large.folder) }
    var buffer = [CChar](repeating: 0, count: 32), count: Int32 = 0
    let status = buffer.withUnsafeMutableBufferPointer { mp_container_get(large.path, "/containers/json?all=1", 200, $0.baseAddress, 32, &count) }
    #expect(status == EMSGSIZE && count == 0)
}
