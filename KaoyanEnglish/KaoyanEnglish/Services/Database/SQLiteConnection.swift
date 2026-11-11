import Foundation
import SQLite3

final class SQLiteConnection {
    private(set) var handle: OpaquePointer?
    init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开文件"
            if let handle { sqlite3_close(handle) }; handle = nil
            throw LibraryError.database(message)
        }
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA foreign_keys = ON")
    }
    deinit { if let handle { sqlite3_close_v2(handle) } }
    func execute(_ sql: String, _ values: [String?] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else { throw failure() }
    }
    func rows(_ sql: String, _ values: [String?] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw failure() }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                if let value = sqlite3_column_text(statement, index) {
                    row[String(cString: sqlite3_column_name(statement, index))] = String(cString: value)
                }
            }
            result.append(row)
        }
    }
    func transaction<T>(_ action: () throws -> T) throws -> T {
        if sqlite3_get_autocommit(handle) == 0 {
            let savepoint = "nested_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            try execute("SAVEPOINT \(savepoint)")
            do {
                let result = try action()
                try execute("RELEASE SAVEPOINT \(savepoint)")
                return result
            } catch {
                try? execute("ROLLBACK TO SAVEPOINT \(savepoint)")
                try? execute("RELEASE SAVEPOINT \(savepoint)")
                throw error
            }
        }
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try action()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in values.enumerated() {
            let status: Int32
            if let value {
                status = sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else { status = sqlite3_bind_null(statement, Int32(index + 1)) }
            if status != SQLITE_OK { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }
    func failure() -> LibraryError { .database(String(cString: sqlite3_errmsg(handle))) }
}
