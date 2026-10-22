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
    private(set) var helperStatus: HelperStatus = .notInstalled
    private(set) var executionError: String?
    private(set) var leases: [HoldLease] = []

    private let engine: Engine
    private let privileged: PrivilegedOps
    private let observationSource: PowerObservationSource
    private let nowEpochSeconds: () -> Int64
    private var started = false
    private var batteryGuardLatched = false
    private var lastHelperRefreshEpochSeconds: Int64 = 0
    private var latestLidStatus: LidLeaseStatus
    private var appliedSystem = false
    private var appliedDisplay = false
    private var appliedLid = false

    init(
        engine: Engine,
        privileged: PrivilegedOps,
        observationSource: PowerObservationSource,
        config: PowerConfig,
        nowEpochSeconds: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        }
    ) {
        self.engine = engine
        self.privileged = privileged
        self.observationSource = observationSource
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
            helperStatus: .error,
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
        decision = PowerDecision(
            preventUserIdleSystemSleep: false,
            preventUserIdleDisplaySleep: false,
            preventLidSleep: false,
            appliedLeaseLevel: nil,
            activeLeaseIds: [],
            automaticRuleApplied: false,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
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
        started = true
        observationSource.subscribe { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        guard started else { return }
        started = false
        observationSource.stop()
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
        if mode == .lid, helperStatus != .installed {
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
        return executionError == nil && acted
    }

    func endSession() {
        leases.removeAll { $0.source == .manual && $0.reason == Self.sessionReason }
        lastHelperRefreshEpochSeconds = 0
        refresh()
    }

    func refresh() {
        guard started else { return }
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
        decision = nextDecision

        apply(decision)
        if let lidError = latestLidStatus.error, !lidError.isEmpty {
            executionError = lidError
        } else if engine.currentState.lastError == nil {
            executionError = nil
        } else {
            executionError = engine.currentState.lastError
        }
    }

    private var manualSessionLease: HoldLease? {
        leases.first { $0.source == .manual && $0.reason == Self.sessionReason }
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
