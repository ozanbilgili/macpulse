import Foundation
import Testing
import Darwin
import TelemetryBridge
@testable import MetricsCore

private func usage(_ pid: Int32 = 10, start: UInt64 = 10, parent: Int32 = 1, cpu: Double? = 0, memory: UInt64? = 100) -> ProcessUsage {
    .init(identity: .init(pid: pid, startMicroseconds: start), parentPID: parent, name: "Fixture", cpuPercent: cpu, footprint: memory, resident: memory, attribution: .independent)
}
private func metadata(_ process: ProcessUsage = usage(), cwd: String? = "/work/test", root: String? = "/work/test", port: UInt16? = 3000,
                      complete: Bool = true, active: Int = 0, queued: UInt64 = 0, time: Double = 0) -> DeveloperReading {
    .init(identity: process.identity, cwd: cwd, projectRoot: root,
          listeners: port.map { [.init(port: $0, ipv6: false, loopback: true, wildcard: false)] } ?? [],
          socketsComplete: complete, activeConnections: active, queuedBytes: queued, uptime: time)
}
private func project(_ process: ProcessUsage = usage(), complete: Bool = true, active: Int = 0, queued: UInt64 = 0,
                     time: Double = 0, port: UInt16? = 3000) -> DevelopmentProject {
    .init(root: "/work/test", members: [.init(usage: process, attribution: .directory,
         metadata: metadata(process, port: port, complete: complete, active: active, queued: queued, time: time))])
}
@Test func projectGroupingKeepsNestedRootsAndEveryProcessOnce() {
    let a = usage(), b = usage(11, parent: 10), c = usage(12, parent: 11)
    let meta = [a.identity: metadata(a), b.identity: metadata(b, cwd: "/work/test/sub", root: "/work/test/sub"), c.identity: metadata(c, cwd: nil, root: nil)]
    let result = ProjectGrouping.group(processes: [a,b,c], metadata: meta)
    #expect(result.projects.count == 2)
    #expect(result.projects.first { $0.root == "/work/test/sub" }?.members.count == 2)
    #expect(Set(result.projects.flatMap(\.members).map(\.id)).count == 3)
}
@Test func explicitUnrelatedDirectoryCannotBorrowParentProject() {
    let a = usage(), b = usage(11, parent: 10)
    let result = ProjectGrouping.group(processes: [a,b], metadata: [a.identity: metadata(a), b.identity: metadata(b, cwd: "/elsewhere", root: nil)])
    #expect(result.projects[0].members.count == 1); #expect(result.unmapped.count == 1)
}
@Test func parentPIDReuseAndCyclesDoNotInventProjectOwnership() {
    let a = usage(10, start: 30), b = usage(11, start: 20, parent: 10), c = usage(12, parent: 13), d = usage(13, parent: 12)
    let result = ProjectGrouping.group(processes: [a,b,c,d], metadata: [a.identity: metadata(a), b.identity: metadata(b, cwd: nil, root: nil),
        c.identity: metadata(c, cwd: nil, root: nil), d.identity: metadata(d, cwd: nil, root: nil)])
    #expect(result.projects[0].members.count == 1); #expect(result.unmapped.count == 3)
}
@Test func oldProcessMetadataCannotAttachToReusedPID() {
    let old = usage(), current = usage(start: 20)
    let result = ProjectGrouping.group(processes: [current], metadata: [old.identity: metadata(old)])
    #expect(result.projects.isEmpty); #expect(result.unmapped.isEmpty)
    #expect(ProjectGrouping.group(processes: [current], metadata: [current.identity: metadata(old)]).projects.isEmpty)
}
@Test func listenersDeduplicateWhileIPv4AndIPv6RemainDistinct() {
    let a = usage(), b = usage(11)
    let m = metadata(a)
    let six = DeveloperReading(identity: b.identity, cwd: m.cwd, projectRoot: m.projectRoot,
        listeners: [m.listeners[0], .init(port: 3000, ipv6: true, loopback: true, wildcard: false)], socketsComplete: true, activeConnections: 0, queuedBytes: 0, uptime: 0)
    let result = ProjectGrouping.group(processes: [a,b], metadata: [a.identity: m, b.identity: six])
    #expect(result.projects[0].listeners.count == 2)
}
@Test func projectUnknownResourcesStayUnknownOrPartial() {
    var p = project(usage(cpu: nil, memory: nil))
    #expect(p.cpuPercent == nil && p.footprint == nil)
    p = .init(root: p.root, members: p.members + project(usage(11, cpu: 2, memory: 50)).members)
    #expect(p.cpuPercent == 2 && p.cpuPartial); #expect(p.footprint == 50 && p.memoryPartial)
}
@Test func treeVisitsCyclesAndRootsExactlyOnce() {
    let a = usage(10, parent: 11), b = usage(11, parent: 10), c = usage(12, start: 20, parent: 10)
    let p = DevelopmentProject(root: "/work/test", members: [a,b,c].map { .init(usage: $0, attribution: .directory, metadata: metadata($0)) })
    #expect(p.tree.count == 3); #expect(Set(p.tree.map(\.member.id)).count == 3)
}
@Test func idleCandidateRequiresTwoMinutesAndListeningPort() {
    var tracker = ProjectIdleTracker()
    var result: [DevelopmentProject] = []
    for time in stride(from: 0.0, through: 120.0, by: 10) { result = tracker.update([project(time: time)], uptime: time) }
    #expect(result[0].activity == .idleCandidate && result[0].quietSeconds == 120)
    tracker.reset()
    for time in stride(from: 0.0, through: 120.0, by: 10) { result = tracker.update([project(time: time, port: nil)], uptime: time) }
    #expect(result[0].activity == .observing)
}
@Test func TCPConnectionOrQueuedBytesPreventsIdleCandidate() {
    for active in [true, false] {
        var tracker = ProjectIdleTracker()
        for time in stride(from: 0.0, through: 130.0, by: 10) {
            let result = tracker.update([project(active: active ? 1 : 0, queued: active ? 0 : 1, time: time)], uptime: time)
            #expect(result[0].activity == .active)
        }
    }
}
@Test func incompleteStaleOrMissingCPUResetsIdleObservation() {
    var tracker = ProjectIdleTracker()
    _ = tracker.update([project()], uptime: 0)
    #expect(tracker.update([project(complete: false, time: 10)], uptime: 10)[0].activity == .unknown)
    #expect(tracker.update([project(usage(cpu: nil), time: 20)], uptime: 20)[0].activity == .unknown)
    #expect(tracker.update([project(time: 0)], uptime: 30)[0].activity == .unknown)
    #expect(tracker.update([project(time: 40)], uptime: 40)[0].quietSeconds == 0)
}
@Test func membershipPortChangesAndLongGapsRestartIdleClock() {
    var tracker = ProjectIdleTracker()
    _ = tracker.update([project()], uptime: 0)
    _ = tracker.update([project(time: 10)], uptime: 10)
    #expect(tracker.update([project(usage(start: 20), time: 20)], uptime: 20)[0].quietSeconds == 0)
    #expect(tracker.update([project(usage(start: 20), time: 30, port: 4000)], uptime: 30)[0].quietSeconds == 0)
    #expect(tracker.update([project(usage(start: 20), time: 60, port: 4000)], uptime: 60)[0].quietSeconds == 0)
}
@Test func projectMarkerPresenceChoosesNearestRootAndSkipsDependencies() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-roots-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let child = folder.appendingPathComponent("child")
    let dependency = folder.appendingPathComponent("node_modules/dependency")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dependency, withIntermediateDirectories: true)
    try Data("not parsed".utf8).write(to: folder.appendingPathComponent("Package.swift"))
    try Data("not parsed".utf8).write(to: child.appendingPathComponent("package.json"))
    try Data("not parsed".utf8).write(to: dependency.appendingPathComponent("package.json"))
    #expect(ProjectRootResolver.resolve(child.path) == child.path)
    #expect(ProjectRootResolver.resolve(dependency.path) == folder.path)
    #expect(ProjectRootResolver.resolve("relative") == nil)
    #expect(ProjectRootResolver.resolve("/") == nil)
}
@Test func developerBridgeRejectsWrongIdentityBeforeReadingMetadata() {
    var info = mp_developer_info(), ports = [mp_tcp_listener](repeating: .init(), count: 2), count: Int32 = 0
    let status = ports.withUnsafeMutableBufferPointer { mp_read_developer(getpid(), 0, &info, $0.baseAddress, 2, &count) }
    #expect(status == MP_PROCESS_CHANGED); #expect(count == 0)
}
@Test func developerAndContainerMetadataAreExcludedFromHistoryAndEncoding() throws {
    let system = SystemMetrics(chip: "Fixture", cores: 4, physicalMemory: 1024, operatingSystem: "Test", uptime: 10, thermalState: "Normal")
    let snapshot = MetricSnapshot(date: Date(), cpu: nil, memory: nil, disk: nil, network: nil, battery: nil, system: system,
        developer: .init(projects: [project()], unmappedListeners: [], coverage: .init(), scannedAt: Date()),
        containers: .init(runtimes: [], scannedAt: Date()), issues: [], collectionMilliseconds: 1)
    let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!encoded.contains("/work/test")); #expect(!encoded.contains("developer")); #expect(!encoded.contains("containers"))
    #expect(snapshot.historySample.developer == nil && snapshot.historySample.containers == nil)
    #expect(HistorySample(snapshot: snapshot).applications.isEmpty)
}
