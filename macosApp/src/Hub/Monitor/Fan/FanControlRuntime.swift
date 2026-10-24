import Foundation
import kmpDomain

/// The root helper owns the curve timer. The app only renews a short lease.
/// If Covio exits or crashes, the helper restores system control automatically.
final class FanControlRuntime: @unchecked Sendable {
    private enum State: String {
        case system
        case applying
        case controlled
        case error
    }

    private let queue = DispatchQueue(label: "com.wyz.covio.fan-control")
    private let log: HelperLog?
    private var access: SMCAccess?
    private var reader: SMCFanReader?
    private var writer: SMCFanWriter?
    private var configuration: MonitorFanConfiguration?
    private var timer: DispatchSourceTimer?
    private var state: State = .system
    private var leaseDeadline = Date.distantPast
    private var heldTemperature: Double?
    private var lastTargets: [Int: Double] = [:]
    private var consecutiveFailures = 0
    private var lastError: String?
    private var controlTemperature: Double?

    init(log: HelperLog? = nil) {
        self.log = log
    }

    func handle(_ request: HelperRequest) -> HelperReply? {
        guard HelperWire.shared.isFanControlCommand(command: request.command) else {
            return nil
        }
        return queue.sync {
            switch request.command {
            case HelperWire.shared.COMMAND_FAN_CONTROL_STATUS:
                return statusReply(requestId: request.requestId)
            case HelperWire.shared.COMMAND_FAN_CONTROL_KEEP_ALIVE:
                return keepAlive(requestId: request.requestId)
            case HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE:
                return configure(request)
            case HelperWire.shared.COMMAND_FAN_CONTROL_RESTORE:
                return restore(requestId: request.requestId, error: nil)
            default:
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: "Command is not allowed"
                )
            }
        }
    }

    func shutdown() {
        queue.sync {
            _ = restore(requestId: "shutdown", error: nil)
        }
    }

    private func configure(_ request: HelperRequest) -> HelperReply {
        guard let parsed = parseConfiguration(request.payload) else {
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: "Invalid fan configuration"
            )
        }
        if parsed.mode.isAutomatic {
            return restore(requestId: request.requestId, error: nil)
        }

        let hardware: (SMCFanReader, SMCFanWriter)
        do {
            hardware = try hardwareOrThrow()
        } catch {
            lastError = String(describing: error)
            state = .error
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: lastError ?? "Fan control is unavailable"
            )
        }

        let fanSnapshot = hardware.0.read()
        guard !fanSnapshot.fans.isEmpty else {
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: "This Mac has no controllable fans"
            )
        }

        let minimums = Dictionary(uniqueKeysWithValues: fanSnapshot.fans.map {
            ($0.index, $0.minimumRPM)
        })
        let maximums = Dictionary(uniqueKeysWithValues: fanSnapshot.fans.map {
            ($0.index, $0.maximumRPM)
        })
        var normalized = parsed.normalized(fanMinimums: minimums, fanMaximums: maximums)
        if normalized.selectedSensorKeys.isEmpty {
            normalized.selectedSensorKeys = SMCFanReader.controlSensorKeys(
                for: fanSnapshot.temperatures,
                allKeys: fanSnapshot.temperatures.map(\.key)
            )
        }

        if writer?.holdingCount ?? 0 > 0 {
            writer?.releaseAll()
        }
        stopTimer()
        configuration = normalized
        state = .applying
        leaseDeadline = Date().addingTimeInterval(MonitorFanPolicy.leaseSeconds)
        heldTemperature = nil
        controlTemperature = nil
        lastTargets.removeAll(keepingCapacity: true)
        consecutiveFailures = 0
        lastError = nil

        do {
            for fan in fanSnapshot.fans {
                try hardware.1.hold(fan.index)
            }
        } catch {
            hardware.1.releaseAll()
            configuration = nil
            state = .error
            lastError = String(describing: error)
            log?.error("Fan control could not take ownership", error)
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: lastError ?? "Fan control could not take ownership"
            )
        }

        writer = hardware.1
        state = .controlled
        startTimer()
        applyControl()
        return statusReply(requestId: request.requestId)
    }

    private func keepAlive(requestId: String) -> HelperReply {
        guard state == .controlled || state == .applying else {
            return statusReply(requestId: requestId)
        }
        leaseDeadline = Date().addingTimeInterval(MonitorFanPolicy.leaseSeconds)
        return statusReply(requestId: requestId)
    }

    private func restore(requestId: String, error: String?) -> HelperReply {
        stopTimer()
        writer?.releaseAll()
        configuration = nil
        state = error == nil ? .system : .error
        leaseDeadline = .distantPast
        heldTemperature = nil
        controlTemperature = nil
        lastTargets.removeAll(keepingCapacity: true)
        consecutiveFailures = 0
        lastError = error
        return statusReply(requestId: requestId)
    }

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + .milliseconds(100),
            repeating: .milliseconds(Int(MonitorFanPolicy.controlIntervalSeconds * 1_000))
        )
        source.setEventHandler { [weak self] in
            self?.applyControl()
        }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func applyControl() {
        guard state == .controlled, let configuration else { return }
        if Date() >= leaseDeadline {
            _ = restore(requestId: "lease-expired", error: nil)
            log?.info("Fan control lease expired; restored system control")
            return
        }
        guard let reader, let writer else { return }

        let selected = Set(configuration.selectedSensorKeys)
        let snapshot = reader.read(sensorKeys: selected.isEmpty ? nil : selected)
        guard !snapshot.fans.isEmpty else {
            registerFailure("Fan readings are unavailable")
            return
        }

        var stableTemperature: Double?
        if configuration.mode == .curve {
            guard let currentTemperature = snapshot.temperatures.map(\.celsius).max() else {
                registerFailure("Control temperature is unavailable")
                return
            }
            stableTemperature = MonitorFanCurve.heldTemperature(
                current: currentTemperature,
                previous: heldTemperature
            )
            heldTemperature = stableTemperature
            controlTemperature = stableTemperature
        }

        do {
            for fan in snapshot.fans {
                let target: Double
                if configuration.mode == .manual {
                    target = configuration.manualRPM[String(fan.index)] ?? fan.minimumRPM
                } else {
                    target = configuration.target(
                        fanIndex: fan.index,
                        temperature: stableTemperature ?? 0,
                        minimumRPM: fan.minimumRPM,
                        maximumRPM: fan.maximumRPM
                    )
                }
                let safeTarget = min(fan.maximumRPM, max(fan.minimumRPM, target))
                let requestedTarget = lastTargets[fan.index]
                let targetDrift = abs(fan.targetRPM - safeTarget) > 25
                if requestedTarget == nil ||
                    abs((requestedTarget ?? 0) - safeTarget) >= 1 ||
                    targetDrift {
                    try writer.writeTarget(fan.index, rpm: safeTarget)
                    lastTargets[fan.index] = safeTarget
                }
            }
            consecutiveFailures = 0
            lastError = nil
        } catch {
            registerFailure(String(describing: error))
        }
    }

    private func registerFailure(_ message: String) {
        consecutiveFailures += 1
        lastError = message
        log?.error("Fan control write failed: \(message)")
        if consecutiveFailures >= MonitorFanPolicy.maximumConsecutiveWriteFailures {
            _ = restore(requestId: "write-failed", error: message)
        }
    }

    private func hardwareOrThrow() throws -> (SMCFanReader, SMCFanWriter) {
        if let reader, let writer {
            return (reader, writer)
        }
        let access = try SMCAccess()
        let keys = access.allKeys()
        let newReader = SMCFanReader(access: access, allKeys: keys)
        let newWriter = SMCFanWriter(access: access, allKeys: keys)
        self.access = access
        reader = newReader
        writer = newWriter
        return (newReader, newWriter)
    }

    private func parseConfiguration(_ payload: [String: String]) -> MonitorFanConfiguration? {
        guard payload["enabled"] == "true",
              let modeText = payload["mode"],
              let mode = switch modeText {
              case "auto": MonitorFanMode.automatic
              case "curve": MonitorFanMode.curve
              case "manual": MonitorFanMode.manual
              default: nil
              },
              let start = Double(payload["start"] ?? ""),
              let full = Double(payload["full"] ?? ""),
              start.isFinite,
              full.isFinite
        else { return nil }

        let sensors = (payload["sensors"] ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        var manualRPM: [String: Double] = [:]
        for pair in (payload["manualRPM"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let fanIndex = Int(parts[0]),
                  let rpm = Double(parts[1]),
                  rpm.isFinite
            else { continue }
            manualRPM[String(fanIndex)] = rpm
        }

        var curves: [String: [MonitorFanCurvePoint]] = [:]
        if let curveText = payload["curves"], !curveText.isEmpty {
            guard let data = curveText.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(
                      [String: [MonitorFanCurvePoint]].self,
                      from: data
                  )
            else {
                return nil
            }
            curves = decoded
        }

        return MonitorFanConfiguration(
            enabled: true,
            mode: mode,
            startCelsius: start,
            fullCelsius: full,
            selectedSensorKeys: sensors,
            manualRPM: manualRPM,
            curves: curves
        )
    }

    private func statusReply(requestId: String) -> HelperReply {
        var result = [
            "state": state.rawValue,
            "active": state == .controlled ? "true" : "false",
            "mode": configuration?.mode.rawValue ?? "system",
            "leaseRemainingSeconds": String(
                max(0, Int(leaseDeadline.timeIntervalSinceNow.rounded(.up)))
            ),
        ]
        if let controlTemperature {
            result["controlTemperature"] = String(format: "%.2f", controlTemperature)
        }
        if let lastError {
            result["error"] = lastError
        }
        return HelperWire.shared.success(requestId: requestId, result: result)
    }
}
