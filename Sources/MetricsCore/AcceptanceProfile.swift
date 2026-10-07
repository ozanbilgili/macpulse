import Foundation

/// Explicit opt-in, isolated install acceptance. Normal launches use the existing store.
public struct AcceptanceProfile: Sendable {
    public let directory: URL
    public var historyURL: URL { directory.appendingPathComponent("history.sqlite") }
    public var preferencesURL: URL { directory.appendingPathComponent("preferences.json") }

    public static func parse(_ arguments: [String]) throws -> AcceptanceProfile? {
        let matches = arguments.indices.filter { arguments[$0] == "--acceptance-directory" }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let index = matches.first, arguments.indices.contains(index + 1),
              arguments[index + 1].hasPrefix("/"), !arguments[index + 1].hasPrefix("--") else {
            throw HistoryError(description: "Geçersiz kabul profili; normal kullanıcı verisine geçilmedi.")
        }
        let url = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let live = home.appendingPathComponent("Library/Application Support/MacPulse", isDirectory: true)
        guard url.path != "/", url.path != home.path,
              url.path != live.path, !live.path.hasPrefix(url.path + "/"), !url.path.hasPrefix(live.path + "/") else {
            throw HistoryError(description: "Kabul profili canlı veri dizininden ayrı olmalı.")
        }
        return AcceptanceProfile(directory: url)
    }
    public func prepare() throws {
        let marker = directory.appendingPathComponent(".macpulse-acceptance")
        let identity = Data("MacPulse isolated acceptance profile v1\n".utf8)
        if FileManager.default.fileExists(atPath: directory.path) {
            guard (try? Data(contentsOf: marker)) == identity else {
                throw HistoryError(description: "Kabul dizini uygulamaya ait değil; değiştirilmedi.")
            }
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try identity.write(to: marker, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }
    public func preferences() -> MonitorPreferences {
        guard let file = try? FileHandle(forReadingFrom: preferencesURL) else { return MonitorPreferences() }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 16_385), data.count <= 16_384,
              let value = try? JSONDecoder().decode(MonitorPreferences.self, from: data) else { return MonitorPreferences() }
        return value
    }
    public func save(_ preferences: MonitorPreferences) throws {
        let data = try JSONEncoder().encode(preferences)
        try data.write(to: preferencesURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: preferencesURL.path)
    }
}
