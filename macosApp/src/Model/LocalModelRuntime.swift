import Foundation
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

enum LocalModelTier: String, CaseIterable, Codable, Sendable {
    case compact2B = "2b"
    case balanced4B = "4b"
    case highQuality8B = "8b"
    case heavy30BA3B = "30b-a3b"

    var rank: Int {
        switch self {
        case .compact2B: 0
        case .balanced4B: 1
        case .highQuality8B: 2
        case .heavy30BA3B: 3
        }
    }

    var minimumPhysicalMemoryBytes: UInt64 {
        switch self {
        case .compact2B: 7 * 1_024 * 1_024 * 1_024
        case .balanced4B: 16 * 1_024 * 1_024 * 1_024
        case .highQuality8B: 24 * 1_024 * 1_024 * 1_024
        case .heavy30BA3B: 32 * 1_024 * 1_024 * 1_024
        }
    }

    var estimatedWorkingSetBytes: UInt64 {
        switch self {
        case .compact2B: 4 * 1_024 * 1_024 * 1_024
        case .balanced4B: 6 * 1_024 * 1_024 * 1_024
        case .highQuality8B: 9 * 1_024 * 1_024 * 1_024
        case .heavy30BA3B: 20 * 1_024 * 1_024 * 1_024
        }
    }

    var supportsAgentToolCalling: Bool {
        self != .heavy30BA3B
    }

    var runtimeDirectoryName: String {
        switch self {
        case .compact2B: "Qwen3VL-2B-Instruct-4bit"
        case .balanced4B: "Qwen3VL-4B-Instruct-4bit"
        case .highQuality8B: "Qwen3VL-8B-Instruct-4bit"
        case .heavy30BA3B: "Qwen3VL-30B-A3B-Instruct-4bit"
        }
    }
}

struct LocalModelCandidate: Sendable, Equatable {
    let tier: LocalModelTier
    let directory: URL
}

enum LocalModelSelector {
    static func supportedTiers(physicalMemoryBytes: UInt64) -> [LocalModelTier] {
        LocalModelTier.allCases.filter {
            physicalMemoryBytes >= $0.minimumPhysicalMemoryBytes
        }
    }

    static func select(
        candidates: [LocalModelCandidate],
        physicalMemoryBytes: UInt64
    ) -> LocalModelCandidate? {
        let supported = Set(supportedTiers(physicalMemoryBytes: physicalMemoryBytes))
        return candidates
            .filter { supported.contains($0.tier) }
            .max { $0.tier.rank < $1.tier.rank }
    }
}

struct SharedModelRuntimeLease<Resource: Sendable>: Sendable {
    let resource: Resource
    private let runtime: SharedModelRuntime<Resource>

    fileprivate init(resource: Resource, runtime: SharedModelRuntime<Resource>) {
        self.resource = resource
        self.runtime = runtime
    }

    func release() async {
        await runtime.releaseLease()
    }
}

/// Serializes access to one expensive local resource.
///
/// The loader runs only once until `unload` clears the resource. A lease holder
/// can await any number of operations while other callers wait for release.
actor SharedModelRuntime<Resource: Sendable> {
    typealias Loader = @Sendable () async throws -> Resource

    private var loader: Loader
    private var resource: Resource?
    private var leased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func acquire() async throws -> SharedModelRuntimeLease<Resource> {
        await acquireLock()
        do {
            try Task.checkCancellation()
            let resource = try await loadIfNeeded()
            try Task.checkCancellation()
            return SharedModelRuntimeLease(resource: resource, runtime: self)
        } catch {
            releaseLock()
            throw error
        }
    }

    func unload() async {
        await acquireLock()
        resource = nil
        releaseLock()
    }

    func replaceLoader(_ next: @escaping Loader) async {
        await acquireLock()
        resource = nil
        loader = next
        releaseLock()
    }

    fileprivate func releaseLease() {
        releaseLock()
    }

    private func loadIfNeeded() async throws -> Resource {
        if let resource { return resource }
        let loaded = try await loader()
        resource = loaded
        return loaded
    }

    private func acquireLock() async {
        if !leased {
            leased = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseLock() {
        if waiters.isEmpty {
            leased = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

protocol LocalModelContainerProviding: Sendable {
    func acquireModelContainer() async throws -> LocalModelLease
    func unloadModelContainer() async
}

struct LocalModelLease: Sendable {
    let container: ModelContainer
    private let lease: SharedModelRuntimeLease<ModelContainer>

    fileprivate init(lease: SharedModelRuntimeLease<ModelContainer>) {
        container = lease.resource
        self.lease = lease
    }

    func release() async {
        await lease.release()
    }
}

typealias LocalModelRuntime = SharedModelRuntime<ModelContainer>

extension SharedModelRuntime: LocalModelContainerProviding where Resource == ModelContainer {
    init(modelDirectory: URL) {
        self.init(loader: {
            try await loadLocalModelContainer(from: modelDirectory)
        })
    }

    func acquireModelContainer() async throws -> LocalModelLease {
        LocalModelLease(lease: try await acquire())
    }

    func unloadModelContainer() async {
        await unload()
    }

    func replaceModelDirectory(_ directory: URL) async {
        await replaceLoader {
            try await loadLocalModelContainer(from: directory)
        }
    }
}

private func loadLocalModelContainer(from directory: URL) async throws -> ModelContainer {
    try validateLocalModelDirectory(directory)
    do {
        return try await VLMModelFactory.shared.loadContainer(
            from: directory,
            using: #huggingFaceTokenizerLoader()
        )
    } catch let error as NamingModelError {
        throw error
    } catch {
        throw NamingModelError(.modelLoadFailed, detail: error.localizedDescription)
    }
}

private func validateLocalModelDirectory(_ directory: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        throw NamingModelError(.modelDirectoryMissing, detail: directory.lastPathComponent)
    }
    for name in ["config.json", "tokenizer.json", "tokenizer_config.json"] {
        guard FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(name).path
        ) else {
            throw NamingModelError(.modelFilesMissing, detail: name)
        }
    }
    let children = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )) ?? []
    guard children.contains(where: { $0.pathExtension == "safetensors" }) else {
        throw NamingModelError(.modelFilesMissing, detail: "safetensors")
    }
}
