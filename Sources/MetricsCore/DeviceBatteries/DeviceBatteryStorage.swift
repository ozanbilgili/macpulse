import Foundation
import CryptoKit

public struct BatteryMigration: Codable, Sendable {
    public var files: [String]
    public var sourceHashes: [String: String]
    public var deviceCount: Int
    public var historyPointCount: Int
}

public struct DeviceBatteryStorage: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static var local: Self {
        Self(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacPulse/DeviceBatteries"))
    }
    public func read<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let data = try? Self.data(directory.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    public func write<T: Encodable>(_ value: T, file: String) throws { try writeData(JSONEncoder().encode(value), file: file) }
    private func writeData(_ data: Data, file: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(file)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func data(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (0...16_777_216).contains(size) else { throw CocoaError(.fileReadTooLarge) }
        return try Data(contentsOf: url)
    }
    /// One-time, validated copy. Never writes to PilBar or replaces a MacPulse file.
    public func migrate(from source: URL) throws -> BatteryMigration {
        if let prior = read(BatteryMigration.self, file: "migration.json") { return prior }
        var pending: [(String, Data)] = [], devices = 0, points = 0
        for file in ["devices.json", "history.json", "preferences.json", "alerts.json"] {
            let url = source.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = try Self.data(url)
            switch file {
            case "devices.json": devices = try JSONDecoder().decode([BatteryDevice].self, from: data).count
            case "history.json": points = try JSONDecoder().decode(BatteryHistory.self, from: data).samples.values.reduce(0) { $0 + $1.count }
            case "preferences.json": _ = try JSONDecoder().decode(BatteryPreferences.self, from: data)
            default: _ = try JSONDecoder().decode(BatteryAlertState.self, from: data)
            }
            pending.append((file, data))
        }
        var copied: [String] = [], hashes: [String:String] = [:]
        for (file, data) in pending {
            guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) else { continue }
            try writeData(data, file: file)
            hashes[file] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            copied.append(file)
        }
        let report = BatteryMigration(files: copied, sourceHashes: hashes, deviceCount: devices, historyPointCount: points)
        try write(report, file: "migration.json")
        return report
    }
}
