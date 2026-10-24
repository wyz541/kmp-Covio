import AppKit
import Foundation
import SwiftUI
import kmpDomain

/// Power 管理面的运行时协调器。
///
/// 它只负责观察、策略和会话意图。
/// IOKit 断言与 helper 仍由 Engine 执行。
@MainActor
@Observable
final class PowerRuntime {
    enum SessionMode: String, CaseIterable, Identifiable {
        case system
        case display
        case lid

        var id: String { rawValue }

        var leaseLevel: HoldLeaseLevel {
            switch self {
            case .system: .system
            case .display: .systemAndDisplay
            case .lid: .closedLid
            }
        }
    }

    enum SessionDuration: String, CaseIterable, Identifiable {
        case fifteenMinutes
        case oneHour
        case twoHours
        case fourHours
        case untilOff

        var id: String { rawValue }

        var seconds: Int64? {
            switch self {
            case .fifteenMinutes: 15 * 60
            case .oneHour: 60 * 60
            case .twoHours: 2 * 60 * 60
            case .fourHours: 4 * 60 * 60
            case .untilOff: nil
            }
        }
    }

    private(set) var config: PowerConfig
    private(set) var observation: PowerObservation
    private(set) var snapshot: PowerSnapshot
    private(set) var decision: PowerDecision
    private(set) var helperStatus: HelperStatus = .missing
    private(set) var executionError: String?
    private(set) var leases: [HoldLease] = []
    private(set) var history: [PowerHistoryEvent] = []
    private(set) var recentHistory: [PowerHistoryEvent] = []
    private(set) var closedLidZeroBrightnessPhase: ClosedLidZeroBrightnessPhase = .disabled
    private(set) var closedLidZeroBrightnessAvailability: ClosedLidBrightnessAvailability
    private(set) var closedLidZeroBrightnessError: String?

    private let engine: Engine
    private let privileged: PrivilegedOps
    private let observationSource: PowerObservationSource
    private let historyStore: PowerHistoryStore
    private let closedLidBrightnessController: ClosedLidZeroBrightnessController
    private let nowEpochSeconds: () -> Int64
    private var started = false
    private var batteryGuardLatched = false
    private var lastHelperRefreshEpochSeconds: Int64 = 0
    private var latestLidStatus: LidLeaseStatus
    private var appliedSystem = false
    private var appliedDisplay = false
    private var appliedLid = false
    private var historyObservers: [NSObjectProtocol] = []
    private var historyInitialized = false
    private var previousDecision: PowerDecision
    private var lastConflict = false
    private var lastWakeObservationAt: Int64?
    private var lastWakeObservationKind: WakeKind?
    private var lastRecordedWakeAt: Int64?
    private var lastSleepAt: Int64?
    private var wakeFallbackTask: Task<Void, Never>?
    private var appliedPowerLidDisplayOff = true

    init(
        engine: Engine,
        privileged: PrivilegedOps,
        observationSource: PowerObservationSource,
        historyStore: PowerHistoryStore,
        config: PowerConfig,
        closedLidBrightnessBackend: ClosedLidBrightnessBackend? = nil,
        closedLidBrightnessStore: ClosedLidBrightnessRecoveryStoring? = nil,
        nowEpochSeconds: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        }
    ) {
        self.engine = engine
        self.privileged = privileged
        self.observationSource = observationSource
        self.historyStore = historyStore
        let brightnessController = ClosedLidZeroBrightnessController(
            backend: closedLidBrightnessBackend ?? DisplayServicesBrightnessBackend(),
            store: closedLidBrightnessStore ?? JSONClosedLidBrightnessRecoveryStore(
                fileURL: AppPaths.closedLidBrightnessRecoveryFile
            ),
            nowEpochSeconds: nowEpochSeconds
        )
        self.closedLidBrightnessController = brightnessController
        closedLidZeroBrightnessAvailability = brightnessController.availability
        self.config = config.normalized()
        self.nowEpochSeconds = nowEpochSeconds
        let emptyObservation = PowerObservation(
            batteryPercent: nil,
            hasBattery: nil,
            powerState: .unknown,
            externalDisplayCount: nil,
            lidState: .unknown,
            thermalState: .unknown,
            lowPowerModeEnabled: nil
        )
        observation = emptyObservation
        snapshot = PowerSnapshot(
            observation: emptyObservation,
            helperStatus: .untrusted,
            sleepDisabled: nil,
            covioOwnsSleepDisabled: nil
        )
        latestLidStatus = LidLeaseStatus(
            available: false,
            protocolVersion: nil,
            sleepDisabled: nil,
            covioOwned: nil,
            activeLeaseCount: 0,
            expiresAtEpochSeconds: nil,
            error: nil
        )
        let initialDecision = PowerDecision(
            preventUserIdleSystemSleep: false,
            preventUserIdleDisplaySleep: false,
            preventLidSleep: false,
            appliedLeaseLevel: nil,
            activeLeaseIds: [],
            automaticRuleApplied: false,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
        decision = initialDecision
        previousDecision = initialDecision
    }

    var isRunning: Bool { started }

    var hasManualSession: Bool {
        leases.contains { $0.source == .manual && $0.reason == Self.sessionReason }
    }

    var sessionMode: SessionMode? {
        guard let lease = manualSessionLease else { return nil }
        if lease.level == .system { return .system }
        if lease.level == .systemAndDisplay { return .display }
        return .lid
    }

    var remainingSeconds: Int64? {
        guard let lease = manualSessionLease else { return nil }
        let capEnd = lease.createdAtEpochSeconds + Int64(config.closedLidTimeCapMinutes) * 60
        let end: Int64?
        if lease.level == .closedLid {
            end = lease.expiresAtEpochSeconds.map { min($0.int64Value, capEnd) } ?? capEnd
        } else {
            end = lease.expiresAtEpochSeconds?.int64Value
        }
        return end.map { max(0, $0 - nowEpochSeconds()) }
    }

    var isHolding: Bool {
        decision.preventUserIdleSystemSleep ||
            decision.preventUserIdleDisplaySleep ||
            decision.preventLidSleep
    }

    func start() {
        guard !started else { return }
        let now = nowEpochSeconds()
        started = true
        loadHistory(nowEpochSeconds: now)
        let wake = engine.currentState.darkWake
        lastWakeObservationAt = wake.lastAtEpochSeconds?.int64Value
        lastWakeObservationKind = wake.lastKind
        installHistoryObservers()
        observationSource.subscribe { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        guard started else { return }
        started = false
        closedLidBrightnessController.stop()
        closedLidZeroBrightnessPhase = closedLidBrightnessController.phase
        closedLidZeroBrightnessError = closedLidBrightnessController.lastError
        appliedPowerLidDisplayOff = true
        engine.setPowerLidDisplayOffEnabled(enabled: true)
        observationSource.stop()
        for observer in historyObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        historyObservers.removeAll(keepingCapacity: true)
        wakeFallbackTask?.cancel()
        wakeFallbackTask = nil
        leases.removeAll(keepingCapacity: true)
        _ = engine.replacePowerLeases(leases: [])
        _ = engine.setPowerLidHold(required: false)
        appliedSystem = false
        appliedDisplay = false
        appliedLid = false
    }

    func refreshHelperStatusNow() {
        lastHelperRefreshEpochSeconds = 0
        refresh()
    }

    func updateConfig(_ next: PowerConfig) {
        config = next.normalized()
        if !config.enabled {
            leases.removeAll(keepingCapacity: true)
        }
        refresh()
    }

    @discardableResult
    func startSession(mode: SessionMode, duration: SessionDuration) -> Bool {
        if mode == .lid, helperStatus != .match {
            executionError = "helper-unavailable"
            return false
        }
        let now = nowEpochSeconds()
        let lease = HoldLease(
            id: "power/session/\(UUID().uuidString)",
            level: mode.leaseLevel,
            source: .manual,
            reason: Self.sessionReason,
            createdAtEpochSeconds: now,
            expiresAtEpochSeconds: duration.seconds.map { KotlinLong(longLong: now + $0) }
        )
        leases.removeAll { $0.source == .manual && $0.reason == Self.sessionReason }
        leases.append(lease)
        lastHelperRefreshEpochSeconds = 0
        refresh()
        let acted = switch mode {
        case .system: decision.preventUserIdleSystemSleep
        case .display: decision.preventUserIdleDisplaySleep
        case .lid: decision.preventLidSleep
        }
        let success = executionError == nil && acted
        if success {
            recordHistory(.holdStarted, detail: sessionModeHistoryDetail(mode), at: now)
        }
        return success
    }

    func endSession() {
        leases.removeAll { $0.source == .manual && $0.reason == Self.sessionReason }
        lastHelperRefreshEpochSeconds = 0
        refresh()
    }

    func refresh() {
        guard started else { return }
        let previousObservation = historyInitialized ? observation : nil
        observation = observationSource.read()
        let now = nowEpochSeconds()
        if now - lastHelperRefreshEpochSeconds >= 5 {
            lastHelperRefreshEpochSeconds = now
            helperStatus = privileged.status()
            latestLidStatus = privileged.lidLeaseStatus()
        }
        snapshot = PowerSnapshot(
            observation: observation,
            helperStatus: helperStatus,
            sleepDisabled: latestLidStatus.sleepDisabled,
            covioOwnsSleepDisabled: latestLidStatus.covioOwned
        )
        recordObservationHistory(previous: previousObservation, at: now)

        let closedLidCapReleased = leases.contains { lease in
            lease.level == .closedLid &&
                (lease.expiresAtEpochSeconds?.int64Value ?? Int64.max) > now &&
                lease.createdAtEpochSeconds + Int64(config.closedLidTimeCapMinutes) * 60 <= now
        }
        if closedLidCapReleased {
            recordHistory(.guardReleased, detail: "closed-lid-time-cap", at: now)
        }
        leases.removeAll { lease in
            if let expiry = lease.expiresAtEpochSeconds, expiry.int64Value <= now { return true }
            if lease.level == .closedLid {
                let cap = lease.createdAtEpochSeconds + Int64(config.closedLidTimeCapMinutes) * 60
                return cap <= now
            }
            return false
        }

        var nextDecision = PowerPolicy.shared.decide(
            config: config,
            snapshot: snapshot,
            leases: leases,
            nowEpochSeconds: now,
            paused: false,
            batteryGuardLatched: batteryGuardLatched
        )
        recordGuardHistory(nextDecision, at: now)
        if containsReleaseVeto(nextDecision.safetyVetoes) {
            leases.removeAll(keepingCapacity: true)
            nextDecision = PowerPolicy.shared.decide(
                config: config,
                snapshot: snapshot,
                leases: [],
                nowEpochSeconds: now,
                paused: false,
                batteryGuardLatched: batteryGuardLatched
            )
        }
        if nextDecision.automaticRuleApplied && !previousDecision.automaticRuleApplied {
            recordHistory(.holdStarted, detail: "automatic", at: now)
        }
        previousDecision = nextDecision
        decision = nextDecision

        apply(decision)
        applyClosedLidZeroBrightness(decision: nextDecision)
        recordWakeHistory(at: now)
        if let lidError = latestLidStatus.error, !lidError.isEmpty {
            executionError = lidError
        } else if engine.currentState.lastError == nil {
            executionError = nil
        } else {
            executionError = engine.currentState.lastError
        }
        if config.closedLidZeroBrightness,
           closedLidZeroBrightnessPhase == .failed,
           let error = closedLidZeroBrightnessError {
            executionError = error
        }
    }

    /// 由 Sleep watcher 或测试调用。系统将要睡眠时记录一条事件。
    func recordSystemSleep() {
        guard started else { return }
        let now = nowEpochSeconds()
        if let lastSleepAt, now - lastSleepAt < 5 { return }
        lastSleepAt = now
        recordHistory(.slept, detail: "", at: now)
    }

    private func installHistoryObservers() {
        let center = NSWorkspace.shared.notificationCenter
        historyObservers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.recordSystemSleep() }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleWakeFallback() }
            },
        ]
    }

    private func scheduleWakeFallback() {
        guard started else { return }
        wakeFallbackTask?.cancel()
        let sleepAt = lastSleepAt
        wakeFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let wakeRecorded = self.lastRecordedWakeAt.map { value in
                sleepAt.map { value > $0 } ?? true
            } ?? false
            if !wakeRecorded {
                let now = self.nowEpochSeconds()
                self.recordHistory(.fullWake, detail: "", at: now)
                self.lastRecordedWakeAt = now
            }
        }
    }

    private func loadHistory(nowEpochSeconds: Int64) {
        let state = historyStore.load(nowEpochSeconds: nowEpochSeconds)
        history = state.events
        recentHistory = PowerHistoryLogic.shared.recent(
            events: state.events,
            nowEpochSeconds: nowEpochSeconds,
            windowSeconds: 86_400
        )
    }

    private func recordObservationHistory(previous: PowerObservation?, at now: Int64) {
        defer { historyInitialized = true }
        if let previous,
           let wasOnAdapter = adapterConnection(previous.powerState),
           let isOnAdapter = adapterConnection(observation.powerState),
           wasOnAdapter != isOnAdapter {
            recordHistory(
                wasOnAdapter ? .adapterDisconnected : .adapterConnected,
                detail: "",
                at: now
            )
        }
        let conflict = snapshot.sleepDisabled?.boolValue == true &&
            snapshot.covioOwnsSleepDisabled?.boolValue != true
        if conflict && !lastConflict {
            recordHistory(.externalConflict, detail: "", at: now)
        } else if !conflict && lastConflict {
            recordHistory(.externalConflictCleared, detail: "", at: now)
        }
        lastConflict = conflict
    }

    private func adapterConnection(_ state: PowerState) -> Bool? {
        switch state {
        case .charging, .charged, .acPower: true
        case .discharging: false
        case .unknown: nil
        default: nil
        }
    }

    private func recordGuardHistory(_ decision: PowerDecision, at now: Int64) {
        let previousVetoes = previousDecision.safetyVetoes
        for veto in decision.safetyVetoes where containsReleaseVeto([veto]) && !previousVetoes.contains(veto) {
            recordHistory(.guardReleased, detail: vetoHistoryDetail(veto), at: now)
        }
    }

    private func recordWakeHistory(at now: Int64) {
        let status = engine.currentState.darkWake
        guard let at = status.lastAtEpochSeconds?.int64Value,
              at >= now - 5,
              at != lastWakeObservationAt || status.lastKind != lastWakeObservationKind
        else { return }
        lastWakeObservationAt = at
        lastWakeObservationKind = status.lastKind
        switch status.lastKind {
        case .dark:
            recordHistory(.darkWake, detail: status.lastReason ?? "", at: at)
            lastRecordedWakeAt = at
        case .full:
            recordHistory(.fullWake, detail: status.lastReason ?? "", at: at)
            lastRecordedWakeAt = at
        case nil:
            break
        default:
            break
        }
    }

    private func recordHistory(_ kind: PowerHistoryKind, detail: String, at epochSeconds: Int64) {
        let event = PowerHistoryEvent(
            id: UUID().uuidString,
            kind: kind,
            atEpochSeconds: epochSeconds,
            detail: detail
        )
        guard let state = historyStore.append(event: event, nowEpochSeconds: epochSeconds) else {
            return
        }
        history = state.events
        recentHistory = PowerHistoryLogic.shared.recent(
            events: state.events,
            nowEpochSeconds: epochSeconds,
            windowSeconds: 86_400
        )
    }

    private func sessionModeHistoryDetail(_ mode: SessionMode) -> String {
        switch mode {
        case .system: "system"
        case .display: "display"
        case .lid: "lid"
        }
    }

    private func vetoHistoryDetail(_ veto: SafetyVeto) -> String {
        switch veto {
        case .batteryFloor: "battery-floor"
        case .thermalSerious: "thermal-serious"
        case .thermalCritical: "thermal-critical"
        case .lowPowerMode: "low-power-mode"
        default: "safety-veto"
        }
    }

    private var manualSessionLease: HoldLease? {
        leases.first { $0.source == .manual && $0.reason == Self.sessionReason }
    }

    private func applyClosedLidZeroBrightness(decision: PowerDecision) {
        let wantsPrivatePath = config.closedLidZeroBrightness && decision.preventLidSleep
        let externalDisplayCount = observation.externalDisplayCount?.intValue
        let canOwnDisplay = wantsPrivatePath &&
            closedLidZeroBrightnessAvailability.isAvailable &&
            externalDisplayCount == 0 &&
            closedLidBrightnessController.phase != .failed
        let previouslyOwnedDisplay = !appliedPowerLidDisplayOff
        let shouldEnablePublicDisplayOff = !canOwnDisplay

        if appliedPowerLidDisplayOff != shouldEnablePublicDisplayOff {
            appliedPowerLidDisplayOff = shouldEnablePublicDisplayOff
            engine.setPowerLidDisplayOffEnabled(enabled: shouldEnablePublicDisplayOff)
        }

        let evaluation = closedLidBrightnessController.evaluate(
            enabled: config.closedLidZeroBrightness,
            sessionActive: decision.preventLidSleep,
            lidState: observation.lidState,
            externalDisplayCount: externalDisplayCount
        )
        closedLidZeroBrightnessPhase = closedLidBrightnessController.phase
        closedLidZeroBrightnessError = closedLidBrightnessController.lastError

        if evaluation.fallbackToPublicDisplayOff {
            if !appliedPowerLidDisplayOff {
                appliedPowerLidDisplayOff = true
                engine.setPowerLidDisplayOffEnabled(enabled: true)
            }
            if previouslyOwnedDisplay && observation.lidState == .closed {
                engine.displaySleepNow()
            }
        }
    }

    private func apply(_ decision: PowerDecision) {
        if appliedSystem != decision.preventUserIdleSystemSleep ||
            appliedDisplay != decision.preventUserIdleDisplaySleep {
            let level: HoldLeaseLevel? = if !decision.preventUserIdleSystemSleep {
                nil
            } else if decision.preventUserIdleDisplaySleep {
                .systemAndDisplay
            } else {
                .system
            }
            let nextLeases = level.map {
                [HoldLease(
                    id: "power/policy/idle",
                    level: $0,
                    source: .agent,
                    reason: "Power policy",
                    createdAtEpochSeconds: nowEpochSeconds(),
                    expiresAtEpochSeconds: nil
                )]
            } ?? []
            if !engine.replacePowerLeases(leases: nextLeases) {
                executionError = engine.currentState.lastError
            }
            appliedSystem = decision.preventUserIdleSystemSleep
            appliedDisplay = decision.preventUserIdleDisplaySleep
        }
        if appliedLid != decision.preventLidSleep {
            if !engine.setPowerLidHold(required: decision.preventLidSleep) {
                executionError = "helper-unavailable"
            }
            appliedLid = decision.preventLidSleep
        }
    }

    private func containsReleaseVeto(_ vetoes: [SafetyVeto]) -> Bool {
        vetoes.contains { veto in
            veto == .batteryFloor ||
                veto == .thermalSerious ||
                veto == .thermalCritical ||
                veto == .lowPowerMode
        }
    }

    private static let sessionReason = "power-session"
}
