import XCTest
import kmpDomain
@testable import Covio

final class ChargeLimitRuntimeTests: XCTestCase {
    private var directory: URL!
    private var stateStore: ChargeLimitRuntimeStateStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-charge-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateStore = ChargeLimitRuntimeStateStore(
            url: directory.appendingPathComponent("charge-limit/runtime.json")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testConfigureStartsChargingAndPersistsTheUserLimit() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 44))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 50).get()
        let configured = try runtime.evaluateNow().get()
        let settled = try runtime.evaluateNow().get()

        XCTAssertEqual(configured.userLimitPercent, 50)
        XCTAssertEqual(configured.effectiveTargetPercent, 50)
        XCTAssertTrue(configured.chargingLatch)
        XCTAssertEqual(settled.phase, "charging")
        XCTAssertEqual(backend.appliedTargets, [50])
        XCTAssertEqual(try stateStore.load()?.userLimitPercent, 50)
    }

    func testFivePercentSailingCycle() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 44))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }
        _ = runtime.configure(userLimitPercent: 50)
        _ = runtime.evaluateNow()

        reader.reading = reading(current: 50)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "holding")
        XCTAssertFalse(try runtime.status().get().chargingLatch)

        reader.reading = reading(current: 47)
        _ = runtime.evaluateNow()
        XCTAssertEqual(backend.appliedTargets, [50, 47])
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "sailing")

        reader.reading = reading(current: 45)
        _ = runtime.evaluateNow()
        XCTAssertEqual(backend.appliedTargets, [50, 47, 50])
        XCTAssertTrue(try runtime.status().get().chargingLatch)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "charging")
    }

    func testAboveTheLimitHoldsTheCurrentLevel() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 64))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 50).get()
        let status = try runtime.evaluateNow().get()

        XCTAssertEqual(status.phase, "aboveLimit")
        XCTAssertEqual(status.effectiveTargetPercent, 64)
        XCTAssertEqual(backend.appliedTargets, [64])
    }

    func testOneHundredPercentReleasesMclOnlyOnce() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 90))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 50).get()
        _ = try runtime.configure(userLimitPercent: 100).get()
        _ = try runtime.evaluateNow().get()

        XCTAssertEqual(backend.appliedTargets, [90, 100])
        XCTAssertNil(try runtime.status().get().effectiveTargetPercent)
        XCTAssertEqual(try runtime.status().get().phase, "charging")
    }

    func testCalibrationAndProtectionDoNotWrite() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(
            reading: reading(current: 50, calibrationActive: true)
        )
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 50).get()
        XCTAssertEqual(try runtime.status().get().phase, "calibration")
        XCTAssertTrue(backend.appliedTargets.isEmpty)

        reader.reading = reading(current: 50, protectionActive: true)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "systemProtection")
        XCTAssertTrue(backend.appliedTargets.isEmpty)
    }

    func testUnsupportedDeviceDoesNotWrite() throws {
        let backend = FakeChargeLimitBackend()
        backend.capabilityValue = .unsupported
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 50))
        )
        defer { _ = runtime.restore() }

        XCTAssertEqual(try runtime.configure(userLimitPercent: 50).get().phase, "unsupported")
        XCTAssertTrue(backend.appliedTargets.isEmpty)
    }

    func testFailedFirstConfigurationRollsBackTheRuntimeState() throws {
        let backend = FakeChargeLimitBackend()
        backend.applyFailure = .readbackFailed("target")
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 44))
        )

        XCTAssertEqual(
            runtime.configure(userLimitPercent: 50),
            .failure(.readbackFailed("target"))
        )
        XCTAssertNil(try stateStore.load())
        XCTAssertTrue(backend.restoreCalled)
        XCTAssertEqual(try runtime.status().get().phase, "off")
    }

    func testFailedLimitChangeKeepsThePreviousIntent() throws {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 44))
        )
        defer { _ = runtime.restore() }
        _ = try runtime.configure(userLimitPercent: 50).get()

        backend.applyFailure = .readbackFailed("target")
        XCTAssertEqual(
            runtime.configure(userLimitPercent: 60),
            .failure(.readbackFailed("target"))
        )
        XCTAssertEqual(try stateStore.load()?.userLimitPercent, 50)
    }

    func testExternalTargetChangeStopsWritesAndReportsConflict() throws {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 44))
        )
        defer { _ = runtime.restore() }
        _ = try runtime.configure(userLimitPercent: 50).get()

        backend.observedTargetOverride = 80
        let conflicted = try runtime.evaluateNow().get()

        XCTAssertEqual(conflicted.phase, "conflict")
        XCTAssertEqual(backend.appliedTargets, [50])
    }

    func testBypassEvidenceIsExposedWhileHolding() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(
            reading: reading(current: 50, bypassEngaged: true)
        )
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 50).get()
        let configured = try runtime.evaluateNow().get()

        XCTAssertEqual(configured.phase, "holding")
        XCTAssertTrue(configured.bypassEngaged)
    }

    func testResumeOnStartupReappliesThePolicy() throws {
        try stateStore.save(
            ChargeLimitRuntimeState(
                userLimitPercent: 50,
                chargingLatch: false,
                lastPhase: "unplugged"
            )
        )
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 45))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        XCTAssertNoThrow(try runtime.resumeOnStartup().get())
        XCTAssertEqual(backend.appliedTargets, [50])
        XCTAssertTrue(try runtime.status().get().chargingLatch)
    }

    func testInvalidLimitsAreRejectedBeforeAnyWrite() {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 50))
        )

        XCTAssertEqual(runtime.configure(userLimitPercent: 79), .failure(.invalidTarget(79)))
        XCTAssertTrue(backend.appliedTargets.isEmpty)
    }

    func testRestoreStopsThePolicyAndRestoresTheBackend() throws {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 44))
        )
        _ = runtime.configure(userLimitPercent: 50)

        XCTAssertNoThrow(try runtime.restore().get())

        XCTAssertTrue(backend.restoreCalled)
        XCTAssertNil(try stateStore.load())
    }

    private func makeRuntime(
        backend: FakeChargeLimitBackend,
        reader: FakeChargeLimitPowerReader
    ) -> ChargeLimitRuntimeController {
        ChargeLimitRuntimeController(
            backend: backend,
            powerReader: reader,
            stateStore: stateStore,
            intervalSeconds: 3_600
        )
    }

    private func reading(
        current: Int?,
        adapter: Bool = true,
        charged: Bool = false,
        calibrationActive: Bool = false,
        protectionActive: Bool = false,
        bypassEngaged: Bool = false
    ) -> ChargeLimitPowerReading {
        ChargeLimitPowerReading(
            adapterConnected: adapter,
            batteryPresent: current != nil,
            currentPercent: current,
            isCharged: charged,
            calibrationActive: calibrationActive,
            systemProtectionActive: protectionActive,
            bypassEngaged: bypassEngaged
        )
    }
}

private final class FakeChargeLimitPowerReader: ChargeLimitPowerReadingSource, @unchecked Sendable {
    var reading: ChargeLimitPowerReading?

    init(reading: ChargeLimitPowerReading?) {
        self.reading = reading
    }

    func read() -> ChargeLimitPowerReading? { reading }
}

private final class FakeChargeLimitBackend: ChargeLimitBackend, @unchecked Sendable {
    var state: ChargeLimitPersistentState?
    var appliedTargets: [Int] = []
    var restoreCalled = false
    var capabilityValue: ChargeLimitSupport = .supported
    var applyFailure: ChargeLimitMCLFailure?
    var observedTargetOverride: Int?

    func capability() -> ChargeLimitSupport { capabilityValue }
    func observedTargetPercent() -> Int? {
        if let observedTargetOverride { return observedTargetOverride }
        guard let target = state?.targetPercent, target < 100 else { return nil }
        return target
    }

    func loadState() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure> {
        .success(state)
    }

    func apply(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure> {
        appliedTargets.append(targetPercent)
        if let applyFailure { return .failure(applyFailure) }
        let updated = ChargeLimitPersistentState(
            targetPercent: targetPercent,
            original: state?.original ?? ChargeLimitOriginals(
                optimizedChargingEnabled: true,
                featureState: 0,
                limitPercent: 80
            )
        )
        state = updated
        return .success(updated)
    }

    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        restoreCalled = true
        state = nil
        return .success(())
    }
}
