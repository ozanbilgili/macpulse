import Foundation

/// Keep macOS's trusted-device Bonjour discovery subscribed while PilBar runs.
/// A one-shot usbmux list alone does not start wireless device discovery.
@MainActor final class MobileDiscovery {
    private var process: Process?
    private var pipe: Pipe?
    private var pendingRefresh: Task<Void, Never>?
    private var lastStart: Date?
    private let cleanup = DeviceStreamCleanup()
    var onChange: (() -> Void)?

    func start() {
        guard process?.isRunning != true,
              lastStart.map({ Date().timeIntervalSince($0) > 10 }) ?? true,
              let tool = DeviceProcessRunner.tool("pilbar-mobile-native") else { return }
        stop()
        lastStart = Date()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["--discover"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self else { return }
                if data.isEmpty { self.stop(); return }
                self.pendingRefresh?.cancel()
                self.pendingRefresh = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self?.onChange?()
                }
            }
        }
        do {
            try process.run()
            self.process = process
            self.pipe = pipe
        } catch { pipe.fileHandleForReading.readabilityHandler = nil }
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let process { cleanup.stop(process) }
        process = nil
        pipe = nil
    }
    func finish() async { stop(); await cleanup.finish() }
}
