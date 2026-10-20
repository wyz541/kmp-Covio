import Darwin
import XCTest
import kmpDomain
@testable import Covio

final class ChargeLimitHelperTests: XCTestCase {
    func testStatusReturnsDisabledWhenNoStateExists() {
        let handler = ChargeLimitHelperCommandHandler(backend: FakeChargeLimitBackend())

        let reply = handler.handle(request("chargeLimitStatus"))

        XCTAssertEqual(reply?.ok, true)
        XCTAssertEqual(reply?.result?["enabled"], "false")
    }

    func testStatusReturnsThePersistedState() {
        let backend = FakeChargeLimitBackend()
        backend.loadedState = ChargeLimitPersistentState(
            targetPercent: 55,
            original: ChargeLimitOriginals(
                optimizedChargingEnabled: true,
                featureState: 0,
                limitPercent: 80
            )
        )
        let handler = ChargeLimitHelperCommandHandler(backend: backend)

        let reply = handler.handle(request("chargeLimitStatus"))

        XCTAssertEqual(reply?.result?["enabled"], "true")
        XCTAssertEqual(reply?.result?["targetPercent"], "55")
        XCTAssertEqual(reply?.result?["originalFeatureState"], "0")
        XCTAssertEqual(reply?.result?["originalLimitPercent"], "80")
        XCTAssertEqual(reply?.result?["originalOptimizedChargingEnabled"], "true")
    }

    func testConfigurePassesTheTargetToTheBackend() {
        let backend = FakeChargeLimitBackend()
        let handler = ChargeLimitHelperCommandHandler(backend: backend)

        let reply = handler.handle(request("chargeLimitConfigure", payload: ["percent": "55"]))

        XCTAssertEqual(reply?.ok, true)
        XCTAssertEqual(backend.appliedPercent, 55)
    }

    func testConfigureReturnsAReadableFailure() {
        let backend = FakeChargeLimitBackend()
        backend.applyFailure = .preferencesSyncFailed
        let handler = ChargeLimitHelperCommandHandler(backend: backend)

        let reply = handler.handle(request("chargeLimitConfigure", payload: ["percent": "55"]))

        XCTAssertEqual(reply?.ok, false)
        XCTAssertEqual(reply?.error, "macOS did not save the charge limit preferences")
    }

    func testRestoreInvokesTheBackend() {
        let backend = FakeChargeLimitBackend()
        let handler = ChargeLimitHelperCommandHandler(backend: backend)

        let reply = handler.handle(request("chargeLimitRestore"))

        XCTAssertEqual(reply?.ok, true)
        XCTAssertTrue(backend.restoreCalled)
    }

    func testNonChargeCommandsAreLeftToTheExistingHelper() {
        let handler = ChargeLimitHelperCommandHandler(backend: FakeChargeLimitBackend())

        XCTAssertNil(handler.handle(request("version")))
    }

    func testCurrentProcessSatisfiesItsOwnDesignatedRequirement() throws {
        let requirement = try XCTUnwrap(HelperSignature.currentRequirement())
        XCTAssertTrue(
            HelperSignature.isAuthorized(
                pid: getpid(),
                requirementText: requirement
            )
        )
    }

    func testANonsenseRequirementIsRejected() {
        XCTAssertFalse(
            HelperSignature.isAuthorized(
                pid: getpid(),
                requirementText: "identifier \"not-covio\""
            )
        )
    }

    func testPeerPidComesFromTheUnixSocket() throws {
        var pair = [Int32](repeating: 0, count: 2)
        let result = pair.withUnsafeMutableBufferPointer { sockets in
            socketpair(AF_UNIX, SOCK_STREAM, 0, sockets.baseAddress)
        }
        XCTAssertEqual(result, 0)
        defer {
            close(pair[0])
            close(pair[1])
        }

        XCTAssertEqual(HelperSignature.peerPID(of: pair[0]), getpid())
    }

    func testSocketPeerAuthorizerUsesTheStoredRequirement() throws {
        let requirement = try XCTUnwrap(HelperSignature.currentRequirement())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-helper-signature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let requirementPath = directory.appendingPathComponent("requirement").path
        try requirement.write(toFile: requirementPath, atomically: true, encoding: .utf8)

        var pair = [Int32](repeating: 0, count: 2)
        let result = pair.withUnsafeMutableBufferPointer { sockets in
            socketpair(AF_UNIX, SOCK_STREAM, 0, sockets.baseAddress)
        }
        XCTAssertEqual(result, 0)
        defer {
            close(pair[0])
            close(pair[1])
        }

        let authorizer = CodeSignaturePeerAuthorizer(requirementPath: requirementPath)
        XCTAssertTrue(authorizer.isAuthorized(descriptor: pair[0]))
    }

    private func request(
        _ command: String,
        payload: [String: String] = [:]
    ) -> HelperRequest {
        HelperRequest(
            version: HelperProtocol.protocolVersion,
            requestId: "r",
            command: command,
            payload: payload
        )
    }
}

private final class FakeChargeLimitBackend: ChargeLimitBackend, @unchecked Sendable {
    var loadedState: ChargeLimitPersistentState?
    var loadFailure: ChargeLimitMCLFailure?
    var applyFailure: ChargeLimitMCLFailure?
    var appliedPercent: Int?
    var restoreCalled = false
    var restoreFailure: ChargeLimitMCLFailure?

    func loadState() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure> {
        if let loadFailure { return .failure(loadFailure) }
        return .success(loadedState)
    }

    func apply(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure> {
        appliedPercent = targetPercent
        if let applyFailure { return .failure(applyFailure) }
        return .success(
            ChargeLimitPersistentState(
                targetPercent: targetPercent,
                original: ChargeLimitOriginals(
                    optimizedChargingEnabled: nil,
                    featureState: nil,
                    limitPercent: nil
                )
            )
        )
    }

    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        restoreCalled = true
        if let restoreFailure { return .failure(restoreFailure) }
        return .success(())
    }
}
