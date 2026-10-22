import XCTest
@testable import Covio

final class MonitorReportExportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-report-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testHTMLIsSelfContainedAccessibleAndEscaped() async throws {
        let report = try await makeSmallReport()
        let html = MonitorReportHTMLExporter().html(
            report: report,
            language: .simplifiedChinese
        )

        XCTAssertTrue(html.contains("role=\"img\""))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("&lt;unsafe&gt;"))
        XCTAssertFalse(html.contains("<unsafe>"))
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("@import"))
        XCTAssertFalse(html.contains("http://"))
        XCTAssertFalse(html.contains("https://"))
    }

    func testExportWritesToTheSelectedFile() async throws {
        let report = try await makeSmallReport()
        let destination = directory.appendingPathComponent("report.html")

        try MonitorReportHTMLExporter().write(
            report: report,
            to: destination,
            language: .simplifiedChinese
        )

        let data = try Data(contentsOf: destination)
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("<!doctype html>"))
    }

    func testTenDayReportStaysBelowFiveMiB() async throws {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(10 * 24 * 60 * 60)
        let samples = (0..<28_800).map { index in
            sample(at: start.addingTimeInterval(Double(index) * 30))
        }
        try await store.insert(samples: samples)
        let range = try MonitorReportRange(start: start, end: end)
        let report = try await MonitorReportBuilder(store: store).build(range: range)

        let data = Data(
            MonitorReportHTMLExporter()
                .html(report: report, language: .simplifiedChinese)
                .utf8
        )

        XCTAssertLessThan(data.count, 5 * 1024 * 1024)
    }

    private func makeSmallReport() async throws -> MonitorReport {
        let store = MonitorHistoryStore(path: databaseURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<12).map {
            sample(at: start.addingTimeInterval(Double($0) * 30))
        }
        try await store.insert(samples: samples)
        try await store.upsert(
            systemEpoch: MonitorSystemEpoch(
                bootID: "boot-1",
                startedAt: start.addingTimeInterval(-60),
                osVersion: "27.0.1",
                osBuild: "26A434",
                model: "<unsafe>",
                chip: "Apple M1 Max",
                memoryBytes: 68_719_476_736,
                diskTotalBytes: 994_662_584_320
            )
        )
        let range = try MonitorReportRange(
            start: start,
            end: start.addingTimeInterval(6 * 60),
            bucketSeconds: 60
        )
        return try await MonitorReportBuilder(store: store).build(range: range)
    }

    private var databaseURL: URL {
        directory.appendingPathComponent("Monitor/history.sqlite")
    }

    private func sample(at date: Date) -> MonitorHistorySample {
        MonitorHistorySample(
            sampledAt: date,
            monotonicNanoseconds: UInt64(max(0, date.timeIntervalSince1970 * 1_000_000_000)),
            bootID: "boot-1",
            powerSource: .ac,
            thermalState: .nominal,
            cpuUsage: 0.42,
            cpuLoad1: 2,
            cpuCoreCount: 10,
            gpuUsage: 0.21,
            gpuMemoryBytes: 1_000,
            memoryUsedBytes: 32_000,
            memoryTotalBytes: 64_000,
            memoryPressure: .normal,
            swapUsedBytes: 0,
            diskReadBytesPerSecond: 1_000,
            diskWriteBytesPerSecond: 2_000,
            diskUsedBytes: 200,
            diskFreeBytes: 800,
            networkReceiveBytesPerSecond: 3_000,
            networkTransmitBytesPerSecond: 4_000,
            batteryPercent: 80,
            batteryTemperatureCelsius: 33,
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
