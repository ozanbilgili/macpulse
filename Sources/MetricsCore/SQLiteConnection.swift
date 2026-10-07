import Foundation
import CSQLite
import Darwin

public struct HistoryError: Error, Sendable, CustomStringConvertible {
    public let description: String
}

// Exclusively owned by HistoryRepository. The pointer never leaves that actor.
final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw HistoryError(description: "Yerel geçmiş veritabanı açılamadı.")
        }
        handle = db
        do {
            sqlite3_busy_timeout(db, 2_000)
            let version = try scalar("PRAGMA user_version")
            guard version <= 2 else { throw HistoryError(description: "Geçmiş veritabanı daha yeni bir uygulama sürümüne ait; mevcut kayıt korundu.") }
            try exec("PRAGMA journal_mode=WAL")
            try exec("PRAGMA synchronous=NORMAL")
            try exec("PRAGMA journal_size_limit=4194304")
            try exec("CREATE TABLE IF NOT EXISTS minutes (start INTEGER PRIMARY KEY, payload TEXT NOT NULL)")
            try exec("CREATE TABLE IF NOT EXISTS days (start INTEGER PRIMARY KEY, payload TEXT NOT NULL)")
            try exec("CREATE TABLE IF NOT EXISTS alerts (id TEXT PRIMARY KEY, updated REAL NOT NULL, payload TEXT NOT NULL)")
            try exec("CREATE INDEX IF NOT EXISTS alerts_updated ON alerts(updated)")
            if version == 1 {
                // Preserve the early phase-3 development database before numerical repair.
                try backup(to: url.deletingLastPathComponent().appendingPathComponent("history-before-schema2-" + UUID().uuidString + ".sqlite"))
                try exec("BEGIN IMMEDIATE")
                do {
                    for table in ["minutes", "days"] {
                        for data in try payloads("SELECT payload FROM \(table)") {
                            var bucket = try JSONDecoder().decode(HistoryBucket.self, from: data)
                            var changed = false
                            for (id, var app) in bucket.applications where app.memory.peak > 0 && app.memory.peak < 1 {
                                // Old UInt64 bit-pattern conversion was a linear subnormal scale.
                                // Scale in two finite steps; 2^1074 itself would overflow Double.
                                app.memory.total = scalbn(app.memory.total, 1023) * 2_251_799_813_685_248
                                app.memory.peak = scalbn(app.memory.peak, 1023) * 2_251_799_813_685_248
                                bucket.applications[id] = app; changed = true
                            }
                            if changed { try write(bucket, table: table) }
                        }
                    }
                    try exec("PRAGMA user_version=2"); try exec("COMMIT")
                } catch { try? exec("ROLLBACK"); throw error }
            }
            if version == 0 { try exec("PRAGMA user_version=2") }
            try protectFiles(url)
        } catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { sqlite3_close(handle) }
    private func backup(to url: URL) throws {
        var destination: OpaquePointer?
        guard sqlite3_open_v2(url.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(destination); throw failure()
        }
        defer { sqlite3_close(destination) }
        guard let copy = sqlite3_backup_init(destination, "main", handle, "main") else { throw failure() }
        let status = sqlite3_backup_step(copy, -1)
        let finish = sqlite3_backup_finish(copy)
        guard status == SQLITE_DONE, finish == SQLITE_OK else { throw failure() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func protectFiles(_ url: URL) throws {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
    func exec(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    func scalar(_ sql: String) throws -> Int {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
        return Int(sqlite3_column_int64(statement, 0))
    }
    func payloads(_ sql: String, from: Double? = nil) throws -> [Data] {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        if let from { guard sqlite3_bind_double(statement, 1, from) == SQLITE_OK else { throw failure() } }
        var data: [Data] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return data }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw failure() }
            data.append(Data(bytes: text, count: Int(sqlite3_column_bytes(statement, 0))))
        }
    }
    func bucket(_ table: String, start: Int64) throws -> HistoryBucket {
        guard let data = try payloads("SELECT payload FROM \(table) WHERE start = ?", from: Double(start)).first else { return HistoryBucket(start: start) }
        return try JSONDecoder().decode(HistoryBucket.self, from: data)
    }
    func write(_ bucket: HistoryBucket, table: String) throws {
        let data = try JSONEncoder().encode(bucket)
        let statement = try prepare("INSERT INTO \(table)(start,payload) VALUES (?,?) ON CONFLICT(start) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int64(statement, 1, bucket.start) == SQLITE_OK else { throw failure() }
        try bind(data, to: statement, index: 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    func write(_ alert: MonitorAlert) throws {
        let statement = try prepare("INSERT INTO alerts(id,updated,payload) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET updated=excluded.updated,payload=excluded.payload")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, alert.id, -1, transient) == SQLITE_OK,
              sqlite3_bind_double(statement, 2, alert.updated.timeIntervalSince1970) == SQLITE_OK else { throw failure() }
        try bind(try JSONEncoder().encode(alert), to: statement, index: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    func retain(since cutoff: Int64) throws {
        for table in ["minutes", "days", "alerts"] {
            let column = table == "alerts" ? "updated" : "start"
            let statement = try prepare("DELETE FROM \(table) WHERE \(column) < ?")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, cutoff) == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        }
    }
    private func bind(_ data: Data, to statement: OpaquePointer, index: Int32) throws {
        guard let text = String(data: data, encoding: .utf8), sqlite3_bind_text(statement, index, text, -1, transient) == SQLITE_OK else { throw failure() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func failure() -> HistoryError {
        HistoryError(description: "Yerel geçmiş kaydı okunamadı/yazılamadı (SQLite \(sqlite3_errcode(handle))). Canlı ölçümler devam eder.")
    }
}
