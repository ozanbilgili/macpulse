import Foundation
import MetricsCore

@MainActor final class PencilMonitor {
    private struct Stream {
        let process: Process
        let pipe: Pipe
        let network: Bool
        var buffer = Data()
    }
    private var streams: [String: Stream] = [:]
    private let cleanup = DeviceStreamCleanup()
    var onSample: ((BatteryDevice) -> Void)?
    var onDisconnected: ((String) -> Void)?

    func reconcile(_ connections: [PencilConnection]) {
        let active = Set(connections.map(\.id))
        for id in Array(streams.keys) where !active.contains(id) { stop(id) }
        for connection in connections {
            if let stream = streams[connection.id], stream.process.isRunning, stream.network == connection.network { continue }
            stop(connection.id)
            start(connection)
        }
    }

    func stopAll() { for id in Array(streams.keys) { stop(id) } }

    private func stop(_ id: String) {
        guard let stream = streams.removeValue(forKey: id) else { return }
        stream.pipe.fileHandleForReading.readabilityHandler = nil
        cleanup.stop(stream.process)
        onDisconnected?("pencil:" + id)
    }
    func finish() async { stopAll(); await cleanup.finish() }

    private func start(_ connection: PencilConnection) {
        guard let tool = DeviceProcessRunner.tool("idevicesyslog") else { return }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = (connection.network ? ["-n"] : []) + ["-u", connection.id, "-x", "--process", "SpringBoard", "-m", "Pencil"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            Task { @MainActor in self?.receive(chunk, id: connection.id) }
        }
        do {
            try process.run()
            streams[connection.id] = Stream(process: process, pipe: pipe, network: connection.network)
        } catch { pipe.fileHandleForReading.readabilityHandler = nil }
    }

    private func receive(_ chunk: Data, id: String) {
        guard var stream = streams[id] else { return }
        if chunk.isEmpty { stop(id); return }
        stream.buffer.append(chunk)
        if stream.buffer.count > 65536 { stream.buffer = Data(stream.buffer.suffix(32768)) }
        if let text = String(data: stream.buffer, encoding: .utf8),
           var sample = PencilLogParser.parse(text, parentID: id) {
            sample.telemetry = .pencilStream
            sample.connection = stream.network ? .viaIPadWiFi : .viaIPadUSB
            stream.buffer.removeAll(keepingCapacity: true)
            streams[id] = stream
            onSample?(sample)
        } else { streams[id] = stream }
    }
}
