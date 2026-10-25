import CryptoKit
import Foundation
import XCTest
@testable import Covio

final class LocalModelDownloaderTests: XCTestCase {
    private let revision = String(repeating: "a", count: 40)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-model-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDownloadVerifiesMovesAndRegistersThePackage() async throws {
        let source = try makeSource()
        let downloader = makeDownloader(
            source: source,
            remote: ImmediateRemoteDownloader(modelData: source.modelData)
        )

        let verified = try await downloader.download(tier: .compact2B)
        let expected = root
            .appendingPathComponent("Packages/2b", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)

        XCTAssertEqual(verified.directory.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Downloads/2b/\(revision)").path
            )
        )
        XCTAssertEqual(
            registry().registration(for: .compact2B)?.directoryPath,
            expected.path
        )
        let status = try await downloader.status(for: .compact2B)
        XCTAssertEqual(status.phase, .ready)
        XCTAssertEqual(status.fractionCompleted, 1)
    }

    func testValidUnregisteredDestinationIsRegisteredWithoutRemoteDownload() async throws {
        let source = try makeSource()
        let destination = root
            .appendingPathComponent("Packages/2b", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try source.manifestData.write(
            to: destination.appendingPathComponent("FileNamingModelManifest.json")
        )
        try source.licenseData.write(to: destination.appendingPathComponent("LICENSE"))
        try source.noticeData.write(to: destination.appendingPathComponent("NOTICE"))
        try source.modelData.write(to: destination.appendingPathComponent("model.safetensors"))
        let downloader = makeDownloader(
            source: source,
            remote: FailingRemoteDownloader()
        )

        let verified = try await downloader.download(tier: .compact2B)

        XCTAssertEqual(verified.directory.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertEqual(registry().registration(for: .compact2B)?.revision, revision)
        let status = try await downloader.status(for: .compact2B)
        XCTAssertEqual(status.phase, .ready)
    }

    func testPausedDownloadSurvivesRestartAndContinues() async throws {
        let source = try makeSource()
        let first = makeDownloader(
            source: source,
            remote: PausingRemoteDownloader(modelData: source.modelData)
        )
        let task = Task { try await first.download(tier: .compact2B) }
        _ = try await waitForPhase(.downloading, downloader: first)

        let paused = await first.pause()
        XCTAssertEqual(paused?.phase, .paused)
        let result = await task.result
        guard case let .failure(error) = result else {
            return XCTFail("The paused download must stop")
        }
        XCTAssertEqual((error as? LocalModelDownloadFailure)?.code, .cancelled)

        let staging = root.appendingPathComponent("Downloads/2b/\(revision)")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: staging.appendingPathComponent("hub/models/test/Qwen3-VL-2B-Instruct-4bit/model.safetensors").path
            )
        )

        let resumed = makeDownloader(
            source: source,
            remote: ResumingRemoteDownloader(modelData: source.modelData)
        )
        let statusBefore = try await resumed.status(for: .compact2B)
        XCTAssertEqual(statusBefore.phase, .paused)

        _ = try await resumed.download(tier: .compact2B)
        XCTAssertEqual(registry().registration(for: .compact2B)?.revision, revision)
        let statusAfter = try await resumed.status(for: .compact2B)
        XCTAssertEqual(statusAfter.phase, .ready)
    }

    func testInterruptedStatusBecomesPausedAfterRestart() async throws {
        let source = try makeSource()
        let roots = LocalModelDownloadRoots(
            downloadsDirectory: root.appendingPathComponent("Downloads", isDirectory: true),
            packagesDirectory: root.appendingPathComponent("Packages", isDirectory: true)
        )
        try LocalModelDownloadStatusStore(roots: roots).save(
            LocalModelDownloadStatus(
                source: source,
                phase: .downloading,
                fractionCompleted: 0.42,
                updatedAtEpochMilliseconds: 100
            )
        )
        let downloader = makeDownloader(
            source: source,
            remote: ImmediateRemoteDownloader(modelData: source.modelData)
        )

        let status = try await downloader.status(for: .compact2B)
        XCTAssertEqual(status.phase, .paused)
        XCTAssertEqual(status.fractionCompleted, 0.42, accuracy: 0.000_1)
        XCTAssertNil(registry().registration(for: .compact2B))
    }

    func testChecksumFailureDoesNotRegisterOrKeepStaging() async throws {
        let source = try makeSource()
        let downloader = makeDownloader(
            source: source,
            remote: ImmediateRemoteDownloader(modelData: Data("wrong-model".utf8))
        )

        do {
            _ = try await downloader.download(tier: .compact2B)
            XCTFail("A checksum mismatch must fail")
        } catch let failure as LocalModelDownloadFailure {
            XCTAssertEqual(failure.code, .verificationFailed)
        }

        XCTAssertNil(registry().registration(for: .compact2B))
        let failedStatus = try await downloader.status(for: .compact2B)
        XCTAssertEqual(failedStatus.phase, .failed)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Downloads/2b/\(revision)").path
            )
        )
    }

    func testInsufficientDiskFailsBeforeRemoteDownload() async throws {
        let source = try makeSource()
        let downloader = makeDownloader(
            source: source,
            remote: ImmediateRemoteDownloader(modelData: source.modelData),
            diskAvailable: 1_024
        )

        do {
            _ = try await downloader.download(tier: .compact2B)
            XCTFail("A low-disk warning must stop the download")
        } catch let failure as LocalModelDownloadFailure {
            XCTAssertEqual(failure.code, .insufficientDisk)
        }
        XCTAssertNil(registry().registration(for: .compact2B))
    }

    func testRemoteFailureDoesNotRegisterOrActivateThePackage() async throws {
        let source = try makeSource()
        let downloader = makeDownloader(
            source: source,
            remote: FailingRemoteDownloader()
        )

        do {
            _ = try await downloader.download(tier: .compact2B)
            XCTFail("A network failure must stop the download")
        } catch let failure as LocalModelDownloadFailure {
            XCTAssertEqual(failure.code, .downloadFailed)
        }

        XCTAssertNil(registry().registration(for: .compact2B))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Packages/2b")
                    .appendingPathComponent(revision)
                    .path
            )
        )
        let status = try await downloader.status(for: .compact2B)
        XCTAssertEqual(status.phase, .failed)
    }

    func testSymbolicLinkSnapshotIsRejectedBeforeWriting() async throws {
        let source = try makeSource()
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let downloader = makeDownloader(
            source: source,
            remote: SymbolicLinkRemoteDownloader(outside: outside)
        )

        do {
            _ = try await downloader.download(tier: .compact2B)
            XCTFail("A symbolic link snapshot must not be verified or registered")
        } catch let failure as LocalModelDownloadFailure {
            XCTAssertEqual(failure.code, .downloadFailed)
        }

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: outside.path),
            []
        )
        XCTAssertNil(registry().registration(for: .compact2B))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Downloads/2b/\(revision)").path
            )
        )
    }

    func testBundleSourceProviderFindsEveryManifestAndAttribution() throws {
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let fixtures: [(LocalModelTier, String, String)] = [
            (.compact2B, "FileNamingModelManifest.json", "Qwen3-VL-2B-Instruct"),
            (.balanced4B, "FileNamingModelManifest-balanced4B.json", "Qwen3-VL-4B-Instruct"),
            (.highQuality8B, "FileNamingModelManifest-highQuality8B.json", "Qwen3-VL-8B-Instruct"),
            (
                .heavy30BA3B,
                "FileNamingModelManifest-heavy30BA3B.json",
                "Qwen3-VL-30B-A3B-Instruct"
            ),
        ]
        var expected: [LocalModelTier: LocalModelPackageSource] = [:]

        for (tier, manifestFile, noticeDirectoryName) in fixtures {
            let licenseData = Data("license-\(tier.rawValue)".utf8)
            let noticeData = Data("notice-\(tier.rawValue)".utf8)
            let manifest = LocalModelPackageManifest(
                schemaVersion: 1,
                tier: tier,
                modelID: "test/\(tier.rawValue)",
                revision: revision,
                displayName: "Test \(tier.rawValue)",
                runtimeDirectory: "Models/\(tier.runtimeDirectoryName)",
                license: "Apache-2.0",
                licenseFile: "LICENSE",
                noticeFile: "NOTICE",
                totalBytes: 0,
                files: []
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try manifestData.write(to: resources.appendingPathComponent(manifestFile))

            let attribution = resources
                .appendingPathComponent("ThirdPartyNotices/model", isDirectory: true)
                .appendingPathComponent(noticeDirectoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: attribution, withIntermediateDirectories: true)
            try licenseData.write(to: attribution.appendingPathComponent("LICENSE"))
            try noticeData.write(to: attribution.appendingPathComponent("NOTICE"))
            expected[tier] = LocalModelPackageSource(
                manifest: manifest,
                manifestData: manifestData,
                licenseData: licenseData,
                noticeData: noticeData
            )
        }

        let provider = BundleLocalModelPackageSourceProvider(resourceDirectory: resources)
        for (tier, _, _) in fixtures {
            XCTAssertEqual(try provider.source(for: tier), expected[tier])
        }
    }

    func testHubRemoteDownloaderDownloadsAPinnedFileWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["COVIO_REAL_MODEL_DOWNLOAD_SMOKE"] == "1" else {
            throw XCTSkip("Set COVIO_REAL_MODEL_DOWNLOAD_SMOKE=1 to use Hugging Face.")
        }
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        let sourceManifestData = try Data(
            contentsOf: resources.appendingPathComponent("FileNamingModelManifest.json")
        )
        let sourceManifest = try JSONDecoder().decode(
            LocalModelPackageManifest.self,
            from: sourceManifestData
        )
        let config = try XCTUnwrap(sourceManifest.files.first { $0.path == "config.json" })
        let manifest = LocalModelPackageManifest(
            schemaVersion: sourceManifest.schemaVersion,
            tier: sourceManifest.tier,
            modelID: sourceManifest.modelID,
            revision: sourceManifest.revision,
            displayName: sourceManifest.displayName,
            runtimeDirectory: sourceManifest.runtimeDirectory,
            license: sourceManifest.license,
            licenseFile: sourceManifest.licenseFile,
            noticeFile: sourceManifest.noticeFile,
            totalBytes: config.size,
            files: [config]
        )
        let base = root.appendingPathComponent("hub-smoke", isDirectory: true)
        let snapshot = try await HubLocalModelRemoteDownloader().download(
            manifest: manifest,
            to: base,
            progress: { _ in }
        )
        let downloaded = snapshot.appendingPathComponent(config.path)
        XCTAssertEqual(try Data(contentsOf: downloaded).count, Int(config.size))
        let digest = SHA256.hash(data: try Data(contentsOf: downloaded))
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(digest, config.sha256)
    }

    private func makeDownloader(
        source: LocalModelPackageSource,
        remote: any LocalModelRemoteDownloading,
        diskAvailable: Int64 = 10_000_000_000
    ) -> LocalModelDownloader {
        let expectation = LocalModelPackageExpectation(
            modelID: source.manifest.modelID,
            revision: source.manifest.revision,
            totalBytes: source.manifest.totalBytes,
            license: source.manifest.license
        )
        let memory = LocalModelMemorySnapshot(
            physicalBytes: 16 * 1_024 * 1_024 * 1_024,
            availableBytes: 12 * 1_024 * 1_024 * 1_024
        )
        return LocalModelDownloader(
            downloadsDirectory: root.appendingPathComponent("Downloads", isDirectory: true),
            packagesDirectory: root.appendingPathComponent("Packages", isDirectory: true),
            registry: LocalModelPackageRegistryStore(
                path: root.appendingPathComponent("imported-packages.json")
            ),
            verifier: LocalModelPackageVerifier(
                expectations: [.compact2B: expectation],
                memorySnapshot: { memory },
                nowEpochMilliseconds: { 123 }
            ),
            expectations: [.compact2B: expectation],
            sourceProvider: FixedLocalModelPackageSourceProvider(source: source),
            remoteFactory: { _ in remote },
            memorySnapshot: { memory },
            availableDiskBytes: { _ in diskAvailable },
            nowEpochMilliseconds: { 456 }
        )
    }

    private func registry() -> LocalModelPackageRegistry {
        LocalModelPackageRegistryStore(
            path: root.appendingPathComponent("imported-packages.json")
        ).load()
    }

    private typealias TestSource = LocalModelPackageSource

    private func makeSource() throws -> TestSource {
        let modelData = Data("verified-model-weights".utf8)
        let digest = SHA256.hash(data: modelData)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = LocalModelPackageManifest(
            schemaVersion: 1,
            tier: .compact2B,
            modelID: "test/Qwen3-VL-2B-Instruct-4bit",
            revision: revision,
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return LocalModelPackageSource(
            manifest: manifest,
            manifestData: try encoder.encode(manifest),
            licenseData: Data("Apache License 2.0".utf8),
            noticeData: Data("Test model notice".utf8)
        )
    }

    private func waitForPhase(
        _ phase: LocalModelDownloadPhase,
        downloader: LocalModelDownloader
    ) async throws -> LocalModelDownloadStatus {
        for _ in 0..<200 {
            let status = try await downloader.status(for: .compact2B)
            if status.phase == phase { return status }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw XCTSkip("Timed out waiting for \(phase.rawValue)")
    }
}

private extension LocalModelPackageSource {
    var modelData: Data {
        // Test sources use one file whose contents are written by the fake transport.
        manifest.files.count == 1 ? Data("verified-model-weights".utf8) : Data()
    }
}

private struct FixedLocalModelPackageSourceProvider: LocalModelPackageSourceProviding {
    let source: LocalModelPackageSource

    func source(for tier: LocalModelTier) throws -> LocalModelPackageSource {
        source
    }
}

private struct ImmediateRemoteDownloader: LocalModelRemoteDownloading {
    let modelData: Data

    func download(
        manifest: LocalModelPackageManifest,
        to downloadBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let directory = try modelDirectory(manifest: manifest, in: downloadBase)
        try modelData.write(to: directory.appendingPathComponent("model.safetensors"))
        progress(0.5)
        progress(1)
        return directory
    }
}

private struct FailingRemoteDownloader: LocalModelRemoteDownloading {
    func download(
        manifest: LocalModelPackageManifest,
        to downloadBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        throw URLError(.notConnectedToInternet)
    }
}

private struct SymbolicLinkRemoteDownloader: LocalModelRemoteDownloading {
    let outside: URL

    func download(
        manifest: LocalModelPackageManifest,
        to downloadBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let directory = try modelDirectory(manifest: manifest, in: downloadBase)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        return directory
    }
}

private struct PausingRemoteDownloader: LocalModelRemoteDownloading {
    let modelData: Data

    func download(
        manifest: LocalModelPackageManifest,
        to downloadBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let directory = try modelDirectory(manifest: manifest, in: downloadBase)
        try Data(modelData.prefix(max(1, modelData.count / 2)))
            .write(to: directory.appendingPathComponent("model.safetensors"))
        progress(0.5)
        try await Task.sleep(for: .seconds(30))
        return directory
    }
}

private struct ResumingRemoteDownloader: LocalModelRemoteDownloading {
    let modelData: Data

    func download(
        manifest: LocalModelPackageManifest,
        to downloadBase: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let directory = try modelDirectory(manifest: manifest, in: downloadBase)
        let partial = directory.appendingPathComponent("model.safetensors")
        guard FileManager.default.fileExists(atPath: partial.path) else {
            throw LocalModelDownloadFailure(
                code: .downloadFailed,
                detail: "The test resume did not find the partial file."
            )
        }
        try modelData.write(to: partial)
        progress(1)
        return directory
    }
}

private func modelDirectory(
    manifest: LocalModelPackageManifest,
    in downloadBase: URL
) throws -> URL {
    let directory = downloadBase
        .appendingPathComponent("models", isDirectory: true)
        .appendingPathComponent(manifest.modelID, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
