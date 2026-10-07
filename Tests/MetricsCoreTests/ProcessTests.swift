import Foundation
import Testing
@testable import MetricsCore

private let chrome = ApplicationDescriptor(name: "Chrome", bundlePath: "/Applications/Chrome.app", bundleIdentifier: "test.chrome")
private let safari = ApplicationDescriptor(name: "Safari", bundlePath: "/Applications/Safari.app", bundleIdentifier: "test.safari")
private let terminal = ApplicationDescriptor(name: "Terminal", bundlePath: "/Applications/Terminal.app", bundleIdentifier: "test.terminal")

private func reading(_ pid: Int32, start: UInt64 = 10, parent: Int32 = 1, name: String = "worker", path: String? = "/usr/bin/worker",
                     coalition: UInt64? = nil, cpu: UInt64? = 2_000_000_000, footprint: UInt64? = 100, rss: UInt64? = 200,
                     time: Double = 12) -> RawProcessReading {
    RawProcessReading(identity: .init(pid: pid, startMicroseconds: start), parentPID: parent, name: name, executablePath: path,
                      coalition: coalition, cpuNanoseconds: cpu, footprint: footprint, resident: rss, uptime: time)
}
private func groups(_ current: [RawProcessReading], previous: [RawProcessReading] = [], apps: [ApplicationDescriptor] = [chrome, safari, terminal]) -> ProcessSnapshot {
    ProcessGrouping.group(current: current, previous: Dictionary(uniqueKeysWithValues: previous.map { ($0.identity, $0) }), applications: apps, coverage: ProcessCoverage())
}

@Test func processCPUUsesSingleCoreScale() throws {
    let before = reading(10, cpu: 0, time: 10)
    #expect(try #require(ProcessCPU.percent(previous: before, current: reading(10))) == 100)
    #expect(try #require(ProcessCPU.percent(previous: before, current: reading(10, cpu: 8_000_000_000))) == 400)
}
@Test func reusedPIDDoesNotInheritCPU() {
    #expect(ProcessCPU.percent(previous: reading(10, start: 10, cpu: 0, time: 10), current: reading(10, start: 11)) == nil)
}
@Test func invalidProcessCPUCountersStayUnknown() {
    let before = reading(10, cpu: 3_000_000_000, time: 10)
    #expect(ProcessCPU.percent(previous: before, current: reading(10, cpu: 2)) == nil)
    #expect(ProcessCPU.percent(previous: before, current: reading(10, cpu: nil)) == nil)
    #expect(ProcessCPU.percent(previous: before, current: reading(10, time: 40)) == nil)
    #expect(ProcessCPU.percent(previous: before, current: reading(10, time: .nan)) == nil)
}
@Test func measuredIdleIsZeroRatherThanUnknown() throws {
    let before = reading(10, time: 10)
    #expect(try #require(ProcessCPU.percent(previous: before, current: reading(10))) == 0)
}
@Test func nestedHelperUsesOutermostApplication() throws {
    let main = reading(10, name: "Chrome", path: "/Applications/Chrome.app/Contents/MacOS/Chrome")
    let helper = reading(11, name: "Renderer", path: "/Applications/Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Renderer")
    let result = groups([main, helper])
    let group = try #require(result.groups.first)
    #expect(result.groups.count == 1)
    #expect(group.name == "Chrome")
    #expect(group.processes.count == 2)
    #expect(group.footprint == 200)
}
@Test func terminalOwnsShellAndDevServer() throws {
    let app = reading(10, start: 1, path: "/Applications/Terminal.app/Contents/MacOS/Terminal")
    let shell = reading(11, start: 2, parent: 10, name: "zsh", path: "/bin/zsh")
    let server = reading(12, start: 3, parent: 11, name: "node", path: "/usr/local/bin/node")
    let result = groups([server, shell, app])
    let group = try #require(result.groups.first)
    #expect(result.groups.count == 1)
    #expect(group.name == "Terminal")
    #expect(group.processes.first(where: { $0.identity.pid == 12 })?.attribution == .parent)
}
@Test func applicationBundleWinsOverLaunchingTerminal() {
    let app = reading(10, start: 1, path: "/Applications/Terminal.app/Contents/MacOS/Terminal")
    let browser = reading(11, start: 2, parent: 10, path: "/Applications/Chrome.app/Contents/MacOS/Chrome")
    #expect(groups([app, browser]).applicationCount == 2)
}
@Test func detachedWebKitHelperUsesUniqueCoalitionOwner() throws {
    let app = reading(10, path: "/Applications/Safari.app/Contents/MacOS/Safari", coalition: 42)
    let helper = reading(11, name: "WebKit", path: "/System/WebKit/WebContent.xpc/Contents/MacOS/WebContent", coalition: 42)
    let group = try #require(groups([app, helper]).groups.first)
    #expect(group.name == "Safari")
    #expect(group.processes.count == 2)
    #expect(group.processes.first(where: { $0.identity.pid == 11 })?.attribution == .coalition)
}
@Test func ambiguousCoalitionDoesNotGuessAnOwner() {
    let a = reading(10, path: "/Applications/Safari.app/Contents/MacOS/Safari", coalition: 42)
    let b = reading(11, path: "/Applications/Chrome.app/Contents/MacOS/Chrome", coalition: 42)
    let helper = reading(12, coalition: 42)
    let result = groups([a, b, helper])
    #expect(result.applicationCount == 2)
    #expect(result.independentCount == 1)
}
@Test func parentPIDReuseDoesNotStealChild() {
    let newParent = reading(10, start: 30, path: "/Applications/Chrome.app/Contents/MacOS/Chrome")
    let oldChild = reading(11, start: 20, parent: 10)
    #expect(groups([newParent, oldChild]).independentCount == 1)
}
@Test func parentCycleTerminatesWithoutAttribution() {
    #expect(groups([reading(10, parent: 11), reading(11, parent: 10)]).independentCount == 2)
}
@Test func closingProcessesDisappearFromGroups() {
    let old = reading(10, path: "/Applications/Chrome.app/Contents/MacOS/Chrome")
    #expect(groups([], previous: [old]).groups.isEmpty)
}
@Test func identicalAppIdentifiersAtDifferentPathsStaySeparate() {
    let copy = ApplicationDescriptor(name: "Chrome", bundlePath: "/Other/Chrome.app", bundleIdentifier: "test.chrome")
    let result = groups([reading(10, path: chrome.bundlePath + "/Contents/MacOS/Chrome"), reading(11, path: copy.bundlePath + "/Contents/MacOS/Chrome")], apps: [chrome, copy])
    #expect(result.applicationCount == 2)
}
@Test func independentExecutablesWithSameNameStaySeparate() {
    let result = groups([reading(10, path: "/one/node"), reading(11, path: "/two/node")])
    #expect(result.groups.count == 2)
}
@Test func partialMetricsKeepMeasuredSubtotalAndCoverage() throws {
    let known = reading(10, path: chrome.bundlePath + "/Contents/MacOS/main")
    let hidden = reading(11, path: chrome.bundlePath + "/Contents/MacOS/helper", cpu: nil, footprint: nil, rss: nil)
    let before = reading(10, path: chrome.bundlePath + "/Contents/MacOS/main", cpu: 0, time: 10)
    let group = try #require(groups([known, hidden], previous: [before]).groups.first)
    #expect(group.footprint == 100)
    #expect(group.memoryMeasuredCount == 1)
    #expect(group.memoryIsPartial)
    #expect(group.cpuPercent == 100)
    #expect(group.cpuIsPartial)
}
@Test func allRestrictedMetricsAreUnknown() throws {
    let group = try #require(groups([reading(10, cpu: nil, footprint: nil, rss: nil)]).groups.first)
    #expect(group.footprint == nil)
    #expect(group.cpuPercent == nil)
    #expect(group.resident == nil)
}
@Test func groupEncodingDoesNotContainExecutableOrBundlePaths() throws {
    let result = groups([reading(10, path: chrome.bundlePath + "/Contents/MacOS/Chrome")])
    let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!json.contains("/Applications"))
    #expect(!json.contains("bundlePath"))
    #expect(!json.contains("executablePath"))
}
@Test func everyProcessIsAssignedExactlyOnce() {
    let processes = [reading(10, path: chrome.bundlePath + "/Contents/MacOS/Chrome"), reading(11, parent: 10), reading(12, path: nil)]
    let result = groups(processes)
    let ids = result.groups.flatMap(\.processes).map(\.identity)
    #expect(ids.count == processes.count)
    #expect(Set(ids).count == ids.count)
}
@Test func sortingPlacesUnknownValuesAfterMeasuredZero() {
    let data = groups([reading(10, name: "unknown", path: "/unknown", footprint: nil, rss: nil), reading(11, name: "idle", path: "/idle", footprint: 0)], previous: [reading(11, name: "idle", path: "/idle", time: 10)])
    #expect(ProcessSort.memory.sorted(data.groups).first?.name == "idle")
    #expect(ProcessSort.cpu.sorted(data.groups).first?.name == "idle")
}
