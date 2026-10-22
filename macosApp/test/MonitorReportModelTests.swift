import XCTest
@testable import Covio

@MainActor
final class MonitorReportModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-report-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testModelBuildsAndClearsHistory() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.insert(samples: [sample(at: now.addingTimeInterval(-60))])
        let model = MonitorReportModel(store: store, now: { now })

        await model.reload()

        XCTAssertEqual(model.report?.coverage.sampleCount, 1)
        XCTAssertNil(model.errorMessage)

        await model.clearHistory()

        let remaining = try await store.sampleCount()
        XCTAssertNil(model.report)
        XCTAssertEqual(remaining, 0)
    }

    func testSelectingLastTenDaysUsesFortyEightMillionSecondWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = MonitorReportModel(
            store: MonitorHistoryStore(path: databaseURL),
            now: { now }
        )

        model.selectLastTenDays()

        XCTAssertEqual(model.endDate, now)
        XCTAssertEqual(model.startDate, now.addingTimeInterval(-10 * 24 * 60 * 60))
    }

    private var databaseURL: URL {
        directory.appendingPathComponent("Monitor/history.sqlite")
    }

    private func sample(at date: Date) -> MonitorHistorySample {
        MonitorHistorySample(
            sampledAt: date,
            monotonicNanoseconds: 1,
            bootID: "boot-1",
            powerSource: .ac,
            thermalState: .nominal,
            cpuUsage: 0.2,
            cpuLoad1: 1,
            cpuCoreCount: 10,
            memoryUsedBytes: 1,
            memoryTotalBytes: 2,
            memoryPressure: .normal,
            diskReadBytesPerSecond: 1,
            diskWriteBytesPerSecond: 1,
            diskUsedBytes: 1,
            diskFreeBytes: 9,
            networkReceiveBytesPerSecond: 1,
            networkTransmitBytesPerSecond: 1,
            batteryPercent: 80,
            batteryTemperatureCelsius: 32,
            systemPowerWatts: 10,
            displayState: .on,
            lidState: .open,
            kind: .periodic,
            quality: .complete
        )
    }
}
