import Foundation

enum DeviceProcessRunner {
    static func stopOwnedStream(_ process: Process) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            guard process.isRunning else { return }
            process.terminate()
            let deadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(25)) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
    }
    /// Commands run off the main thread. Output goes to a private, anonymous temporary file,
    /// avoiding pipe deadlocks; it is unlinked immediately and never leaves raw device logs.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 8,
                    keepPartialOutput: Bool = false) -> Data? {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-battery-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forUpdating: temporary) else { return nil }
        try? FileManager.default.removeItem(at: temporary)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && !Task.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
        let timedOut = process.isRunning || Task.isCancelled
        if timedOut {
            process.terminate()
            let stopDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < stopDeadline { Thread.sleep(forTimeInterval: 0.025) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        guard keepPartialOutput || (!timedOut && process.terminationStatus == 0) else { return nil }
        try? handle.seek(toOffset: 0)
        return try? handle.read(upToCount: 4 * 1024 * 1024)
    }

    static func tool(_ name: String) -> String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/" + name).path
        return ([bundled].compactMap { $0 } + ["/opt/homebrew/bin/" + name, "/usr/local/bin/" + name])
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

@MainActor final class DeviceStreamCleanup {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    func stop(_ process: Process) {
        let id = UUID(), job = DeviceProcessRunner.stopOwnedStream(process)
        tasks[id] = Task { [weak self] in await job.value; self?.tasks.removeValue(forKey: id) }
    }
    func finish() async { for task in tasks.values { await task.value } }
}
