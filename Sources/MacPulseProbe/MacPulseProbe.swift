import Foundation
import Darwin
import MetricsCore

struct ProbeReport: Encodable {
    let accepted: Bool
    let failures: [String]
    let snapshots: [MetricSnapshot]
    let peakResidentBytes: Int
    let processSummary: ProcessProbeSummary?
    let fixtureCPUPercent: Double?
    let fixtureFootprintBytes: UInt64?
    let fixtureResidentBytes: UInt64?
    let fixturePSResidentBytes: UInt64?
    let fixtureDisappeared: Bool?
    let historyVerification: HistoryProbeSummary?
    let developerSummary: DeveloperProbeSummary?
    let containerSummary: ContainerProbeSummary?
    let serverVerification: ServerProbeSummary?
    let hardwareVerification: HardwareProbeVerification?
    let accessorySummary: AccessoryProbeSummary?
    let accessoryVerification: AccessoryProbeVerification?
}

struct AccessoryProbeSummary: Encodable {
    let bluetoothAvailable: Bool
    let bluetoothPower: String
    let bluetoothCount, connectedCount, reportedBatteryCount, retainedOfflineBatteryCount, discardedOfflineBatteryCount: Int
    let bluetoothTruncated: Bool
    let bluetoothCollectionMilliseconds: Double
    let audioAvailable: Bool
    let audioCount, audioInputCount, audioOutputCount, audioFailures: Int
    let defaultInputResolved, defaultOutputResolved, defaultSystemOutputResolved, audioTruncated: Bool
    let audioCollectionMilliseconds: Double
    init(_ snapshot: MetricSnapshot) {
        let b = snapshot.bluetooth, a = snapshot.audio
        bluetoothAvailable = b?.available ?? false; bluetoothPower = b?.power.rawValue ?? "unknown"
        bluetoothCount = b?.accessories.count ?? 0; connectedCount = b?.accessories.filter { $0.connection == .connected }.count ?? 0
        reportedBatteryCount = b?.accessories.reduce(0) { $0 + $1.reportedBatteries.count } ?? 0
        retainedOfflineBatteryCount = b?.accessories.filter { $0.connection != .connected }.reduce(0) { $0 + $1.reportedBatteries.count } ?? 0
        discardedOfflineBatteryCount = b?.discardedOfflineBatteryCount ?? 0
        bluetoothTruncated = b?.truncated ?? false; bluetoothCollectionMilliseconds = b?.collectionMilliseconds ?? 0
        audioAvailable = a?.available ?? false; audioCount = a?.devices.count ?? 0
        audioInputCount = a?.devices.filter { ($0.inputChannels ?? 0) > 0 }.count ?? 0
        audioOutputCount = a?.devices.filter { ($0.outputChannels ?? 0) > 0 }.count ?? 0
        audioFailures = a?.failures ?? 0; audioTruncated = a?.truncated ?? false
        defaultInputResolved = a?.input != nil; defaultOutputResolved = a?.output != nil; defaultSystemOutputResolved = a?.systemOutput != nil
        audioCollectionMilliseconds = a?.collectionMilliseconds ?? 0
    }
}
struct AccessoryProbeVerification: Encodable {
    let accepted: Bool
    let failures: [String]
    let freshInventory, offlineBatteryHidden, pausedBatteryHidden, expiredBatteryHidden, inventoryExcludedFromHistory: Bool
    init(_ snapshot: MetricSnapshot) {
        var errors: [String] = []
        freshInventory = snapshot.bluetooth.map { $0.available && $0.fresh(at: Date()) } ?? false
        offlineBatteryHidden = snapshot.bluetooth?.accessories.allSatisfy { $0.connection == .connected || $0.reportedBatteries.isEmpty } ?? false
        pausedBatteryHidden = snapshot.bluetooth.map { b in b.accessories.allSatisfy { b.batteries($0, at: b.date, paused: true).isEmpty } } ?? false
        expiredBatteryHidden = snapshot.bluetooth.map { b in b.accessories.allSatisfy { b.batteries($0, at: b.date.addingTimeInterval(46)).isEmpty } } ?? false
        inventoryExcludedFromHistory = snapshot.historySample.bluetooth == nil && snapshot.historySample.audio == nil
        if !freshInventory { errors.append("Bluetooth source is unavailable or stale") }
        if !offlineBatteryHidden || !pausedBatteryHidden || !expiredBatteryHidden { errors.append("Accessory cached battery scope failed") }
        if !inventoryExcludedFromHistory { errors.append("Accessory inventory entered chart history") }
        if let audio = snapshot.audio, audio.available {
            if Set(audio.devices.map(\.id)).count != audio.devices.count || audio.devices.contains(where: { $0.id == 0 }) { errors.append("Audio inventory identity validation failed") }
            if audio.devices.contains(where: { d in [d.inputVolume, d.outputVolume].compactMap { $0 }.contains { !$0.isFinite || !(0...100).contains($0) } }) { errors.append("Audio volume range failed") }
        } else { errors.append("Core Audio source is unavailable") }
        failures = errors; accepted = errors.isEmpty
    }
}

struct DeveloperProbeSummary: Encodable {
    let projectCount, projectProcessCount, listenerProcessCount, unmappedListenerCount, idleCandidateCount: Int
    let coverage: DeveloperCoverage
    init(_ snapshot: DeveloperSnapshot) {
        projectCount = snapshot.projects.count; projectProcessCount = snapshot.projects.reduce(0) { $0 + $1.members.count }
        listenerProcessCount = snapshot.listenerProcessCount; unmappedListenerCount = snapshot.unmappedListeners.count
        idleCandidateCount = snapshot.projects.filter { $0.activity == .idleCandidate }.count; coverage = snapshot.coverage
    }
}
struct ContainerProbeSummary: Encodable {
    struct Runtime: Encodable { let name: String; let state: ContainerRuntimeState; let containerCount, runningCount, measuredCount, unknownCPUCount: Int; let truncated: Bool }
    let runtimes: [Runtime]
    init(_ snapshot: ContainerSnapshot) {
        runtimes = snapshot.runtimes.map { Runtime(name: $0.name, state: $0.state, containerCount: $0.containers.count,
            runningCount: $0.containers.filter(\.running).count, measuredCount: $0.containers.filter { $0.resources != nil }.count,
            unknownCPUCount: $0.containers.filter { $0.running && $0.resources?.cpuPercent == nil }.count, truncated: $0.inventoryTruncated) }
    }
}
struct ServerProbeSummary: Encodable { let detectedLoopbackPort, matchedLSOF, matchedProjectRoot, matchedIdentity, disappeared: Bool }

struct HistoryProbeSummary: Encodable {
    let observedSeconds: Double
    let minuteCount, dayCount, gapCount: Int
    let reopenedSeconds: Double
    let integrityOK: Bool
    let includesProcessInventory: Bool
    let maxApplicationMemoryBytes: Double
}

struct ApplicationProbeSummary: Encodable {
    let name: String
    let bundleIdentifier: String?
    let processCount: Int
    let cpuPercent: Double?
    let footprint: UInt64?
    let bundleMembers, parentMembers, coalitionMembers: Int
}
struct ProcessProbeSummary: Encodable {
    let processCount, applicationCount, independentCount, cpuMeasuredCount, memoryMeasuredCount: Int
    let coverage: ProcessCoverage
    let applications: [ApplicationProbeSummary]
    init(_ snapshot: ProcessSnapshot) {
        processCount = snapshot.processCount; applicationCount = snapshot.applicationCount; independentCount = snapshot.independentCount
        cpuMeasuredCount = snapshot.cpuMeasuredCount; memoryMeasuredCount = snapshot.memoryMeasuredCount; coverage = snapshot.coverage
        applications = snapshot.groups.filter { $0.kind == .application }.map { group in
            ApplicationProbeSummary(name: group.name, bundleIdentifier: group.bundleIdentifier, processCount: group.processes.count,
                cpuPercent: group.cpuPercent, footprint: group.footprint,
                bundleMembers: group.processes.filter { $0.attribution == .bundle }.count,
                parentMembers: group.processes.filter { $0.attribution == .parent }.count,
                coalitionMembers: group.processes.filter { $0.attribution == .coalition }.count)
        }
    }
}

@main struct MacPulseProbe {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--verification-fixture") {
            var server: Int32 = -1
            if CommandLine.arguments.contains("--verification-server") {
                server = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                guard server >= 0 else { exit(1) }
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
                address.sin_addr.s_addr = inet_addr("127.0.0.1")
                let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
                guard bound == 0, Darwin.listen(server, 1) == 0 else { exit(1) }
                var size = socklen_t(MemoryLayout<sockaddr_in>.size)
                let found = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(server, $0, &size) } }
                guard found == 0 else { exit(1) }
                FileHandle.standardOutput.write(Data("\(UInt16(bigEndian: address.sin_port))\n".utf8))
            }
            // Only the explicit verification command spawns this bounded, cooperative child.
            // It touches 16 MiB, works for six seconds, and exits by itself; no signal is sent.
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: 16 * 1024 * 1024, alignment: 4096)
            buffer.initializeMemory(as: UInt8.self, repeating: 7, count: 16 * 1024 * 1024)
            let deadline = ProcessInfo.processInfo.systemUptime + (server >= 0 ? 12 : 6)
            var value: UInt8 = 7
            while ProcessInfo.processInfo.systemUptime < deadline {
                value &+= 1
                buffer.storeBytes(of: value, as: UInt8.self)
            }
            buffer.deallocate()
            if server >= 0 { Darwin.close(server) }
            return
        }
        let sampler = MetricSampler()
        var snapshots: [MetricSnapshot] = []
        let args = CommandLine.arguments
        var fixture: Process?
        var serverPort: UInt16?
        var serverFolder: URL?
        defer { if let serverFolder { try? FileManager.default.removeItem(at: serverFolder) } }
        if args.contains("--verify-processes") || args.contains("--verify-projects") {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            child.arguments = ["--verification-fixture"]
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            let output = Pipe()
            do {
                if args.contains("--verify-projects") {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-server-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder.appendingPathComponent(".git"), withIntermediateDirectories: true)
                    serverFolder = folder; child.currentDirectoryURL = folder
                    child.arguments?.append("--verification-server"); child.standardOutput = output
                }
                try child.run(); fixture = child
                if serverFolder != nil {
                    let data = output.fileHandleForReading.availableData
                    serverPort = UInt16(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            catch { FileHandle.standardError.write(Data("Unable to start local verification fixture\n".utf8)); exit(1) }
            try? await Task.sleep(for: .milliseconds(300))
        }
        let count: Int
        if fixture != nil { count = 3 }
        else if let index = args.firstIndex(of: "--samples"), args.indices.contains(index + 1), let value = Int(args[index + 1]) {
            count = min(120, max(2, value))
        } else { count = 3 }
        for index in 0..<count {
            snapshots.append(await sampler.sample(applications: RunningApplicationCatalog.read()))
            if index + 1 < count { try? await Task.sleep(for: .seconds(2)) }
        }
        var failures: [String] = []
        if snapshots.first?.cpu != nil { failures.append("CPU first sample must establish a baseline") }
        if snapshots.first?.processes?.cpuMeasuredCount != 0 { failures.append("Process CPU first sample must establish a baseline") }
        if let last = snapshots.last {
            if let cpu = last.cpu {
                if !cpu.used.isFinite || cpu.used < 0 || cpu.used > 100.0001 { failures.append("Invalid CPU range") }
            } else { failures.append("No CPU rate after warmup") }
            if let memory = last.memory {
                if memory.total == 0 || memory.used > memory.total { failures.append("Invalid memory accounting") }
            } else { failures.append("No memory reading") }
            if let disk = last.disk {
                if disk.total == 0 || disk.available > disk.total { failures.append("Invalid disk capacity") }
            } else { failures.append("No disk capacity") }
            if let network = last.network {
                if network.incomingRate == nil || network.outgoingRate == nil { failures.append("No network baseline") }
            } else { failures.append("No network reading") }
            if last.battery == nil { failures.append("Power source query failed") }
            if let processes = last.processes {
                let ids = processes.groups.flatMap(\.processes).map(\.identity)
                if ids.isEmpty { failures.append("No accessible process readings") }
                if ids.count != Set(ids).count { failures.append("Processes assigned more than once") }
                let accounted = processes.processCount + processes.coverage.otherUsers + processes.coverage.metadataUnavailable + processes.coverage.exitedOrChanged
                if accounted != processes.coverage.enumerated { failures.append("Process coverage accounting mismatch") }
                if processes.coverage.truncated { failures.append("Process inventory truncated") }
                if processes.cpuMeasuredCount == 0 { failures.append("No process CPU rate after warmup") }
            } else { failures.append("No process snapshot") }
        }
        var fixtureCPU: Double?
        var fixtureFootprint, fixtureResident, fixturePSResident: UInt64?
        var fixtureDisappeared: Bool?
        var serverSummary: ServerProbeSummary?
        if let fixture {
            let entries = snapshots.dropFirst().compactMap { snapshot in
                snapshot.processes?.groups.flatMap(\.processes).first { $0.identity.pid == fixture.processIdentifier }
            }
            fixtureCPU = entries.compactMap(\.cpuPercent).max()
            fixtureFootprint = entries.compactMap(\.footprint).max()
            fixtureResident = entries.compactMap(\.resident).max()
            let ps = Process()
            let pipe = Pipe()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-p", String(fixture.processIdentifier), "-o", "rss="]
            ps.standardOutput = pipe
            do {
                try ps.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                ps.waitUntilExit()
                if let text = String(data: data, encoding: .utf8), let kb = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) { fixturePSResident = kb * 1024 }
            } catch { failures.append("Unable to read fixture RSS with ps") }
            if let fixtureCPU {
                if fixtureCPU < 50 || fixtureCPU > 150 { failures.append("Single-core fixture CPU not on expected percent scale") }
            } else { failures.append("Fixture CPU unavailable") }
            if (fixtureFootprint ?? 0) < 16 * 1024 * 1024 { failures.append("Fixture footprint misses touched allocation") }
            if let fixtureResident, let fixturePSResident {
                if abs(Double(fixtureResident) - Double(fixturePSResident)) > Double(fixturePSResident) * 0.15 { failures.append("Fixture RSS differs from ps by more than 15 percent") }
            } else { failures.append("Fixture RSS comparison unavailable") }
            var detected = false, rootMatched = false, identityMatched = false, lsofMatched = false
            if let serverFolder, let serverPort {
                if let project = snapshots.last?.developer?.projects.first(where: { $0.members.contains { $0.id.pid == fixture.processIdentifier } }),
                   let member = project.members.first(where: { $0.id.pid == fixture.processIdentifier }) {
                    detected = member.metadata?.listeners.contains { $0.port == serverPort && $0.loopback && !$0.ipv6 } == true
                    rootMatched = URL(fileURLWithPath: project.root).resolvingSymlinksInPath().path == serverFolder.resolvingSymlinksInPath().path
                    identityMatched = member.id == member.metadata?.identity
                }
                let lsof = Process(), pipe = Pipe()
                lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                lsof.arguments = ["-nP", "-a", "-p", String(fixture.processIdentifier), "-iTCP", "-sTCP:LISTEN", "-Fn"]
                lsof.standardOutput = pipe; lsof.standardError = FileHandle.nullDevice
                do {
                    try lsof.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); lsof.waitUntilExit()
                    lsofMatched = String(decoding: data, as: UTF8.self).contains("127.0.0.1:\(serverPort)")
                } catch { failures.append("Fixture lsof comparison unavailable") }
            }
            fixture.waitUntilExit()
            let after = await sampler.sample(applications: RunningApplicationCatalog.read())
            fixtureDisappeared = after.processes?.groups.flatMap(\.processes).contains { $0.identity.pid == fixture.processIdentifier } == false
            if fixtureDisappeared != true { failures.append("Exited fixture remains in process inventory") }
            if args.contains("--verify-projects") {
                let disappeared = after.developer?.projects.flatMap(\.members).contains { $0.id.pid == fixture.processIdentifier } == false
                serverSummary = ServerProbeSummary(detectedLoopbackPort: detected, matchedLSOF: lsofMatched, matchedProjectRoot: rootMatched,
                    matchedIdentity: identityMatched, disappeared: disappeared)
                if !(detected && lsofMatched && rootMatched && identityMatched && disappeared) { failures.append("Live TCP/project identity verification failed") }
            }
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        var historySummary: HistoryProbeSummary?
        if args.contains("--verify-history") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-probe-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                let url = folder.appendingPathComponent("history.sqlite")
                let repository = try HistoryRepository(url: url)
                for snapshot in snapshots { _ = try await repository.ingest(snapshot) }
                let minutes = try await repository.report(range: .hour)
                let days = try await repository.report(range: .week)
                try await repository.interrupt()
                let reopened = try HistoryRepository(url: url)
                let restored = try await reopened.report(range: .hour)
                let valid = try await reopened.integrityCheck()
                let json = String(decoding: try JSONEncoder().encode(minutes.buckets), as: UTF8.self)
                let inventory = ["bundlePath", "executablePath", "startMicroseconds", "parentPID"].contains { json.contains($0) }
                let maxMemory = minutes.applications.map { $0.memory.peak }.max() ?? 0
                if !maxMemory.isFinite || maxMemory < 1_048_576 { failures.append("History application memory is not on a numeric byte scale") }
                if minutes.observedSeconds <= 0 || minutes.moment(.cpu).average == nil { failures.append("No persisted history after rate warmup") }
                if abs(minutes.observedSeconds - days.observedSeconds) > 0.001 { failures.append("Minute/day history accounting mismatch") }
                if abs(minutes.observedSeconds - restored.observedSeconds) > 0.001 { failures.append("Reopened history differs from persisted minutes") }
                if !valid || inventory { failures.append("History integrity or inventory exclusion failed") }
                historySummary = HistoryProbeSummary(observedSeconds: minutes.observedSeconds, minuteCount: minutes.buckets.count,
                    dayCount: days.buckets.count, gapCount: minutes.gapCount, reopenedSeconds: restored.observedSeconds,
                    integrityOK: valid, includesProcessInventory: inventory, maxApplicationMemoryBytes: maxMemory)
            } catch { failures.append("History live persistence verification failed") }
        }
        let hardwareVerification = args.contains("--verify-hardware") ? await verifyHardware(sampler) : nil
        if let hardwareVerification { failures += hardwareVerification.failures }
        let accessoryVerification = args.contains("--verify-accessories") ? snapshots.last.map(AccessoryProbeVerification.init) : nil
        if let accessoryVerification { failures += accessoryVerification.failures }
        getrusage(RUSAGE_SELF, &usage)
        let report = ProbeReport(accepted: failures.isEmpty, failures: failures,
            snapshots: args.contains("--include-processes") ? snapshots : snapshots.map(\.historySample), peakResidentBytes: usage.ru_maxrss,
            processSummary: snapshots.last?.processes.map(ProcessProbeSummary.init), fixtureCPUPercent: fixtureCPU,
            fixtureFootprintBytes: fixtureFootprint, fixtureResidentBytes: fixtureResident,
            fixturePSResidentBytes: fixturePSResident, fixtureDisappeared: fixtureDisappeared, historyVerification: historySummary,
            developerSummary: snapshots.last?.developer.map(DeveloperProbeSummary.init), containerSummary: snapshots.last?.containers.map(ContainerProbeSummary.init), serverVerification: serverSummary, hardwareVerification: hardwareVerification,
            accessorySummary: snapshots.last.map(AccessoryProbeSummary.init), accessoryVerification: accessoryVerification)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(report) { FileHandle.standardOutput.write(data); print("") }
        exit(failures.isEmpty ? 0 : 1)
    }
}
