import Foundation
import SQLite3

enum SQLiteValue {
    case int(Int)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String, sql: String)
    case step(String)
    case bind(String)

    var description: String {
        switch self {
        case .open(let message): return "open: \(message)"
        case .prepare(let message, let sql): return "prepare: \(message) — \(sql)"
        case .step(let message): return "step: \(message)"
        case .bind(let message): return "bind: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal SQLite wrapper. Not thread-safe: always owned by a single actor.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private var statementCache: [String: SQLiteStatement] = [:]

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            handle = nil
            throw SQLiteError.open(message)
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA temp_store = MEMORY")
    }

    deinit {
        statementCache.removeAll()
        sqlite3_close_v2(handle)
    }

    var errorMessage: String {
        guard let handle else { return "closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw SQLiteError.step(message + " — " + sql)
        }
    }

    /// Returns a cached, reset statement for `sql`.
    func prepare(_ sql: String) throws -> SQLiteStatement {
        if let cached = statementCache[sql] {
            cached.reset()
            return cached
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepare(errorMessage, sql: sql)
        }
        let wrapped = SQLiteStatement(handle: statement, database: self)
        statementCache[sql] = wrapped
        return wrapped
    }

    func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        try statement.bind(values)
        _ = try statement.step()
        statement.reset()
    }

    func query(_ sql: String, _ values: [SQLiteValue] = [], row: (SQLiteStatement) throws -> Void) throws {
        let statement = try prepare(sql)
        try statement.bind(values)
        while try statement.step() {
            try row(statement)
        }
        statement.reset()
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var userVersion: Int {
        get {
            var version = 0
            try? query("PRAGMA user_version") { version = $0.int(0) }
            return version
        }
        set {
            try? execute("PRAGMA user_version = \(newValue)")
        }
    }

    static func compileOptionEnabled(_ name: String) -> Bool {
        sqlite3_compileoption_used(name) != 0
    }
}

final class SQLiteStatement {
    let handle: OpaquePointer
    private unowned let database: SQLiteDatabase

    init(handle: OpaquePointer, database: SQLiteDatabase) {
        self.handle = handle
        self.database = database
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    func bind(_ values: [SQLiteValue]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .int(let int):
                result = sqlite3_bind_int64(handle, index, Int64(int))
            case .double(let double):
                result = sqlite3_bind_double(handle, index, double)
            case .text(let text):
                result = sqlite3_bind_text(handle, index, text, -1, SQLITE_TRANSIENT)
            case .blob(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(handle, index, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }
            case .null:
                result = sqlite3_bind_null(handle, index)
            }
            if result != SQLITE_OK {
                throw SQLiteError.bind(database.errorMessage)
            }
        }
    }

    /// Returns true while rows are available.
    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError.step(database.errorMessage)
        }
    }

    func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(handle, column))
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(handle, column)
    }

    func text(_ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: pointer)
    }

    func blob(_ column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(handle, column))
        guard count > 0, let pointer = sqlite3_column_blob(handle, column) else { return nil }
        return Data(bytes: pointer, count: count)
    }
}

// MARK: - Vector encoding

extension Array where Element == Float {
    var sqliteData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }

    init(sqliteData data: Data) {
        let count = data.count / MemoryLayout<Float>.stride
        var result = [Float](repeating: 0, count: count)
        _ = result.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        self = result
    }
}
