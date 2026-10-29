import Foundation
import kmpDomain

@MainActor
final class MonitorFanControlModel: ObservableObject {
    enum HelperAvailability: Equatable {
        case checking
        case ready
        case missing
        case outdated
        case unavailable
    }

    @Published var configuration: MonitorFanConfiguration
    @Published private(set) var availability: HelperAvailability = .checking
    @Published private(set) var busy = false
    @Published private(set) var helperStatus: FanControlHelperStatus?
    @Published private(set) var message: String?

    var hasPendingManualWrite: Bool { manualApplyTask != nil }
    var visibleErrorMessage: String? { message ?? helperStatus?.error }

    private let client: HelperClient
    private let defaults: UserDefaults
    private var didAdoptSensors = false
    private var skipsAvailabilityRefresh = false
    private var manualApplyTask: Task<Void, Never>?
    private var curveApplyTask: Task<Void, Never>?

    private static let preferencesKey = "monitor.fan.control.v1"

    init(client: HelperClient = HelperClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferencesKey),
           let value = try? JSONDecoder().decode(MonitorFanConfiguration.self, from: data) {
            configuration = value
        } else {
            configuration = .defaultValue
        }
    }

    #if DEBUG
    init(
        previewConfiguration: MonitorFanConfiguration,
        availability: HelperAvailability,
        helperStatus: FanControlHelperStatus? = nil
    ) {
        client = HelperClient()
        defaults = UserDefaults(suiteName: "CovioMonitorFanPreview") ?? .standard
        configuration = previewConfiguration
        self.availability = availability
        self.helperStatus = helperStatus
        skipsAvailabilityRefresh = true
    }
    #endif

    func refreshAvailability() {
        guard !busy, !skipsAvailabilityRefresh else { return }
        Task.detached(priority: .userInitiated) { [client] in
            let helperStatus = HelperReleaseInspector.inspect(client: client)
            let availability: HelperAvailability
            switch helperStatus {
            case .match:
                availability = .ready
            case .missing:
                availability = .missing
            case .outdated, .identityMismatch:
                availability = .outdated
            default:
                availability = .unavailable
            }
            let status = availability == .ready ? client.fanControlStatus() : nil
            await MainActor.run {
                self.availability = availability
                self.helperStatus = status
                if availability != .ready || status?.active != true {
                    if self.configuration.enabled {
                        self.configuration.enabled = false
                        self.persist()
                    }
                }
            }
        }
    }

    func adoptDefaultSensors(from reading: MonitorFanReading) {
        guard !didAdoptSensors else { return }
        didAdoptSensors = true
        let known = Set(reading.temperatures.map(\.key))
        if configuration.selectedSensorKeys.isEmpty ||
            configuration.selectedSensorKeys.allSatisfy({ !known.contains($0) }) {
            configuration.selectedSensorKeys = SMCFanReader.controlSensorKeys(
                for: reading.temperatures.map {
                    SMCTemperatureReading(key: $0.key, celsius: $0.celsius)
                },
                allKeys: reading.temperatures.map(\.key)
            )
            persist()
        }
    }

    func setEnabled(_ enabled: Bool, reading: MonitorFanReading) {
        curveApplyTask?.cancel()
        configuration.enabled = enabled
        if enabled, configuration.mode.isAutomatic {
            configuration.mode = .curve
        }
        if enabled, configuration.mode == .manual,
           reading.units.allSatisfy({ manualMode(for: $0.index) == .automatic }) {
            for fan in reading.units {
                configuration.manualModes[String(fan.index)] = .manual
            }
        }
        persist()
        if enabled {
            apply(reading: reading)
        } else {
            restore()
        }
    }

    func setMode(_ mode: MonitorFanMode, reading: MonitorFanReading) {
        manualApplyTask?.cancel()
        curveApplyTask?.cancel()
        configuration.mode = mode
        configuration.enabled = !mode.isAutomatic
        if mode == .manual {
            for fan in reading.units {
                configuration.manualModes[String(fan.index)] = .manual
            }
        }
        persist()
        if mode.isAutomatic {
            restore()
        } else {
            apply(reading: reading)
        }
    }

    func applyPreset(_ preset: MonitorFanConfiguration, reading: MonitorFanReading) {
        manualApplyTask?.cancel()
        curveApplyTask?.cancel()
        let sensorKeys = configuration.selectedSensorKeys
        configuration.startCelsius = preset.startCelsius
        configuration.fullCelsius = preset.fullCelsius
        configuration.mode = .curve
        configuration.enabled = true
        configuration.selectedSensorKeys = sensorKeys
        configuration.curves.removeAll()
        configuration.batteryCurves.removeAll()
        persist()
        apply(reading: reading)
    }

    func applyCurve(reading: MonitorFanReading) {
        guard configuration.enabled else {
            persist()
            return
        }
        apply(reading: reading)
    }

    /// fanIndex 为 nil 时把同一条曲线写入全部风扇。
    func setCurve(
        fanIndex: Int?,
        points: [MonitorFanCurvePoint],
        source: MonitorFanCurveSource,
        reading: MonitorFanReading
    ) {
        let indices = fanIndex.map { [$0] } ?? reading.units.map(\.index)
        for index in indices {
            if source == .battery {
                configuration.batteryCurves[String(index)] = points
            } else {
                configuration.curves[String(index)] = points
            }
        }
        let minimums = Dictionary(uniqueKeysWithValues: reading.units.map {
            ($0.index, $0.minimumRPM)
        })
        let maximums = Dictionary(uniqueKeysWithValues: reading.units.map {
            ($0.index, $0.maximumRPM)
        })
        configuration = configuration.normalized(
            fanMinimums: minimums,
            fanMaximums: maximums
        )
        persist()
        if configuration.enabled, configuration.mode == .curve {
            apply(reading: reading)
        }
    }

    /// 清除自定义曲线，恢复当前起转/全速两点曲线。
    func clearCurve(
        fanIndex: Int?,
        source: MonitorFanCurveSource,
        reading: MonitorFanReading
    ) {
        let indices = fanIndex.map { [$0] } ?? reading.units.map(\.index)
        for index in indices {
            if source == .battery {
                configuration.batteryCurves.removeValue(forKey: String(index))
            } else {
                configuration.curves.removeValue(forKey: String(index))
            }
        }
        persist()
        if configuration.enabled, configuration.mode == .curve {
            apply(reading: reading)
        }
    }

    func copyAdapterCurvesToBattery(reading: MonitorFanReading) {
        for fan in reading.units {
            configuration.batteryCurves[String(fan.index)] = configuration.curvePoints(
                for: fan.index,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM,
                source: .adapter
            )
        }
        configuration = configuration.normalized(
            fanMinimums: Dictionary(uniqueKeysWithValues: reading.units.map {
                ($0.index, $0.minimumRPM)
            }),
            fanMaximums: Dictionary(uniqueKeysWithValues: reading.units.map {
                ($0.index, $0.maximumRPM)
            })
        )
        persist()
        if configuration.enabled, configuration.mode == .curve {
            apply(reading: reading)
        }
    }

    func updatePowerSource(
        _ source: MonitorFanPowerSource,
        reading: MonitorFanReading
    ) {
        guard configuration.powerSource != source else { return }
        curveApplyTask?.cancel()
        configuration.powerSource = source
        persist()
        guard configuration.enabled,
              configuration.mode == .curve,
              configuration.enabledTemperatureSources.isEmpty
        else { return }
        if busy {
            scheduleCurveApply(reading: reading)
        } else {
            apply(reading: reading)
        }
    }

    func setManualRPM(_ rpm: Double, fanIndex: Int, reading: MonitorFanReading) {
        if configuration.syncFans {
            for (index, target) in MonitorFanSpeedSync.targets(
                sourceFanIndex: fanIndex,
                rpm: rpm,
                units: reading.units
            ) {
                configuration.manualRPM[String(index)] = target
                configuration.manualModes[String(index)] = .manual
            }
        } else {
            configuration.manualRPM[String(fanIndex)] = rpm.rounded()
            configuration.manualModes[String(fanIndex)] = .manual
        }
        persist()
        if configuration.enabled, configuration.mode == .manual {
            scheduleManualApply(reading: reading)
        }
    }

    func manualMode(for fanIndex: Int) -> MonitorFanMode {
        configuration.manualModes[String(fanIndex)] == .automatic ? .automatic : .manual
    }

    func setManualMode(
        _ mode: MonitorFanMode,
        fanIndex: Int,
        reading: MonitorFanReading
    ) {
        guard mode == .automatic || mode == .manual else { return }
        manualApplyTask?.cancel()
        let indices = configuration.syncFans ? reading.units.map(\.index) : [fanIndex]
        for index in indices {
            configuration.manualModes[String(index)] = mode
        }
        persist()
        if configuration.enabled, configuration.mode == .manual {
            apply(reading: reading)
        }
    }

    func setSyncFans(_ enabled: Bool) {
        configuration.syncFans = enabled
        persist()
    }

    func setSensor(_ key: String, enabled: Bool, reading: MonitorFanReading) {
        var selected = Set(configuration.selectedSensorKeys)
        if enabled {
            selected.insert(key)
        } else {
            selected.remove(key)
        }
        if selected.isEmpty { return }
        configuration.selectedSensorKeys = selected.sorted()
        persist()
        if configuration.enabled, configuration.mode == .curve {
            apply(reading: reading)
        }
    }

    func setTemperatureSource(
        _ source: MonitorFanTemperatureSource,
        enabled: Bool,
        reading: MonitorFanReading
    ) {
        curveApplyTask?.cancel()
        if enabled {
            if !configuration.hasTemperatureRules(for: source) {
                configuration.temperatureRules[source.rawValue] =
                    MonitorFanTemperatureRule.defaultPoints(for: source)
            }
        } else {
            configuration.temperatureRules.removeValue(forKey: source.rawValue)
        }
        persist()
        if configuration.enabled, configuration.mode == .curve {
            apply(reading: reading)
        }
    }

    func setTemperatureRulePoints(
        _ points: [MonitorFanTemperatureRulePoint],
        source: MonitorFanTemperatureSource,
        reading: MonitorFanReading,
        applyImmediately: Bool
    ) {
        guard points.count >= 2 else { return }
        configuration.temperatureRules[source.rawValue] = points
        let minimums = Dictionary(uniqueKeysWithValues: reading.units.map {
            ($0.index, $0.minimumRPM)
        })
        let maximums = Dictionary(uniqueKeysWithValues: reading.units.map {
            ($0.index, $0.maximumRPM)
        })
        configuration = configuration.normalized(
            fanMinimums: minimums,
            fanMaximums: maximums
        )
        persist()
        guard configuration.enabled, configuration.mode == .curve else { return }
        if applyImmediately {
            curveApplyTask?.cancel()
            apply(reading: reading)
        } else {
            scheduleCurveApply(reading: reading)
        }
    }

    func restore() {
        manualApplyTask?.cancel()
        curveApplyTask?.cancel()
        guard !busy else { return }
        if skipsAvailabilityRefresh {
            configuration.enabled = false
            configuration.mode = .automatic
            return
        }
        busy = true
        message = nil
        Task.detached(priority: .userInitiated) { [client] in
            let result = client.restoreFanControl()
            await MainActor.run {
                self.busy = false
                if result.ok {
                    self.configuration.enabled = false
                    self.configuration.mode = .automatic
                    self.helperStatus = result.status ?? FanControlHelperStatus(
                        active: false,
                        mode: "system",
                        controlTemperature: nil,
                        leaseRemainingSeconds: 0,
                        error: nil
                    )
                    FanControlLeaseKeeper.shared.stop()
                    self.persist()
                } else {
                    self.message = result.message
                }
            }
        }
    }

    func installHelper(runtime: AppRuntime?) {
        guard let runtime else { return }
        runtime.installHelper()
        message = nil
        Task {
            try? await Task.sleep(for: .seconds(2))
            refreshAvailability()
        }
    }

    private func apply(reading: MonitorFanReading) {
        guard !busy else { return }
        if skipsAvailabilityRefresh { return }
        guard !configuration.mode.isAutomatic else {
            restore()
            return
        }
        let minimums = Dictionary(uniqueKeysWithValues: reading.units.map {
            ($0.index, $0.minimumRPM)
        })
        let maximums = Dictionary(uniqueKeysWithValues: reading.units.map {
            ($0.index, $0.maximumRPM)
        })
        configuration = configuration.normalized(
            fanMinimums: minimums,
            fanMaximums: maximums
        )
        if configuration.selectedSensorKeys.isEmpty {
            configuration.selectedSensorKeys = SMCFanReader.controlSensorKeys(
                for: reading.temperatures.map {
                    SMCTemperatureReading(key: $0.key, celsius: $0.celsius)
                },
                allKeys: reading.temperatures.map(\.key)
            )
        }
        persist()

        guard availability == .ready else {
            configuration.enabled = false
            persist()
            message = nil
            return
        }

        let configuration = configuration
        busy = true
        message = nil
        Task.detached(priority: .userInitiated) { [client] in
            guard HelperReleaseInspector.inspect(client: client).allowsPrivilegedWrites else {
                await MainActor.run {
                    self.busy = false
                    self.configuration.enabled = false
                    FanControlLeaseKeeper.shared.stop()
                    self.persist()
                }
                return
            }
            let result = client.configureFanControl(configuration)
            await MainActor.run {
                self.busy = false
                if result.ok {
                    let status = result.status ?? FanControlHelperStatus(
                        active: true,
                        mode: configuration.mode.rawValue,
                        controlTemperature: configuration.controlTemperature(in: reading),
                        leaseRemainingSeconds: Int(MonitorFanPolicy.leaseSeconds),
                        error: nil
                    )
                    self.configuration.enabled = status.active
                    self.helperStatus = status
                    if status.active {
                        FanControlLeaseKeeper.shared.start(configuration: configuration)
                    } else {
                        FanControlLeaseKeeper.shared.stop()
                    }
                } else {
                    self.configuration.enabled = false
                    self.message = result.message
                    FanControlLeaseKeeper.shared.stop()
                }
                self.persist()
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.preferencesKey)
    }

    private func scheduleManualApply(reading: MonitorFanReading) {
        manualApplyTask?.cancel()
        manualApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.configuration.enabled, self.configuration.mode == .manual else {
                self.manualApplyTask = nil
                return
            }
            self.apply(reading: reading)
            self.manualApplyTask = nil
        }
    }

    private func scheduleCurveApply(reading: MonitorFanReading) {
        curveApplyTask?.cancel()
        curveApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard let self else { return }
            while self.busy {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  self.configuration.enabled,
                  self.configuration.mode == .curve
            else {
                self.curveApplyTask = nil
                return
            }
            self.apply(reading: reading)
            self.curveApplyTask = nil
        }
    }
}
