import XCTest
@testable import Covio

final class MonitorHistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-monitor-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripPreservesSamplesEventsGapsAndEpochs() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = makeSample(at: start)
        let event = MonitorHistoryEvent(
            occurredAt: start.addingTimeInterval(1),
            bootID: "boot-1",
            kind: .thermalFair,
            detailCode: "fair",
            source: .covio,
            confidence: .observed
        )
        let epoch = MonitorSystemEpoch(
            bootID: "boot-1",
            startedAt: start.addingTimeInterval(-60),
            osVersion: "27.0.1",
            osBuild: "26A434",
            model: "MacBookPro18,2",
            chip: "Apple M1 Max",
            memoryBytes: 68_719_476_736,
            diskTotalBytes: 994_662_584_320,
            ssdModel: "APPLE SSD AP1024R"
        )
        let gap = MonitorHistoryGap(
            startedAt: start.addingTimeInterval(30),
            endedAt: start.addingTimeInterval(60),
            bootID: "boot-1",
            reason: .sleep
        )

        try await store.insert(samples: [sample])
        try await store.insert(event: event)
        try await store.insert(gap: gap)
        try await store.upsert(systemEpoch: epoch)

        let storedSamples = try await store.samples(
            from: start,
            to: start.addingTimeInterval(1)
        )
        let storedEvents = try await store.events(
            from: start,
            to: start.addingTimeInterval(2)
        )
        let storedGaps = try await store.gaps(
            overlapping: start,
            through: start.addingTimeInterval(60)
        )
        let storedEpochs = try await store.systemEpochs()
        XCTAssertEqual(storedSamples, [sample])
        XCTAssertEqual(storedEvents, [event])
        XCTAssertEqual(storedGaps, [gap])
        XCTAssertEqual(storedEpochs, [epoch])
    }

    func testDatabaseReopensWithSchemaVersionOne() async throws {
        let first = MonitorHistoryStore(path: databaseURL)
        let sample = makeSample(at: Date(timeIntervalSince1970: 1_800_000_000))
        try await first.insert(samples: [sample])

        let reopened = MonitorHistoryStore(path: databaseURL)

        let version = try await reopened.schemaVersion()
        let count = try await reopened.sampleCount()
        let latest = try await reopened.latestSampleDate()
        XCTAssertEqual(version, 1)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(
            latest?.timeIntervalSince1970 ?? 0,
            sample.sampledAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testPruneDropsSamplesOlderThanFourteenDays() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = makeSample(at: now.addingTimeInterval(-15 * 24 * 60 * 60))
        let fresh = makeSample(at: now.addingTimeInterval(-60))

        try await store.insert(samples: [old, fresh])
        try await store.prune(now: now)

        let count = try await store.sampleCount()
        let remaining = try await store.samples(
            from: now.addingTimeInterval(-24 * 60 * 60),
            to: now
        )
        XCTAssertEqual(count, 1)
        XCTAssertEqual(remaining.map(\.bootID), ["boot-1"])
    }

    func testPruneEnforcesConfiguredByteLimit() async throws {
        let store = MonitorHistoryStore(
            path: databaseURL,
            configuration: MonitorHistoryStoreConfiguration(
                maximumAge: 14 * 24 * 60 * 60,
                maximumBytes: 64 * 1024,
                maximumWALBytes: 0
            )
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<6_000).map {
            makeSample(at: start.addingTimeInterval(Double($0) * 30))
        }

        try await store.insert(samples: samples)
        let before = try await store.sampleCount()
        try await store.prune(now: start.addingTimeInterval(6_000 * 30))

        let after = try await store.sampleCount()
        let bytes = await store.databaseSizeBytes()
        XCTAssertLessThan(after, before)
        XCTAssertLessThanOrEqual(bytes, 64 * 1024)
    }

    func testClearAllRemovesEveryHistoryRow() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.insert(samples: [makeSample(at: start)])
        try await store.insert(
            event: MonitorHistoryEvent(
                occurredAt: start,
                bootID: "boot-1",
                kind: .sleep
            )
        )
        try await store.insert(
            gap: MonitorHistoryGap(
                startedAt: start,
                endedAt: start.addingTimeInterval(10),
                bootID: "boot-1",
                reason: .sleep
            )
        )
        try await store.upsert(
            systemEpoch: MonitorSystemEpoch(
                bootID: "boot-1",
                startedAt: start,
                osVersion: "27.0.1",
                osBuild: "26A434",
                model: "MacBookPro18,2",
                chip: "Apple M1 Max",
                memoryBytes: 1,
                diskTotalBytes: 1
            )
        )

        try await store.deleteAll()

        let count = try await store.sampleCount()
        let events = try await store.events(from: start, to: start)
        let gaps = try await store.gaps(overlapping: start, through: start)
        let epochs = try await store.systemEpochs()
        XCTAssertEqual(count, 0)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(gaps.isEmpty)
        XCTAssertTrue(epochs.isEmpty)
    }

    func testCorruptDatabaseIsPreservedAndReplaced() async throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a sqlite database".utf8).write(to: databaseURL)
        let store = MonitorHistoryStore(path: databaseURL)

        let version = try await store.schemaVersion()
        XCTAssertEqual(version, 1)

        let names = try FileManager.default.contentsOfDirectory(
            atPath: databaseURL.deletingLastPathComponent().path
        )
        XCTAssertTrue(names.contains { $0.contains(".corrupt-") })
    }

    func testInvalidSampleReturnsWriteFailure() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let invalid = makeSample(at: Date(), bootID: "")

        do {
            try await store.insert(samples: [invalid])
            XCTFail("Expected a write failure")
        } catch let error as MonitorHistoryStoreError {
            guard case .writeFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let count = try await store.sampleCount()
        XCTAssertEqual(count, 0)
    }

    func testOpenGapCanBeClosed() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.insert(
            gap: MonitorHistoryGap(
                startedAt: start,
                endedAt: nil,
                bootID: "boot-1",
                reason: .sleep
            )
        )

        try await store.closeOpenGap(bootID: "boot-1", endedAt: start.addingTimeInterval(90))

        let gaps = try await store.gaps(
            overlapping: start,
            through: start.addingTimeInterval(100)
        )
        let gap = try XCTUnwrap(gaps.first)
        XCTAssertEqual(
            gap.endedAt?.timeIntervalSince1970 ?? 0,
            start.addingTimeInterval(90).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testFourteenDaysOfThirtySecondSamplesStayUnder64MiB() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<40_320).map {
            makeSample(at: start.addingTimeInterval(Double($0) * 30))
        }

        try await store.insert(samples: samples)

        let count = try await store.sampleCount()
        let bytes = await store.databaseSizeBytes()
        XCTAssertEqual(count, 40_320)
        XCTAssertLessThan(bytes, 64 * 1024 * 1024)
    }

    func testDefaultPathSitsUnderMonitorDirectory() {
        XCTAssertEqual(
            AppPaths.monitorHistoryFile.deletingLastPathComponent().lastPathComponent,
            "Monitor"
        )
        XCTAssertEqual(AppPaths.monitorHistoryFile.lastPathComponent, "history.sqlite")
        XCTAssertEqual(
            AppPaths.monitorHistoryFile.deletingLastPathComponent().deletingLastPathComponent(),
            AppPaths.supportDirectory
        )
    }

    private var databaseURL: URL {
        directory.appendingPathComponent("Monitor/history.sqlite")
    }

    private func makeSample(
        at date: Date,
        bootID: String = "boot-1"
    ) -> MonitorHistorySample {
        MonitorHistorySample(
            sampledAt: date,
            monotonicNanoseconds: UInt64(max(0, date.timeIntervalSince1970 * 1_000_000_000)),
            bootID: bootID,
            powerSource: .ac,
            thermalState: .nominal,
            cpuUsage: 0.42,
            cpuLoad1: 2.5,
            cpuCoreCount: 10,
            gpuUsage: 0.31,
            gpuMemoryBytes: 2_048,
            memoryUsedBytes: 34_000_000_000,
            memoryTotalBytes: 68_719_476_736,
            memoryPressure: .normal,
            swapUsedBytes: 0,
            diskReadBytesPerSecond: 1_024,
            diskWriteBytesPerSecond: 2_048,
            diskUsedBytes: 250_000_000_000,
            diskFreeBytes: 700_000_000_000,
            networkReceiveBytesPerSecond: 4_096,
            networkTransmitBytesPerSecond: 1_024,
            batteryPercent: 80,
            batteryTemperatureCelsius: 32.2,
            batteryHealthPercent: 94,
            systemPowerWatts: 18.5,
            batteryPowerWatts: 0,
            displayState: .on,
            lidState: .open,
            kind: .periodic,
            quality: .complete
        )
    }
}
