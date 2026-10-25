import AppKit
import XCTest
@testable import Covio

final class FanControlSleepPolicyTests: XCTestCase {
    func testSleepSavesConfigurationAndWakeRestoresIt() {
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            manualRPM: ["0": 2_200]
        )
        var policy = FanControlSleepPolicy()

        policy.start(configuration)
        XCTAssertEqual(policy.willSleep(), configuration)
        XCTAssertEqual(policy.didWake(), configuration)
        XCTAssertNil(policy.didWake())
    }

    func testStoppingDuringSleepPreventsWakeRestore() {
        var policy = FanControlSleepPolicy()
        policy.start(MonitorFanConfiguration(enabled: true, mode: .curve))

        XCTAssertNotNil(policy.willSleep())
        policy.stop()

        XCTAssertNil(policy.didWake())
    }

    func testAutomaticModeIsNotSuspended() {
        var policy = FanControlSleepPolicy()
        policy.start(MonitorFanConfiguration(enabled: false, mode: .automatic))

        XCTAssertNil(policy.willSleep())
    }

    func testLeaseKeeperRestoresBeforeSleepAndReconfiguresAfterWake() {
        let client = FakeFanControlLeaseClient()
        let center = NotificationCenter()
        let keeper = FanControlLeaseKeeper(
            client: client,
            notificationCenter: center,
            wakeDelay: 0,
            observeSleepWake: true
        )
        let configuration = MonitorFanConfiguration(
            enabled: true,
            mode: .manual,
            manualRPM: ["0": 2_200]
        )

        keeper.start(configuration: configuration)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        wait(for: [client.restoreExpectation], timeout: 2)

        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        wait(for: [client.configureExpectation], timeout: 2)

        XCTAssertEqual(client.configuredConfiguration, configuration)
        keeper.stop()
    }
}

private final class FakeFanControlLeaseClient: FanControlLeaseClient, @unchecked Sendable {
    let restoreExpectation = XCTestExpectation(description: "restore before sleep")
    let configureExpectation = XCTestExpectation(description: "configure after wake")
    var allowsFanControlWrites = true
    private let lock = NSLock()
    private var storedConfiguration: MonitorFanConfiguration?

    var configuredConfiguration: MonitorFanConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return storedConfiguration
    }

    func keepAliveFanControl() -> FanControlHelperStatus? { nil }

    func configureFanControl(_ configuration: MonitorFanConfiguration) -> FanControlCommandResult {
        lock.lock()
        storedConfiguration = configuration
        lock.unlock()
        configureExpectation.fulfill()
        return FanControlCommandResult(ok: true, message: nil, status: nil)
    }

    func restoreFanControl() -> FanControlCommandResult {
        restoreExpectation.fulfill()
        return FanControlCommandResult(ok: true, message: nil, status: nil)
    }
}
