import Foundation

enum MonitorReportError: Error, LocalizedError, Equatable {
    case invalidRange
    case rangeTooLong
    case invalidBucketSize

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            "The report start time must be earlier than the end time."
        case .rangeTooLong:
            "The report range cannot exceed 14 days."
        case .invalidBucketSize:
            "The report bucket size must be between 60 and 3600 seconds."
        }
    }
}

struct MonitorReportRange: Equatable, Sendable {
    static let maximumDays = 14
    static let defaultBucketSeconds = 5 * 60
    static let minimumBucketSeconds = 60
    static let maximumBucketSeconds = 60 * 60

    let start: Date
    let end: Date
    let bucketSeconds: Int

    init(
        start: Date,
        end: Date,
        bucketSeconds: Int = defaultBucketSeconds
    ) throws {
        guard end > start else { throw MonitorReportError.invalidRange }
        guard end.timeIntervalSince(start) <= Double(Self.maximumDays * 24 * 60 * 60) else {
            throw MonitorReportError.rangeTooLong
        }
        guard (Self.minimumBucketSeconds...Self.maximumBucketSeconds).contains(bucketSeconds) else {
            throw MonitorReportError.invalidBucketSize
        }
        self.start = start
        self.end = end
        self.bucketSeconds = bucketSeconds
    }

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

enum MonitorReportMetric: String, CaseIterable, Hashable, Sendable {
    case cpuUsage = "cpu.usage"
    case gpuUsage = "gpu.usage"
    case memoryFraction = "memory.used"
    case swapUsed = "memory.swap"
    case diskReadRate = "disk.read"
    case diskWriteRate = "disk.write"
    case networkReceiveRate = "network.receive"
    case networkTransmitRate = "network.transmit"
    case batteryPercent = "battery.percent"
    case batteryTemperature = "battery.temperature"
    case systemPower = "power.system"
    case batteryPower = "power.battery"
    case cpuTemperature = "cpu.temperature"
    case gpuTemperature = "gpu.temperature"
    case fanRPM = "sensor.fan.rpm"
    case cpuFrequency = "cpu.frequency"
}

struct MonitorReportPeak: Equatable, Sendable {
    let metric: MonitorReportMetric
    let value: Double
    let at: Date
}

struct MonitorReportThresholdInterval: Equatable, Sendable {
    enum Kind: String, Sendable {
        case cpuHigh = "cpu.high"
        case gpuHigh = "gpu.high"
        case lowDiskSpace = "disk.low"
        case batteryHighTemperature = "battery.high-temperature"
        case thermalFair = "thermal.fair"
        case thermalSerious = "thermal.serious"
        case thermalCritical = "thermal.critical"
    }

    let kind: Kind
    let start: Date
    let end: Date
    let peakValue: Double?

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

struct MonitorReportBucket: Equatable, Sendable {
    let start: Date
    let end: Date
    let sampleCount: Int
    let cpuUsage: Double?
    let gpuUsage: Double?
    let memoryFraction: Double?
    let swapUsedBytes: Double?
    let diskReadBytesPerSecond: Double?
    let diskWriteBytesPerSecond: Double?
    let networkReceiveBytesPerSecond: Double?
    let networkTransmitBytesPerSecond: Double?
    let batteryPercent: Double?
    let batteryTemperatureCelsius: Double?
    let systemPowerWatts: Double?
    let batteryPowerWatts: Double?
    let highestMemoryPressure: MonitorHistorySample.MemoryPressure?
    let highestThermalState: MonitorHistorySample.ThermalState?
    let acSampleCount: Int
    let batterySampleCount: Int
}

struct MonitorReportGapSummary: Equatable, Sendable {
    let reason: MonitorHistoryGap.Reason
    let duration: TimeInterval
    let count: Int
}

struct MonitorReportCoverage: Equatable, Sendable {
    let requestedSeconds: TimeInterval
    let observedSeconds: TimeInterval
    let sleepSeconds: TimeInterval
    let unknownSeconds: TimeInterval
    let coverageFraction: Double
    let sampleCount: Int
    let firstSampleAt: Date?
    let lastSampleAt: Date?

    var isPartial: Bool {
        coverageFraction < 0.9
    }
}

struct MonitorReport: Equatable, Sendable {
    let range: MonitorReportRange
    let generatedAt: Date
    let coverage: MonitorReportCoverage
    let buckets: [MonitorReportBucket]
    let peaks: [MonitorReportPeak]
    let thresholdIntervals: [MonitorReportThresholdInterval]
    let events: [MonitorHistoryEvent]
    let gaps: [MonitorHistoryGap]
    let gapSummaries: [MonitorReportGapSummary]
    let systemEpochs: [MonitorSystemEpoch]
    let unavailableMetrics: [MonitorReportMetric]
    let highestMemoryPressure: MonitorHistorySample.MemoryPressure?
    let highestThermalState: MonitorHistorySample.ThermalState?

    var hasData: Bool {
        coverage.sampleCount > 0
    }
}
