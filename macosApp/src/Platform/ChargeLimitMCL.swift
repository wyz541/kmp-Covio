import Foundation
import kmpDomain

/// 第一次覆盖前的原值。`nil` 表示键原本不存在，恢复时必须删除。
struct ChargeLimitOriginals: Codable, Equatable {
    var optimizedChargingEnabled: Bool?
    var featureState: Int?
    var limitPercent: Int?
}

/// helper 持久化的策略状态。
struct ChargeLimitPersistentState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var enabled = true
    var targetPercent: Int
    var original: ChargeLimitOriginals
}

enum ChargeLimitMCLFailure: Error, Equatable, CustomStringConvertible {
    case invalidTarget(Int)
    case stateUnreadable
    case stateWriteFailed
    case readbackFailed(String)

    var description: String {
        switch self {
        case .invalidTarget(let value):
            "Invalid charge limit: \(value)"
        case .stateUnreadable:
            "Charge limit state is unreadable"
        case .stateWriteFailed:
            "Charge limit state could not be saved"
        case .readbackFailed(let key):
            "Charge limit preference readback failed: \(key)"
        }
    }
}

/// 只允许 root 读写、原子替换的状态文件。
final class ChargeLimitStateStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        url: URL,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    /// 文件不存在返回 nil。文件存在但损坏时抛错，绝不把损坏状态当成首次运行。
    func load() throws -> ChargeLimitPersistentState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        guard let state = try? decoder.decode(ChargeLimitPersistentState.self, from: data),
              state.schemaVersion == ChargeLimitPersistentState.currentSchemaVersion
        else {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        return state
    }

    func save(_ state: ChargeLimitPersistentState) throws {
        do {
            try prepareDirectory()
            let data = try encoder.encode(state)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw ChargeLimitMCLFailure.stateWriteFailed
        }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw ChargeLimitMCLFailure.stateWriteFailed
        }
    }

    private func prepareDirectory() throws {
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}

/// helper 使用的 MCL 后端端口。测试注入假实现，不需要 root。
protocol ChargeLimitBackend: Sendable {
    func capability() -> ChargeLimitSupport
    func observedTargetPercent() -> Int?
    func loadState() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure>
    func apply(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure>
    func restore() -> Result<Void, ChargeLimitMCLFailure>
}

/// MCL 后端。只做根偏好与状态文件，不接 socket，也不执行当前真机验证。
final class ChargeLimitMCLController: ChargeLimitBackend, @unchecked Sendable {
    private let stateStore: ChargeLimitStateStore
    private let powerUI: PowerUIChargeReading
    private let lock = NSLock()
    private let allowedTargets: [Int]

    init(
        stateStore: ChargeLimitStateStore,
        powerUI: PowerUIChargeReading = SystemPowerUIChargeClient()
    ) {
        self.stateStore = stateStore
        self.powerUI = powerUI
        allowedTargets = stride(from: powerUI.minimumSupportedPercent, through: 100, by: 5).map { $0 }
    }

    /// 运行时探测系统接口。接口缺失或报告不支持时，策略不得写入。
    func capability() -> ChargeLimitSupport {
        switch powerUI.capability() {
        case .supported: .supported
        case .unsupported: .unsupported
        }
    }

    /// 读取系统当前登记的目标。外部修改由策略转成冲突态，不静默覆盖。
    func observedTargetPercent() -> Int? {
        lock.withLock {
            guard powerUI.isMCLEnabled() == true else { return nil }
            return powerUI.currentLimit()
        }
    }

    /// 读取上次保存的策略状态。状态文件损坏时明确失败。
    func loadState() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure> {
        lock.withLock { loadStateLocked() }
    }

    /// `targetPercent == 100` 表示 `100%` 模式：释放 MCL，让系统充满。
    func apply(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure> {
        lock.withLock { applyLocked(targetPercent: targetPercent) }
    }

    /// 恢复第一次覆盖前的状态。重复调用是成功的空操作。
    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        lock.withLock { restoreLocked() }
    }

    private func loadStateLocked() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure> {
        do {
            return .success(try stateStore.load())
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
    }

    private func applyLocked(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure> {
        guard allowedTargets.contains(targetPercent) else {
            return .failure(.invalidTarget(targetPercent))
        }

        let existing: ChargeLimitPersistentState?
        do {
            existing = try stateStore.load()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }

        let original = existing?.original ?? captureOriginals()
        let staged = ChargeLimitPersistentState(
            enabled: true,
            targetPercent: targetPercent,
            original: original
        )
        do {
            try stateStore.save(staged)
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }

        if targetPercent == 100 {
            guard powerUI.disableMCL(), powerUI.isMCLEnabled() == false else {
                return .failure(.readbackFailed("MCL release"))
            }
        } else {
            guard powerUI.applyLimit(targetPercent),
                  powerUI.isMCLEnabled() == true,
                  powerUI.currentLimit() == targetPercent
            else {
                return .failure(.readbackFailed("MCL target"))
            }
        }
        return .success(staged)
    }

    private func restoreLocked() -> Result<Void, ChargeLimitMCLFailure> {
        let state: ChargeLimitPersistentState?
        do {
            state = try stateStore.load()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
        guard let state else { return .success(()) }

        if state.original.featureState == 1 {
            guard let originalLimit = state.original.limitPercent,
                  allowedTargets.contains(originalLimit)
            else {
                return .failure(.readbackFailed("original MCL target"))
            }
            _ = powerUI.disableMCL()
            guard powerUI.applyLimit(originalLimit),
                  powerUI.isMCLEnabled() == true,
                  powerUI.currentLimit() == originalLimit
            else {
                return .failure(.readbackFailed("original MCL target"))
            }
        } else {
            guard powerUI.disableMCL(), powerUI.isMCLEnabled() == false else {
                return .failure(.readbackFailed("MCL release"))
            }
        }
        do {
            try stateStore.clear()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }
        return .success(())
    }

    private func captureOriginals() -> ChargeLimitOriginals {
        let enabled = powerUI.isMCLEnabled()
        return ChargeLimitOriginals(
            optimizedChargingEnabled: nil,
            featureState: enabled.map { $0 ? 1 : 0 },
            limitPercent: enabled == true ? powerUI.currentLimit() : nil
        )
    }
}
