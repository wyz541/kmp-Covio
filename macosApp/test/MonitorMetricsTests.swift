import XCTest
@testable import Covio

final class MonitorMetricsTests: XCTestCase {
    func testRateUsesElapsedTime() {
        XCTAssertEqual(
            MonitorRate.perSecond(current: 1_040, previous: 40, elapsed: 2),
            500,
            accuracy: 0.001
        )
    }

    func testRateRejectsCounterReset() {
        XCTAssertEqual(
            MonitorRate.perSecond(current: 10, previous: 100, elapsed: 1),
            0
        )
    }

    func testHistoryKeepsNewestSamples() {
        var history = MonitorHistory(capacity: 3)
        for index in 0..<5 {
            history.append(snapshot(cpu: Double(index) / 10))
        }
        XCTAssertEqual(history.cpu, [0.2, 0.3, 0.4])
    }

    func testHistoryClampsInvalidValues() {
        var history = MonitorHistory(capacity: 2)
        history.append(snapshot(cpu: 1.4))
        history.append(snapshot(cpu: -0.2))
        XCTAssertEqual(history.cpu, [1.4, 0])
    }

    func testPercentFormattingClampsAndRounds() {
        XCTAssertEqual(MonitorFormat.percent(-0.4), "0%")
        XCTAssertEqual(MonitorFormat.percent(0.376), "38%")
        XCTAssertEqual(MonitorFormat.percent(1.8), "100%")
    }

    func testByteFormattingUsesDecimalUnits() {
        XCTAssertEqual(MonitorFormat.bytes(0), "0.00 B")
        XCTAssertEqual(MonitorFormat.bytes(1_500), "1.50 KB")
        XCTAssertEqual(MonitorFormat.bytes(2_500_000), "2.50 MB")
        XCTAssertEqual(MonitorFormat.rate(1_500), "1.50 KB/s")
    }

    func testDurationFormatting() {
        XCTAssertEqual(MonitorFormat.duration(nil), "—")
        XCTAssertEqual(MonitorFormat.duration(30), "<1m")
        XCTAssertEqual(MonitorFormat.duration(3_600), "1h 0m")
        XCTAssertEqual(MonitorFormat.duration(93_600), "1d 2h")
    }

    func testBatteryUsesSlowCadence() {
        let pluggedIn = snapshot(battery: .init(percent: 80, state: .acPower, remaining: nil))
        let onBattery = snapshot(battery: .init(percent: 80, state: .discharging, remaining: 3_600))
        XCTAssertEqual(MonitorCadence.interval(for: pluggedIn), MonitorCadence.pluggedIn)
        XCTAssertEqual(MonitorCadence.interval(for: onBattery), MonitorCadence.onBattery)
    }

    private func snapshot(
        cpu: Double? = nil,
        battery: MonitorSnapshot.Battery? = nil
    ) -> MonitorSnapshot {
        MonitorSnapshot(
            cpu: cpu.map {
                MonitorSnapshot.CPU(
                    usage: $0,
                    perCore: [$0],
                    loadAverage: 0,
                    coreCount: 1,
                    uptime: 1
                )
            },
            gpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: battery,
            thermal: .nominal,
            sampledAt: Date()
        )
    }
}
