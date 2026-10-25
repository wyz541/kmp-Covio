import CryptoKit
import XCTest
@testable import Covio

final class LocalModelPackageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-model-package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testValidPackageChecksRevisionLicenseAndEveryChecksum() throws {
        let package = try makePackage()
        let verifier = makeVerifier(totalBytes: package.modelSize)
        let verified = try verifier.verify(directory: package.directory, tier: .compact2B)
        XCTAssertEqual(verified.manifest.revision, revision)
        XCTAssertEqual(verified.directory.standardizedFileURL, package.directory.standardizedFileURL)
    }

    func testChecksumMismatchIsRejected() throws {
        let package = try makePackage()
        try Data(repeating: 0, count: Int(package.modelSize)).write(
            to: package.directory.appendingPathComponent("model.safetensors")
        )
        let verifier = makeVerifier(totalBytes: package.modelSize)
        XCTAssertThrowsError(try verifier.verify(directory: package.directory, tier: .compact2B)) {
            XCTAssertEqual(($0 as? LocalModelPackageFailure)?.code, .checksumMismatch)
        }
    }

    func testUnsafeManifestPathIsRejectedByTheSharedContract() throws {
        let package = try makePackage()
        let manifestURL = package.directory.appendingPathComponent("FileNamingModelManifest.json")
        let manifest = try JSONDecoder().decode(
            LocalModelPackageManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let unsafe = LocalModelPackageManifest(
            schemaVersion: manifest.schemaVersion,
            tier: manifest.tier,
            modelID: manifest.modelID,
            revision: manifest.revision,
            displayName: manifest.displayName,
            runtimeDirectory: manifest.runtimeDirectory,
            license: manifest.license,
            licenseFile: manifest.licenseFile,
            noticeFile: manifest.noticeFile,
            totalBytes: manifest.totalBytes,
            files: manifest.files.map {
                LocalModelPackageFile(path: "../\($0.path)", size: $0.size, sha256: $0.sha256)
            }
        )
        try JSONEncoder().encode(unsafe).write(to: manifestURL)

        XCTAssertThrowsError(
            try makeVerifier(totalBytes: package.modelSize)
                .verify(directory: package.directory, tier: .compact2B)
        ) {
            XCTAssertEqual(($0 as? LocalModelPackageFailure)?.code, .invalidPath)
        }
    }

    func testRevisionMismatchIsRejected() throws {
        let package = try makePackage(revision: String(repeating: "b", count: 40))
        XCTAssertThrowsError(
            try makeVerifier(totalBytes: package.modelSize)
                .verify(directory: package.directory, tier: .compact2B)
        ) {
            XCTAssertEqual(($0 as? LocalModelPackageFailure)?.code, .revisionMismatch)
        }
    }

    func testTierMismatchIsRejected() throws {
        let package = try makePackage()
        XCTAssertThrowsError(
            try makeVerifier(totalBytes: package.modelSize, additionalTier: .balanced4B)
                .verify(directory: package.directory, tier: .balanced4B)
        ) {
            XCTAssertEqual(($0 as? LocalModelPackageFailure)?.code, .tierMismatch)
        }
    }

    func testInsufficientMemoryIsRejectedBeforeReadingWeights() throws {
        let package = try makePackage()
        let verifier = makeVerifier(
            totalBytes: package.modelSize,
            memory: LocalModelMemorySnapshot(
                physicalBytes: 16 * 1_024 * 1_024 * 1_024,
                availableBytes: 1 * 1_024 * 1_024 * 1_024
            )
        )
        XCTAssertThrowsError(try verifier.verify(directory: package.directory, tier: .compact2B)) {
            XCTAssertEqual(($0 as? LocalModelPackageFailure)?.code, .insufficientMemory)
        }
    }

    func testImporterRegistersAVerifiedPackage() throws {
        let package = try makePackage()
        let registry = LocalModelPackageRegistryStore(
            path: directory.appendingPathComponent("registry/imported.json")
        )
        let importer = LocalModelPackageImporter(
            verifier: makeVerifier(totalBytes: package.modelSize),
            registry: registry
        )

        let verified = try importer.importPackage(directory: package.directory, tier: .compact2B)
        let loaded = registry.load()

        XCTAssertEqual(verified.tier, .compact2B)
        XCTAssertEqual(loaded.selectedTier, .compact2B)
        XCTAssertEqual(loaded.registration(for: .compact2B)?.revision, revision)
        XCTAssertEqual(loaded.registration(for: .compact2B)?.directoryPath, package.directory.path)
    }

    func testAgentRejectsAThirtyBModelBeforeLoadingIt() async {
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: { .failure("unused") },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in .failure("unused") }
            )
        )
        let model = LocalAgentModel(
            modelDirectory: directory.appendingPathComponent("missing-model"),
            gateway: gateway,
            agentToolCallingAvailable: { false }
        )

        do {
            _ = try await model.respond(to: "hello") { _ in }
            XCTFail("30B-A3B must not enter the Agent tool-calling path")
        } catch let error as NamingModelError {
            XCTAssertEqual(error.code, .agentModelUnsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private var revision: String { String(repeating: "a", count: 40) }

    private func makeVerifier(
        totalBytes: Int64,
        additionalTier: LocalModelTier? = nil,
        memory: LocalModelMemorySnapshot = LocalModelMemorySnapshot(
            physicalBytes: 16 * 1_024 * 1_024 * 1_024,
            availableBytes: 12 * 1_024 * 1_024 * 1_024
        )
    ) -> LocalModelPackageVerifier {
        let expectation = LocalModelPackageExpectation(
            modelID: "test/Qwen3-VL-2B-Instruct-4bit",
            revision: revision,
            totalBytes: totalBytes,
            license: "Apache-2.0"
        )
        var expectations: [LocalModelTier: LocalModelPackageExpectation] = [
            .compact2B: expectation
        ]
        if let additionalTier {
            expectations[additionalTier] = expectation
        }
        return LocalModelPackageVerifier(
            expectations: expectations,
            memorySnapshot: { memory },
            nowEpochMilliseconds: { 123 }
        )
    }

    private func makePackage(revision manifestRevision: String? = nil) throws -> (
        directory: URL,
        modelSize: Int64
    ) {
        let package = directory.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let model = Data("local-model-weights".utf8)
        try model.write(to: package.appendingPathComponent("model.safetensors"))
        try Data("Apache License 2.0".utf8).write(to: package.appendingPathComponent("LICENSE"))
        try Data("Covio model notice".utf8).write(to: package.appendingPathComponent("NOTICE"))
        let manifest = LocalModelPackageManifest(
            schemaVersion: 1,
            tier: .compact2B,
            modelID: "test/Qwen3-VL-2B-Instruct-4bit",
            revision: manifestRevision ?? revision,
            displayName: "Test model",
            runtimeDirectory: "Models/\(LocalModelTier.compact2B.runtimeDirectoryName)",
            license: "Apache-2.0",
            licenseFile: "LICENSE",
            noticeFile: "NOTICE",
            totalBytes: Int64(model.count),
            files: [
                LocalModelPackageFile(
                    path: "model.safetensors",
                    size: Int64(model.count),
                    sha256: SHA256.hash(data: model).map { String(format: "%02x", $0) }.joined()
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(
            to: package.appendingPathComponent("FileNamingModelManifest.json")
        )
        return (package, Int64(model.count))
    }
}
