import Foundation
import SQLite3

/// An error of SQLite.
public struct SQLiteError: Error, Sendable, Equatable, CustomStringConvertible {
    public var code: Int32
    public var message: String

    public var description: String { "SQLite error \(code): \(message)" }
}

/// A value for a statement parameter.
public enum SQLiteValue: Sendable, Equatable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null
}

extension SQLiteValue {
    public init(_ value: Int?) { self = value.map { .integer(Int64($0)) } ?? .null }
    public init(_ value: Int64?) { self = value.map { .integer($0) } ?? .null }
    public init(_ value: Double?) { self = value.map { .real($0) } ?? .null }
    public init(_ value: String?) { self = value.map { .text($0) } ?? .null }
    public init(_ value: Bool) { self = .integer(value ? 1 : 0) }
}

/// A connection to one SQLite file. It is not safe to use from two threads at the same time.
/// `NavDatabaseReader` keeps it in a `Mutex`.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private var cache: [String: SQLiteStatement] = [:]

    public enum Mode {
        /// Read only. The file must not change while it is open (SQLite `immutable=1`).
        case readOnlyImmutable
        /// Read and write. The file is created when it does not exist.
        case readWriteCreate
    }

    public init(path: String, mode: Mode) throws(SQLiteError) {
        let flags: Int32
        let name: String
        switch mode {
        case .readOnlyImmutable:
            flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
            // A URI is necessary for the parameter. The path can have spaces, so it is percent-encoded.
            name = URL(fileURLWithPath: path).absoluteString + "?immutable=1"
        case .readWriteCreate:
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
            name = path
        }
        var db: OpaquePointer?
        let code = sqlite3_open_v2(name, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close_v2(db)
            throw SQLiteError(code: code, message: message)
        }
        handle = db
    }

    deinit {
        cache.removeAll()
        sqlite3_close_v2(handle)
    }

    var lastError: SQLiteError {
        SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }

    /// Runs one or more statements without parameters and results.
    public func execute(_ sql: String) throws(SQLiteError) {
        var message: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &message)
        if code != SQLITE_OK {
            let text = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            throw SQLiteError(code: code, message: text)
        }
    }

    /// A prepared statement. The statement is kept and used again for the same SQL text.
    public func statement(_ sql: String) throws(SQLiteError) -> SQLiteStatement {
        if let cached = cache[sql] {
            cached.reset()
            return cached
        }
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw lastError
        }
        let statement = SQLiteStatement(pointer, database: self)
        cache[sql] = statement
        return statement
    }

    /// Runs a query and maps each row.
    public func rows<T>(_ sql: String, _ parameters: [SQLiteValue] = [], _ map: (SQLiteStatement) throws(SQLiteError) -> T) throws(SQLiteError) -> [T] {
        let statement = try statement(sql)
        defer { statement.reset() }
        try statement.bind(parameters)
        var result: [T] = []
        while try statement.step() {
            result.append(try map(statement))
        }
        return result
    }

    /// Runs a statement that changes data.
    public func run(_ sql: String, _ parameters: [SQLiteValue] = []) throws(SQLiteError) {
        let statement = try statement(sql)
        defer { statement.reset() }
        try statement.bind(parameters)
        while try statement.step() {}
    }

    /// The first column of the first row, or nil.
    public func scalar(_ sql: String, _ parameters: [SQLiteValue] = []) throws(SQLiteError) -> SQLiteValue? {
        try rows(sql, parameters) { $0.value(0) }.first
    }
}

/// A prepared statement of `SQLiteDatabase`.
public final class SQLiteStatement {
    private let pointer: OpaquePointer
    private unowned let database: SQLiteDatabase

    init(_ pointer: OpaquePointer, database: SQLiteDatabase) {
        self.pointer = pointer
        self.database = database
    }

    deinit {
        sqlite3_finalize(pointer)
    }

    func reset() {
        sqlite3_reset(pointer)
        sqlite3_clear_bindings(pointer)
    }

    func bind(_ values: [SQLiteValue]) throws(SQLiteError) {
        // SQLITE_TRANSIENT: SQLite makes its own copy of the text.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .integer(let v): code = sqlite3_bind_int64(pointer, index, v)
            case .real(let v): code = sqlite3_bind_double(pointer, index, v)
            case .text(let v): code = sqlite3_bind_text(pointer, index, v, -1, transient)
            case .null: code = sqlite3_bind_null(pointer, index)
            }
            guard code == SQLITE_OK else { throw database.lastError }
        }
    }

    /// Returns true when there is a row, false at the end.
    func step() throws(SQLiteError) -> Bool {
        switch sqlite3_step(pointer) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw database.lastError
        }
    }

    public func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(pointer, column) == SQLITE_NULL
    }

    public func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(pointer, column)
    }

    public func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(pointer, column))
    }

    public func optionalInt(_ column: Int32) -> Int? {
        isNull(column) ? nil : int(column)
    }

    public func double(_ column: Int32) -> Double {
        sqlite3_column_double(pointer, column)
    }

    public func optionalDouble(_ column: Int32) -> Double? {
        isNull(column) ? nil : double(column)
    }

    public func text(_ column: Int32) -> String {
        guard let c = sqlite3_column_text(pointer, column) else { return "" }
        return String(cString: c)
    }

    public func optionalText(_ column: Int32) -> String? {
        isNull(column) ? nil : text(column)
    }

    public func bool(_ column: Int32) -> Bool {
        int64(column) != 0
    }

    public func value(_ column: Int32) -> SQLiteValue {
        switch sqlite3_column_type(pointer, column) {
        case SQLITE_INTEGER: .integer(int64(column))
        case SQLITE_FLOAT: .real(double(column))
        case SQLITE_NULL: .null
        default: .text(text(column))
        }
    }
}
