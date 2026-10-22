import Foundation
import SQLite3

private struct MonitorHistorySQLiteFailure: Error {
    let code: Int32
    let message: String
}

private final class MonitorHistorySQLiteConnection: @unchecked Sendable {
    let database: OpaquePointer

    init(database: OpaquePointer) {
        self.database = database
    }

    deinit {
        sqlite3_close_v2(database)
    }
}

/// 本地性能历史数据库。
///
/// 用一个 actor 串行化所有访问。SQLite 连接不跨实例共享。
actor MonitorHistoryStore: MonitorHistoryStoring {
    private static let schemaVersion = 1
    private static let sampleColumnList = """
        sampled_at_ms, monotonic_ns, boot_id, power_source, thermal_state,
        cpu_usage, cpu_load_1, cpu_core_count, gpu_usage, gpu_memory_bytes,
        memory_used_bytes, memory_total_bytes, memory_pressure, swap_used_bytes,
        disk_read_bps, disk_write_bps, disk_used_bytes, disk_free_bytes,
        network_receive_bps, network_transmit_bps, battery_percent,
        battery_temp_c, battery_health_pct, system_power_w, battery_power_w,
        display_state, lid_state, sample_kind, quality
        """

    private var connection: MonitorHistorySQLiteConnection?
    private let openingError: MonitorHistoryStoreError?
    private let configuration: MonitorHistoryStoreConfiguration
    private let path: URL

    init(
        path: URL = AppPaths.monitorHistoryFile,
        configuration: MonitorHistoryStoreConfiguration = .standard
    ) {
        self.path = path
        self.configuration = configuration
        do {
            connection = try Self.openDatabase(path: path)
            openingError = nil
        } catch {
            connection = nil
            openingError = Self.storeError(error)
        }
    }

    func schemaVersion() throws -> Int {
        let database = try readyDatabase()
        return try readUserVersion(database)
    }

    func databaseSizeBytes() -> Int64 {
        Self.databaseSizeBytes(path: path)
    }

    func insert(samples: [MonitorHistorySample]) throws {
        guard !samples.isEmpty else { return }
        let database = try readyDatabase()
        try transaction(database) {
            let statement = try prepare(
                database,
                """
                INSERT INTO samples (
                    \(Self.sampleColumnList)
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
                """
            )
            defer { sqlite3_finalize(statement) }

            for sample in samples {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bindSample(sample, to: statement)
                try stepDone(statement, database: database)
            }
        }
        try checkpointIfNeeded()
    }

    func insert(event: MonitorHistoryEvent) throws {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            INSERT OR IGNORE INTO events
                (occurred_at_ms, boot_id, kind, detail_code, source, confidence)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(statement, index: 1, value: Self.milliseconds(event.occurredAt))
        try bindText(statement, index: 2, value: event.bootID)
        try bindText(statement, index: 3, value: event.kind.rawValue)
        try bindText(statement, index: 4, value: event.detailCode)
        try bindText(statement, index: 5, value: event.source.rawValue)
        try bindText(statement, index: 6, value: event.confidence.rawValue)
        try stepDone(statement, database: database)
        try checkpointIfNeeded()
    }

    func insert(gap: MonitorHistoryGap) throws {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            INSERT INTO gaps (started_at_ms, ended_at_ms, boot_id, reason)
            VALUES (?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(statement, index: 1, value: Self.milliseconds(gap.startedAt))
        if let endedAt = gap.endedAt {
            try bindInt64(statement, index: 2, value: Self.milliseconds(endedAt))
        } else {
            try bindNull(statement, index: 2)
        }
        try bindText(statement, index: 3, value: gap.bootID)
        try bindText(statement, index: 4, value: gap.reason.rawValue)
        try stepDone(statement, database: database)
        try checkpointIfNeeded()
    }

    func upsert(systemEpoch: MonitorSystemEpoch) throws {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            INSERT INTO system_epochs (
                boot_id, started_at_ms, os_version, os_build, model, chip,
                memory_bytes, disk_total_bytes, ssd_model
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(boot_id) DO UPDATE SET
                started_at_ms = excluded.started_at_ms,
                os_version = excluded.os_version,
                os_build = excluded.os_build,
                model = excluded.model,
                chip = excluded.chip,
                memory_bytes = excluded.memory_bytes,
                disk_total_bytes = excluded.disk_total_bytes,
                ssd_model = excluded.ssd_model
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(statement, index: 1, value: systemEpoch.bootID)
        try bindInt64(statement, index: 2, value: Self.milliseconds(systemEpoch.startedAt))
        try bindText(statement, index: 3, value: systemEpoch.osVersion)
        try bindText(statement, index: 4, value: systemEpoch.osBuild)
        try bindText(statement, index: 5, value: systemEpoch.model)
        try bindText(statement, index: 6, value: systemEpoch.chip)
        try bindUInt64(statement, index: 7, value: systemEpoch.memoryBytes)
        try bindUInt64(statement, index: 8, value: systemEpoch.diskTotalBytes)
        try bindOptionalText(statement, index: 9, value: systemEpoch.ssdModel)
        try stepDone(statement, database: database)
    }

    func closeOpenGap(bootID: String, endedAt: Date) throws {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            UPDATE gaps
            SET ended_at_ms = ?
            WHERE boot_id = ? AND ended_at_ms IS NULL
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(statement, index: 1, value: Self.milliseconds(endedAt))
        try bindText(statement, index: 2, value: bootID)
        try stepDone(statement, database: database)
    }

    func samples(from start: Date, to end: Date) throws -> [MonitorHistorySample] {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            SELECT \(Self.sampleColumnList)
            FROM samples
            WHERE sampled_at_ms >= ? AND sampled_at_ms <= ?
            ORDER BY sampled_at_ms ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindRange(statement, start: start, end: end)

        var values: [MonitorHistorySample] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw Self.sqliteReadError(database, fallback: "Could not read performance samples.")
            }
            values.append(try sample(from: statement))
        }
        return values
    }

    func events(from start: Date, to end: Date) throws -> [MonitorHistoryEvent] {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            SELECT occurred_at_ms, boot_id, kind, detail_code, source, confidence
            FROM events
            WHERE occurred_at_ms >= ? AND occurred_at_ms <= ?
            ORDER BY occurred_at_ms ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindRange(statement, start: start, end: end)

        var values: [MonitorHistoryEvent] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw Self.sqliteReadError(database, fallback: "Could not read performance events.")
            }
            guard let kind = MonitorHistoryEvent.Kind(rawValue: text(statement, column: 2)),
                  let source = MonitorHistoryEvent.Source(rawValue: text(statement, column: 4)),
                  let confidence = MonitorHistoryEvent.Confidence(rawValue: text(statement, column: 5))
            else {
                throw MonitorHistoryStoreError.readFailed("A performance event has an unknown enum value.")
            }
            values.append(
                MonitorHistoryEvent(
                    occurredAt: Self.date(milliseconds: sqlite3_column_int64(statement, 0)),
                    bootID: text(statement, column: 1),
                    kind: kind,
                    detailCode: text(statement, column: 3),
                    source: source,
                    confidence: confidence
                )
            )
        }
        return values
    }

    func gaps(overlapping start: Date, through end: Date) throws -> [MonitorHistoryGap] {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            SELECT started_at_ms, ended_at_ms, boot_id, reason
            FROM gaps
            WHERE started_at_ms <= ?
              AND (ended_at_ms IS NULL OR ended_at_ms >= ?)
            ORDER BY started_at_ms ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(statement, index: 1, value: Self.milliseconds(end))
        try bindInt64(statement, index: 2, value: Self.milliseconds(start))

        var values: [MonitorHistoryGap] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw Self.sqliteReadError(database, fallback: "Could not read performance gaps.")
            }
            guard let reason = MonitorHistoryGap.Reason(rawValue: text(statement, column: 3)) else {
                throw MonitorHistoryStoreError.readFailed("A performance gap has an unknown reason.")
            }
            let endedAt = sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil
                : Self.date(milliseconds: sqlite3_column_int64(statement, 1))
            values.append(
                MonitorHistoryGap(
                    startedAt: Self.date(milliseconds: sqlite3_column_int64(statement, 0)),
                    endedAt: endedAt,
                    bootID: text(statement, column: 2),
                    reason: reason
                )
            )
        }
        return values
    }

    func systemEpochs() throws -> [MonitorSystemEpoch] {
        let database = try readyDatabase()
        let statement = try prepare(
            database,
            """
            SELECT boot_id, started_at_ms, os_version, os_build, model, chip,
                   memory_bytes, disk_total_bytes, ssd_model
            FROM system_epochs
            ORDER BY started_at_ms ASC
            """
        )
        defer { sqlite3_finalize(statement) }

        var values: [MonitorSystemEpoch] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw Self.sqliteReadError(database, fallback: "Could not read system epochs.")
            }
            values.append(
                MonitorSystemEpoch(
                    bootID: text(statement, column: 0),
                    startedAt: Self.date(milliseconds: sqlite3_column_int64(statement, 1)),
                    osVersion: text(statement, column: 2),
                    osBuild: text(statement, column: 3),
                    model: text(statement, column: 4),
                    chip: text(statement, column: 5),
                    memoryBytes: UInt64(clamping: sqlite3_column_int64(statement, 6)),
                    diskTotalBytes: UInt64(clamping: sqlite3_column_int64(statement, 7)),
                    ssdModel: optionalText(statement, column: 8)
                )
            )
        }
        return values
    }

    func latestSampleDate() throws -> Date? {
        let database = try readyDatabase()
        let statement = try prepare(database, "SELECT MAX(sampled_at_ms) FROM samples")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.sqliteReadError(database, fallback: "Could not read the latest sample.")
        }
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return Self.date(milliseconds: sqlite3_column_int64(statement, 0))
    }

    func sampleCount() throws -> Int {
        let database = try readyDatabase()
        return try count(database, table: "samples")
    }

    func prune(now: Date) throws {
        let database = try readyDatabase()
        let cutoff = now.addingTimeInterval(-configuration.maximumAge)
        let cutoffMilliseconds = Self.milliseconds(cutoff)

        try transaction(database) {
            try execute(
                database,
                "DELETE FROM samples WHERE sampled_at_ms < ?",
                bindings: [.int64(cutoffMilliseconds)]
            )
            try execute(
                database,
                "DELETE FROM events WHERE occurred_at_ms < ?",
                bindings: [.int64(cutoffMilliseconds)]
            )
            try execute(
                database,
                """
                DELETE FROM gaps
                WHERE started_at_ms < ?
                  AND (ended_at_ms IS NULL OR ended_at_ms < ?)
                """,
                bindings: [.int64(cutoffMilliseconds), .int64(cutoffMilliseconds)]
            )
            try execute(
                database,
                """
                DELETE FROM system_epochs
                WHERE boot_id NOT IN (
                    SELECT boot_id FROM samples
                    UNION SELECT boot_id FROM events
                    UNION SELECT boot_id FROM gaps
                )
                """
            )
            try execute(
                database,
                "UPDATE gaps SET ended_at_ms = started_at_ms WHERE ended_at_ms IS NULL AND started_at_ms < ?",
                bindings: [.int64(cutoffMilliseconds)]
            )
        }

        try checkpoint(truncate: true)
        try enforceSizeLimit(database: database)
        try checkpointIfNeeded()
    }

    func deleteAll() throws {
        let database = try readyDatabase()
        try transaction(database) {
            for table in ["samples", "events", "gaps", "system_epochs"] {
                try execute(database, "DELETE FROM \(table)")
            }
        }
        try checkpoint(truncate: true)
    }

    // MARK: - Opening and schema

    private static func openDatabase(path: URL) throws -> MonitorHistorySQLiteConnection {
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw MonitorHistoryStoreError.openFailed(error.localizedDescription)
        }

        do {
            let database = try openRaw(path: path)
            do {
                try validate(database)
                try configure(database)
                try migrate(database)
                applyFilePermissions(path)
                return MonitorHistorySQLiteConnection(database: database)
            } catch {
                sqlite3_close_v2(database)
                throw error
            }
        } catch let failure as MonitorHistorySQLiteFailure {
            guard failure.code == SQLITE_CORRUPT || failure.code == SQLITE_NOTADB else {
                throw MonitorHistoryStoreError.openFailed(failure.message)
            }
            try preserveCorruptDatabase(path: path)
            let database = try openRaw(path: path)
            do {
                try validate(database)
                try configure(database)
                try migrate(database)
                applyFilePermissions(path)
                return MonitorHistorySQLiteConnection(database: database)
            } catch let failure as MonitorHistorySQLiteFailure {
                sqlite3_close_v2(database)
                throw MonitorHistoryStoreError.openFailed(failure.message)
            }
        }
    }

    private static func openRaw(path: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Could not open the database."
            if let database { sqlite3_close_v2(database) }
            throw MonitorHistorySQLiteFailure(code: result, message: message)
        }
        return database
    }

    private static func validate(_ database: OpaquePointer) throws {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, "PRAGMA quick_check", -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw MonitorHistorySQLiteFailure(
                code: result,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW, text(statement, column: 0).lowercased() == "ok" else {
            throw MonitorHistorySQLiteFailure(
                code: step == SQLITE_ROW ? SQLITE_CORRUPT : step,
                message: "The history database failed quick_check."
            )
        }
    }

    private static func configure(_ database: OpaquePointer) throws {
        sqlite3_busy_timeout(database, 1_000)
        try execute(database, "PRAGMA journal_mode = WAL")
        try execute(database, "PRAGMA synchronous = NORMAL")
        try execute(database, "PRAGMA foreign_keys = ON")
        try execute(database, "PRAGMA wal_autocheckpoint = 1000")
        try execute(database, "PRAGMA temp_store = MEMORY")
    }

    private static func migrate(_ database: OpaquePointer) throws {
        let version = try readUserVersion(database)
        guard version <= schemaVersion else {
            throw MonitorHistoryStoreError.unsupportedSchema(version)
        }
        guard version < schemaVersion else { return }

        try transaction(database) {
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS metadata (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                ) STRICT
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS samples (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sampled_at_ms INTEGER NOT NULL,
                    monotonic_ns INTEGER NOT NULL CHECK (monotonic_ns >= 0),
                    boot_id TEXT NOT NULL CHECK (length(boot_id) > 0),
                    power_source TEXT NOT NULL,
                    thermal_state TEXT NOT NULL,
                    cpu_usage REAL,
                    cpu_load_1 REAL,
                    cpu_core_count INTEGER,
                    gpu_usage REAL,
                    gpu_memory_bytes REAL,
                    memory_used_bytes REAL,
                    memory_total_bytes REAL,
                    memory_pressure TEXT,
                    swap_used_bytes REAL,
                    disk_read_bps REAL,
                    disk_write_bps REAL,
                    disk_used_bytes REAL,
                    disk_free_bytes REAL,
                    network_receive_bps REAL,
                    network_transmit_bps REAL,
                    battery_percent REAL,
                    battery_temp_c REAL,
                    battery_health_pct REAL,
                    system_power_w REAL,
                    battery_power_w REAL,
                    display_state TEXT NOT NULL,
                    lid_state TEXT NOT NULL,
                    sample_kind TEXT NOT NULL,
                    quality TEXT NOT NULL
                ) STRICT
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    occurred_at_ms INTEGER NOT NULL,
                    boot_id TEXT NOT NULL CHECK (length(boot_id) > 0),
                    kind TEXT NOT NULL,
                    detail_code TEXT NOT NULL DEFAULT '',
                    source TEXT NOT NULL,
                    confidence TEXT NOT NULL,
                    UNIQUE (occurred_at_ms, boot_id, kind, detail_code)
                ) STRICT
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS gaps (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at_ms INTEGER NOT NULL,
                    ended_at_ms INTEGER,
                    boot_id TEXT NOT NULL CHECK (length(boot_id) > 0),
                    reason TEXT NOT NULL,
                    CHECK (ended_at_ms IS NULL OR ended_at_ms >= started_at_ms)
                ) STRICT
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS system_epochs (
                    boot_id TEXT PRIMARY KEY CHECK (length(boot_id) > 0),
                    started_at_ms INTEGER NOT NULL,
                    os_version TEXT NOT NULL,
                    os_build TEXT NOT NULL,
                    model TEXT NOT NULL,
                    chip TEXT NOT NULL,
                    memory_bytes INTEGER NOT NULL CHECK (memory_bytes >= 0),
                    disk_total_bytes INTEGER NOT NULL CHECK (disk_total_bytes >= 0),
                    ssd_model TEXT
                ) STRICT
                """
            )
            try execute(
                database,
                "CREATE INDEX IF NOT EXISTS samples_by_time ON samples(sampled_at_ms, id)"
            )
            try execute(
                database,
                "CREATE INDEX IF NOT EXISTS samples_by_boot ON samples(boot_id, sampled_at_ms)"
            )
            try execute(
                database,
                "CREATE INDEX IF NOT EXISTS events_by_time ON events(occurred_at_ms, id)"
            )
            try execute(
                database,
                "CREATE INDEX IF NOT EXISTS gaps_by_time ON gaps(started_at_ms, ended_at_ms)"
            )
            try execute(
                database,
                "INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', '1')"
            )
            try execute(database, "PRAGMA user_version = 1")
        }
    }

    private static func preserveCorruptDatabase(path: URL) throws {
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        let backupBase = "\(path.deletingPathExtension().lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970 * 1000)).\(path.pathExtension)"
        let backupURL = path.deletingLastPathComponent().appendingPathComponent(backupBase)
        do {
            try FileManager.default.moveItem(at: path, to: backupURL)
            for suffix in ["-wal", "-shm"] {
                let source = URL(fileURLWithPath: path.path + suffix)
                if FileManager.default.fileExists(atPath: source.path) {
                    let target = URL(fileURLWithPath: backupURL.path + suffix)
                    try FileManager.default.moveItem(at: source, to: target)
                }
            }
        } catch {
            throw MonitorHistoryStoreError.openFailed(
                "Could not preserve the corrupt history database: \(error.localizedDescription)"
            )
        }
    }

    private static func applyFilePermissions(_ path: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }

    // MARK: - Reading and writing samples

    private func bindSample(_ sample: MonitorHistorySample, to statement: OpaquePointer) throws {
        try bindInt64(statement, index: 1, value: Self.milliseconds(sample.sampledAt))
        try bindUInt64(statement, index: 2, value: sample.monotonicNanoseconds)
        try bindText(statement, index: 3, value: sample.bootID)
        try bindText(statement, index: 4, value: sample.powerSource.rawValue)
        try bindText(statement, index: 5, value: sample.thermalState.rawValue)
        try bindOptionalDouble(statement, index: 6, value: sample.cpuUsage)
        try bindOptionalDouble(statement, index: 7, value: sample.cpuLoad1)
        try bindOptionalInt(statement, index: 8, value: sample.cpuCoreCount)
        try bindOptionalDouble(statement, index: 9, value: sample.gpuUsage)
        try bindOptionalDouble(statement, index: 10, value: sample.gpuMemoryBytes)
        try bindOptionalDouble(statement, index: 11, value: sample.memoryUsedBytes)
        try bindOptionalDouble(statement, index: 12, value: sample.memoryTotalBytes)
        try bindOptionalText(statement, index: 13, value: sample.memoryPressure?.rawValue)
        try bindOptionalDouble(statement, index: 14, value: sample.swapUsedBytes)
        try bindOptionalDouble(statement, index: 15, value: sample.diskReadBytesPerSecond)
        try bindOptionalDouble(statement, index: 16, value: sample.diskWriteBytesPerSecond)
        try bindOptionalDouble(statement, index: 17, value: sample.diskUsedBytes)
        try bindOptionalDouble(statement, index: 18, value: sample.diskFreeBytes)
        try bindOptionalDouble(statement, index: 19, value: sample.networkReceiveBytesPerSecond)
        try bindOptionalDouble(statement, index: 20, value: sample.networkTransmitBytesPerSecond)
        try bindOptionalDouble(statement, index: 21, value: sample.batteryPercent)
        try bindOptionalDouble(statement, index: 22, value: sample.batteryTemperatureCelsius)
        try bindOptionalDouble(statement, index: 23, value: sample.batteryHealthPercent)
        try bindOptionalDouble(statement, index: 24, value: sample.systemPowerWatts)
        try bindOptionalDouble(statement, index: 25, value: sample.batteryPowerWatts)
        try bindText(statement, index: 26, value: sample.displayState.rawValue)
        try bindText(statement, index: 27, value: sample.lidState.rawValue)
        try bindText(statement, index: 28, value: sample.kind.rawValue)
        try bindText(statement, index: 29, value: sample.quality.rawValue)
    }

    private func sample(from statement: OpaquePointer) throws -> MonitorHistorySample {
        guard let powerSource = MonitorHistorySample.PowerSource(rawValue: text(statement, column: 3)),
              let thermalState = MonitorHistorySample.ThermalState(rawValue: text(statement, column: 4)),
              let displayState = MonitorHistorySample.DisplayState(rawValue: text(statement, column: 25)),
              let lidState = MonitorHistorySample.LidState(rawValue: text(statement, column: 26)),
              let kind = MonitorHistorySample.Kind(rawValue: text(statement, column: 27)),
              let quality = MonitorHistorySample.Quality(rawValue: text(statement, column: 28))
        else {
            throw MonitorHistoryStoreError.readFailed("A performance sample has an unknown enum value.")
        }
        let pressure = optionalText(statement, column: 12).flatMap(MonitorHistorySample.MemoryPressure.init(rawValue:))
        return MonitorHistorySample(
            sampledAt: Self.date(milliseconds: sqlite3_column_int64(statement, 0)),
            monotonicNanoseconds: UInt64(clamping: sqlite3_column_int64(statement, 1)),
            bootID: text(statement, column: 2),
            powerSource: powerSource,
            thermalState: thermalState,
            cpuUsage: optionalDouble(statement, column: 5),
            cpuLoad1: optionalDouble(statement, column: 6),
            cpuCoreCount: optionalInt(statement, column: 7),
            gpuUsage: optionalDouble(statement, column: 8),
            gpuMemoryBytes: optionalDouble(statement, column: 9),
            memoryUsedBytes: optionalDouble(statement, column: 10),
            memoryTotalBytes: optionalDouble(statement, column: 11),
            memoryPressure: pressure,
            swapUsedBytes: optionalDouble(statement, column: 13),
            diskReadBytesPerSecond: optionalDouble(statement, column: 14),
            diskWriteBytesPerSecond: optionalDouble(statement, column: 15),
            diskUsedBytes: optionalDouble(statement, column: 16),
            diskFreeBytes: optionalDouble(statement, column: 17),
            networkReceiveBytesPerSecond: optionalDouble(statement, column: 18),
            networkTransmitBytesPerSecond: optionalDouble(statement, column: 19),
            batteryPercent: optionalDouble(statement, column: 20),
            batteryTemperatureCelsius: optionalDouble(statement, column: 21),
            batteryHealthPercent: optionalDouble(statement, column: 22),
            systemPowerWatts: optionalDouble(statement, column: 23),
            batteryPowerWatts: optionalDouble(statement, column: 24),
            displayState: displayState,
            lidState: lidState,
            kind: kind,
            quality: quality
        )
    }

    // MARK: - Retention

    private func enforceSizeLimit(database: OpaquePointer) throws {
        var size = Self.databaseSizeBytes(path: path)
        guard size > configuration.maximumBytes else { return }

        while size > configuration.maximumBytes {
            let sampleTotal = try count(database, table: "samples")
            if sampleTotal > 0 {
                let deleteCount = max(256, sampleTotal / 10)
                try execute(
                    database,
                    """
                    DELETE FROM samples
                    WHERE id IN (
                        SELECT id FROM samples
                        ORDER BY sampled_at_ms ASC, id ASC
                        LIMIT ?
                    )
                    """,
                    bindings: [.int64(Int64(deleteCount))]
                )
            } else {
                let eventTotal = try count(database, table: "events")
                if eventTotal > 0 {
                    try execute(
                        database,
                        """
                        DELETE FROM events
                        WHERE id IN (
                            SELECT id FROM events
                            ORDER BY occurred_at_ms ASC, id ASC
                            LIMIT 256
                        )
                        """
                    )
                } else {
                    let gapTotal = try count(database, table: "gaps")
                    guard gapTotal > 0 else { break }
                    try execute(
                        database,
                        """
                        DELETE FROM gaps
                        WHERE id IN (
                            SELECT id FROM gaps
                            ORDER BY started_at_ms ASC, id ASC
                            LIMIT 256
                        )
                        """
                    )
                }
            }
            try checkpoint(truncate: true)
            size = Self.databaseSizeBytes(path: path)
        }

        if size > configuration.maximumBytes {
            try execute(database, "VACUUM")
            try checkpoint(truncate: true)
        }
    }

    private func checkpointIfNeeded() throws {
        guard configuration.maximumWALBytes > 0 else { return }
        let walURL = URL(fileURLWithPath: path.path + "-wal")
        let walBytes = Self.fileSize(walURL)
        if walBytes > configuration.maximumWALBytes {
            try checkpoint(truncate: true)
        }
    }

    private func checkpoint(truncate: Bool) throws {
        let database = try readyDatabase()
        try executeAllowingRows(
            database,
            truncate ? "PRAGMA wal_checkpoint(TRUNCATE)" : "PRAGMA wal_checkpoint(PASSIVE)"
        )
    }

    // MARK: - Helpers

    private func readyDatabase() throws -> OpaquePointer {
        if let openingError { throw openingError }
        guard let connection else {
            throw MonitorHistoryStoreError.openFailed("The database connection is unavailable.")
        }
        return connection.database
    }

    private func transaction<T>(_ database: OpaquePointer, _ body: () throws -> T) throws -> T {
        try Self.transaction(database, body)
    }

    private static func transaction<T>(
        _ database: OpaquePointer,
        _ body: () throws -> T
    ) throws -> T {
        try execute(database, "BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute(database, "COMMIT")
            return value
        } catch {
            try? execute(database, "ROLLBACK")
            throw error
        }
    }

    private func bindRange(_ statement: OpaquePointer, start: Date, end: Date) throws {
        try bindInt64(statement, index: 1, value: Self.milliseconds(start))
        try bindInt64(statement, index: 2, value: Self.milliseconds(end))
    }

    private func count(_ database: OpaquePointer, table: String) throws -> Int {
        let statement = try prepare(database, "SELECT COUNT(*) FROM \(table)")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.sqliteReadError(database, fallback: "Could not count \(table).")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func readUserVersion(_ database: OpaquePointer) throws -> Int {
        try Self.readUserVersion(database)
    }

    private static func readUserVersion(_ database: OpaquePointer) throws -> Int {
        let statement = try prepare(database, "PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw MonitorHistorySQLiteFailure(
                code: SQLITE_ERROR,
                message: "Could not read the history schema version."
            )
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        try Self.prepare(database, sql)
    }

    private static func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw Self.sqliteError(database, fallback: "Could not prepare a database statement.")
        }
        return statement
    }

    private enum Binding {
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
            throw MonitorHistorySQLiteFailure(code: result, message: detail)
        }
        sqlite3_free(message)
    }

    private func executeAllowingRows(_ database: OpaquePointer, _ sql: String) throws {
        let statement = try prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else {
                throw Self.sqliteError(database, fallback: "Could not run a database pragma.")
            }
        }
    }

    private func bindText(_ statement: OpaquePointer, index: Int32, value: String) throws {
        try Self.bindText(statement, index: index, value: value)
    }

    private static func bindText(
        _ statement: OpaquePointer,
        index: Int32,
        value: String
    ) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw Self.sqliteError(nil, fallback: "Could not bind history text.")
        }
    }

    private func bindOptionalText(
        _ statement: OpaquePointer,
        index: Int32,
        value: String?
    ) throws {
        if let value {
            try bindText(statement, index: index, value: value)
        } else {
            try bindNull(statement, index: index)
        }
    }

    private func bindInt64(_ statement: OpaquePointer, index: Int32, value: Int64) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw MonitorHistoryStoreError.writeFailed("Could not bind a history integer.")
        }
    }

    private func bindUInt64(_ statement: OpaquePointer, index: Int32, value: UInt64) throws {
        try bindInt64(statement, index: index, value: Int64(clamping: value))
    }

    private func bindOptionalInt(
        _ statement: OpaquePointer,
        index: Int32,
        value: Int?
    ) throws {
        if let value {
            try bindInt64(statement, index: index, value: Int64(clamping: value))
        } else {
            try bindNull(statement, index: index)
        }
    }

    private func bindOptionalDouble(
        _ statement: OpaquePointer,
        index: Int32,
        value: Double?
    ) throws {
        if let value, value.isFinite {
            guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
                throw MonitorHistoryStoreError.writeFailed("Could not bind a history number.")
            }
        } else {
            try bindNull(statement, index: index)
        }
    }

    private func bindNull(_ statement: OpaquePointer, index: Int32) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw MonitorHistoryStoreError.writeFailed("Could not bind a null history value.")
        }
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.sqliteError(database, fallback: "Could not store performance history.")
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        Self.text(statement, column: column)
    }

    private static func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column: column)
    }

    private func optionalDouble(_ statement: OpaquePointer, column: Int32) -> Double? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, column)
    }

    private func optionalInt(_ statement: OpaquePointer, column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, column))
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func databaseSizeBytes(path: URL) -> Int64 {
        fileSize(path) + fileSize(URL(fileURLWithPath: path.path + "-wal"))
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return bytes.int64Value
    }

    private static func sqliteError(
        _ database: OpaquePointer?,
        fallback: String
    ) -> MonitorHistoryStoreError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? ""
        return .writeFailed(message.isEmpty ? fallback : message)
    }

    private static func sqliteReadError(
        _ database: OpaquePointer?,
        fallback: String
    ) -> MonitorHistoryStoreError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? ""
        return .readFailed(message.isEmpty ? fallback : message)
    }

    private static func storeError(_ error: Error) -> MonitorHistoryStoreError {
        if let error = error as? MonitorHistoryStoreError { return error }
        if let error = error as? MonitorHistorySQLiteFailure {
            return .openFailed(error.message)
        }
        return .openFailed(error.localizedDescription)
    }
}
