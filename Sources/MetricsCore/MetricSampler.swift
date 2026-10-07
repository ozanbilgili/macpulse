import Foundation
import Darwin
import TelemetryBridge

public actor MetricSampler {
    private var previousCPU: CPUTicks?
    private var previousDisk: [UInt64: TransferCounters] = [:]
    private var previousNetwork: [String: TransferCounters] = [:]
    private var previousTime: Double?
    private var sessionReceived: UInt64 = 0
    private var sessionSent: UInt64 = 0
    private let chip: String
    private var processSampler = ProcessSampler()
    private var developerSampler = DeveloperSampler()
    private var containerSampler = ContainerSampler()
    private var hardwareSampler = HardwareSampler()
    private var bluetoothSampler = BluetoothSampler()
    private let audioSampler = AudioSampler()

    public init() {
        var size = 0
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            let status = buffer.withUnsafeMutableBufferPointer { sysctlbyname("machdep.cpu.brand_string", $0.baseAddress, &size, nil, 0) }
            self.chip = status == 0 ? buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : "Mac"
        } else { self.chip = "Mac" }
    }

    public func refreshBluetooth() { bluetoothSampler.reset() }

    public func resetBaselines() {
        previousCPU = nil
        previousDisk = [:]
        previousNetwork = [:]
        previousTime = nil
        processSampler.resetBaselines()
        developerSampler.reset()
        containerSampler.reset()
        hardwareSampler.reset()
        bluetoothSampler.reset()
    }

    public func sample(applications: [ApplicationDescriptor] = []) -> MetricSnapshot {
        let start = ProcessInfo.processInfo.systemUptime
        let seconds = previousTime.map { start - $0 }
        // A wake, a paused monitor or a delayed poll establishes a fresh rate baseline.
        let continuous = seconds.map { $0 > 0 && $0 <= 20 } ?? false
        var issues: [MetricIssue] = []
        func failed(_ id: String, _ message: String) { issues.append(MetricIssue(id: id, message: message)) }

        var cpuRaw = mp_cpu_ticks()
        var cpu: CPUUsage?
        if mp_read_cpu(&cpuRaw) == 0 {
            let current = CPUTicks(user: cpuRaw.user, system: cpuRaw.system, idle: cpuRaw.idle, nice: cpuRaw.nice)
            if continuous, let previousCPU { cpu = CPUUsage.between(previousCPU, current) }
            previousCPU = current
        } else { previousCPU = nil; failed("cpu", "CPU ölçümü alınamadı.") }

        var memoryRaw = mp_memory()
        var memory: MemoryMetrics?
        if mp_read_memory(&memoryRaw) == 0, memoryRaw.total > 0 {
            let pressure: MemoryPressure = switch memoryRaw.pressure {
            case 1: .normal; case 2: .warning; case 4: .critical; default: .unavailable
            }
            memory = MemoryMetrics(total: memoryRaw.total, app: memoryRaw.app, wired: memoryRaw.wired,
                compressed: memoryRaw.compressed, cached: memoryRaw.cached, free: memoryRaw.free,
                swap: memoryRaw.swap_valid != 0 ? memoryRaw.swap : nil, pressure: pressure)
        } else { failed("memory", "Bellek ölçümü alınamadı.") }

        var capacityRaw = mp_disk_capacity()
        var diskEntries = [mp_disk_entry](repeating: mp_disk_entry(), count: 32)
        var driverCount: Int32 = 0
        let capacityStatus = mp_read_disk_capacity(&capacityRaw)
        let ioStatus = diskEntries.withUnsafeMutableBufferPointer { mp_read_disk_entries($0.baseAddress, Int32($0.count), &driverCount) }
        var io: TransferDelta?
        if ioStatus == 0 {
            let current = Dictionary(uniqueKeysWithValues: diskEntries.prefix(Int(driverCount)).map {
                ($0.identifier, TransferCounters(incoming: $0.read, outgoing: $0.written))
            })
            if continuous, let seconds {
                let deltas = CounterMath.deltas(previous: previousDisk, current: current, seconds: seconds)
                if deltas.count == current.count {
                    io = TransferDelta(incomingBytes: deltas.values.reduce(0) { $0 + $1.incomingBytes },
                        outgoingBytes: deltas.values.reduce(0) { $0 + $1.outgoingBytes },
                        incomingRate: deltas.values.reduce(0) { $0 + $1.incomingRate },
                        outgoingRate: deltas.values.reduce(0) { $0 + $1.outgoingRate })
                }
            }
            previousDisk = current
        } else { previousDisk = [:]; failed("diskIO", "Disk okuma/yazma ölçümü bu sistemde alınamadı.") }
        let disk: DiskMetrics?
        if capacityStatus == 0, capacityRaw.total > 0 {
            disk = DiskMetrics(total: capacityRaw.total, available: capacityRaw.available, io: io, driverCount: Int(driverCount))
        } else { disk = nil; failed("disk", "Disk kapasitesi alınamadı.") }

        var entries = [mp_network_entry](repeating: mp_network_entry(), count: 32)
        var count: Int32 = 0
        let networkStatus = entries.withUnsafeMutableBufferPointer { mp_read_network($0.baseAddress, Int32($0.count), &count) }
        var network: NetworkMetrics?
        if networkStatus == 0 {
            var current: [String: TransferCounters] = [:]
            for var entry in entries.prefix(Int(count)) {
                let name = withUnsafePointer(to: &entry.name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
                }
                current[name] = TransferCounters(incoming: entry.received, outgoing: entry.sent)
            }
            // Per-interface deltas avoid spikes when an adapter appears or disappears.
            let deltas = continuous ? CounterMath.deltas(previous: previousNetwork, current: current, seconds: seconds!) : [:]
            sessionReceived += deltas.values.reduce(0) { $0 + $1.incomingBytes }
            sessionSent += deltas.values.reduce(0) { $0 + $1.outgoingBytes }
            let interfaces = current.keys.sorted().map { NetworkInterface(id: $0, transfer: deltas[$0]) }
            let hasBaseline = current.isEmpty || (continuous && deltas.count == current.count)
            network = NetworkMetrics(interfaces: interfaces,
                incomingRate: hasBaseline ? deltas.values.reduce(0) { $0 + $1.incomingRate } : nil,
                outgoingRate: hasBaseline ? deltas.values.reduce(0) { $0 + $1.outgoingRate } : nil,
                sessionReceived: sessionReceived, sessionSent: sessionSent)
            previousNetwork = current
        } else { previousNetwork = [:]; failed("network", "Ağ ölçümü alınamadı.") }

        var batteryRaw = mp_battery()
        var battery: BatteryMetrics?
        if mp_read_battery(&batteryRaw) == 0 {
            battery = BatteryMetrics(present: batteryRaw.present != 0,
                percent: batteryRaw.present != 0 && batteryRaw.percent >= 0 ? min(100, Int(batteryRaw.percent)) : nil,
                onAC: batteryRaw.on_ac != 0, charging: batteryRaw.charging != 0,
                minutesRemaining: batteryRaw.minutes_remaining > 0 ? Int(batteryRaw.minutes_remaining) : nil,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        } else { failed("battery", "Pil ölçümü alınamadı.") }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let thermal: String = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Normal"; case .fair: "Orta"; case .serious: "Yüksek"; case .critical: "Kritik"; @unknown default: "Bilinmiyor"
        }
        let system = SystemMetrics(chip: chip, cores: ProcessInfo.processInfo.processorCount,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            operatingSystem: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            uptime: start, thermalState: thermal)
        let processes = processSampler.sample(applications: applications)
        let developer = developerSampler.sample(processes, uptime: start)
        let containers = containerSampler.sample(readings: processes == nil ? nil : processSampler.latestReadings, uptime: start)
        let hardware = hardwareSampler.sample()
        let bluetooth = bluetoothSampler.sample(uptime: start)
        let audio = audioSampler.sample()
        if processes == nil { failed("processes", "Süreç listesi alınamadı.") }
        previousTime = start
        return MetricSnapshot(date: Date(), cpu: cpu, memory: memory, disk: disk, network: network,
            battery: battery, system: system, processes: processes, developer: developer, containers: containers, hardware: hardware, bluetooth: bluetooth, audio: audio, issues: issues,
            collectionMilliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000)
    }
}
