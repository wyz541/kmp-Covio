import Foundation
import SQLite3

struct AgentHistorySession: Sendable, Equatable {
    let id: UUID
    let title: String
    let startedAtEpochMilliseconds: Int64
    let updatedAtEpochMilliseconds: Int64
    let messages: [AgentChatMessage]
    let audits: [AgentToolAudit]
}

protocol AgentHistoryStoring: Sendable {
    func loadLatestSession() async throws -> AgentHistorySession?
    func saveSession(_ session: AgentHistorySession) async throws
    func deleteSession(id: UUID) async throws
    func deleteAllSessions() async throws
}

struct AgentHistoryStoreError: Error, LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

private final class AgentHistorySQLiteConnection: @unchecked Sendable {
    let database: OpaquePointer

    init(database: OpaquePointer) {
        self.database = database
    }

    deinit {
        sqlite3_close_v2(database)
    }
}

actor AgentHistoryStore: AgentHistoryStoring {
    private let connection: AgentHistorySQLiteConnection?
    private let openingError: AgentHistoryStoreError?

    init(path: URL) {
        do {
            connection = try Self.openDatabase(path: path)
            openingError = nil
        } catch {
            connection = nil
            openingError = Self.storeError(error)
        }
    }


    func loadLatestSession() async throws -> AgentHistorySession? {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            SELECT id, title, started_at, updated_at
            FROM agent_sessions
            ORDER BY updated_at DESC, rowid DESC
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let id = UUID(uuidString: text(statement, column: 0)) else {
            throw AgentHistoryStoreError(message: "The Agent history session ID is invalid.")
        }
        let title = text(statement, column: 1)
        let startedAt = sqlite3_column_int64(statement, 2)
        let updatedAt = sqlite3_column_int64(statement, 3)
        return AgentHistorySession(
            id: id,
            title: title,
            startedAtEpochMilliseconds: startedAt,
            updatedAtEpochMilliseconds: updatedAt,
            messages: try loadMessages(database: database, sessionID: id),
            audits: try loadAudits(database: database, sessionID: id)
        )
    }

    func saveSession(_ session: AgentHistorySession) async throws {
        let database = try readyDatabase()
        try transaction(database) {
            let upsert = try prepare(
                database,
                """
                INSERT INTO agent_sessions (id, title, started_at, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    started_at = MIN(agent_sessions.started_at, excluded.started_at),
                    updated_at = excluded.updated_at
                """
            )
            defer { sqlite3_finalize(upsert) }
            try bindText(upsert, index: 1, value: session.id.uuidString.lowercased())
            try bindText(upsert, index: 2, value: session.title)
            try bindInt64(upsert, index: 3, value: session.startedAtEpochMilliseconds)
            try bindInt64(upsert, index: 4, value: session.updatedAtEpochMilliseconds)
            try stepDone(upsert, database: database)

            try execute(
                database,
                "DELETE FROM agent_messages WHERE session_id = ?",
                bindings: [.text(session.id.uuidString.lowercased())]
            )
            try execute(
                database,
                "DELETE FROM agent_audits WHERE session_id = ?",
                bindings: [.text(session.id.uuidString.lowercased())]
            )

            for (position, message) in session.messages.enumerated() {
                let statement = try prepare(
                    database,
                    """
                    INSERT INTO agent_messages
                        (id, session_id, position, role, body, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """
                )
                defer { sqlite3_finalize(statement) }
                try bindText(statement, index: 1, value: message.id.uuidString.lowercased())
                try bindText(statement, index: 2, value: session.id.uuidString.lowercased())
                try bindInt64(statement, index: 3, value: Int64(position))
                try bindText(statement, index: 4, value: message.role.storageValue)
                try bindText(statement, index: 5, value: message.text)
                try bindInt64(statement, index: 6, value: message.createdAtEpochMilliseconds)
                try stepDone(statement, database: database)
            }

            for (position, audit) in session.audits.enumerated() {
                let statement = try prepare(
                    database,
                    """
                    INSERT INTO agent_audits
                        (id, session_id, position, tool_name, risk, status, detail,
                         error_code, duration_ms, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                )
                defer { sqlite3_finalize(statement) }
                try bindText(statement, index: 1, value: audit.id)
                try bindText(statement, index: 2, value: session.id.uuidString.lowercased())
                try bindInt64(statement, index: 3, value: Int64(position))
                try bindText(statement, index: 4, value: audit.toolName)
                try bindText(statement, index: 5, value: audit.risk.rawValue)
                try bindText(statement, index: 6, value: audit.status.rawValue)
                try bindText(statement, index: 7, value: audit.detail)
                try bindOptionalText(statement, index: 8, value: audit.errorCode?.rawValue)
                if let duration = audit.durationMilliseconds {
                    try bindInt64(statement, index: 9, value: Int64(duration))
                } else {
                    guard sqlite3_bind_null(statement, 9) == SQLITE_OK else {
                        throw Self.sqliteError(database, fallback: "Could not bind an audit duration.")
                    }
                }
                try bindInt64(statement, index: 10, value: audit.createdAtEpochMilliseconds)
                try stepDone(statement, database: database)
            }
        }
    }

    func deleteSession(id: UUID) async throws {
        let database = try readyDatabase()
        try execute(
            database,
            "DELETE FROM agent_sessions WHERE id = ?",
            bindings: [.text(id.uuidString.lowercased())]
        )
    }

    func deleteAllSessions() async throws {
        let database = try readyDatabase()
        try execute(database, "DELETE FROM agent_sessions")
    }

    func schemaVersion() async throws -> Int {
        let database = try readyDatabase()
        return try Self.userVersion(database)
    }

    private func loadMessages(
        database: OpaquePointer,
        sessionID: UUID
    ) throws -> [AgentChatMessage] {
        let statement = try prepare(
            database,
            """
            SELECT id, role, body, created_at
            FROM agent_messages
            WHERE session_id = ?
            ORDER BY position ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(statement, index: 1, value: sessionID.uuidString.lowercased())
        var messages: [AgentChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, column: 0)),
                  let role = AgentChatRole(storageValue: text(statement, column: 1))
            else {
                throw AgentHistoryStoreError(message: "The Agent history message is invalid.")
            }
            messages.append(
                AgentChatMessage(
                    id: id,
                    role: role,
                    text: text(statement, column: 2),
                    createdAtEpochMilliseconds: sqlite3_column_int64(statement, 3)
                )
            )
        }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw Self.sqliteError(database, fallback: "Could not read Agent history messages.")
        }
        return messages
    }

    private func loadAudits(
        database: OpaquePointer,
        sessionID: UUID
    ) throws -> [AgentToolAudit] {
        let statement = try prepare(
            database,
            """
            SELECT id, tool_name, risk, status, detail, error_code, duration_ms, created_at
            FROM agent_audits
            WHERE session_id = ?
            ORDER BY position ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(statement, index: 1, value: sessionID.uuidString.lowercased())
        var audits: [AgentToolAudit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let risk = AgentToolRisk(rawValue: text(statement, column: 2)),
                  let status = AgentToolAuditStatus(rawValue: text(statement, column: 3))
            else {
                throw AgentHistoryStoreError(message: "The Agent audit record is invalid.")
            }
            let errorCode: AgentServiceErrorCode?
            if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                errorCode = nil
            } else {
                guard let value = AgentServiceErrorCode(rawValue: text(statement, column: 5)) else {
                    throw AgentHistoryStoreError(message: "The Agent audit error code is invalid.")
                }
                errorCode = value
            }
            let duration = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int64(statement, 6))
            audits.append(
                AgentToolAudit(
                    id: text(statement, column: 0),
                    toolName: text(statement, column: 1),
                    risk: risk,
                    status: status,
                    detail: text(statement, column: 4),
                    errorCode: errorCode,
                    durationMilliseconds: duration,
                    createdAtEpochMilliseconds: sqlite3_column_int64(statement, 7)
                )
            )
        }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw Self.sqliteError(database, fallback: "Could not read Agent audit records.")
        }
        return audits
    }

    private func readyDatabase() throws -> OpaquePointer {
        if let openingError {
            throw openingError
        }
        guard let connection else {
            throw AgentHistoryStoreError(message: "The Agent history database is unavailable.")
        }
        return connection.database
    }

    private static func openDatabase(path: URL) throws -> AgentHistorySQLiteConnection {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Could not open the Agent history database."
            if let database { sqlite3_close_v2(database) }
            throw AgentHistoryStoreError(message: message)
        }
        do {
            try execute(database, "PRAGMA foreign_keys = ON")
            try execute(database, "PRAGMA journal_mode = WAL")
            try execute(database, "PRAGMA synchronous = NORMAL")
            sqlite3_busy_timeout(database, 1_000)
            try migrate(database)
            return AgentHistorySQLiteConnection(database: database)
        } catch {
            sqlite3_close_v2(database)
            throw error
        }
    }

    private static func migrate(_ database: OpaquePointer) throws {
        var version = try userVersion(database)
        if version < 1 {
            try transaction(database) {
                try execute(
                    database,
                    """
                    CREATE TABLE IF NOT EXISTS agent_sessions (
                        id TEXT PRIMARY KEY NOT NULL,
                        title TEXT NOT NULL,
                        started_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL
                    )
                    """
                )
                try execute(
                    database,
                    """
                    CREATE TABLE IF NOT EXISTS agent_messages (
                        id TEXT PRIMARY KEY NOT NULL,
                        session_id TEXT NOT NULL
                            REFERENCES agent_sessions(id) ON DELETE CASCADE,
                        position INTEGER NOT NULL,
                        role TEXT NOT NULL,
                        body TEXT NOT NULL,
                        created_at INTEGER NOT NULL,
                        UNIQUE(session_id, position)
                    )
                    """
                )
                try execute(
                    database,
                    """
                    CREATE TABLE IF NOT EXISTS agent_audits (
                        id TEXT PRIMARY KEY NOT NULL,
                        session_id TEXT NOT NULL
                            REFERENCES agent_sessions(id) ON DELETE CASCADE,
                        position INTEGER NOT NULL,
                        tool_name TEXT NOT NULL,
                        risk TEXT NOT NULL,
                        status TEXT NOT NULL,
                        detail TEXT NOT NULL,
                        error_code TEXT,
                        duration_ms INTEGER,
                        created_at INTEGER NOT NULL,
                        UNIQUE(session_id, position)
                    )
                    """
                )
                try execute(
                    database,
                    "CREATE INDEX IF NOT EXISTS agent_messages_session ON agent_messages(session_id, position)"
                )
                try execute(
                    database,
                    "CREATE INDEX IF NOT EXISTS agent_audits_session ON agent_audits(session_id, position)"
                )
                try execute(database, "PRAGMA user_version = 1")
                version = 1
            }
        }
        guard version == 1 else {
            throw AgentHistoryStoreError(
                message: "The Agent history database version is not supported."
            )
        }
    }


    private static func userVersion(_ database: OpaquePointer) throws -> Int {
        let statement = try prepare(database, "PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw sqliteError(database, fallback: "Could not read the database version.")
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func transaction(
        _ database: OpaquePointer,
        operation: () throws -> Void
    ) throws {
        try execute(database, "BEGIN IMMEDIATE")
        do {
            try operation()
            try execute(database, "COMMIT")
        } catch {
            try? execute(database, "ROLLBACK")
            throw error
        }
    }

    private func transaction(
        _ database: OpaquePointer,
        operation: () throws -> Void
    ) throws {
        try execute(database, "BEGIN IMMEDIATE")
        do {
            try operation()
            try execute(database, "COMMIT")
        } catch {
            try? execute(database, "ROLLBACK")
            throw error
        }
    }

    private enum Binding {
        case text(String)
        case int64(Int64)
    }

    private func execute(
        _ database: OpaquePointer,
        _ sql: String,
        bindings: [Binding] = []
    ) throws {
        let statement = try prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() {
            switch binding {
            case .text(let value):
                try bindText(statement, index: Int32(offset + 1), value: value)
            case .int64(let value):
                try bindInt64(statement, index: Int32(offset + 1), value: value)
            }
        }
        try stepDone(statement, database: database)
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let detail = message.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(message)
            throw AgentHistoryStoreError(message: detail)
        }
        sqlite3_free(message)
    }

    private func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        try Self.prepare(database, sql)
    }

    private static func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw sqliteError(database, fallback: "Could not prepare a database statement.")
        }
        return statement
    }

    private func bindText(
        _ statement: OpaquePointer,
        index: Int32,
        value: String
    ) throws {
        try Self.bindText(statement, index: index, value: value)
    }

    private static func bindText(
        _ statement: OpaquePointer,
        index: Int32,
        value: String
    ) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw AgentHistoryStoreError(message: "Could not bind Agent history text.")
        }
    }

    private func bindOptionalText(
        _ statement: OpaquePointer,
        index: Int32,
        value: String?
    ) throws {
        if let value {
            try bindText(statement, index: index, value: value)
        } else if sqlite3_bind_null(statement, index) != SQLITE_OK {
            throw AgentHistoryStoreError(message: "Could not bind an optional Agent history value.")
        }
    }

    private func bindInt64(
        _ statement: OpaquePointer,
        index: Int32,
        value: Int64
    ) throws {
        try Self.bindInt64(statement, index: index, value: value)
    }

    private static func bindInt64(
        _ statement: OpaquePointer,
        index: Int32,
        value: Int64
    ) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw AgentHistoryStoreError(message: "Could not bind an Agent history number.")
        }
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        try Self.stepDone(statement, database: database)
    }

    private static func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(database, fallback: "Could not store Agent history.")
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        Self.text(statement, column: column)
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private static func sqliteError(
        _ database: OpaquePointer,
        fallback: String
    ) -> AgentHistoryStoreError {
        let message = String(cString: sqlite3_errmsg(database))
        return AgentHistoryStoreError(message: message.isEmpty ? fallback : message)
    }

    private static func storeError(_ error: Error) -> AgentHistoryStoreError {
        if let error = error as? AgentHistoryStoreError { return error }
        return AgentHistoryStoreError(message: error.localizedDescription)
    }
}

private extension AgentChatRole {
    var storageValue: String {
        switch self {
        case .user: "user"
        case .assistant: "assistant"
        case .service: "service"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "user": self = .user
        case "assistant": self = .assistant
        case "service": self = .service
        default: return nil
        }
    }
}
