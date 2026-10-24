import XCTest
@testable import Covio

final class MonitorFanTests: XCTestCase {
    func testCurveClampsAtFanLimits() {
        XCTAssertEqual(
            MonitorFanCurve.target(
                temperature: 50,
                startCelsius: 60,
                fullCelsius: 90,
                minimumRPM: 1_500,
                maximumRPM: 5_000
            ),
            1_500
        )
        XCTAssertEqual(
            MonitorFanCurve.target(
                temperature: 100,
                startCelsius: 60,
                fullCelsius: 90,
                minimumRPM: 1_500,
                maximumRPM: 5_000
            ),
            5_000
        )
    }

    func testCurveInterpolatesLinearly() {
        XCTAssertEqual(
            MonitorFanCurve.target(
                temperature: 75,
                startCelsius: 60,
                fullCelsius: 90,
                minimumRPM: 1_500,
                maximumRPM: 5_500
            ),
            3_500,
            accuracy: 0.001
        )
    }

    func testHysteresisPreventsSmallTemperatureDrops() {
        XCTAssertEqual(
            MonitorFanCurve.heldTemperature(current: 68.7, previous: 70),
            70,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanCurve.heldTemperature(current: 68.4, previous: 70),
            68.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanCurve.heldTemperature(current: 72, previous: 70),
            72,
            accuracy: 0.001
        )
    }

    func testConfigurationNormalizesCurveAndManualRPM() {
        let value = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            startCelsius: 20,
            fullCelsius: 21,
            selectedSensorKeys: ["TCMz", "TCMz"],
            manualRPM: ["0": 900, "1": 9_000]
        ).normalized(
            fanMinimums: [0: 1_200],
            fanMaximums: [0: 5_000, 1: 6_000]
        )

        XCTAssertEqual(value.startCelsius, 35)
        XCTAssertEqual(value.fullCelsius, 40)
        XCTAssertEqual(value.selectedSensorKeys, ["TCMz"])
        XCTAssertEqual(value.manualRPM["0"], 1_200)
        XCTAssertEqual(value.manualRPM["1"], 6_000)
    }

    func testControlTemperatureUsesSelectedSensors() {
        let reading = MonitorFanReading(
            temperatures: [
                .init(key: "TCMz", celsius: 72),
                .init(key: "TG0D", celsius: 64),
                .init(key: "TB0T", celsius: 38),
            ],
            units: []
        )

        XCTAssertEqual(
            reading.controlTemperature(selectedKeys: ["TCMz"]),
            72
        )
        XCTAssertEqual(
            reading.controlTemperature(selectedKeys: ["TG0D", "TB0T"]),
            64
        )
        XCTAssertEqual(
            reading.controlTemperature(selectedKeys: []),
            72
        )
    }

    func testMonitorHistoryTracksTheFanSeries() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 72)],
            units: [
                .init(
                    index: 0,
                    rpm: 2_200,
                    minimumRPM: 1_200,
                    maximumRPM: 5_000,
                    targetRPM: 2_100,
                    mode: 1
                ),
                .init(
                    index: 1,
                    rpm: 2_600,
                    minimumRPM: 1_200,
                    maximumRPM: 5_500,
                    targetRPM: 2_500,
                    mode: 1
                ),
            ]
        )
        let snapshot = MonitorSnapshot(
            cpu: nil,
            gpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: nil,
            power: nil,
            fan: reading,
            thermal: .nominal,
            sampledAt: Date()
        )
        var history = MonitorHistory(capacity: 2)
        history.append(snapshot, fanControlTemperature: 68)
        history.append(snapshot)

        XCTAssertEqual(history.fanTemperature, [68, 72])
        XCTAssertEqual(history.fanRPM, [2_600, 2_600])
    }

    func testHelperPayloadUsesStableFieldNames() {
        let payload = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            startCelsius: 58,
            fullCelsius: 86,
            selectedSensorKeys: ["TCMz", "TG0D"],
            manualRPM: ["1": 2_400, "0": 2_200]
        ).helperPayload()

        XCTAssertEqual(payload["enabled"], "true")
        XCTAssertEqual(payload["mode"], "manual")
        XCTAssertEqual(payload["start"], "58")
        XCTAssertEqual(payload["full"], "86")
        XCTAssertEqual(payload["sensors"], "TCMz,TG0D")
        XCTAssertEqual(payload["manualRPM"], "0:2200,1:2400")
    }
}
