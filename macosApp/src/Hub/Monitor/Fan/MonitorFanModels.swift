import Foundation

struct MonitorFanReading: Equatable, Sendable {
    struct Temperature: Equatable, Sendable, Identifiable {
        let key: String
        let celsius: Double

        var id: String { key }
    }

    struct Unit: Equatable, Sendable, Identifiable {
        let index: Int
        let rpm: Double
        let minimumRPM: Double
        let maximumRPM: Double
        let targetRPM: Double
        let mode: Int

        var id: Int { index }
    }

    let temperatures: [Temperature]
    let units: [Unit]

    var maximumTemperature: Double? {
        temperatures.map(\.celsius).max()
    }

    func controlTemperature(selectedKeys: Set<String>) -> Double? {
        let selected = temperatures.filter { selectedKeys.contains($0.key) }
        return (selected.isEmpty ? temperatures : selected).map(\.celsius).max()
    }
}

enum MonitorFanMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual
}

struct MonitorFanConfiguration: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var mode: MonitorFanMode = .automatic
    var startCelsius: Double = 58
    var fullCelsius: Double = 86
    var selectedSensorKeys: [String] = []
    var manualRPM: [String: Double] = [:]

    static let defaultValue = MonitorFanConfiguration()

    func normalized(fanMinimums: [Int: Double] = [:], fanMaximums: [Int: Double] = [:]) -> Self {
        var copy = self
        copy.startCelsius = min(
            MonitorFanPolicy.maximumStartCelsius,
            max(MonitorFanPolicy.minimumStartCelsius, startCelsius.rounded())
        )
        let minimumFull = copy.startCelsius + MonitorFanPolicy.minimumTemperatureSpan
        copy.fullCelsius = min(
            MonitorFanPolicy.maximumFullCelsius,
            max(minimumFull, fullCelsius.rounded())
        )
        copy.selectedSensorKeys = Array(Set(selectedSensorKeys.filter { !$0.isEmpty }))
            .sorted()
            .prefix(MonitorFanPolicy.maximumSensorCount)
            .map(\.self)

        var normalizedRPM: [String: Double] = [:]
        for (key, value) in manualRPM where Int(key) != nil {
            guard let fanIndex = Int(key), value.isFinite else { continue }
            let minimum = max(0, fanMinimums[fanIndex] ?? 0)
            let maximum = max(minimum, fanMaximums[fanIndex] ?? MonitorFanPolicy.maximumRPM)
            normalizedRPM[key] = min(maximum, max(minimum, value.rounded()))
        }
        copy.manualRPM = normalizedRPM
        return copy
    }

    func controlTemperature(in reading: MonitorFanReading) -> Double? {
        reading.controlTemperature(selectedKeys: Set(selectedSensorKeys))
    }

    func helperPayload() -> [String: String] {
        let rpm = manualRPM.keys
            .compactMap { key -> (Int, Double)? in
                guard let index = Int(key) else { return nil }
                return (index, manualRPM[key] ?? 0)
            }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0):\(Int($0.1.rounded()))" }
            .joined(separator: ",")
        return [
            "enabled": enabled ? "true" : "false",
            "mode": mode == .manual ? "manual" : "auto",
            "start": String(format: "%.0f", startCelsius),
            "full": String(format: "%.0f", fullCelsius),
            "sensors": selectedSensorKeys.joined(separator: ","),
            "manualRPM": rpm,
        ]
    }

    var selectedSensorCount: Int {
        max(1, selectedSensorKeys.count)
    }
}

enum MonitorFanPolicy {
    static let minimumStartCelsius = 35.0
    static let maximumStartCelsius = 80.0
    static let maximumFullCelsius = 105.0
    static let minimumTemperatureSpan = 5.0
    static let hysteresisCelsius = 1.5
    static let maximumSensorCount = 32
    static let maximumRPM = 15_000.0
    static let heartbeatSeconds: TimeInterval = 5
    static let leaseSeconds: TimeInterval = 20
    static let controlIntervalSeconds: TimeInterval = 1
    static let maximumConsecutiveWriteFailures = 3

    static let quiet = MonitorFanConfiguration(
        enabled: true,
        mode: .automatic,
        startCelsius: 80,
        fullCelsius: 100
    )

    static let balanced = MonitorFanConfiguration(
        enabled: true,
        mode: .automatic,
        startCelsius: 70,
        fullCelsius: 95
    )

    static let turbo = MonitorFanConfiguration(
        enabled: true,
        mode: .automatic,
        startCelsius: 55,
        fullCelsius: 85
    )
}

enum MonitorFanCurve {
    static func target(
        temperature: Double,
        startCelsius: Double,
        fullCelsius: Double,
        minimumRPM: Double,
        maximumRPM: Double
    ) -> Double {
        let safeFull = max(startCelsius + 0.001, fullCelsius)
        let progress = min(max((temperature - startCelsius) / (safeFull - startCelsius), 0), 1)
        return min(maximumRPM, max(minimumRPM, minimumRPM + (maximumRPM - minimumRPM) * progress))
    }

    static func heldTemperature(
        current: Double,
        previous: Double?,
        hysteresis: Double = MonitorFanPolicy.hysteresisCelsius
    ) -> Double {
        guard let previous else { return current }
        if current >= previous { return current }
        return previous - current <= hysteresis ? previous : current
    }
}

enum MonitorFanFormat {
    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f °C", value)
    }

    static func celsius(_ value: Double) -> String {
        "\(Int(value.rounded())) °C"
    }

    static func rpm(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded())) RPM"
    }

    static func targetRPM(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f", value)
    }
}
