import Foundation

/// Downloads the real 2B package, pauses it, restarts the downloader and verifies corruption rejection.
/// This entry point exists for the release artifact validation in issue #381.
enum ModelDownloadAcceptanceVerifier {
    static func run(outputURL: URL) async -> Int32 {
        do {
            let result = try await perform()
            let data = try JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: outputURL, options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            let message = "Model download acceptance failed: \(error.localizedDescription)"
            FileHandle.standardError.write(Data((message + "\n").utf8))
            return 1
        }
    }

    private static func perform() async throws -> [String: Any] {
        let tier = LocalModelTier.compact2B
        let source = try BundleLocalModelPackageSourceProvider().source(for: tier)
        let manifest = source.manifest
        let pauseThreshold = Int64(
            ProcessInfo.processInfo.environment["COVIO_MODEL_DOWNLOAD_ACCEPTANCE_PAUSE_BYTES"]
                ?? "33554432"
        ) ?? 33_554_432
        let roots = LocalModelDownloadRoots(
            downloadsDirectory: AppPaths.localModelDownloadsDirectory,
            packagesDirectory: AppPaths.localModelPackagesDirectory
        )
        let registry = LocalModelPackageRegistryStore(path: AppPaths.localModelPackagesFile)
        let partialFile = roots.stagingDirectory(for: tier, revision: manifest.revision)
            .appendingPathComponent("hub/models", isDirectory: true)
            .appendingPathComponent(manifest.modelID, isDirectory: true)
            .appendingPathComponent("model.safetensors")

        let first = makeDownloader(roots: roots, registry: registry)
        let task = Task { try await first.download(tier: tier) }
        let pausedAt = try await waitForPartialModel(
            at: partialFile,
            threshold: pauseThreshold,
            downloader: first,
            tier: tier
        )
        let pausedStatus = await first.pause()
        let stopResult = await task.result
        guard case let .failure(stopError) = stopResult else {
            throw AcceptanceError("The download completed before the pause request.")
        }
        guard let downloadFailure = stopError as? LocalModelDownloadFailure,
              downloadFailure.code == .cancelled
        else {
            throw AcceptanceError("The paused download did not report cancelled: \(stopError)")
        }
        guard pausedStatus?.phase == .paused else {
            throw AcceptanceError("The downloader did not persist a paused status.")
        }

        let resumed = makeDownloader(roots: roots, registry: registry)
        let beforeResume = try await resumed.status(for: tier)
        guard beforeResume.phase == .paused else {
            throw AcceptanceError("A restarted downloader did not load the paused status.")
        }
        let verified = try await resumed.download(tier: tier)
        guard verified.tier == tier, verified.manifest.revision == manifest.revision else {
            throw AcceptanceError("The verified package identity differs from the manifest.")
        }
        let registration = registry.load().registration(for: tier)
        guard registration?.revision == manifest.revision else {
            throw AcceptanceError("The verified package was not registered.")
        }

        let restarted = makeDownloader(roots: roots, registry: registry)
        let ready = try await restarted.status(for: tier)
        guard ready.phase == .ready, ready.downloadedBytes == manifest.totalBytes else {
            throw AcceptanceError("A restarted downloader did not report the package ready.")
        }

        let corruptionCheck = try await verifyCorruptionRejection(
            packageDirectory: verified.directory,
            tier: tier
        )

        return [
            "schemaVersion": 1,
            "ok": true,
            "tier": tier.rawValue,
            "modelID": manifest.modelID,
            "revision": manifest.revision,
            "totalBytes": manifest.totalBytes,
            "pauseThresholdBytes": pauseThreshold,
            "paused": [
                "partialFileBytes": pausedAt.fileBytes,
                "downloadedBytes": pausedStatus?.downloadedBytes ?? 0,
                "phase": pausedStatus?.phase.rawValue ?? "unknown",
            ],
            "resume": [
                "downloadedBytesBeforeResume": beforeResume.downloadedBytes,
                "phaseBeforeResume": beforeResume.phase.rawValue,
                "readyBytes": ready.downloadedBytes,
                "readyPhase": ready.phase.rawValue,
            ],
            "registry": [
                "selectedTier": registry.load().selectedTier?.rawValue ?? "none",
                "registeredRevision": registration?.revision ?? "none",
                "packageDirectory": registration?.directoryPath ?? "none",
            ],
            "corruption": corruptionCheck,
            "app": [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "buildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                "releaseId": Bundle.main.object(forInfoDictionaryKey: "CovioReleaseId") as? String ?? "",
            ],
        ]
    }

    private static func makeDownloader(
        roots: LocalModelDownloadRoots,
        registry: LocalModelPackageRegistryStore
    ) -> LocalModelDownloader {
        LocalModelDownloader(
            downloadsDirectory: roots.downloadsDirectory,
            packagesDirectory: roots.packagesDirectory,
            registry: registry,
            sourceProvider: BundleLocalModelPackageSourceProvider()
        )
    }

    private static func waitForPartialModel(
        at url: URL,
        threshold: Int64,
        downloader: LocalModelDownloader,
        tier: LocalModelTier
    ) async throws -> (fileBytes: Int64, status: LocalModelDownloadStatus) {
        for _ in 0..<720 {
            let fileBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let status = try await downloader.status(for: tier)
            if fileBytes >= threshold {
                return (fileBytes, status)
            }
            if status.phase == .failed || status.phase == .ready {
                throw AcceptanceError("The download ended before the pause threshold: \(status.phase.rawValue)")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw AcceptanceError("The download did not reach the pause threshold.")
    }

    private static func verifyCorruptionRejection(
        packageDirectory: URL,
        tier: LocalModelTier
    ) async throws -> [String: Any] {
        let fileURL = packageDirectory.appendingPathComponent("config.json")
        let original = try Data(contentsOf: fileURL)
        guard !original.isEmpty else {
            throw AcceptanceError("The model config is empty.")
        }
        var corrupted = original
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0x01
        try corrupted.write(to: fileURL, options: .atomic)
        let verifier = LocalModelPackageVerifier()
        do {
            _ = try await Task.detached { try verifier.verify(directory: packageDirectory, tier: tier) }.value
            throw AcceptanceError("A corrupted model package passed verification.")
        } catch let failure as LocalModelPackageFailure {
            guard failure.code == .checksumMismatch else {
                throw AcceptanceError("The corrupted package failed with \(failure.code.rawValue).")
            }
        } catch {
            throw error
        }
        try original.write(to: fileURL, options: .atomic)
        _ = try await Task.detached {
            try verifier.verify(directory: packageDirectory, tier: tier)
        }.value
        return [
            "rejectedErrorCode": LocalModelPackageError.checksumMismatch.rawValue,
            "restored": true,
        ]
    }
}

private struct AcceptanceError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
