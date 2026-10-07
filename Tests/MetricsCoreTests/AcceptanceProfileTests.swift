import Foundation
import Testing
import Darwin
@testable import MetricsCore

@Test func ordinaryLaunchKeepsExistingUserProfile() throws {
    #expect(try AcceptanceProfile.parse(["MacPulse", "--diagnostics-file", "/tmp/diagnostics.json"]) == nil)
}
@Test func malformedAcceptanceArgumentNeverFallsBackToLiveData() {
    for args in [["MacPulse", "--acceptance-directory"], ["MacPulse", "--acceptance-directory", "relative"],
                 ["MacPulse", "--acceptance-directory", "/tmp/a", "--acceptance-directory", "/tmp/b"]] {
        #expect(throws: (any Error).self) { try AcceptanceProfile.parse(args) }
    }
}
@Test func acceptanceCannotSelectLiveHistoryOrItsParent() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    for url in [URL(fileURLWithPath: "/"), home, home.appendingPathComponent("Library"),
                home.appendingPathComponent("Library/Application Support/MacPulse"),
                home.appendingPathComponent("Library/Application Support/MacPulse/child")] {
        #expect(throws: (any Error).self) { try AcceptanceProfile.parse(["MacPulse", "--acceptance-directory", url.path]) }
    }
}
@Test func isolatedPreferencesPersistAcrossReopenWithPrivatePermissions() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-acceptance-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let profile = try #require(try AcceptanceProfile.parse(["MacPulse", "--acceptance-directory", dir.path]))
    try profile.prepare()
    #expect(profile.preferences() == MonitorPreferences())
    let changed = MonitorPreferences(theme: .light, interval: 5, menuMetrics: [.gpu, .memory])
    try profile.save(changed)
    let reopened = try #require(try AcceptanceProfile.parse(["MacPulse", "--acceptance-directory", dir.path]))
    try reopened.prepare()
    #expect(reopened.preferences() == changed)
    #expect(try FileManager.default.attributesOfItem(atPath: profile.preferencesURL.path)[.posixPermissions] as? Int == 0o600)
    #expect(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int == 0o700)
}
@Test func acceptanceDoesNotModifyExistingUnmarkedDirectory() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-unowned-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    defer { try? FileManager.default.removeItem(at: dir) }
    let profile = try #require(try AcceptanceProfile.parse(["MacPulse", "--acceptance-directory", dir.path]))
    #expect(throws: (any Error).self) { try profile.prepare() }
    #expect(!FileManager.default.fileExists(atPath: profile.preferencesURL.path))
    #expect(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int == 0o755)
}
@Test func oversizedOrCorruptAcceptancePreferencesKeepFreshDefaults() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-corrupt-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let profile = try #require(try AcceptanceProfile.parse(["MacPulse", "--acceptance-directory", dir.path]))
    try profile.prepare()
    for data in [Data("broken".utf8), Data(repeating: 32, count: 16_385)] {
        try data.write(to: profile.preferencesURL)
        #expect(profile.preferences() == MonitorPreferences())
    }
}
@Test func socketMetadataRecognizesSymlinkIdentityAndRejectsRegularFile() throws {
    let dir = URL(fileURLWithPath: "/tmp/mp-socket-" + UUID().uuidString.prefix(8))
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("s").path
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0); #expect(fd >= 0)
    defer { Darwin.close(fd) }
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { bytes in bytes.copyBytes(from: (path + "\0").utf8) }
    let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    #expect(bound == 0)
    let alias = dir.appendingPathComponent("alias").path
    try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: path)
    let key = try #require(ContainerSampler.socketKey(path))
    #expect(ContainerSampler.isSocket(path) && ContainerSampler.isSocket(alias))
    #expect(ContainerSampler.socketKey(alias) == key)
    let regular = dir.appendingPathComponent("file"); try Data().write(to: regular)
    #expect(!ContainerSampler.isSocket(regular.path) && !ContainerSampler.isSocket(dir.path + "/missing"))
}
