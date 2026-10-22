import Foundation

/// 一次可持久化的 macOS 性能样本。
///
/// 这里只保存报告需要的系统指标。
/// 不保存进程名、应用路径、网络接口名称或用户内容。
enum MonitorHistoryCadence {
    static let pluggedInInterval: TimeInterval = 30
    static let batteryInterval: TimeInterval = 60

    static func interval(for sample: MonitorHistorySample) -> TimeInterval {
        sample.powerSource == .battery ? batteryInterval : pluggedInInterval
    }

    static func gapThreshold(for interval: TimeInterval) -> TimeInterval {
        max(interval * 2.5, 5)
    }
}

struct MonitorHistorySample: Equatable, Sendable {
    enum PowerSource: String, CaseIterable, Sendable {
        case ac
        case battery
        case unknown
    }

    enum ThermalState: String, CaseIterable, Sendable {
        case nominal
        case fair
        case serious
        case critical
    }

    enum MemoryPressure: String, CaseIterable, Sendable {
        case normal
        case warning
        case critical
    }

    enum DisplayState: String, CaseIterable, Sendable {
        case on
        case off
        case unknown
    }

    enum LidState: String, CaseIterable, Sendable {
        case open
        case closed
        case unknown
    }

    enum Kind: String, CaseIterable, Sendable {
        case periodic
        case event
        case wake
    }

    enum Quality: String, CaseIterable, Sendable {
        case complete
        case partial
    }

    let sampledAt: Date
    let monotonicNanoseconds: UInt64
    let bootID: String
    let powerSource: PowerSource
    let thermalState: ThermalState
    let cpuUsage: Double?
    let cpuLoad1: Double?
    let cpuCoreCount: Int?
    let gpuUsage: Double?
    let gpuMemoryBytes: Double?
    let memoryUsedBytes: Double?
    let memoryTotalBytes: Double?
    let memoryPressure: MemoryPressure?
    let swapUsedBytes: Double?
    let diskReadBytesPerSecond: Double?
    let diskWriteBytesPerSecond: Double?
    let diskUsedBytes: Double?
    let diskFreeBytes: Double?
    let networkReceiveBytesPerSecond: Double?
    let networkTransmitBytesPerSecond: Double?
    let batteryPercent: Double?
    let batteryTemperatureCelsius: Double?
    let batteryHealthPercent: Double?
    let systemPowerWatts: Double?
    let batteryPowerWatts: Double?
    let displayState: DisplayState
    let lidState: LidState
    let kind: Kind
    let quality: Quality

    init(
        sampledAt: Date,
        monotonicNanoseconds: UInt64,
        bootID: String,
        powerSource: PowerSource = .unknown,
        thermalState: ThermalState = .nominal,
        cpuUsage: Double? = nil,
        cpuLoad1: Double? = nil,
        cpuCoreCount: Int? = nil,
        gpuUsage: Double? = nil,
        gpuMemoryBytes: Double? = nil,
        memoryUsedBytes: Double? = nil,
        memoryTotalBytes: Double? = nil,
        memoryPressure: MemoryPressure? = nil,
        swapUsedBytes: Double? = nil,
        diskReadBytesPerSecond: Double? = nil,
        diskWriteBytesPerSecond: Double? = nil,
        diskUsedBytes: Double? = nil,
        diskFreeBytes: Double? = nil,
        networkReceiveBytesPerSecond: Double? = nil,
        networkTransmitBytesPerSecond: Double? = nil,
        batteryPercent: Double? = nil,
        batteryTemperatureCelsius: Double? = nil,
        batteryHealthPercent: Double? = nil,
        systemPowerWatts: Double? = nil,
        batteryPowerWatts: Double? = nil,
        displayState: DisplayState = .unknown,
        lidState: LidState = .unknown,
        kind: Kind = .periodic,
        quality: Quality = .complete
    ) {
        self.sampledAt = sampledAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.bootID = bootID
        self.powerSource = powerSource
        self.thermalState = thermalState
        self.cpuUsage = cpuUsage
        self.cpuLoad1 = cpuLoad1
        self.cpuCoreCount = cpuCoreCount
        self.gpuUsage = gpuUsage
        self.gpuMemoryBytes = gpuMemoryBytes
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPressure = memoryPressure
        self.swapUsedBytes = swapUsedBytes
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.diskUsedBytes = diskUsedBytes
        self.diskFreeBytes = diskFreeBytes
        self.networkReceiveBytesPerSecond = networkReceiveBytesPerSecond
        self.networkTransmitBytesPerSecond = networkTransmitBytesPerSecond
        self.batteryPercent = batteryPercent
        self.batteryTemperatureCelsius = batteryTemperatureCelsius
        self.batteryHealthPercent = batteryHealthPercent
        self.systemPowerWatts = systemPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
        self.displayState = displayState
        self.lidState = lidState
        self.kind = kind
        self.quality = quality
    }

    func replacingKind(_ kind: Kind) -> MonitorHistorySample {
        MonitorHistorySample(
            sampledAt: sampledAt,
            monotonicNanoseconds: monotonicNanoseconds,
            bootID: bootID,
            powerSource: powerSource,
            thermalState: thermalState,
            cpuUsage: cpuUsage,
            cpuLoad1: cpuLoad1,
            cpuCoreCount: cpuCoreCount,
            gpuUsage: gpuUsage,
            gpuMemoryBytes: gpuMemoryBytes,
            memoryUsedBytes: memoryUsedBytes,
            memoryTotalBytes: memoryTotalBytes,
            memoryPressure: memoryPressure,
            swapUsedBytes: swapUsedBytes,
            diskReadBytesPerSecond: diskReadBytesPerSecond,
            diskWriteBytesPerSecond: diskWriteBytesPerSecond,
            diskUsedBytes: diskUsedBytes,
            diskFreeBytes: diskFreeBytes,
            networkReceiveBytesPerSecond: networkReceiveBytesPerSecond,
            networkTransmitBytesPerSecond: networkTransmitBytesPerSecond,
            batteryPercent: batteryPercent,
            batteryTemperatureCelsius: batteryTemperatureCelsius,
            batteryHealthPercent: batteryHealthPercent,
            systemPowerWatts: systemPowerWatts,
            batteryPowerWatts: batteryPowerWatts,
            displayState: displayState,
            lidState: lidState,
            kind: kind,
            quality: quality
        )
    }
}

/// 一条有固定类型的历史事件。
struct MonitorHistoryEvent: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case sleep
        case darkWake = "dark_wake"
        case fullWake = "full_wake"
        case adapterConnected = "adapter_connected"
        case adapterDisconnected = "adapter_disconnected"
        case thermalNominal = "thermal_nominal"
        case thermalFair = "thermal_fair"
        case thermalSerious = "thermal_serious"
        case thermalCritical = "thermal_critical"
        case boot
        case shutdownOrCrash = "shutdown_or_crash"
        case appCrashSummary = "app_crash_summary"
    }

    enum Source: String, CaseIterable, Sendable {
        case covio
        case oslog
        case diagnosticReport = "diagnostic_report"
    }

    enum Confidence: String, CaseIterable, Sendable {
        case observed
        case bestEffort = "best_effort"
    }

    let occurredAt: Date
    let bootID: String
    let kind: Kind
    let detailCode: String
    let source: Source
    let confidence: Confidence

    init(
        occurredAt: Date,
        bootID: String,
        kind: Kind,
        detailCode: String = "",
        source: Source = .covio,
        confidence: Confidence = .observed
    ) {
        self.occurredAt = occurredAt
        self.bootID = bootID
        self.kind = kind
        self.detailCode = detailCode
        self.source = source
        self.confidence = confidence
    }
}

/// 一段没有有效样本的时间。
struct MonitorHistoryGap: Equatable, Sendable {
    enum Reason: String, CaseIterable, Hashable, Sendable {
        case sleep
        case appStopped = "app_stopped"
        case reboot
        case clockChange = "clock_change"
        case writeFailed = "write_failed"
        case unknown
    }

    let startedAt: Date
    let endedAt: Date?
    let bootID: String
    let reason: Reason

    init(startedAt: Date, endedAt: Date?, bootID: String, reason: Reason) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bootID = bootID
        self.reason = reason
    }
}

/// 一个 boot session 使用的系统与硬件元数据。
struct MonitorSystemEpoch: Equatable, Sendable {
    let bootID: String
    let startedAt: Date
    let osVersion: String
    let osBuild: String
    let model: String
    let chip: String
    let memoryBytes: UInt64
    let diskTotalBytes: UInt64
    let ssdModel: String?

    init(
        bootID: String,
        startedAt: Date,
        osVersion: String,
        osBuild: String,
        model: String,
        chip: String,
        memoryBytes: UInt64,
        diskTotalBytes: UInt64,
        ssdModel: String? = nil
    ) {
        self.bootID = bootID
        self.startedAt = startedAt
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.model = model
        self.chip = chip
        self.memoryBytes = memoryBytes
        self.diskTotalBytes = diskTotalBytes
        self.ssdModel = ssdModel
    }
}

enum MonitorHistoryStoreError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "History store could not open: \(message)"
        case .readFailed(let message):
            "History store could not read: \(message)"
        case .writeFailed(let message):
            "History store could not write: \(message)"
        case .unsupportedSchema(let version):
            "History store schema version \(version) is newer than this build."
        }
    }
}

struct MonitorHistoryStoreConfiguration: Equatable, Sendable {
    var maximumAge: TimeInterval
    var maximumBytes: Int64
    var maximumWALBytes: Int64

    static let standard = MonitorHistoryStoreConfiguration(
        maximumAge: 14 * 24 * 60 * 60,
        maximumBytes: 64 * 1024 * 1024,
        maximumWALBytes: 16 * 1024 * 1024
    )

    init(
        maximumAge: TimeInterval,
        maximumBytes: Int64,
        maximumWALBytes: Int64
    ) {
        self.maximumAge = max(60, maximumAge)
        self.maximumBytes = max(32 * 1024, maximumBytes)
        self.maximumWALBytes = max(0, maximumWALBytes)
    }
}

protocol MonitorHistoryStoring: Sendable {
    func insert(samples: [MonitorHistorySample]) async throws
    func insert(event: MonitorHistoryEvent) async throws
    func insert(gap: MonitorHistoryGap) async throws
    func upsert(systemEpoch: MonitorSystemEpoch) async throws
    func closeOpenGap(bootID: String, endedAt: Date) async throws
    func samples(from start: Date, to end: Date) async throws -> [MonitorHistorySample]
    func events(from start: Date, to end: Date) async throws -> [MonitorHistoryEvent]
    func gaps(overlapping start: Date, through end: Date) async throws -> [MonitorHistoryGap]
    func systemEpochs() async throws -> [MonitorSystemEpoch]
    func latestSampleDate() async throws -> Date?
    func sampleCount() async throws -> Int
    func prune(now: Date) async throws
    func deleteAll() async throws
}
