import Foundation
import kmpDomain

/// 一次电量读取。OS 读取留在生产实现，测试替换这个端口。
struct ChargeLimitPowerReading: Equatable, Sendable {
    let adapterConnected: Bool
    let batteryPresent: Bool
    let currentPercent: Int?
    let isCharged: Bool
    let calibrationActive: Bool
    let systemProtectionActive: Bool
    let bypassEngaged: Bool
}

protocol ChargeLimitPowerReadingSource: Sendable {
    func read() -> ChargeLimitPowerReading?
}

/// 运行时持久化的用户意图。
struct ChargeLimitRuntimeState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var userLimitPercent: Int
    var chargingLatch = false
    var lastPhase = "off"
}

/// runtime 状态文件。与根偏好状态分开，避免把用户上限和 MCL 执行目标混在一起。
final class ChargeLimitRuntimeStateStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func load() throws -> ChargeLimitRuntimeState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        guard let state = try? decoder.decode(ChargeLimitRuntimeState.self, from: data),
              state.schemaVersion == ChargeLimitRuntimeState.currentSchemaVersion
        else {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        return state
    }

    func save(_ state: ChargeLimitRuntimeState) throws {
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

/// helper 对状态命令返回的完整状态。
struct ChargeLimitRuntimeStatus: Equatable, Sendable {
    let userLimitPercent: Int
    let effectiveTargetPercent: Int?
    let chargingLatch: Bool
    let phase: String
    let bypassEngaged: Bool
    let original: ChargeLimitOriginals?
}

protocol ChargeLimitRuntimeControlling: Sendable {
    func status() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure>
    func configure(userLimitPercent: Int) -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure>
    func restore() -> Result<Void, ChargeLimitMCLFailure>
}

/// 持续执行 5% 回差策略的 helper 运行时。
///
/// 策略函数仍在共享层。这个类只负责读取系统、执行动作和持久化用户意图。
final class ChargeLimitRuntimeController: ChargeLimitRuntimeControlling, @unchecked Sendable {
    private let queueKey = DispatchSpecificKey<Void>()

    private let backend: ChargeLimitBackend
    private let powerReader: ChargeLimitPowerReadingSource
    private let stateStore: ChargeLimitRuntimeStateStore
    private let intervalSeconds: TimeInterval
    private let queue = DispatchQueue(label: "com.wyz.covio.charge-limit-runtime")
    private var timer: DispatchSourceTimer?
    private var bypassEngaged = false

    init(
        backend: ChargeLimitBackend,
        powerReader: ChargeLimitPowerReadingSource,
        stateStore: ChargeLimitRuntimeStateStore,
        intervalSeconds: TimeInterval = 5
    ) {
        self.backend = backend
        self.powerReader = powerReader
        self.stateStore = stateStore
        self.intervalSeconds = max(0.1, intervalSeconds)
        queue.setSpecific(key: queueKey, value: ())
    }

    /// helper 启动后恢复上次配置。
    func resumeOnStartup() -> Result<Void, ChargeLimitMCLFailure> {
        syncOnQueue {
            do {
                guard try stateStore.load() != nil else { return .success(()) }
            } catch let failure as ChargeLimitMCLFailure {
                return .failure(failure)
            } catch {
                return .failure(.stateUnreadable)
            }
            startTimerLocked()
            switch evaluateLocked() {
            case .success:
                return .success(())
            case .failure(let failure):
                return .failure(failure)
            }
        }
    }

    func status() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        syncOnQueue { statusLocked() }
    }

    func configure(userLimitPercent: Int) -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        guard ChargeLimitPolicy.shared.isValidUpperLimit(percent: Int32(userLimitPercent)) else {
            return .failure(.invalidTarget(userLimitPercent))
        }
        return syncOnQueue {
            let previous: ChargeLimitRuntimeState?
            do {
                previous = try stateStore.load()
            } catch let failure as ChargeLimitMCLFailure {
                return .failure(failure)
            } catch {
                return .failure(.stateUnreadable)
            }
            let state = ChargeLimitRuntimeState(
                userLimitPercent: userLimitPercent,
                chargingLatch: false,
                lastPhase: "applying"
            )
            do {
                try stateStore.save(state)
            } catch let failure as ChargeLimitMCLFailure {
                return .failure(failure)
            } catch {
                return .failure(.stateWriteFailed)
            }
            startTimerLocked()
            switch evaluateLocked() {
            case .success:
                return statusLocked()
            case .failure(let failure):
                _ = rollbackConfigurationLocked(previous: previous)
                return .failure(failure)
            }
        }
    }

    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        syncOnQueue {
            stopTimerLocked()
            let restored = backend.restore()
            guard case .success = restored else { return restored }
            do {
                try stateStore.clear()
            } catch let failure as ChargeLimitMCLFailure {
                return .failure(failure)
            } catch {
                return .failure(.stateWriteFailed)
            }
            bypassEngaged = false
            return .success(())
        }
    }

    /// 测试和电源事件使用。调用方不需要等待下一个定时器。
    @discardableResult
    func evaluateNow() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        syncOnQueue {
            switch evaluateLocked() {
            case .success:
                return statusLocked()
            case .failure(let failure):
                return .failure(failure)
            }
        }
    }

    private func startTimerLocked() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler { [weak self] in
            _ = self?.evaluateLocked()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimerLocked() {
        timer?.cancel()
        timer = nil
    }

    private func evaluateLocked() -> Result<Void, ChargeLimitMCLFailure> {
        let state: ChargeLimitRuntimeState
        do {
            guard let loaded = try stateStore.load() else { return .success(()) }
            state = loaded
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
        guard let reading = powerReader.read() else {
            return .failure(.readbackFailed("battery power source"))
        }
        let backendState: ChargeLimitPersistentState?
        switch backend.loadState() {
        case .success(let loaded):
            backendState = loaded
        case .failure(let failure):
            return .failure(failure)
        }
        let observedTarget = backend.observedTargetPercent()
        let expectedTarget = effectiveTarget(backendState?.targetPercent)
        let observation = ChargeLimitObservation(
            enabled: true,
            upperLimitPercent: Int32(state.userLimitPercent),
            adapterConnected: reading.adapterConnected,
            currentPercent: reading.currentPercent.map { KotlinInt(int: Int32($0)) },
            helperInstalled: true,
            support: backend.capability(),
            batteryPresent: reading.batteryPresent,
            isCharged: reading.isCharged,
            calibrationActive: reading.calibrationActive,
            systemProtectionActive: reading.systemProtectionActive,
            conflict: backendState != nil && observedTarget != expectedTarget,
            errorMessage: nil,
            observedTargetPercent: observedTarget.map {
                KotlinInt(int: Int32($0))
            },
            writePending: false,
            bypassEngaged: reading.bypassEngaged
        )
        let decision = ChargeLimitPolicy.shared.evaluate(
            observation: observation,
            previous: ChargeLimitPolicyState(chargingLatch: state.chargingLatch)
        )
        bypassEngaged = decision.bypassEngaged
        let updated = ChargeLimitRuntimeState(
            userLimitPercent: state.userLimitPercent,
            chargingLatch: decision.chargingLatch,
            lastPhase: phaseName(decision.phase)
        )
        do {
            try stateStore.save(updated)
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }

        if decision.action == .setTarget, let target = decision.targetPercent?.int32Value {
            switch backend.apply(targetPercent: Int(target)) {
            case .success:
                return .success(())
            case .failure(let failure):
                return .failure(failure)
            }
        }
        if decision.action == .releaseTarget {
            switch backend.apply(targetPercent: 100) {
            case .success:
                return .success(())
            case .failure(let failure):
                return .failure(failure)
            }
        }
        if backendState == nil,
           decision.action == .none,
           let target = decision.targetPercent?.int32Value {
            switch backend.apply(targetPercent: Int(target)) {
            case .success:
                return .success(())
            case .failure(let failure):
                return .failure(failure)
            }
        }
        return .success(())
    }

    /// 新设置失败时恢复上一次用户意图。首次启用失败时同时恢复系统原值。
    private func rollbackConfigurationLocked(
        previous: ChargeLimitRuntimeState?
    ) -> ChargeLimitMCLFailure? {
        if let previous {
            do {
                try stateStore.save(previous)
                startTimerLocked()
                return nil
            } catch let failure as ChargeLimitMCLFailure {
                return failure
            } catch {
                return .stateWriteFailed
            }
        }

        stopTimerLocked()
        let restored = backend.restore()
        guard case .success = restored else {
            if case .failure(let failure) = restored { return failure }
            return .stateWriteFailed
        }
        do {
            try stateStore.clear()
        } catch let failure as ChargeLimitMCLFailure {
            return failure
        } catch {
            return .stateWriteFailed
        }
        bypassEngaged = false
        return nil
    }

    private func statusLocked() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        let state: ChargeLimitRuntimeState?
        do {
            state = try stateStore.load()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
        guard let state else {
            return .success(
                ChargeLimitRuntimeStatus(
                    userLimitPercent: 0,
                    effectiveTargetPercent: nil,
                    chargingLatch: false,
                    phase: "off",
                    bypassEngaged: false,
                    original: nil
                )
            )
        }
        let backendState: ChargeLimitPersistentState?
        switch backend.loadState() {
        case .success(let loaded):
            backendState = loaded
        case .failure(let failure):
            return .failure(failure)
        }
        return .success(
            ChargeLimitRuntimeStatus(
                userLimitPercent: state.userLimitPercent,
                effectiveTargetPercent: effectiveTarget(backendState?.targetPercent),
                chargingLatch: state.chargingLatch,
                phase: state.lastPhase,
                bypassEngaged: bypassEngaged,
                original: backendState?.original
            )
        )
    }

    /// 后端用 100 表示已经释放 MCL；对策略而言这是“没有目标”。
    private func effectiveTarget(_ target: Int?) -> Int? {
        guard let target, target < 100 else { return nil }
        return target
    }

    private func phaseName(_ phase: ChargeLimitPhase) -> String {
        switch phase {
        case .off: "off"
        case .noBattery: "noBattery"
        case .unplugged: "unplugged"
        case .applying: "applying"
        case .charging: "charging"
        case .sailing: "sailing"
        case .holding: "holding"
        case .aboveLimit: "aboveLimit"
        case .full: "full"
        case .calibration: "calibration"
        case .systemProtection: "systemProtection"
        case .conflict: "conflict"
        case .error: "error"
        case .unsupported: "unsupported"
        case .helperMissing: "helperMissing"
        default: "unknown"
        }
    }

    private func syncOnQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }
        return queue.sync(execute: body)
    }
}
