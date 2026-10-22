import XCTest
@testable import Covio

final class MonitorReportBuilderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRangeRejectsMoreThanFourteenDays() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertThrowsError(
            try MonitorReportRange(
                start: start,
                end: start.addingTimeInterval(15 * 24 * 60 * 60)
            )
        ) { error in
            XCTAssertEqual(error as? MonitorReportError, .rangeTooLong)
        }
    }

    func testEmptyRangeReturnsExplicitEmptyState() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let range = try MonitorReportRange(
            start: start,
            end: start.addingTimeInterval(24 * 60 * 60)
        )

        let report = try await MonitorReportBuilder(store: store).build(range: range)

        XCTAssertFalse(report.hasData)
        XCTAssertEqual(report.coverage.sampleCount, 0)
        XCTAssertEqual(report.coverage.coverageFraction, 0)
        XCTAssertEqual(report.coverage.unknownSeconds, 24 * 60 * 60, accuracy: 0.001)
        XCTAssertTrue(report.buckets.allSatisfy { $0.sampleCount == 0 })
    }

    func testTenDaySyntheticReportComputesBucketsPeaksAndThresholds() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(10 * 24 * 60 * 60)
        let samples = (0..<28_800).map { index in
            let high = (10_000..<10_010).contains(index)
            let hot = (20_000..<20_005).contains(index)
            return sample(
                at: start.addingTimeInterval(Double(index) * 30),
                cpu: high ? 0.92 : 0.30,
                gpu: high ? 0.86 : 0.20,
                usedDisk: 950,
                freeDisk: 50,
                batteryTemperature: hot ? 47 : 33
            )
        }
        try await store.insert(samples: samples)
        let range = try MonitorReportRange(start: start, end: end)

        let report = try await MonitorReportBuilder(store: store).build(range: range)

        XCTAssertTrue(report.hasData)
        XCTAssertEqual(report.coverage.sampleCount, 28_800)
        XCTAssertEqual(report.coverage.coverageFraction, 1, accuracy: 0.001)
        XCTAssertEqual(report.buckets.count, 2_880)
        XCTAssertEqual(report.buckets.reduce(0) { $0 + $1.sampleCount }, 28_800)
        XCTAssertEqual(
            report.peaks.first { $0.metric == .cpuUsage }?.value ?? 0,
            0.92,
            accuracy: 0.001
        )
        XCTAssertTrue(report.thresholdIntervals.contains { $0.kind == .cpuHigh })
        XCTAssertTrue(report.thresholdIntervals.contains { $0.kind == .gpuHigh })
        XCTAssertTrue(report.thresholdIntervals.contains { $0.kind == .lowDiskSpace })
        XCTAssertTrue(report.thresholdIntervals.contains { $0.kind == .batteryHighTemperature })
        XCTAssertTrue(report.unavailableMetrics.contains(.cpuTemperature))
        XCTAssertTrue(report.unavailableMetrics.contains(.fanRPM))
    }

    func testSleepGapReducesCoverageAndIsSeparatedFromUnknownTime() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(60 * 60)
        let sleepStart = start.addingTimeInterval(10 * 60)
        let sleepEnd = start.addingTimeInterval(20 * 60)
        var samples: [MonitorHistorySample] = []
        for index in 0..<120 {
            let date = start.addingTimeInterval(Double(index) * 30)
            if date >= sleepStart, date < sleepEnd { continue }
            samples.append(sample(at: date))
        }
        try await store.insert(samples: samples)
        try await store.insert(
            gap: MonitorHistoryGap(
                startedAt: sleepStart,
                endedAt: sleepEnd,
                bootID: "boot-1",
                reason: .sleep
            )
        )
        let range = try MonitorReportRange(start: start, end: end)

        let report = try await MonitorReportBuilder(store: store).build(range: range)

        XCTAssertGreaterThan(report.coverage.sleepSeconds, 599)
        XCTAssertLessThan(report.coverage.sleepSeconds, 601)
        XCTAssertLessThan(report.coverage.unknownSeconds, 1)
        XCTAssertTrue(report.coverage.isPartial)
        XCTAssertTrue(report.gapSummaries.contains { $0.reason == .sleep && $0.count == 1 })
    }

    func testEventsAreSortedByTime() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(60 * 60)
        try await store.insert(samples: [sample(at: start)])
        try await store.insert(
            event: MonitorHistoryEvent(
                occurredAt: start.addingTimeInterval(30),
                bootID: "boot-1",
                kind: .fullWake
            )
        )
        try await store.insert(
            event: MonitorHistoryEvent(
                occurredAt: start.addingTimeInterval(10),
                bootID: "boot-1",
                kind: .sleep
            )
        )
        let range = try MonitorReportRange(start: start, end: end)

        let report = try await MonitorReportBuilder(store: store).build(range: range)

        XCTAssertEqual(report.events.map(\.kind), [.sleep, .fullWake])
    }

    private var databaseURL: URL {
        directory.appendingPathComponent("Monitor/history.sqlite")
    }

    private func sample(
        at date: Date,
        cpu: Double = 0.4,
        gpu: Double = 0.2,
        usedDisk: Double = 200,
        freeDisk: Double = 800,
        batteryTemperature: Double = 33
    ) -> MonitorHistorySample {
        MonitorHistorySample(
            sampledAt: date,
            monotonicNanoseconds: UInt64(max(0, date.timeIntervalSince1970 * 1_000_000_000)),
            bootID: "boot-1",
            powerSource: .ac,
            thermalState: .nominal,
            cpuUsage: cpu,
            cpuLoad1: 2,
            cpuCoreCount: 10,
            gpuUsage: gpu,
            gpuMemoryBytes: 2_000,
            memoryUsedBytes: 32_000,
            memoryTotalBytes: 64_000,
            memoryPressure: .normal,
            swapUsedBytes: 0,
            diskReadBytesPerSecond: 1_000,
            diskWriteBytesPerSecond: 2_000,
            diskUsedBytes: usedDisk,
            diskFreeBytes: freeDisk,
            networkReceiveBytesPerSecond: 3_000,
            networkTransmitBytesPerSecond: 4_000,
            batteryPercent: 80,
            batteryTemperatureCelsius: batteryTemperature,
            batteryHealthPercent: 94,
            systemPowerWatts: 18,
            batteryPowerWatts: nil,
            displayState: .on,
            lidState: .open,
            kind: .periodic,
            quality: .complete
        )
    }
}
