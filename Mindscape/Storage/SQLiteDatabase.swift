import Foundation
import SQLite3

enum SQLValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}

struct SQLRow {
    private let values: [String: SQLValue]

    init(values: [String: SQLValue]) {
        self.values = values
    }

    func string(_ key: String) -> String? {
        if case .text(let value)? = values[key] { return value }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case .int(let value)? = values[key] { return Int(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        switch values[key] {
        case .double(let value)?: return value
        case .int(let value)?: return Double(value)
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool {
        (int(key) ?? 0) != 0
    }
}

enum DatabaseError: LocalizedError {
    case open(String)
    case execute(String)
    case prepare(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): return "数据库打开失败：\(message)"
        case .execute(let message): return "数据库执行失败：\(message)"
        case .prepare(let message): return "SQL 准备失败：\(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw DatabaseError.open(message)
        }
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA busy_timeout = 3000;")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw DatabaseError.execute(message)
        }
    }

    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw DatabaseError.execute(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }

        var rows: [SQLRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw DatabaseError.execute(String(cString: sqlite3_errmsg(handle)))
            }
            var values: [String: SQLValue] = [:]
            let columnCount = sqlite3_column_count(statement)
            for index in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    values[name] = .int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    values[name] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, index) {
                        values[name] = .text(String(cString: text))
                    } else {
                        values[name] = .null
                    }
                case SQLITE_NULL:
                    values[name] = .null
                default:
                    values[name] = .null
                }
            }
            rows.append(SQLRow(values: values))
        }
        return rows
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        for (index, value) in params.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text):
                sqlite3_bind_text(statement, position, (text as NSString).utf8String, -1, SQLITE_TRANSIENT)
            case .int(let number):
                sqlite3_bind_int64(statement, position, number)
            case .double(let number):
                sqlite3_bind_double(statement, position, number)
            case .null:
                sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }
}
