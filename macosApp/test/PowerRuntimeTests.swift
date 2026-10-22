import XCTest
import kmpDomain
@testable import Covio

@MainActor
final class PowerRuntimeTests: XCTestCase {
    private var fixture: Fixture!
    private var observation: FakePowerObservationSource!
    private var runtime: PowerRuntime!

    override func setUp() {
        super.setUp()
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

    func testClosedLidSessionRefusesWhenHelperIsMissing() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertFalse(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertEqual(runtime.executionError, "helper-unavailable")
        XCTAssertFalse(runtime.hasManualSession)
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
    }

    private func makeRuntime(config: PowerConfig) -> PowerRuntime {
        PowerRuntime(
            engine: fixture.engine,
            privileged: fixture.privileged,
            observationSource: observation,
            config: config,
            nowEpochSeconds: { 1_000 }
        )
    }

    private func makeObservation(
        powerState: PowerState,
        batteryPercent: Int,
        hasBattery: Bool,
        thermalState: ThermalState = .nominal
    ) -> PowerObservation {
        PowerObservation(
            batteryPercent: KotlinInt(int: Int32(batteryPercent)),
            hasBattery: KotlinBoolean(bool: hasBattery),
            powerState: powerState,
            externalDisplayCount: KotlinInt(int: 0),
            lidState: .open,
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
        closedLidTimeCapMinutes: Int32 = 240
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
            closedLidTimeCapMinutes: closedLidTimeCapMinutes
        )
    }
}
