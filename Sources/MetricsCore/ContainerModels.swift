import Foundation

public enum ContainerRuntimeState: String, Sendable, Encodable {
    case available = "Bağlı", notRunning = "Çalışmıyor", noSocket = "Yerel socket bulunamadı", unavailable = "Erişilemiyor"
}
public struct ContainerPort: Sendable, Encodable {
    public let containerPort: Int
    public let hostPort: Int?
    public let protocolName, scope, family: String
    public var label: String { (hostPort.map { "\($0) → " } ?? "") + "\(containerPort)/\(protocolName)" + (hostPort == nil ? "" : " · \(family) · \(scope)") }
}
public struct ContainerResourceUsage: Sendable, Encodable {
    public let cpuPercent: Double?
    public let memoryBytes, memoryLimitBytes, receivedBytes, sentBytes: UInt64?
}
struct ContainerCPUReading: Sendable {
    let total, system, cores: UInt64
    let uptime: Double
    static func percent(previous: Self?, current: Self) -> Double? {
        guard let previous, current.uptime - previous.uptime > 0, current.uptime - previous.uptime <= 30,
              previous.cores == current.cores, current.cores > 0, current.cores <= 4096,
              current.total >= previous.total, previous.system > 0, current.system > previous.system else { return nil }
        let value = Double(current.total - previous.total) / Double(current.system - previous.system) * Double(current.cores) * 100
        return value.isFinite && value <= Double(current.cores) * 105 ? value : nil
    }
}
public struct ContainerEntry: Sendable, Encodable, Identifiable {
    public let id, name, image, state, status: String
    public let composeProject: String?
    public let ports: [ContainerPort]
    public var resources: ContainerResourceUsage?
    public var running: Bool { state == "running" }
}
public struct ContainerRuntimeSnapshot: Sendable, Encodable, Identifiable {
    public let id, name: String
    public let state: ContainerRuntimeState
    public let containers: [ContainerEntry]
    public let inventoryTruncated: Bool
    public let resourcesUnavailable: Int
}
public struct ContainerSnapshot: Sendable, Encodable {
    public let runtimes: [ContainerRuntimeSnapshot]
    public let scannedAt: Date
    public var containerCount: Int { runtimes.reduce(0) { $0 + $1.containers.count } }
    public var runningCount: Int { runtimes.reduce(0) { $0 + $1.containers.filter(\.running).count } }
}

enum ContainerAPIError: Error { case response, schema, limit }
enum ContainerAPI {
    static func counter(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return UInt64(number.stringValue)
    }
    static func cpuReading(_ data: Data, uptime: Double) throws -> ContainerCPUReading? {
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cpu = row["cpu_stats"] as? [String: Any], let usage = cpu["cpu_usage"] as? [String: Any],
              let total = counter(usage["total_usage"]), let system = counter(cpu["system_cpu_usage"]),
              let cores = counter(cpu["online_cpus"]) ?? (usage["percpu_usage"] as? [Any]).map({ UInt64($0.count) }), cores > 0 else { return nil }
        return ContainerCPUReading(total: total, system: system, cores: cores, uptime: uptime)
    }
    static func body(_ response: Data) throws -> Data {
        guard response.count <= 2_097_152, let boundary = response.range(of: Data("\r\n\r\n".utf8)), boundary.lowerBound < 16_384,
              let header = String(data: response[..<boundary.lowerBound], encoding: .utf8) else { throw ContainerAPIError.response }
        let lines = header.components(separatedBy: "\r\n")
        guard lines.first?.split(separator: " ").dropFirst().first == "200" else { throw ContainerAPIError.response }
        let fields = Dictionary(lines.dropFirst().compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }, uniquingKeysWith: { _, last in last })
        let payload = Data(response[boundary.upperBound...])
        if let encoding = fields["content-encoding"], encoding != "identity" { throw ContainerAPIError.response }
        if fields["transfer-encoding"]?.lowercased() == "chunked" {
            var data = Data(), offset = 0
            while offset < payload.count {
                guard let lineEnd = payload.range(of: Data("\r\n".utf8), in: offset..<payload.count),
                      let line = String(data: payload[offset..<lineEnd.lowerBound], encoding: .ascii),
                      let token = line.split(separator: ";").first, let size = Int(token, radix: 16), size >= 0 else { throw ContainerAPIError.response }
                offset = lineEnd.upperBound
                if size == 0 { guard payload.count - offset >= 2 else { throw ContainerAPIError.response }; return data }
                guard size <= 2_097_152 - data.count, size <= payload.count - offset - 2 else { throw ContainerAPIError.limit }
                data.append(payload[offset..<offset + size]); offset += size
                guard payload[offset..<offset + 2] == Data("\r\n".utf8) else { throw ContainerAPIError.response }
                offset += 2
            }
            throw ContainerAPIError.response
        }
        if let length = fields["content-length"] { guard Int(length) == payload.count else { throw ContainerAPIError.response } }
        return payload
    }
    static func inventory(_ data: Data) throws -> (entries: [ContainerEntry], truncated: Bool) {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ContainerAPIError.schema }
        let entries = try rows.prefix(128).map { row -> ContainerEntry in
            guard let id = row["Id"] as? String, validID(id), let state = row["State"] as? String else { throw ContainerAPIError.schema }
            let rawName = (row["Names"] as? [String])?.first ?? String(id.prefix(12))
            let labels = row["Labels"] as? [String: Any]
            let ports = (row["Ports"] as? [[String: Any]] ?? []).prefix(64).compactMap { port -> ContainerPort? in
                guard let value = port["PrivatePort"] as? Int, value > 0, value <= 65535 else { return nil }
                let host = port["PublicPort"] as? Int
                let ip = port["IP"] as? String ?? ""
                let scope = ip.isEmpty ? "arayüz bilinmiyor" : ["127.0.0.1", "::1"].contains(ip) ? "yerel" : ["0.0.0.0", "::"].contains(ip) ? "tüm arayüzler" : "belirli arayüz"
                let family = ip.isEmpty ? "IP ailesi bilinmiyor" : ip.contains(":") ? "IPv6" : "IPv4"
                return ContainerPort(containerPort: value, hostPort: host.flatMap { $0 > 0 && $0 <= 65535 ? $0 : nil }, protocolName: clipped(port["Type"] as? String ?? "tcp"), scope: scope, family: family)
            }
            return ContainerEntry(id: id, name: clipped(rawName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
                image: clipped(row["Image"] as? String ?? "—"), state: clipped(state), status: clipped(row["Status"] as? String ?? state),
                composeProject: (labels?["com.docker.compose.project"] as? String).map(clipped), ports: Array(ports))
        }
        guard Set(entries.map(\.id)).count == entries.count else { throw ContainerAPIError.schema }
        return (entries, rows.count > 128)
    }
    static func validID(_ id: String) -> Bool { id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) } }
    static func clipped(_ value: String) -> String { String(value.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(240)) }
    static func resources(_ data: Data) throws -> ContainerResourceUsage {
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ContainerAPIError.schema }
        func nested(_ parent: [String: Any]?, _ key: String) -> [String: Any]? { parent?[key] as? [String: Any] }
        let cpu = nested(row, "cpu_stats"), previous = nested(row, "precpu_stats")
        let usage = nested(cpu, "cpu_usage"), before = nested(previous, "cpu_usage")
        var cpuPercent: Double?
        if let total = counter(usage?["total_usage"]), let oldTotal = counter(before?["total_usage"]),
           let system = counter(cpu?["system_cpu_usage"]), let oldSystem = counter(previous?["system_cpu_usage"]),
           total >= oldTotal, oldSystem > 0, system > oldSystem,
           let cores = counter(cpu?["online_cpus"]) ?? (usage?["percpu_usage"] as? [Any]).map({ UInt64($0.count) }), cores > 0 {
            cpuPercent = ContainerCPUReading.percent(previous: .init(total: oldTotal, system: oldSystem, cores: cores, uptime: 0),
                current: .init(total: total, system: system, cores: cores, uptime: 1))
        }
        let memory = nested(row, "memory_stats")
        let networks = row["networks"] as? [String: [String: Any]]
        func totalNetwork(_ key: String) -> UInt64? {
            guard let networks, !networks.isEmpty else { return nil }
            var total: UInt64 = 0
            for interface in networks.values {
                guard let value = counter(interface[key]) else { return nil }
                let sum = total.addingReportingOverflow(value); guard !sum.overflow else { return nil }; total = sum.partialValue
            }
            return total
        }
        return ContainerResourceUsage(cpuPercent: cpuPercent, memoryBytes: counter(memory?["usage"]), memoryLimitBytes: counter(memory?["limit"]),
            receivedBytes: totalNetwork("rx_bytes"), sentBytes: totalNetwork("tx_bytes"))
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
