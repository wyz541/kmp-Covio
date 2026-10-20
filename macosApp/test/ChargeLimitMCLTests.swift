import XCTest
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

    func testApplyWritesInOrderAndPersistsOriginals() throws {
        let preferences = FakeChargeLimitPreferences()
        preferences.bools[ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled] = true
        preferences.ints[ChargeLimitPreferenceDomain.keyFeatureState] = 0
        preferences.ints[ChargeLimitPreferenceDomain.keyLimitValue] = 80
        let controller = makeController(preferences: preferences)

        let result = controller.apply(targetPercent: 55)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 55)
        XCTAssertEqual(state.original.featureState, 0)
        XCTAssertEqual(state.original.limitPercent, 80)
        XCTAssertEqual(state.original.optimizedChargingEnabled, true)
        XCTAssertEqual(
            preferences.writeLog,
            [
                "bool:enabled=false",
                "int:mclLimitValue=55",
                "int:MCLFeatureState=1",
            ]
        )
        XCTAssertEqual(preferences.notifications, 1)
        XCTAssertEqual(preferences.ints[ChargeLimitPreferenceDomain.keyLimitValue], 55)
        XCTAssertEqual(preferences.ints[ChargeLimitPreferenceDomain.keyFeatureState], 1)
        XCTAssertEqual(preferences.bools[ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled], false)
    }

    func testApplyAtOneHundredReleasesMcl() throws {
        let preferences = FakeChargeLimitPreferences()
        preferences.ints[ChargeLimitPreferenceDomain.keyFeatureState] = 0
        preferences.ints[ChargeLimitPreferenceDomain.keyLimitValue] = 80
        preferences.bools[ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled] = true
        let controller = makeController(preferences: preferences)

        let result = controller.apply(targetPercent: 100)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 100)
        XCTAssertEqual(
            preferences.writeLog,
            [
                "bool:enabled=false",
                "int:MCLFeatureState=0",
            ]
        )
        XCTAssertEqual(preferences.ints[ChargeLimitPreferenceDomain.keyFeatureState], 0)
        XCTAssertEqual(powerUI.disableCalls, 1)
    }

    func testRestorePutsBackEveryOriginalValue() throws {
        let preferences = FakeChargeLimitPreferences()
        preferences.bools[ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled] = true
        preferences.ints[ChargeLimitPreferenceDomain.keyFeatureState] = 0
        preferences.ints[ChargeLimitPreferenceDomain.keyLimitValue] = 80
        let controller = makeController(preferences: preferences)
        _ = controller.apply(targetPercent: 55)
        preferences.writeLog.removeAll()

        let result = controller.restore()

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(
            preferences.writeLog,
            [
                "int:MCLFeatureState=0",
                "int:mclLimitValue=80",
                "bool:enabled=true",
                "int:MCLFeatureState=0",
            ]
        )
        XCTAssertEqual(preferences.ints[ChargeLimitPreferenceDomain.keyLimitValue], 80)
        XCTAssertEqual(preferences.ints[ChargeLimitPreferenceDomain.keyFeatureState], 0)
        XCTAssertEqual(preferences.bools[ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled], true)
        XCTAssertNil(try stateStore.load())
        XCTAssertEqual(preferences.notifications, 2)
        XCTAssertEqual(powerUI.disableCalls, 1)
    }

    func testRestoreRemovesKeysThatWereOriginallyAbsent() throws {
        let preferences = FakeChargeLimitPreferences()
        let controller = makeController(preferences: preferences)
        _ = controller.apply(targetPercent: 55)

        XCTAssertNoThrow(try controller.restore().get())

        XCTAssertTrue(preferences.ints.isEmpty)
        XCTAssertTrue(preferences.bools.isEmpty)
    }

    func testRestoreDoesNothingWhenNoStateExists() {
        let preferences = FakeChargeLimitPreferences()
        let controller = makeController(preferences: preferences)

        XCTAssertNoThrow(try controller.restore().get())
        XCTAssertTrue(preferences.writeLog.isEmpty)
        XCTAssertEqual(preferences.notifications, 0)
    }

    func testChangingTargetKeepsTheFirstOriginalSnapshot() throws {
        let preferences = FakeChargeLimitPreferences()
        preferences.bools[ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled] = true
        preferences.ints[ChargeLimitPreferenceDomain.keyFeatureState] = 0
        preferences.ints[ChargeLimitPreferenceDomain.keyLimitValue] = 80
        let controller = makeController(preferences: preferences)

        _ = controller.apply(targetPercent: 55)
        let result = controller.apply(targetPercent: 60)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.original.featureState, 0)
        XCTAssertEqual(state.original.limitPercent, 80)
        XCTAssertEqual(state.original.optimizedChargingEnabled, true)
    }

    func testSyncFailureLeavesTheStateFileForRetry() {
        let preferences = FakeChargeLimitPreferences()
        preferences.syncResult = false
        let controller = makeController(preferences: preferences)

        let result = controller.apply(targetPercent: 55)

        XCTAssertEqual(result, .failure(.preferencesSyncFailed))
        XCTAssertNoThrow(try XCTUnwrap(stateStore.load()))

        preferences.syncResult = true
        XCTAssertNoThrow(try controller.restore().get())
        XCTAssertNil(try? stateStore.load())
    }

    func testCorruptStateBlocksWrites() throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: stateURL)
        let preferences = FakeChargeLimitPreferences()
        let controller = makeController(preferences: preferences)

        XCTAssertEqual(controller.apply(targetPercent: 55), .failure(.stateUnreadable))
        XCTAssertTrue(preferences.writeLog.isEmpty)
    }

    func testInvalidTargetsAreRejected() {
        let preferences = FakeChargeLimitPreferences()
        let controller = makeController(preferences: preferences)

        for target in [0, 19, 79, 101, 105] {
            XCTAssertEqual(controller.apply(targetPercent: target), .failure(.invalidTarget(target)))
        }
    }

    func testStateFileIsRootReadWriteOnly() throws {
        let preferences = FakeChargeLimitPreferences()
        let controller = makeController(preferences: preferences)

        _ = controller.apply(targetPercent: 55)

        let attributes = try FileManager.default.attributesOfItem(atPath: stateURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testCapabilityComesFromPowerUIProbe() {
        let controller = makeController(preferences: FakeChargeLimitPreferences())

        powerUI.capabilityValue = .supported
        XCTAssertEqual(controller.capability(), .supported)

        powerUI.capabilityValue = .unsupported
        XCTAssertEqual(controller.capability(), .unsupported)
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

    private func makeController(
        preferences: FakeChargeLimitPreferences
    ) -> ChargeLimitMCLController {
        ChargeLimitMCLController(
            preferences: preferences,
            stateStore: stateStore,
            powerUI: powerUI
        )
    }

    private func successState(
        _ result: Result<ChargeLimitPersistentState, ChargeLimitMCLFailure>
    ) -> ChargeLimitPersistentState? {
        guard case .success(let state) = result else { return nil }
        return state
    }
}

private final class FakePowerUIChargeReading: PowerUIChargeReading, @unchecked Sendable {
    var capabilityValue: PowerUICapability = .supported
    var bypass = false
    var disableResult = true
    var disableCalls = 0

    func capability() -> PowerUICapability { capabilityValue }
    func bypassEngaged() -> Bool { bypass }

    func disableMCL() -> Bool {
        disableCalls += 1
        return disableResult
    }
}

private final class FakeChargeLimitPreferences: ChargeLimitPreferenceStore {
    var ints: [String: Int] = [:]
    var bools: [String: Bool] = [:]
    var writeLog: [String] = []
    var notifications = 0
    var syncResult = true

    func readInt(_ key: String) -> Int? { ints[key] }
    func readBool(_ key: String) -> Bool? { bools[key] }

    func writeInt(_ key: String, value: Int) {
        ints[key] = value
        writeLog.append("int:\(key)=\(value)")
    }

    func writeBool(_ key: String, value: Bool) {
        bools[key] = value
        writeLog.append("bool:\(key)=\(value)")
    }

    func remove(_ key: String) {
        ints.removeValue(forKey: key)
        bools.removeValue(forKey: key)
        writeLog.append("remove:\(key)")
    }

    func synchronize() -> Bool { syncResult }

    func notifyChanged() { notifications += 1 }
}
