import CryptoKit
import Foundation
import XCTest
@testable import Covio

@MainActor
final class ModelSetupRuntimeTests: XCTestCase {
    private let revision = String(repeating: "a", count: 40)
    private var root: URL!
    private var registry: LocalModelPackageRegistryStore!
    private var packagesDirectory: URL!
    private var statusStore: LocalModelDownloadStatusStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-model-setup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = LocalModelPackageRegistryStore(path: root.appendingPathComponent("registry.json"))
        packagesDirectory = root.appendingPathComponent("Packages", isDirectory: true)
        statusStore = LocalModelDownloadStatusStore(
            roots: LocalModelDownloadRoots(
                downloadsDirectory: root.appendingPathComponent("Downloads", isDirectory: true),
                packagesDirectory: packagesDirectory
            )
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNoModelStartsNotInstalledWithoutDownloading() async throws {
        let source = try makeSource()
        let installer = ControllableInstaller(
            status: status(source: source, phase: .notDownloaded),
            verified: makeVerified(source: source)
        )
        let runtime = makeRuntime(installer: installer)

        await runtime.refresh()

        XCTAssertEqual(runtime.state(for: .compact2B).phase, .notInstalled)
        XCTAssertFalse(runtime.isAIReady)
        let calls = await installer.downloadCalls
        XCTAssertEqual(calls, 0)
    }

    func testStaleRevisionIsShownAsRevisionMismatch() async throws {
        let oldRevision = String(repeating: "b", count: 40)
        let oldSource = try makeSource(revision: oldRevision)
        try statusStore.save(status(source: oldSource, phase: .paused, fraction: 0.3))
        let installer = FailingInstaller(
            status: status(source: oldSource, phase: .paused, fraction: 0.3),
            failure: LocalModelDownloadFailure(code: .downloadFailed, detail: "unused")
        )
        let runtime = makeRuntime(installer: installer)

        await runtime.refresh()

        let state = runtime.state(for: .compact2B)
        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(state.failure, .revisionMismatch)
    }

    func testPauseAndResumeKeepProgressAndActivateTheModel() async throws {
        let source = try makeSource()
        let verified = makeVerified(source: source)
        let installer = ControllableInstaller(
            status: status(source: source, phase: .notDownloaded),
            verified: verified
        )
        var activatedTier: LocalModelTier?
        let runtime = makeRuntime(installer: installer)
        runtime.activatePackage = { package in
            activatedTier = package.tier
        }

        let first = Task { await runtime.download(.compact2B) }
        try await waitForDownloadCalls(1, installer: installer)
        try await Task.sleep(for: .milliseconds(20))
        let downloadingState = runtime.state(for: .compact2B)
        XCTAssertEqual(downloadingState.phase, .downloading, "\(downloadingState)")
        XCTAssertEqual(downloadingState.fractionCompleted, 0.4, accuracy: 0.000_1)

        await runtime.pause()
        await first.value
        await Task.yield()
        XCTAssertNil(runtime.operationTier)
        XCTAssertEqual(runtime.state(for: .compact2B).phase, .paused)
        XCTAssertEqual(runtime.state(for: .compact2B).fractionCompleted, 0.4, accuracy: 0.000_1)

        let resumed = Task { await runtime.download(.compact2B) }
        try await waitForDownloadCalls(2, installer: installer)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(runtime.state(for: .compact2B).phase, .downloading)
        await installer.finishDownload()
        await resumed.value

        XCTAssertEqual(activatedTier, .compact2B)
        XCTAssertEqual(runtime.state(for: .compact2B).phase, .ready)
        XCTAssertEqual(runtime.activeTier, .compact2B)
    }

    func testDiskFailureDoesNotMarkTheModelReady() async throws {
        let source = try makeSource()
        let installer = FailingInstaller(
            status: status(source: source, phase: .notDownloaded),
            failure: LocalModelDownloadFailure(code: .insufficientDisk, detail: "full")
        )
        let runtime = makeRuntime(installer: installer)

        await runtime.download(.compact2B)

        let state = runtime.state(for: .compact2B)
        XCTAssertEqual(state.phase, .failed)
        XCTAssertEqual(state.failure, .insufficientDisk)
        XCTAssertNil(runtime.activeTier)
    }

    func testImportVerifiesAndActivatesALocalPackage() async throws {
        let source = try makeSource()
        let imported = root.appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
        try source.manifestData.write(
            to: imported.appendingPathComponent("FileNamingModelManifest.json")
        )
        try source.licenseData.write(to: imported.appendingPathComponent("LICENSE"))
        try source.noticeData.write(to: imported.appendingPathComponent("NOTICE"))
        try Data("verified-model-weights".utf8).write(
            to: imported.appendingPathComponent("model.safetensors")
        )
        let installer = FailingInstaller(
            status: status(source: source, phase: .notDownloaded),
            failure: LocalModelDownloadFailure(code: .downloadFailed, detail: "unused")
        )
        let runtime = makeRuntime(installer: installer)
        var activatedDirectory: URL?
        runtime.activatePackage = { package in
            activatedDirectory = package.directory
        }

        await runtime.importPackage(tier: .compact2B, directory: imported)

        XCTAssertEqual(activatedDirectory?.standardizedFileURL, imported.standardizedFileURL)
        XCTAssertEqual(runtime.state(for: .compact2B).phase, .ready)
        XCTAssertEqual(
            registry.load().registration(for: .compact2B)?.directoryPath,
            imported.path
        )
    }

    func testRemovingManagedModelDeletesFilesAndClearsRegistration() async throws {
        let source = try makeSource()
        let verified = makeVerified(source: source)
        try FileManager.default.createDirectory(at: verified.directory, withIntermediateDirectories: true)
        try source.manifestData.write(
            to: verified.directory.appendingPathComponent("FileNamingModelManifest.json")
        )
        try registry.register(verified)
        let installer = ControllableInstaller(
            status: status(source: source, phase: .ready, fraction: 1),
            verified: verified
        )
        let runtime = makeRuntime(installer: installer)
        runtime.setActiveTier(.compact2B)
        var deactivatedTier: LocalModelTier?
        runtime.deactivatePackage = { tier in deactivatedTier = tier }

        await runtime.remove(.compact2B)

        XCTAssertEqual(deactivatedTier, .compact2B)
        XCTAssertNil(registry.load().registration(for: .compact2B))
        XCTAssertFalse(FileManager.default.fileExists(atPath: verified.directory.path))
        XCTAssertEqual(runtime.state(for: .compact2B).phase, .notInstalled)
        let resetCalls = await installer.resetCalls
        XCTAssertEqual(resetCalls, 1)
    }

    private func makeRuntime(installer: any LocalModelInstalling) -> ModelSetupRuntime {
        let memory = self.memory
        return ModelSetupRuntime(
            installer: installer,
            registry: registry,
            statusStore: statusStore,
            verifier: LocalModelPackageVerifier(
                expectations: [.compact2B: expectation],
                memorySnapshot: { memory },
                nowEpochMilliseconds: { 1 }
            ),
            packagesDirectory: packagesDirectory,
            physicalMemoryBytes: memory.physicalBytes,
            pollInterval: .milliseconds(2),
            catalog: [
                ModelSetupInfo(
                    tier: .compact2B,
                    displayName: "Test model",
                    modelID: expectation.modelID,
                    revision: expectation.revision,
                    license: expectation.license,
                    totalBytes: expectation.totalBytes,
                    minimumPhysicalMemoryBytes: LocalModelTier.compact2B.minimumPhysicalMemoryBytes
                ),
            ]
        )
    }

    private var expectation: LocalModelPackageExpectation {
        LocalModelPackageExpectation(
            modelID: "test/Qwen3-VL-2B-Instruct-4bit",
            revision: revision,
            totalBytes: 22,
            license: "Apache-2.0"
        )
    }

    private var memory: LocalModelMemorySnapshot {
        LocalModelMemorySnapshot(
            physicalBytes: 32 * 1_024 * 1_024 * 1_024,
            availableBytes: 24 * 1_024 * 1_024 * 1_024
        )
    }

    private func makeSource(revision sourceRevision: String? = nil) throws -> LocalModelPackageSource {
        let modelData = Data("verified-model-weights".utf8)
        let digest = SHA256.hash(data: modelData)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = LocalModelPackageManifest(
            schemaVersion: 1,
            tier: .compact2B,
            modelID: expectation.modelID,
            revision: sourceRevision ?? revision,
            displayName: "Test model",
            runtimeDirectory: "Models/\(LocalModelTier.compact2B.runtimeDirectoryName)",
            license: "Apache-2.0",
            licenseFile: "LICENSE",
            noticeFile: "NOTICE",
            totalBytes: Int64(modelData.count),
            files: [
                LocalModelPackageFile(
                    path: "model.safetensors",
                    size: Int64(modelData.count),
                    sha256: digest
                ),
            ]
        )
        return LocalModelPackageSource(
            manifest: manifest,
            manifestData: try JSONEncoder().encode(manifest),
            licenseData: Data("Apache License 2.0".utf8),
            noticeData: Data("Test notice".utf8)
        )
    }

    private func makeVerified(source: LocalModelPackageSource) -> VerifiedLocalModelPackage {
        VerifiedLocalModelPackage(
            tier: .compact2B,
            directory: packagesDirectory
                .appendingPathComponent("2b", isDirectory: true)
                .appendingPathComponent(revision, isDirectory: true),
            manifest: source.manifest,
            verifiedAtEpochMilliseconds: 1
        )
    }

    private func status(
        source: LocalModelPackageSource,
        phase: LocalModelDownloadPhase,
        fraction: Double = 0
    ) -> LocalModelDownloadStatus {
        LocalModelDownloadStatus(
            source: source,
            phase: phase,
            fractionCompleted: fraction,
            updatedAtEpochMilliseconds: 1
        )
    }

    private func waitForDownloadCalls(
        _ expected: Int,
        installer: ControllableInstaller
    ) async throws {
        for _ in 0..<300 {
            if await installer.downloadCalls >= expected { return }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for download call \(expected)")
    }
}

private actor ControllableInstaller: LocalModelInstalling {
    private var currentStatus: LocalModelDownloadStatus
    private let verified: VerifiedLocalModelPackage
    private var continuation: CheckedContinuation<VerifiedLocalModelPackage, Error>?
    private(set) var downloadCalls = 0
    private(set) var resetCalls = 0

    init(status: LocalModelDownloadStatus, verified: VerifiedLocalModelPackage) {
        currentStatus = status
        self.verified = verified
    }

    func status(for tier: LocalModelTier) -> LocalModelDownloadStatus {
        currentStatus
    }

    func download(tier: LocalModelTier) async throws -> VerifiedLocalModelPackage {
        downloadCalls += 1
        currentStatus.phase = .downloading
        currentStatus.setFraction(0.4, now: 2)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func pause() -> LocalModelDownloadStatus? {
        currentStatus.phase = .paused
        currentStatus.errorCode = .cancelled
        continuation?.resume(throwing: LocalModelDownloadFailure(
            code: .cancelled,
            detail: "paused"
        ))
        continuation = nil
        return currentStatus
    }

    func finishDownload() {
        currentStatus.phase = .ready
        currentStatus.setFraction(1, now: 3)
        continuation?.resume(returning: verified)
        continuation = nil
    }

    func reset(tier: LocalModelTier) {
        resetCalls += 1
        currentStatus.phase = .notDownloaded
        currentStatus.setFraction(0, now: 4)
    }
}

private actor FailingInstaller: LocalModelInstalling {
    private let currentStatus: LocalModelDownloadStatus
    private let failure: LocalModelDownloadFailure

    init(status: LocalModelDownloadStatus, failure: LocalModelDownloadFailure) {
        currentStatus = status
        self.failure = failure
    }

    func status(for tier: LocalModelTier) -> LocalModelDownloadStatus { currentStatus }
    func download(tier: LocalModelTier) async throws -> VerifiedLocalModelPackage { throw failure }
    func pause() -> LocalModelDownloadStatus? { currentStatus }
    func reset(tier: LocalModelTier) {}
}
