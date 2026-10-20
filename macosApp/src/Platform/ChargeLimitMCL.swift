import CoreFoundation
import Foundation
import kmpDomain

/// PowerUIAgent 的 MCL 偏好域。写入这个域需要 root。
enum ChargeLimitPreferenceDomain {
    static let domain = "com.apple.smartcharging.topoffprotection"
    static let keyOptimizedChargingEnabled = "enabled"
    static let keyFeatureState = "MCLFeatureState"
    static let keyLimitValue = "mclLimitValue"
    static let changedNotification = "com.apple.smartcharging.defaultschanged"
}

/// 根偏好读写端口。测试替换这个端口，生产实现写到 PowerUIAgent 的偏好域。
protocol ChargeLimitPreferenceStore {
    func readInt(_ key: String) -> Int?
    func readBool(_ key: String) -> Bool?
    func writeInt(_ key: String, value: Int)
    func writeBool(_ key: String, value: Bool)
    func remove(_ key: String)
    func synchronize() -> Bool
    func notifyChanged()
}

/// 生产环境的 `CFPreferences` 实现。
final class CFPreferencesChargeLimitStore: ChargeLimitPreferenceStore {
    private let domain = ChargeLimitPreferenceDomain.domain as CFString

    func readInt(_ key: String) -> Int? {
        (CFPreferencesCopyValue(
            key as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? NSNumber)?.intValue
    }

    func readBool(_ key: String) -> Bool? {
        (CFPreferencesCopyValue(
            key as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? NSNumber)?.boolValue
    }

    func writeInt(_ key: String, value: Int) {
        CFPreferencesSetValue(
            key as CFString,
            NSNumber(value: value),
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    func writeBool(_ key: String, value: Bool) {
        CFPreferencesSetValue(
            key as CFString,
            NSNumber(value: value),
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    func remove(_ key: String) {
        CFPreferencesSetValue(
            key as CFString,
            nil,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    func synchronize() -> Bool {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func notifyChanged() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(ChargeLimitPreferenceDomain.changedNotification as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }
}

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
    case preferencesSyncFailed
    case readbackFailed(String)

    var description: String {
        switch self {
        case .invalidTarget(let value):
            "Invalid charge limit: \(value)"
        case .stateUnreadable:
            "Charge limit state is unreadable"
        case .stateWriteFailed:
            "Charge limit state could not be saved"
        case .preferencesSyncFailed:
            "macOS did not save the charge limit preferences"
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
    private let preferences: ChargeLimitPreferenceStore
    private let stateStore: ChargeLimitStateStore
    private let powerUI: PowerUIChargeReading
    private let lock = NSLock()
    private let allowedTargets = stride(from: 20, through: 100, by: 5).map { $0 }

    init(
        preferences: ChargeLimitPreferenceStore,
        stateStore: ChargeLimitStateStore,
        powerUI: PowerUIChargeReading = SystemPowerUIChargeClient()
    ) {
        self.preferences = preferences
        self.stateStore = stateStore
        self.powerUI = powerUI
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
            guard preferences.readInt(ChargeLimitPreferenceDomain.keyFeatureState) == 1,
                  let limit = preferences.readInt(ChargeLimitPreferenceDomain.keyLimitValue),
                  allowedTargets.contains(limit)
            else {
                return nil
            }
            return limit
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
            _ = powerUI.disableMCL()
        }
        preferences.writeBool(ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled, value: false)
        if targetPercent < 100 {
            preferences.writeInt(ChargeLimitPreferenceDomain.keyLimitValue, value: targetPercent)
            preferences.writeInt(ChargeLimitPreferenceDomain.keyFeatureState, value: 1)
        } else {
            preferences.writeInt(ChargeLimitPreferenceDomain.keyFeatureState, value: 0)
        }

        guard preferences.synchronize() else {
            return .failure(.preferencesSyncFailed)
        }
        preferences.notifyChanged()

        if targetPercent < 100 {
            guard preferences.readInt(ChargeLimitPreferenceDomain.keyLimitValue) == targetPercent else {
                return .failure(.readbackFailed(ChargeLimitPreferenceDomain.keyLimitValue))
            }
            guard preferences.readInt(ChargeLimitPreferenceDomain.keyFeatureState) == 1 else {
                return .failure(.readbackFailed(ChargeLimitPreferenceDomain.keyFeatureState))
            }
        } else {
            guard preferences.readInt(ChargeLimitPreferenceDomain.keyFeatureState) == 0 else {
                return .failure(.readbackFailed(ChargeLimitPreferenceDomain.keyFeatureState))
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

        // 先关闭 MCL，再恢复值和开关，避免短暂的错误策略组合。
        _ = powerUI.disableMCL()
        preferences.writeInt(ChargeLimitPreferenceDomain.keyFeatureState, value: 0)

        restoreInt(
            key: ChargeLimitPreferenceDomain.keyLimitValue,
            value: state.original.limitPercent
        )
        restoreBool(
            key: ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled,
            value: state.original.optimizedChargingEnabled
        )
        restoreInt(
            key: ChargeLimitPreferenceDomain.keyFeatureState,
            value: state.original.featureState
        )

        guard preferences.synchronize() else {
            return .failure(.preferencesSyncFailed)
        }
        preferences.notifyChanged()
        guard preferences.readInt(ChargeLimitPreferenceDomain.keyFeatureState) == state.original.featureState else {
            return .failure(.readbackFailed(ChargeLimitPreferenceDomain.keyFeatureState))
        }
        guard preferences.readInt(ChargeLimitPreferenceDomain.keyLimitValue) == state.original.limitPercent else {
            return .failure(.readbackFailed(ChargeLimitPreferenceDomain.keyLimitValue))
        }
        guard preferences.readBool(ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled) ==
            state.original.optimizedChargingEnabled
        else {
            return .failure(.readbackFailed(ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled))
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
        ChargeLimitOriginals(
            optimizedChargingEnabled: preferences.readBool(
                ChargeLimitPreferenceDomain.keyOptimizedChargingEnabled
            ),
            featureState: preferences.readInt(ChargeLimitPreferenceDomain.keyFeatureState),
            limitPercent: preferences.readInt(ChargeLimitPreferenceDomain.keyLimitValue)
        )
    }

    private func restoreInt(key: String, value: Int?) {
        if let value {
            preferences.writeInt(key, value: value)
        } else {
            preferences.remove(key)
        }
    }

    private func restoreBool(key: String, value: Bool?) {
        if let value {
            preferences.writeBool(key, value: value)
        } else {
            preferences.remove(key)
        }
    }
}
