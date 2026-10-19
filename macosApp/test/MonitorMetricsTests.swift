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
        let pluggedIn = snapshot(power: power(supply: .adapter))
        let onBattery = snapshot(power: power(supply: .battery))
        XCTAssertEqual(MonitorCadence.interval(for: pluggedIn), MonitorCadence.pluggedIn)
        XCTAssertEqual(MonitorCadence.interval(for: onBattery), MonitorCadence.onBattery)
    }

    func testPowerRefreshIsOneSecond() {
        XCTAssertEqual(MonitorPowerFormat.powerRefreshSeconds, 1)
        XCTAssertLessThanOrEqual(MonitorPowerFormat.estimateRefreshSeconds, 10)
    }

    func testPowerFormattingUsesOneDecimal() {
        XCTAssertEqual(MonitorPowerFormat.temperature(32.19), "32.2 ℃")
        XCTAssertEqual(MonitorPowerFormat.watts(4.449), "4.4 W")
        XCTAssertEqual(MonitorPowerFormat.remaining(3_900, language: .simplifiedChinese), "1 小时 5 分钟")
        XCTAssertEqual(MonitorPowerFormat.remaining(3_900, language: .english), "1h 5m")
        XCTAssertEqual(MonitorPowerFormat.energy(12.345), "12.3 mWh")
        XCTAssertEqual(MonitorPowerFormat.share(0.426), "43%")
        XCTAssertEqual(MonitorPowerFormat.temperature(nil), "—")
    }

    func testPowerWarningThresholds() {
        XCTAssertEqual(MonitorPowerFormat.lowBatteryPercent, 20)
        XCTAssertEqual(MonitorPowerFormat.criticalBatteryPercent, 5)
        XCTAssertEqual(MonitorPowerFormat.highTemperatureCelsius, 45)
    }

    func testPowerSupplyMappingCoversThreeVisibleStates() {
        XCTAssertEqual(
            MonitorPowerFormat.batterySupply(
                adapterConnected: false,
                isCharging: false,
                isCharged: false,
                hasBattery: true
            ),
            .battery
        )
        XCTAssertEqual(
            MonitorPowerFormat.batterySupply(
                adapterConnected: true,
                isCharging: true,
                isCharged: false,
                hasBattery: true
            ),
            .charging
        )
        XCTAssertEqual(
            MonitorPowerFormat.batterySupply(
                adapterConnected: true,
                isCharging: false,
                isCharged: true,
                hasBattery: true
            ),
            .adapter
        )
        XCTAssertEqual(
            MonitorPowerFormat.batterySupply(
                adapterConnected: true,
                isCharging: false,
                isCharged: false,
                hasBattery: false
            ),
            .adapter
        )
        XCTAssertEqual(
            MonitorPowerFormat.batterySupply(
                adapterConnected: false,
                isCharging: false,
                isCharged: false,
                hasBattery: false
            ),
            .unknown
        )
    }

    func testMultiBatteryPercentUsesTotalCapacity() {
        XCTAssertEqual(
            MonitorPowerFormat.aggregateBatteryPercent(
                currentCapacities: [4_000, 1_000],
                maximumCapacities: [8_000, 2_000]
            ) ?? 0,
            50,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorPowerFormat.aggregateBatteryPercent(
                currentCapacities: [80, 40],
                maximumCapacities: [100, 100]
            ) ?? 0,
            60,
            accuracy: 0.001
        )
        XCTAssertNil(
            MonitorPowerFormat.aggregateBatteryPercent(
                currentCapacities: [50],
                maximumCapacities: []
            )
        )
    }

    func testBatteryTemperatureUsesRegistryHundredths() {
        XCTAssertEqual(
            MonitorPowerFormat.batteryTemperatureCelsius(raw: 3_219) ?? 0,
            32.19,
            accuracy: 0.001
        )
        XCTAssertNil(MonitorPowerFormat.batteryTemperatureCelsius(raw: 0))
    }

    func testMilliwattConversion() {
        XCTAssertEqual(
            MonitorPowerFormat.watts(fromMilliwatts: 4_449) ?? 0,
            4.449,
            accuracy: 0.001
        )
        XCTAssertNil(MonitorPowerFormat.watts(fromMilliwatts: nil))
    }

    func testRemainingEstimateUsesAveragePower() {
        XCTAssertEqual(
            MonitorPowerFormat.estimatedRemainingSeconds(
                capacityWattHours: 100,
                percent: 50,
                averageWatts: 10
            ) ?? 0,
            18_000,
            accuracy: 0.001
        )
        XCTAssertNil(
            MonitorPowerFormat.estimatedRemainingSeconds(
                capacityWattHours: nil,
                percent: 50,
                averageWatts: 10
            )
        )
    }

    func testPowerReadFailureIsPerReading() {
        let failed = power(
            supply: .battery,
            batteryAvailable: false,
            powerAvailable: true
        )
        XCTAssertTrue(failed.hasReadFailure)

        let desktop = MonitorSnapshot.Power(
            supply: .adapter,
            hasBattery: false,
            batteryPercent: nil,
            temperatureCelsius: nil,
            watts: 8,
            averageWatts: nil,
            remainingSeconds: nil,
            topApps: [],
            batteryDataAvailable: false,
            powerDataAvailable: true,
            energyDataAvailable: true
        )
        XCTAssertFalse(desktop.hasReadFailure)
    }

    func testPowerAverageKeepsNewestSamples() {
        var average = MonitorPowerAverage(capacity: 3)
        _ = average.append(1)
        _ = average.append(2)
        _ = average.append(3)
        XCTAssertEqual(average.append(6) ?? 0, 11.0 / 3.0, accuracy: 0.001)
        average.reset()
        XCTAssertEqual(average.append(8) ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(average.average, 8)
    }

    func testPowerLayoutDegradesInRequiredOrder() {
        XCTAssertEqual(
            MonitorPowerLayoutPolicy.resolve(height: 200),
            .init(showsTopApps: true, showsRemaining: true, showsPower: true)
        )
        XCTAssertEqual(
            MonitorPowerLayoutPolicy.resolve(height: 169),
            .init(showsTopApps: false, showsRemaining: true, showsPower: true)
        )
        XCTAssertEqual(
            MonitorPowerLayoutPolicy.resolve(height: 131),
            .init(showsTopApps: false, showsRemaining: false, showsPower: true)
        )
        XCTAssertEqual(
            MonitorPowerLayoutPolicy.resolve(height: 100),
            .init(showsTopApps: false, showsRemaining: false, showsPower: false)
        )
    }

    func testEnergyWindowAggregatesProcessesByApplication() {
        var window = MonitorEnergyWindow()
        let start = Date(timeIntervalSince1970: 3_600)
        let baseline = [
            sample(pid: 10, app: "alpha", energy: 1_000_000_000),
            sample(pid: 11, app: "alpha", energy: 2_000_000_000),
            sample(pid: 20, app: "beta", energy: 3_000_000_000),
        ]
        XCTAssertTrue(window.update(samples: baseline, at: start).isEmpty)

        let measured = [
            sample(pid: 10, app: "alpha", energy: 4_600_000_000),
            sample(pid: 11, app: "alpha", energy: 5_600_000_000),
            sample(pid: 20, app: "beta", energy: 6_600_000_000),
        ]
        let top = window.update(samples: measured, at: start.addingTimeInterval(10))
        XCTAssertEqual(top.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(top[0].energyMilliwattHours, 2, accuracy: 0.001)
        XCTAssertEqual(top[1].energyMilliwattHours, 1, accuracy: 0.001)
        XCTAssertEqual(top[0].share, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(top[1].share, 1.0 / 3.0, accuracy: 0.001)
    }

    func testEnergyWindowKeepsOnlyThreeTopApps() {
        var window = MonitorEnergyWindow()
        let start = Date(timeIntervalSince1970: 7_200)
        let baseline = (0..<4).map {
            sample(pid: Int32($0 + 1), app: "app\($0)", energy: 0)
        }
        _ = window.update(samples: baseline, at: start)

        let measured = (0..<4).map { index in
            sample(
                pid: Int32(index + 1),
                app: "app\(index)",
                energy: UInt64(3_600_000_000 * (index + 1))
            )
        }
        let top = window.update(samples: measured, at: start.addingTimeInterval(10))
        XCTAssertEqual(top.map(\.name), ["app3", "app2", "app1"])
    }

    func testEnergyWindowDropsBucketsOlderThanOneHour() {
        var window = MonitorEnergyWindow()
        let start = Date(timeIntervalSince1970: 10_800)
        let baseline = [sample(pid: 42, app: "alpha", energy: 0)]
        _ = window.update(samples: baseline, at: start)
        let firstDelta = [sample(pid: 42, app: "alpha", energy: 3_600_000_000)]
        let first = window.update(samples: firstDelta, at: start.addingTimeInterval(60))
        XCTAssertEqual(first.first?.energyMilliwattHours ?? 0, 1, accuracy: 0.001)

        let secondDelta = [sample(pid: 42, app: "alpha", energy: 7_200_000_000)]
        let later = window.update(
            samples: secondDelta,
            at: start.addingTimeInterval(61 * 60)
        )
        XCTAssertEqual(later.first?.energyMilliwattHours ?? 0, 1, accuracy: 0.001)

        let empty = window.update(samples: [], at: start.addingTimeInterval(122 * 60))
        XCTAssertTrue(empty.isEmpty)
    }

    private func sample(
        pid: Int32,
        app: String,
        energy: UInt64
    ) -> MonitorProcessEnergySample {
        MonitorProcessEnergySample(
            processIdentifier: pid,
            applicationID: app,
            applicationName: app,
            bundlePath: nil,
            cumulativeNanojoules: energy
        )
    }

    private func power(
        supply: MonitorSnapshot.Power.Supply,
        percent: Double? = 80,
        temperature: Double? = 32.2,
        watts: Double? = 4.5,
        remaining: TimeInterval? = nil,
        topApps: [MonitorSnapshot.Power.TopApp] = [],
        batteryAvailable: Bool = true,
        powerAvailable: Bool = true,
        energyAvailable: Bool = true
    ) -> MonitorSnapshot.Power {
        MonitorSnapshot.Power(
            supply: supply,
            hasBattery: true,
            batteryPercent: percent,
            temperatureCelsius: temperature,
            watts: watts,
            averageWatts: watts,
            remainingSeconds: remaining,
            topApps: topApps,
            batteryDataAvailable: batteryAvailable,
            powerDataAvailable: powerAvailable,
            energyDataAvailable: energyAvailable
        )
    }

    private func snapshot(
        cpu: Double? = nil,
        battery: MonitorSnapshot.Battery? = nil,
        power: MonitorSnapshot.Power? = nil
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
            power: power,
            thermal: .nominal,
            sampledAt: Date()
        )
    }
}
