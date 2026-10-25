import Foundation

enum ModelSetupPhase: String, Sendable, Equatable {
    case notInstalled
    case unsupported
    case downloading
    case paused
    case verifying
    case ready
    case failed
}

enum ModelSetupFailure: String, Sendable, Equatable {
    case insufficientDisk
    case insufficientMemory
    case network
    case revisionMismatch
    case verification
    case activation
    case generic
}

struct ModelSetupInfo: Identifiable, Sendable, Equatable {
    let tier: LocalModelTier
    let displayName: String
    let modelID: String
    let revision: String
    let license: String
    let totalBytes: Int64
    let minimumPhysicalMemoryBytes: UInt64

    var id: String { tier.rawValue }

    static func make(for tier: LocalModelTier) -> ModelSetupInfo {
        let expectation = LocalModelPackageCatalog.expectations[tier]
        return ModelSetupInfo(
            tier: tier,
            displayName: tier.displayName,
            modelID: expectation?.modelID ?? "unknown",
            revision: expectation?.revision ?? "",
            license: expectation?.license ?? "Apache-2.0",
            totalBytes: expectation?.totalBytes ?? 0,
            minimumPhysicalMemoryBytes: tier.minimumPhysicalMemoryBytes
        )
    }
}

struct ModelSetupState: Identifiable, Sendable, Equatable {
    let info: ModelSetupInfo
    var phase: ModelSetupPhase
    var fractionCompleted: Double
    var downloadedBytes: Int64
    var failure: ModelSetupFailure?
    var detail: String?

    var id: String { info.id }
    var tier: LocalModelTier { info.tier }
    var isReady: Bool { phase == .ready }

    static func initial(info: ModelSetupInfo) -> ModelSetupState {
        ModelSetupState(
            info: info,
            phase: .notInstalled,
            fractionCompleted: 0,
            downloadedBytes: 0,
            failure: nil,
            detail: nil
        )
    }
}

/// Keeps model installation state out of the Hub downloader.
/// Views call this type. Tests replace the downloader with an actor fake.
@MainActor
@Observable
final class ModelSetupRuntime {
    typealias Activation = (VerifiedLocalModelPackage) async throws -> Void
    typealias Deactivation = (LocalModelTier) async throws -> Void

    private let installer: any LocalModelInstalling
    private let registry: LocalModelPackageRegistryStore
    private let statusStore: LocalModelDownloadStatusStore
    private let verifier: LocalModelPackageVerifier
    private let packagesDirectory: URL
    private let physicalMemoryBytes: UInt64
    private let pollInterval: Duration
    private let infos: [ModelSetupInfo]

    private(set) var states: [LocalModelTier: ModelSetupState]
    private(set) var selectedTier: LocalModelTier
    private(set) var activeTier: LocalModelTier?
    private(set) var operationTier: LocalModelTier?
    private(set) var bundledTier: LocalModelTier?
    var activatePackage: Activation?
    var deactivatePackage: Deactivation?

    init(
        installer: any LocalModelInstalling = LocalModelDownloader(),
        registry: LocalModelPackageRegistryStore = LocalModelPackageRegistryStore(
            path: AppPaths.localModelPackagesFile
        ),
        statusStore: LocalModelDownloadStatusStore = LocalModelDownloadStatusStore(
            roots: LocalModelDownloadRoots(
                downloadsDirectory: AppPaths.localModelDownloadsDirectory,
                packagesDirectory: AppPaths.localModelPackagesDirectory
            )
        ),
        verifier: LocalModelPackageVerifier = LocalModelPackageVerifier(),
        packagesDirectory: URL = AppPaths.localModelPackagesDirectory,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        pollInterval: Duration = .milliseconds(150),
        catalog: [ModelSetupInfo]? = nil
    ) {
        let infos = catalog ?? LocalModelTier.allCases.map(ModelSetupInfo.make)
        let registryValue = registry.load()
        var states: [LocalModelTier: ModelSetupState] = [:]
        for info in infos {
            states[info.tier] = Self.initialState(
                info: info,
                registration: registryValue.registration(for: info.tier),
                status: statusStore.load(for: info.tier),
                supported: physicalMemoryBytes >= info.minimumPhysicalMemoryBytes
            )
        }
        let selected = registryValue.selectedTier
            ?? states.values
                .filter(\.isReady)
                .max { $0.tier.rank < $1.tier.rank }?
                .tier
            ?? infos.first(where: { physicalMemoryBytes >= $0.minimumPhysicalMemoryBytes })?.tier
            ?? .compact2B

        self.installer = installer
        self.registry = registry
        self.statusStore = statusStore
        self.verifier = verifier
        self.packagesDirectory = packagesDirectory
        self.physicalMemoryBytes = physicalMemoryBytes
        self.pollInterval = pollInterval
        self.infos = infos
        self.states = states
        self.selectedTier = selected
    }

    var orderedStates: [ModelSetupState] {
        infos.compactMap { states[$0.tier] }
    }

    var isBusy: Bool { operationTier != nil }

    var activeState: ModelSetupState? {
        activeTier.flatMap { states[$0] }
    }

    var preferredState: ModelSetupState {
        states[activeTier ?? selectedTier]
            ?? states[.compact2B]
            ?? ModelSetupState.initial(info: ModelSetupInfo.make(for: .compact2B))
    }

    var isAIReady: Bool { activeState?.isReady == true }
    var activeModelSupportsAgent: Bool {
        activeTier?.supportsAgentToolCalling == true && isAIReady
    }

    func state(for tier: LocalModelTier) -> ModelSetupState {
        states[tier] ?? ModelSetupState.initial(info: ModelSetupInfo.make(for: tier))
    }

    func supports(_ tier: LocalModelTier) -> Bool {
        physicalMemoryBytes >= tier.minimumPhysicalMemoryBytes
    }

    func registration(for tier: LocalModelTier) -> ImportedLocalModelPackage? {
        registry.load().registration(for: tier)
    }

    var selectedRegisteredTier: LocalModelTier? {
        registry.load().selectedTier
    }

    func setActiveTier(_ tier: LocalModelTier?) {
        activeTier = tier
        if let tier {
            selectedTier = tier
            if var state = states[tier], state.phase == .notInstalled {
                state.phase = .ready
                states[tier] = state
            }
        }
    }

    func markBundledModel(tier: LocalModelTier) {
        bundledTier = tier
        selectedTier = tier
        activeTier = tier
        var state = state(for: tier)
        state.phase = supports(tier) ? .ready : .unsupported
        states[tier] = state
    }

    func isBundled(_ tier: LocalModelTier) -> Bool { bundledTier == tier }

    func refresh() async {
        guard operationTier == nil else { return }
        let registryValue = registry.load()
        for info in infos {
            if bundledTier == info.tier {
                var state = state(for: info.tier)
                state.phase = supports(info.tier) ? .ready : .unsupported
                states[info.tier] = state
                continue
            }
            states[info.tier] = Self.initialState(
                info: info,
                registration: registryValue.registration(for: info.tier),
                status: statusStore.load(for: info.tier),
                supported: supports(info.tier)
            )
        }
        if let registrationTier = registryValue.selectedTier {
            selectedTier = registrationTier
        } else if activeTier == nil {
            selectedTier = orderedStates
                .filter(\.isReady)
                .max { $0.tier.rank < $1.tier.rank }?
                .tier
                ?? supportedTier
        }
    }

    func download(_ tier: LocalModelTier) async {
        guard operationTier == nil else { return }
        guard supports(tier) else {
            setFailure(.insufficientMemory, tier: tier)
            return
        }
        operationTier = tier
        selectedTier = tier
        update(tier) { state in
            state.phase = .downloading
            state.fractionCompleted = 0
            state.downloadedBytes = 0
            state.failure = nil
            state.detail = nil
        }
        let previousSelectedTier = registry.load().selectedTier
        let poll = Task { [weak self] in
            await self?.pollStatus(tier: tier)
        }
        defer {
            poll.cancel()
            operationTier = nil
        }
        do {
            let verified = try await installer.download(tier: tier)
            try await finishActivation(verified, previousSelectedTier: previousSelectedTier)
        } catch is CancellationError {
            markPaused(tier)
        } catch {
            markFailure(error, tier: tier)
        }
    }

    func pause() async {
        guard let tier = operationTier else { return }
        if let status = await installer.pause() {
            apply(status)
        } else {
            markPaused(tier)
        }
    }

    func activate(_ tier: LocalModelTier) async {
        guard operationTier == nil else { return }
        guard let registration = registry.load().registration(for: tier) else {
            setFailure(.verification, tier: tier)
            return
        }
        operationTier = tier
        selectedTier = tier
        update(tier) { state in
            state.phase = .verifying
            state.failure = nil
            state.detail = nil
        }
        let previousSelectedTier = registry.load().selectedTier
        defer { operationTier = nil }
        do {
            let verifier = verifier
            let directory = URL(fileURLWithPath: registration.directoryPath, isDirectory: true)
            let verified = try await Task.detached(priority: .userInitiated) {
                try verifier.verify(directory: directory, tier: tier)
            }.value
            try registry.select(tier: tier)
            try await finishActivation(verified, previousSelectedTier: previousSelectedTier)
        } catch {
            markFailure(error, tier: tier)
        }
    }

    func importPackage(tier: LocalModelTier, directory: URL) async {
        guard operationTier == nil else { return }
        guard supports(tier) else {
            setFailure(.insufficientMemory, tier: tier)
            return
        }
        operationTier = tier
        selectedTier = tier
        update(tier) { state in
            state.phase = .verifying
            state.failure = nil
            state.detail = nil
        }
        let previousSelectedTier = registry.load().selectedTier
        defer { operationTier = nil }
        do {
            let verifier = verifier
            let verified = try await Task.detached(priority: .userInitiated) {
                try verifier.verify(directory: directory, tier: tier)
            }.value
            try registry.register(verified)
            try await finishActivation(verified, previousSelectedTier: previousSelectedTier)
        } catch {
            markFailure(error, tier: tier)
        }
    }

    func remove(_ tier: LocalModelTier) async {
        guard operationTier == nil else { return }
        operationTier = tier
        defer { operationTier = nil }
        do {
            try await deactivatePackage?(tier)
            let registration = registry.load().registration(for: tier)
            if let registration,
               isManagedPackage(URL(fileURLWithPath: registration.directoryPath, isDirectory: true)),
               FileManager.default.fileExists(atPath: registration.directoryPath)
            {
                try FileManager.default.removeItem(
                    at: URL(fileURLWithPath: registration.directoryPath, isDirectory: true)
                )
            }
            try registry.remove(tier: tier)
            try await installer.reset(tier: tier)
            if activeTier == tier { activeTier = nil }
            if bundledTier == tier { bundledTier = nil }
            states[tier] = Self.initialState(
                info: state(for: tier).info,
                registration: nil,
                status: nil,
                supported: supports(tier)
            )
            if selectedTier == tier {
                selectedTier = orderedStates
                    .filter(\.isReady)
                    .max { $0.tier.rank < $1.tier.rank }?
                    .tier
                    ?? supportedTier
            }
        } catch {
            markFailure(error, tier: tier)
        }
    }

    private var supportedTier: LocalModelTier {
        infos.first(where: { supports($0.tier) })?.tier ?? .compact2B
    }

    private func finishActivation(
        _ verified: VerifiedLocalModelPackage,
        previousSelectedTier: LocalModelTier?
    ) async throws {
        do {
            try await activatePackage?(verified)
            activeTier = verified.tier
            selectedTier = verified.tier
            update(verified.tier) { state in
                state.phase = .ready
                state.fractionCompleted = 1
                state.downloadedBytes = state.info.totalBytes
                state.failure = nil
                state.detail = nil
            }
        } catch {
            if registry.load().selectedTier == verified.tier {
                _ = try? registry.select(tier: previousSelectedTier)
            }
            throw error
        }
    }

    private func pollStatus(tier: LocalModelTier) async {
        while !Task.isCancelled, operationTier == tier {
            if let status = try? await installer.status(for: tier) {
                apply(status)
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func apply(_ status: LocalModelDownloadStatus) {
        guard status.tier == operationTier else { return }
        let info = state(for: status.tier).info
        guard status.modelID == info.modelID, status.revision == info.revision else {
            setFailure(.revisionMismatch, tier: status.tier)
            return
        }
        update(status.tier) { state in
            state.fractionCompleted = min(max(status.fractionCompleted, 0), 1)
            state.downloadedBytes = min(max(status.downloadedBytes, 0), status.totalBytes)
            state.detail = status.detail
            switch status.phase {
            case .notDownloaded:
                state.phase = .notInstalled
                state.failure = nil
            case .downloading:
                state.phase = .downloading
                state.failure = nil
            case .paused:
                state.phase = .paused
                state.failure = nil
            case .verifying, .ready:
                state.phase = .verifying
                state.failure = nil
            case .failed:
                state.phase = .failed
                state.failure = Self.failure(for: status.errorCode)
            }
        }
    }

    private func markPaused(_ tier: LocalModelTier) {
        update(tier) { state in
            state.phase = .paused
            state.failure = nil
            state.detail = nil
        }
    }

    private func setFailure(_ failure: ModelSetupFailure, tier: LocalModelTier) {
        update(tier) { state in
            state.phase = .failed
            state.failure = failure
        }
    }

    private func markFailure(_ error: Error, tier: LocalModelTier) {
        if let failure = error as? LocalModelDownloadFailure {
            if failure.code == .cancelled {
                markPaused(tier)
                return
            }
            setFailure(Self.failure(for: failure.code), tier: tier)
            states[tier]?.detail = failure.detail
            return
        }
        if let failure = error as? LocalModelPackageFailure {
            setFailure(Self.failure(for: failure.code), tier: tier)
            states[tier]?.detail = failure.detail
            return
        }
        setFailure(.activation, tier: tier)
        states[tier]?.detail = error.localizedDescription
    }

    private func update(_ tier: LocalModelTier, _ mutate: (inout ModelSetupState) -> Void) {
        guard var state = states[tier] else { return }
        mutate(&state)
        states[tier] = state
    }

    private func isManagedPackage(_ directory: URL) -> Bool {
        let root = packagesDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let path = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private static func initialState(
        info: ModelSetupInfo,
        registration: ImportedLocalModelPackage?,
        status: LocalModelDownloadStatus?,
        supported: Bool
    ) -> ModelSetupState {
        guard supported else {
            return ModelSetupState(
                info: info,
                phase: .unsupported,
                fractionCompleted: 0,
                downloadedBytes: 0,
                failure: .insufficientMemory,
                detail: nil
            )
        }
        if registration != nil {
            let directory = URL(fileURLWithPath: registration?.directoryPath ?? "", isDirectory: true)
            let manifest = directory.appendingPathComponent("FileNamingModelManifest.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return ModelSetupState(
                    info: info,
                    phase: .ready,
                    fractionCompleted: 1,
                    downloadedBytes: info.totalBytes,
                    failure: nil,
                    detail: nil
                )
            }
            return ModelSetupState(
                info: info,
                phase: .failed,
                fractionCompleted: 0,
                downloadedBytes: 0,
                failure: .verification,
                detail: "The registered model directory is missing."
            )
        }
        guard let status, status.tier == info.tier else {
            return .initial(info: info)
        }
        if status.modelID != info.modelID || status.revision != info.revision {
            return ModelSetupState(
                info: info,
                phase: .failed,
                fractionCompleted: status.fractionCompleted,
                downloadedBytes: status.downloadedBytes,
                failure: .revisionMismatch,
                detail: status.detail
            )
        }
        let phase: ModelSetupPhase
        let failure: ModelSetupFailure?
        switch status.phase {
        case .notDownloaded:
            phase = .notInstalled
            failure = nil
        case .downloading, .verifying:
            phase = .paused
            failure = nil
        case .paused:
            phase = .paused
            failure = nil
        case .ready:
            phase = .paused
            failure = nil
        case .failed:
            phase = .failed
            failure = Self.failure(for: status.errorCode)
        }
        return ModelSetupState(
            info: info,
            phase: phase,
            fractionCompleted: min(max(status.fractionCompleted, 0), 1),
            downloadedBytes: min(max(status.downloadedBytes, 0), status.totalBytes),
            failure: failure,
            detail: status.detail
        )
    }

    private static func failure(for error: LocalModelDownloadErrorCode?) -> ModelSetupFailure {
        switch error {
        case .insufficientDisk: .insufficientDisk
        case .insufficientMemory, .insufficientHardware: .insufficientMemory
        case .revisionMismatch: .revisionMismatch
        case .verificationFailed, .existingPackageInvalid: .verification
        case .activationFailed: .activation
        case .sourceUnavailable, .downloadFailed: .network
        case .busy, .manifestInvalid, .cancelled, .none: .generic
        }
    }

    private static func failure(for error: LocalModelPackageError) -> ModelSetupFailure {
        switch error {
        case .insufficientHardware, .insufficientMemory: .insufficientMemory
        case .revisionMismatch: .revisionMismatch
        case .checksumMismatch, .fileMissing, .fileSizeMismatch, .symbolicLink, .totalSizeMismatch:
            .verification
        case .manifestUnreadable, .unsupportedSchema, .tierMismatch, .modelMismatch,
             .licenseRejected, .invalidPath, .modelBusy:
            .generic
        }
    }
}
