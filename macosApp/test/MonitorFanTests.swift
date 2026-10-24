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

    func testMultiPointCurveInterpolatesBetweenNearestPoints() {
        let points = [
            MonitorFanCurvePoint(temperature: 40, rpm: 1_200),
            MonitorFanCurvePoint(temperature: 65, rpm: 2_400),
            MonitorFanCurvePoint(temperature: 85, rpm: 4_800),
        ]

        XCTAssertEqual(
            MonitorFanCurve.target(
                points: points,
                temperature: 75,
                minimumRPM: 1_200,
                maximumRPM: 5_800
            ),
            3_600,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MonitorFanCurve.target(
                points: points,
                temperature: 30,
                minimumRPM: 1_200,
                maximumRPM: 5_800
            ),
            1_200
        )
        XCTAssertEqual(
            MonitorFanCurve.target(
                points: points,
                temperature: 100,
                minimumRPM: 1_200,
                maximumRPM: 5_800
            ),
            4_800
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

    func testManualModesNormalizeAndDefaultToManual() {
        let value = MonitorFanConfiguration(
            mode: .manual,
            manualModes: [
                "0": .automatic,
                "1": .curve,
                "bad": .manual,
            ]
        ).normalized(fanMinimums: [0: 1_200, 1: 1_500])

        XCTAssertEqual(value.manualModes, ["0": .automatic, "1": .manual])
        XCTAssertEqual(value.controlMode(for: 0), .automatic)
        XCTAssertEqual(value.controlMode(for: 1), .manual)
        XCTAssertEqual(value.controlMode(for: 2), .manual)
    }

    func testCurveModeIgnoresPerFanManualModes() {
        let value = MonitorFanConfiguration(
            mode: .curve,
            manualModes: ["0": .automatic, "1": .manual]
        )

        XCTAssertEqual(value.controlMode(for: 0), .curve)
        XCTAssertEqual(value.controlMode(for: 1), .curve)
    }

    func testEachFanUsesItsOwnCurve() {
        let configuration = MonitorFanConfiguration(
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 40, rpm: 1_200),
                    MonitorFanCurvePoint(temperature: 90, rpm: 5_000),
                ],
                "1": [
                    MonitorFanCurvePoint(temperature: 40, rpm: 1_500),
                    MonitorFanCurvePoint(temperature: 90, rpm: 6_000),
                ],
            ]
        )

        XCTAssertEqual(
            configuration.target(
                fanIndex: 0,
                temperature: 65,
                minimumRPM: 1_200,
                maximumRPM: 5_000
            ),
            3_100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            configuration.target(
                fanIndex: 1,
                temperature: 65,
                minimumRPM: 1_500,
                maximumRPM: 6_000
            ),
            3_750,
            accuracy: 0.001
        )
    }

    func testCurveNormalizationSortsDeduplicatesAndClamps() {
        let configuration = MonitorFanConfiguration(
            startCelsius: 58,
            fullCelsius: 86,
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 90, rpm: 9_000),
                    MonitorFanCurvePoint(temperature: 20, rpm: 200),
                    MonitorFanCurvePoint(temperature: 70, rpm: 2_505),
                    MonitorFanCurvePoint(temperature: 70, rpm: 2_600),
                ],
            ]
        ).normalized(
            fanMinimums: [0: 1_200],
            fanMaximums: [0: 5_000]
        )

        XCTAssertEqual(configuration.curves["0"]?.map(\.temperature), [40, 70, 90])
        XCTAssertEqual(configuration.curves["0"]?.map(\.rpm), [1_200, 2_600, 5_000])
    }

    func testCurveNormalizationKeepsBothEndpointsWhenReducingPointCount() {
        let points = (0..<12).map { index in
            MonitorFanCurvePoint(
                temperature: 40 + Double(index * 5),
                rpm: 1_200 + Double(index * 300)
            )
        }

        let normalized = MonitorFanCurve.normalized(
            points,
            minimumRPM: 1_200,
            maximumRPM: 5_800
        )

        XCTAssertEqual(normalized.count, MonitorFanPolicy.maximumCurvePointCount)
        XCTAssertEqual(normalized.first?.temperature, 40)
        XCTAssertEqual(normalized.last?.temperature, 95)
    }

    func testConfigurationRoundTripsPerFanCurves() throws {
        let original = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            manualModes: ["0": .automatic, "1": .manual],
            syncFans: true,
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 45, rpm: 1_200),
                    MonitorFanCurvePoint(temperature: 78, rpm: 3_900),
                    MonitorFanCurvePoint(temperature: 92, rpm: 5_800),
                ],
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MonitorFanConfiguration.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testLegacyConfigurationWithoutCurvesUsesTwoPointFallback() throws {
        let data = Data(
            """
            {"enabled":true,"mode":"automatic","startCelsius":58,"fullCelsius":86,
             "selectedSensorKeys":["TCMz"],"manualRPM":{}}
            """.utf8
        )
        let configuration = try JSONDecoder().decode(MonitorFanConfiguration.self, from: data)

        XCTAssertEqual(configuration.mode, .curve)
        XCTAssertTrue(configuration.manualModes.isEmpty)
        XCTAssertFalse(configuration.syncFans)
        XCTAssertTrue(configuration.curves.isEmpty)
        XCTAssertEqual(
            configuration.curvePoints(for: 0, minimumRPM: 1_200, maximumRPM: 5_800),
            [
                MonitorFanCurvePoint(temperature: 58, rpm: 1_200),
                MonitorFanCurvePoint(temperature: 86, rpm: 5_800),
            ]
        )
    }

    func testHelperPayloadRoundTripsPerFanCurves() throws {
        let payload = MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            curves: [
                "0": [
                    MonitorFanCurvePoint(temperature: 45, rpm: 1_200),
                    MonitorFanCurvePoint(temperature: 92, rpm: 5_800),
                ],
                "1": [
                    MonitorFanCurvePoint(temperature: 50, rpm: 1_300),
                    MonitorFanCurvePoint(temperature: 96, rpm: 6_000),
                ],
            ]
        ).helperPayload()
        let curveText = try XCTUnwrap(payload["curves"])
        let decoded = try JSONDecoder().decode(
            [String: [MonitorFanCurvePoint]].self,
            from: Data(curveText.utf8)
        )

        XCTAssertEqual(decoded["0"]?.first?.temperature, 45)
        XCTAssertEqual(decoded["1"]?.last?.rpm, 6_000)
    }

    func testHelperPayloadRoundTripsManualModes() throws {
        let payload = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            manualModes: ["0": .automatic, "1": .manual]
        ).helperPayload()
        let modeText = try XCTUnwrap(payload["manualModes"])
        let decoded = try JSONDecoder().decode(
            [String: MonitorFanMode].self,
            from: Data(modeText.utf8)
        )

        XCTAssertEqual(decoded, ["0": .automatic, "1": .manual])
    }

    func testSystemAutomaticAndCurveUseDifferentHelperModes() {
        let automatic = MonitorFanConfiguration(
            enabled: true,
            mode: .automatic
        ).helperPayload()
        let curve = MonitorFanConfiguration(
            enabled: true,
            mode: .curve
        ).helperPayload()

        XCTAssertEqual(automatic["mode"], "auto")
        XCTAssertEqual(curve["mode"], "curve")
    }

    func testDisabledLegacyAutomaticConfigurationStaysSystemControlled() throws {
        let data = Data(#"{"enabled":false,"mode":"automatic"}"#.utf8)
        let configuration = try JSONDecoder().decode(MonitorFanConfiguration.self, from: data)

        XCTAssertEqual(configuration.mode, .automatic)
    }

    func testSynchronizedManualRPMUsesEachFanRange() {
        let units = [
            MonitorFanReading.Unit(
                index: 0,
                rpm: 3_500,
                minimumRPM: 1_200,
                maximumRPM: 5_800,
                targetRPM: 3_500,
                mode: 1
            ),
            MonitorFanReading.Unit(
                index: 1,
                rpm: 3_650,
                minimumRPM: 1_300,
                maximumRPM: 6_000,
                targetRPM: 3_650,
                mode: 1
            ),
        ]

        let targets = MonitorFanSpeedSync.targets(
            sourceFanIndex: 0,
            rpm: 3_500,
            units: units
        )

        XCTAssertEqual(targets, [0: 3_500, 1: 3_650])
    }

    @MainActor
    func testManualModeSwitchSynchronizesWhenEnabled() {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_000, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            manualModes: ["0": .manual, "1": .manual],
            syncFans: true
        )
        let model = MonitorFanControlModel(
            previewConfiguration: configuration,
            availability: .ready
        )

        model.setManualMode(.automatic, fanIndex: 0, reading: reading)

        XCTAssertEqual(model.manualMode(for: 0), .automatic)
        XCTAssertEqual(model.manualMode(for: 1), .automatic)

        var independentConfiguration = configuration
        independentConfiguration.syncFans = false
        let independent = MonitorFanControlModel(
            previewConfiguration: independentConfiguration,
            availability: .ready
        )
        independent.setManualMode(.automatic, fanIndex: 0, reading: reading)

        XCTAssertEqual(independent.manualMode(for: 0), .automatic)
        XCTAssertEqual(independent.manualMode(for: 1), .manual)
    }

    @MainActor
    func testManualRPMWriteUsesThreeHundredMillisecondDebounce() async {
        let reading = MonitorFanReading(
            temperatures: [.init(key: "TCMz", celsius: 65)],
            units: [
                .init(index: 0, rpm: 2_200, minimumRPM: 1_200, maximumRPM: 5_000, targetRPM: 2_200, mode: 1),
                .init(index: 1, rpm: 2_300, minimumRPM: 1_300, maximumRPM: 6_000, targetRPM: 2_300, mode: 1),
            ]
        )
        let model = MonitorFanControlModel(
            previewConfiguration: MonitorFanConfiguration(
                enabled: true,
                mode: .manual,
                manualRPM: ["0": 2_200, "1": 2_300],
                manualModes: ["0": .manual, "1": .manual]
            ),
            availability: .ready
        )

        model.setManualRPM(2_400, fanIndex: 0, reading: reading)
        XCTAssertTrue(model.hasPendingManualWrite)
        try? await Task.sleep(for: .milliseconds(150))
        model.setManualRPM(2_600, fanIndex: 0, reading: reading)
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(model.hasPendingManualWrite)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.hasPendingManualWrite)
        XCTAssertEqual(model.configuration.manualRPM["0"], 2_600)
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
