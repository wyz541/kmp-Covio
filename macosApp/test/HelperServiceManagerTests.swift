import ServiceManagement
import XCTest
@testable import Covio

final class HelperServiceManagerTests: XCTestCase {
    private var directory: URL!
    private var legacyPlist: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-helper-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        legacyPlist = directory.appendingPathComponent("legacy.plist").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testUnregisteredServiceWithoutLegacyPlistIsNotRegistered() {
        let manager = manager(status: .notRegistered)

        XCTAssertEqual(manager.state, .notRegistered)
    }

    func testLegacyPlistIsVisibleBeforeMigration() throws {
        try Data().write(to: URL(fileURLWithPath: legacyPlist))
        let manager = manager(status: .enabled)

        XCTAssertEqual(manager.state, .legacy)
    }

    func testEnabledAndApprovalStatesMapDirectly() {
        XCTAssertEqual(manager(status: .enabled).state, .enabled)
        XCTAssertEqual(manager(status: .requiresApproval).state, .requiresApproval)
    }

    func testNotFoundWithoutLegacyPlistStaysNotFound() {
        XCTAssertEqual(manager(status: .notFound).state, .notFound)
    }

    func testOpenSettingsUsesTheSystemSettingsEntryPoint() {
        var opened = false
        let manager = SMAppHelperServiceManager(
            backing: FakeSMAppServiceBacking(status: .requiresApproval),
            legacyPlistPath: legacyPlist,
            legacySocketPath: directory.appendingPathComponent("helper.sock").path,
            openSettings: { opened = true }
        )

        manager.openSystemSettings()

        XCTAssertTrue(opened)
    }

    func testRegistrationErrorKeepsTheUnderlyingError() {
        let backing = FakeSMAppServiceBacking(status: .notRegistered)
        backing.registerError = TestError.failed
        let manager = SMAppHelperServiceManager(
            backing: backing,
            legacyPlistPath: legacyPlist,
            legacySocketPath: directory.appendingPathComponent("helper.sock").path
        )

        XCTAssertThrowsError(try manager.register()) { error in
            XCTAssertTrue(error is HelperServiceError)
        }
        XCTAssertTrue(manager.state.isError)
    }

    func testSuccessfulRegistrationRequestsApproval() throws {
        let manager = manager(status: .notRegistered)

        try manager.register()

        XCTAssertEqual(manager.state, .requiresApproval)
    }

    func testInstallTransactionReplacesTheRegistrationWithoutReadingTheOldHelper() {
        let manager = manager(status: .enabled)

        let result = HelperInstaller.registerForInstallTransaction(
            serviceManager: manager,
            legacyPlistPath: legacyPlist
        )

        XCTAssertEqual(result, .requiresApproval)
        XCTAssertEqual(manager.state, .requiresApproval)
    }

    func testInstallTransactionRejectsALegacyDaemon() throws {
        try Data().write(to: URL(fileURLWithPath: legacyPlist))
        let manager = manager(status: .notRegistered)

        let result = HelperInstaller.registerForInstallTransaction(
            serviceManager: manager,
            legacyPlistPath: legacyPlist
        )

        guard case .failed(let message) = result else {
            return XCTFail("legacy daemon should block the transaction")
        }
        XCTAssertTrue(message.contains("Legacy helper"))
    }

    private func manager(status: SMAppService.Status) -> SMAppHelperServiceManager {
        SMAppHelperServiceManager(
            backing: FakeSMAppServiceBacking(status: status),
            legacyPlistPath: legacyPlist,
            legacySocketPath: directory.appendingPathComponent("helper.sock").path
        )
    }
}

private extension HelperServiceState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

private final class FakeSMAppServiceBacking: SMAppServiceBacking {
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        if let registerError { throw registerError }
        status = .requiresApproval
    }

    func unregister() throws {
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}

private enum TestError: Error {
    case failed
}
