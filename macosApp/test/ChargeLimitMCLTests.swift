import XCTest
import kmpDomain
@testable import Covio

final class ChargeLimitMCLTests: XCTestCase {
    private var directory: URL!
    private var stateURL: URL!
    private var stateStore: ChargeLimitStateStore!
    private var powerUI: FakePowerUIChargeReading!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-mcl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateURL = directory.appendingPathComponent("charge-limit/state.json")
        stateStore = ChargeLimitStateStore(url: stateURL)
        powerUI = FakePowerUIChargeReading()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testApplyUsesPowerUIAndPersistsOriginals() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 80
        let controller = makeController()

        let result = controller.apply(targetPercent: 85)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 85)
        XCTAssertEqual(state.original.featureState, 1)
        XCTAssertEqual(state.original.limitPercent, 80)
        XCTAssertNil(state.original.optimizedChargingEnabled)
        XCTAssertEqual(powerUI.appliedLimits, [85])
        XCTAssertEqual(powerUI.currentPercent, 85)
        XCTAssertTrue(powerUI.enabled == true)
    }

    func testApplyAtOneHundredReleasesMcl() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 85
        let controller = makeController()

        let result = controller.apply(targetPercent: 100)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 100)
        XCTAssertEqual(powerUI.disableCalls, 1)
        XCTAssertFalse(powerUI.enabled == true)
    }

    func testRestoreReappliesTheOriginalNativeLimit() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 80
        let controller = makeController()
        _ = controller.apply(targetPercent: 85)

        XCTAssertNoThrow(try controller.restore().get())

        XCTAssertEqual(powerUI.appliedLimits, [85, 80])
        XCTAssertEqual(powerUI.currentPercent, 80)
        XCTAssertTrue(powerUI.enabled == true)
        XCTAssertEqual(powerUI.disableCalls, 1)
        XCTAssertNil(try stateStore.load())
    }

    func testRestoreKeepsOriginallyDisabledMclDisabled() throws {
        powerUI.enabled = false
        powerUI.currentPercent = 80
        let controller = makeController()
        _ = controller.apply(targetPercent: 85)

        XCTAssertNoThrow(try controller.restore().get())

        XCTAssertFalse(powerUI.enabled == true)
        XCTAssertEqual(powerUI.disableCalls, 1)
        XCTAssertNil(try stateStore.load())
    }

    func testRestoreDoesNothingWhenNoStateExists() {
        let controller = makeController()

        XCTAssertNoThrow(try controller.restore().get())
        XCTAssertTrue(powerUI.appliedLimits.isEmpty)
        XCTAssertEqual(powerUI.disableCalls, 0)
    }

    func testChangingTargetKeepsTheFirstOriginalSnapshot() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 80
        let controller = makeController()

        _ = controller.apply(targetPercent: 85)
        let result = controller.apply(targetPercent: 90)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.original.featureState, 1)
        XCTAssertEqual(state.original.limitPercent, 80)
        XCTAssertEqual(powerUI.appliedLimits, [85, 90])
    }

    func testApplyFailureLeavesTheStateFileForRuntimeRollback() {
        powerUI.applyResult = false
        let controller = makeController()

        let result = controller.apply(targetPercent: 85)

        XCTAssertEqual(result, .failure(.readbackFailed("MCL target")))
        XCTAssertNoThrow(try XCTUnwrap(stateStore.load()))
    }

    func testCorruptStateBlocksWrites() throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: stateURL)
        let controller = makeController()

        XCTAssertEqual(controller.apply(targetPercent: 85), .failure(.stateUnreadable))
        XCTAssertTrue(powerUI.appliedLimits.isEmpty)
    }

    func testTargetsBelowEightyAreRejected() {
        let controller = makeController()

        for target in [0, 75, 79, 101, 105] {
            XCTAssertEqual(controller.apply(targetPercent: target), .failure(.invalidTarget(target)))
        }
    }

    func testStateFileIsRootReadWriteOnly() throws {
        let controller = makeController()
        _ = controller.apply(targetPercent: 85)

        let attributes = try FileManager.default.attributesOfItem(atPath: stateURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testCapabilityComesFromPowerUIProbe() {
        let controller = makeController()

        powerUI.capabilityValue = .supported
        XCTAssertEqual(controller.capability(), .supported)

        powerUI.capabilityValue = .unsupported
        XCTAssertEqual(controller.capability(), .unsupported)
    }

    func testObservedTargetComesFromMclState() {
        let controller = makeController()

        powerUI.enabled = true
        powerUI.currentPercent = 85
        XCTAssertEqual(controller.observedTargetPercent(), 85)

        powerUI.enabled = false
        XCTAssertNil(controller.observedTargetPercent())
    }

    func testBypassStateUsesOnlyTheLatestTimelineEvent() {
        let ended: [String: Any] = [
            "Timeline": [
                ["date": "20", "event": "BypassEngaged"],
                ["date": "30", "event": "Engaged"],
            ],
        ]
        XCTAssertFalse(SystemPowerUIChargeClient.isBypassEngaged(status: ended))

        let active: [String: Any] = [
            "Timeline": [
                ["date": "20", "event": "Engaged"],
                ["date": "30", "event": "BypassEngaged"],
                ["date": "40", "event": "EligibleForIdle"],
            ],
        ]
        XCTAssertTrue(SystemPowerUIChargeClient.isBypassEngaged(status: active))
        XCTAssertFalse(SystemPowerUIChargeClient.isBypassEngaged(status: ["Timeline": []]))
    }

    private func makeController() -> ChargeLimitMCLController {
        ChargeLimitMCLController(stateStore: stateStore, powerUI: powerUI)
    }

    private func successState(
        _ result: Result<ChargeLimitPersistentState, ChargeLimitMCLFailure>
    ) -> ChargeLimitPersistentState? {
        guard case .success(let state) = result else { return nil }
        return state
    }
}

private final class FakePowerUIChargeReading: PowerUIChargeReading, @unchecked Sendable {
    let minimumSupportedPercent = 80
    var capabilityValue: PowerUICapability = .supported
    var enabled: Bool? = true
    var currentPercent: Int? = 80
    var applyResult = true
    var appliedLimits: [Int] = []
    var disableResult = true
    var disableCalls = 0

    func capability() -> PowerUICapability { capabilityValue }
    func isMCLEnabled() -> Bool? { enabled }
    func currentLimit() -> Int? { currentPercent }

    func applyLimit(_ percent: Int) -> Bool {
        appliedLimits.append(percent)
        guard applyResult else { return false }
        enabled = true
        currentPercent = percent
        return true
    }

    func bypassEngaged() -> Bool { false }

    func disableMCL() -> Bool {
        disableCalls += 1
        guard disableResult else { return false }
        enabled = false
        return true
    }
}
