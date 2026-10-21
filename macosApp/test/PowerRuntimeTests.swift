import XCTest
import kmpDomain
@testable import Covio

@MainActor
final class PowerRuntimeTests: XCTestCase {
    private var fixture: Fixture!
    private var observation: FakePowerObservationSource!
    private var runtime: PowerRuntime!
    private var historyDirectory: URL!
    private var historyStore: PowerHistoryStore!
    private var brightnessBackend: FakeClosedLidBrightnessBackend!
    private var brightnessStore: FakeClosedLidBrightnessRecoveryStore!

    override func setUp() {
        super.setUp()
        historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-power-history-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        historyStore = PowerHistoryStore.companion.create(
            path: historyDirectory.appendingPathComponent("history.json").path
        )
        brightnessBackend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        brightnessStore = FakeClosedLidBrightnessRecoveryStore()
        fixture = Fixture()
        fixture.privileged.installed = false
        fixture.engine.start()
        observation = FakePowerObservationSource()
    }

    override func tearDown() {
        runtime?.stop()
        fixture?.engine.stop()
        runtime = nil
        observation = nil
        fixture = nil
        if let historyDirectory {
            try? FileManager.default.removeItem(at: historyDirectory)
        }
        historyDirectory = nil
        historyStore = nil
        brightnessBackend = nil
        brightnessStore = nil
        super.tearDown()
    }

    func testAdapterRuleCreatesAnActualIdleAssertion() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true))

        runtime.start()

        XCTAssertTrue(runtime.decision.automaticRuleApplied)
        XCTAssertTrue(runtime.decision.preventUserIdleSystemSleep)
        XCTAssertEqual(fixture.sleep.prevention, .system)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .holdStarted })
    }

    func testAdapterTransitionsAndSleepEventsArePersisted() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()
        observation.value = makeObservation(powerState: .discharging, batteryPercent: 70, hasBattery: true)
        runtime.refresh()
        runtime.recordSystemSleep()

        let state = historyStore.load(nowEpochSeconds: 1_000)
        XCTAssertTrue(state.events.contains { $0.kind == .adapterDisconnected })
        XCTAssertTrue(state.events.contains { $0.kind == .slept })
        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .adapterDisconnected })
    }

    func testHistoryWriteFailureDoesNotBlockThePolicy() throws {
        let blocker = historyDirectory.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        historyStore = PowerHistoryStore.companion.create(
            path: blocker.appendingPathComponent("history.json").path
        )
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true))

        runtime.start()

        XCTAssertTrue(runtime.decision.automaticRuleApplied)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(runtime.recentHistory.isEmpty)
    }

    func testExternalSleepDisabledConflictIsRecorded() {
        fixture.privileged.installed = true
        fixture.privileged.sleepDisabled = true
        fixture.privileged.covioOwned = false
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .externalConflict })
        XCTAssertTrue(runtime.snapshot.sleepDisabled?.boolValue == true)

        fixture.privileged.sleepDisabled = false
        fixture.privileged.covioOwned = nil
        runtime.refreshHelperStatusNow()

        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .externalConflictCleared })
    }

    func testDarkWakeFromTheWakeLogIsRecorded() {
        let initial = WakeEvent(kind: .full, atEpochSeconds: 900, reason: "Initial")
        let wakes = WakeLogStore(WakeLogSnapshot(events: [initial], darkWakeCount24h: 0))
        let wakeFixture = Fixture(wakeLogReader: wakes)
        wakeFixture.engine.start()
        let wakeObservation = FakePowerObservationSource(
            value: makeObservation(powerState: .discharging, batteryPercent: 80, hasBattery: true)
        )
        let wakeRuntime = makeRuntime(
            config: makeConfig(),
            fixture: wakeFixture,
            observationSource: wakeObservation
        )
        wakeRuntime.start()
        wakes.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "RTC")],
            darkWakeCount24h: 1
        )

        wakeFixture.watcher.wake()
        wakeRuntime.refresh()

        XCTAssertTrue(wakeRuntime.recentHistory.contains {
            $0.kind == .darkWake && $0.detail == "RTC"
        })
        wakeRuntime.stop()
        wakeFixture.engine.stop()
    }

    func testFullWakeFromTheWakeLogIsRecorded() {
        let initial = WakeEvent(kind: .dark, atEpochSeconds: 900, reason: "Initial")
        let wakes = WakeLogStore(WakeLogSnapshot(events: [initial], darkWakeCount24h: 1))
        let wakeFixture = Fixture(wakeLogReader: wakes)
        wakeFixture.engine.start()
        let wakeObservation = FakePowerObservationSource(
            value: makeObservation(powerState: .discharging, batteryPercent: 80, hasBattery: true)
        )
        let wakeRuntime = makeRuntime(
            config: makeConfig(),
            fixture: wakeFixture,
            observationSource: wakeObservation
        )
        wakeRuntime.start()
        wakes.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .full, atEpochSeconds: 1_000, reason: "UserActivity")],
            darkWakeCount24h: 1
        )

        wakeFixture.watcher.wake()
        wakeRuntime.refresh()

        XCTAssertTrue(wakeRuntime.recentHistory.contains { $0.kind == .fullWake })
        wakeRuntime.stop()
        wakeFixture.engine.stop()
    }

    func testClosedLidCapReleasesTheSessionAndRecordsTheGuard() {
        var now: Int64 = 1_000
        fixture.privileged.installed = true
        fixture.privileged.sleepDisabled = false
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(
            config: makeConfig(allowClosedLid: true, closedLidTimeCapMinutes: 30),
            nowEpochSeconds: { now }
        )
        runtime.start()
        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .untilOff))

        now = 2_800
        runtime.refresh()

        XCTAssertFalse(runtime.hasManualSession)
        XCTAssertEqual(runtime.leases.count, 0)
        XCTAssertTrue(runtime.recentHistory.contains {
            $0.kind == .guardReleased && $0.detail == "closed-lid-time-cap"
        })
    }

    func testEndingSessionKeepsLeasesFromOtherSources() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()
        fixture.engine.setIdleSleepAvailable(available: false)

        XCTAssertTrue(runtime.startSession(mode: .display, duration: .oneHour))
        XCTAssertEqual(runtime.decision.appliedLeaseLevel, .systemAndDisplay)
        runtime.endSession()

        XCTAssertFalse(runtime.hasManualSession)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertEqual(fixture.engine.currentState.idleSleepPrevention, .system)
    }

    func testClosedLidPowerSessionTurnsDisplayOffAfterTheLidCloses() {
        fixture.privileged.installed = true
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertTrue(fixture.privileged.sleepDisabled)

        fixture.lid.emit(.closed)

        XCTAssertEqual(fixture.sleep.displayCalls, 1)
        XCTAssertEqual(fixture.sleep.sleepCalls, 0)
    }

    func testClosedLidSessionRefusesWhenHelperIsMissing() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertFalse(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertEqual(runtime.executionError, "helper-unavailable")
        XCTAssertFalse(runtime.hasManualSession)
    }

    func testExperimentalClosedLidPathOwnsBrightnessAndSuppressesPublicDisplayOff() {
        fixture.privileged.installed = true
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(closedLidZeroBrightness: true))
        runtime.start()

        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .oneHour))
        fixture.lid.emit(.closed)
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime.refresh()

        XCTAssertEqual(brightnessBackend.brightness, 0)
        XCTAssertEqual(runtime.closedLidZeroBrightnessPhase, .active)
        XCTAssertEqual(fixture.sleep.displayCalls, 0)

        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime.refresh()

        XCTAssertEqual(brightnessBackend.brightness, 0.6, accuracy: 0.001)
        XCTAssertEqual(runtime.closedLidZeroBrightnessPhase, .ready)
        XCTAssertNil(brightnessStore.record)
    }

    func testExperimentalBrightnessFailureFallsBackToPublicDisplayOff() {
        fixture.privileged.installed = true
        brightnessBackend.failingSetValues = [0]
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(closedLidZeroBrightness: true))
        runtime.start()

        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .oneHour))
        fixture.lid.emit(.closed)
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime.refresh()

        XCTAssertEqual(runtime.closedLidZeroBrightnessPhase, .failed)
        XCTAssertEqual(brightnessBackend.brightness, 0.6, accuracy: 0.001)
        XCTAssertEqual(fixture.sleep.displayCalls, 1)

        runtime.refresh()
        XCTAssertEqual(fixture.sleep.displayCalls, 1)
    }

    func testCriticalThermalStateReleasesEveryPowerLease() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true))
        runtime.start()
        XCTAssertTrue(runtime.startSession(mode: .system, duration: .oneHour))

        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            thermalState: .critical
        )
        runtime.refresh()

        XCTAssertTrue(runtime.leases.isEmpty)
        XCTAssertTrue(runtime.decision.safetyVetoes.contains(.thermalCritical))
        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertEqual(fixture.sleep.prevention, .none)
        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .guardReleased })
    }

    func testUnknownObservationDoesNotFabricateAValueOrAHold() {
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true, keepAwakeOnBattery: true))
        runtime.start()

        XCTAssertNil(runtime.observation.batteryPercent)
        XCTAssertNil(runtime.observation.hasBattery)
        XCTAssertNil(runtime.observation.externalDisplayCount)
        XCTAssertNil(runtime.observation.lowPowerModeEnabled)
        XCTAssertEqual(runtime.observation.powerState, .unknown)
        XCTAssertEqual(runtime.observation.thermalState, .unknown)
        XCTAssertFalse(runtime.isHolding)
        XCTAssertFalse(runtime.decision.automaticRuleApplied)
        XCTAssertTrue(runtime.recentHistory.isEmpty)
    }

    private func makeRuntime(
        config: PowerConfig,
        fixture: Fixture? = nil,
        observationSource: FakePowerObservationSource? = nil,
        brightnessBackend: FakeClosedLidBrightnessBackend? = nil,
        brightnessStore: FakeClosedLidBrightnessRecoveryStore? = nil,
        nowEpochSeconds: @escaping () -> Int64 = { 1_000 }
    ) -> PowerRuntime {
        PowerRuntime(
            engine: (fixture ?? self.fixture).engine,
            privileged: (fixture ?? self.fixture).privileged,
            observationSource: observationSource ?? observation,
            historyStore: historyStore,
            config: config,
            closedLidBrightnessBackend: brightnessBackend ?? self.brightnessBackend,
            closedLidBrightnessStore: brightnessStore ?? self.brightnessStore,
            nowEpochSeconds: nowEpochSeconds
        )
    }

    private func makeObservation(
        powerState: PowerState,
        batteryPercent: Int,
        hasBattery: Bool,
        thermalState: ThermalState = .nominal,
        lidState: LidState = .open
    ) -> PowerObservation {
        PowerObservation(
            batteryPercent: KotlinInt(int: Int32(batteryPercent)),
            hasBattery: KotlinBoolean(bool: hasBattery),
            powerState: powerState,
            externalDisplayCount: KotlinInt(int: 0),
            lidState: lidState,
            thermalState: thermalState,
            lowPowerModeEnabled: KotlinBoolean(bool: false)
        )
    }

    private func makeConfig(
        enabled: Bool = true,
        keepAwakeOnAdapter: Bool = false,
        keepAwakeOnBattery: Bool = false,
        allowClosedLid: Bool = true,
        pauseClosedLidWithExternalDisplay: Bool = true,
        batteryFloorPercent: Int32 = 15,
        batteryFloorRecoveryPercent: Int32 = 20,
        yieldOnLowPowerMode: Bool = true,
        heatGuardEnabled: Bool = true,
        closedLidTimeCapMinutes: Int32 = 240,
        closedLidZeroBrightness: Bool = false
    ) -> PowerConfig {
        PowerConfig(
            enabled: enabled,
            keepAwakeOnAdapter: keepAwakeOnAdapter,
            keepAwakeOnBattery: keepAwakeOnBattery,
            allowClosedLid: allowClosedLid,
            pauseClosedLidWithExternalDisplay: pauseClosedLidWithExternalDisplay,
            batteryFloorPercent: batteryFloorPercent,
            batteryFloorRecoveryPercent: batteryFloorRecoveryPercent,
            yieldOnLowPowerMode: yieldOnLowPowerMode,
            heatGuardEnabled: heatGuardEnabled,
            closedLidTimeCapMinutes: closedLidTimeCapMinutes,
            closedLidZeroBrightness: closedLidZeroBrightness
        )
    }
}
