import Foundation
import TelemetryBridge

struct ProcessSampler {
    private(set) var latestReadings: [RawProcessReading] = []
    private var previous: [ProcessIdentity: RawProcessReading] = [:]
    private var descriptorCache: [String: ApplicationDescriptor] = [:]

    mutating func resetBaselines() { previous = [:] }

    mutating func sample(applications: [ApplicationDescriptor]) -> ProcessSnapshot? {
        var pids = [Int32](repeating: 0, count: 16_384)
        var count: Int32 = 0
        var truncated: Int32 = 0
        let status = pids.withUnsafeMutableBufferPointer { mp_list_process_ids($0.baseAddress, Int32($0.count), &count, &truncated) }
        guard status == 0 else { previous = [:]; latestReadings = []; return nil }
        var coverage = ProcessCoverage()
        coverage.truncated = truncated != 0
        var readings: [RawProcessReading] = []
        for pid in pids.prefix(Int(count)) where pid > 0 {
            coverage.enumerated += 1
            var raw = mp_process()
            switch mp_read_process(pid, &raw) {
            case Int32(MP_PROCESS_OTHER_USER): coverage.otherUsers += 1; continue
            case Int32(MP_PROCESS_GONE), Int32(MP_PROCESS_CHANGED): coverage.exitedOrChanged += 1; continue
            case Int32(MP_PROCESS_METADATA_DENIED): coverage.metadataUnavailable += 1; continue
            case 0: break
            default: coverage.metadataUnavailable += 1; continue
            }
            let path = raw.path_status == 0 ? withUnsafePointer(to: &raw.path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) }
            } : nil
            let shortName = withUnsafePointer(to: &raw.name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
            }
            let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? (shortName.isEmpty ? "Süreç \(pid)" : shortName)
            if raw.usage_status != 0 { coverage.usageUnavailable += 1 }
            if raw.coalition_status != 0 { coverage.coalitionUnavailable += 1 }
            readings.append(RawProcessReading(identity: ProcessIdentity(pid: pid, startMicroseconds: raw.start_seconds * 1_000_000 + raw.start_microseconds),
                parentPID: raw.parent_pid, name: name, executablePath: path,
                coalition: raw.coalition_status == 0 && raw.coalition > 0 ? raw.coalition : nil,
                cpuNanoseconds: raw.usage_status == 0 ? raw.cpu_nanoseconds : nil,
                footprint: raw.usage_status == 0 ? raw.footprint : nil, resident: raw.usage_status == 0 ? raw.resident : nil,
                uptime: ProcessInfo.processInfo.systemUptime))
        }
        var descriptors = Dictionary(applications.map { ($0.bundlePath, $0) }, uniquingKeysWith: { first, _ in first })
        let roots = Set(readings.compactMap { $0.executablePath.flatMap(ProcessGrouping.bundleRoot) })
        for root in roots where descriptors[root] == nil {
            if let cached = descriptorCache[root] { descriptors[root] = cached; continue }
            guard let bundle = Bundle(url: URL(fileURLWithPath: root)),
                  bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else { continue }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? URL(fileURLWithPath: root).deletingPathExtension().lastPathComponent
            let descriptor = ApplicationDescriptor(name: name, bundlePath: root, bundleIdentifier: bundle.bundleIdentifier)
            descriptors[root] = descriptor
            descriptorCache[root] = descriptor
        }
        // Bound cached asset metadata; unused process baselines disappear every sample.
        if descriptorCache.count > 256 { descriptorCache = descriptorCache.filter { roots.contains($0.key) } }
        let result = ProcessGrouping.group(current: readings, previous: previous, applications: Array(descriptors.values), coverage: coverage)
        previous = Dictionary(readings.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        latestReadings = readings
        return result
    }
}
