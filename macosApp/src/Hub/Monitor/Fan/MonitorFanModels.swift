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

struct MonitorFanCurvePoint: Codable, Equatable, Sendable, Identifiable {
    var temperature: Double
    var rpm: Double

    var id: String { "\(temperature)-\(rpm)" }
}

struct MonitorFanConfiguration: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var mode: MonitorFanMode = .automatic
    var startCelsius: Double = 58
    var fullCelsius: Double = 86
    var selectedSensorKeys: [String] = []
    var manualRPM: [String: Double] = [:]
    /// 风扇序号对应的多点曲线。缺少某台风扇时，使用起转/全速两点曲线。
    var curves: [String: [MonitorFanCurvePoint]] = [:]

    static let defaultValue = MonitorFanConfiguration()

    init(
        enabled: Bool = false,
        mode: MonitorFanMode = .automatic,
        startCelsius: Double = 58,
        fullCelsius: Double = 86,
        selectedSensorKeys: [String] = [],
        manualRPM: [String: Double] = [:],
        curves: [String: [MonitorFanCurvePoint]] = [:]
    ) {
        self.enabled = enabled
        self.mode = mode
        self.startCelsius = startCelsius
        self.fullCelsius = fullCelsius
        self.selectedSensorKeys = selectedSensorKeys
        self.manualRPM = manualRPM
        self.curves = curves
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case startCelsius
        case fullCelsius
        case selectedSensorKeys
        case manualRPM
        case curves
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try container.decodeIfPresent(MonitorFanMode.self, forKey: .mode) ?? .automatic
        startCelsius = try container.decodeIfPresent(Double.self, forKey: .startCelsius) ?? 58
        fullCelsius = try container.decodeIfPresent(Double.self, forKey: .fullCelsius) ?? 86
        selectedSensorKeys = try container.decodeIfPresent([String].self, forKey: .selectedSensorKeys) ?? []
        manualRPM = try container.decodeIfPresent([String: Double].self, forKey: .manualRPM) ?? [:]
        curves = try container.decodeIfPresent(
            [String: [MonitorFanCurvePoint]].self,
            forKey: .curves
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(mode, forKey: .mode)
        try container.encode(startCelsius, forKey: .startCelsius)
        try container.encode(fullCelsius, forKey: .fullCelsius)
        try container.encode(selectedSensorKeys, forKey: .selectedSensorKeys)
        try container.encode(manualRPM, forKey: .manualRPM)
        try container.encode(curves, forKey: .curves)
    }

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

        var normalizedCurves: [String: [MonitorFanCurvePoint]] = [:]
        for (key, points) in curves {
            guard let fanIndex = Int(key), fanIndex >= 0 else { continue }
            let minimum = max(0, fanMinimums[fanIndex] ?? 0)
            let maximum = max(minimum, fanMaximums[fanIndex] ?? MonitorFanPolicy.maximumRPM)
            let normalizedPoints = MonitorFanCurve.normalized(points, minimumRPM: minimum, maximumRPM: maximum)
            if normalizedPoints.count >= 2 {
                normalizedCurves[key] = normalizedPoints
            }
        }
        copy.curves = normalizedCurves
        return copy
    }

    func controlTemperature(in reading: MonitorFanReading) -> Double? {
        reading.controlTemperature(selectedKeys: Set(selectedSensorKeys))
    }

    /// 返回指定风扇的曲线。没有自定义曲线时，沿用起转/全速两点曲线。
    func curvePoints(
        for fanIndex: Int,
        minimumRPM: Double,
        maximumRPM: Double
    ) -> [MonitorFanCurvePoint] {
        if let points = curves[String(fanIndex)], points.count >= 2 {
            return points
        }
        return [
            MonitorFanCurvePoint(temperature: startCelsius, rpm: minimumRPM),
            MonitorFanCurvePoint(temperature: fullCelsius, rpm: maximumRPM),
        ]
    }

    func target(
        fanIndex: Int,
        temperature: Double,
        minimumRPM: Double,
        maximumRPM: Double
    ) -> Double {
        MonitorFanCurve.target(
            points: curvePoints(
                for: fanIndex,
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM
            ),
            temperature: temperature,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM
        )
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let curveText = curves.isEmpty
            ? ""
            : (try? encoder.encode(curves)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return [
            "enabled": enabled ? "true" : "false",
            "mode": mode == .manual ? "manual" : "auto",
            "start": String(format: "%.0f", startCelsius),
            "full": String(format: "%.0f", fullCelsius),
            "sensors": selectedSensorKeys.joined(separator: ","),
            "manualRPM": rpm,
            "curves": curveText,
        ]
    }

    var selectedSensorCount: Int {
        max(1, selectedSensorKeys.count)
    }
}

enum MonitorFanPolicy {
    static let minimumStartCelsius = 35.0
    static let maximumStartCelsius = 80.0
    static let minimumCurveCelsius = 40.0
    static let maximumFullCelsius = 105.0
    static let maximumCurvePointCount = 8
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
        target(
            points: [
                MonitorFanCurvePoint(temperature: startCelsius, rpm: minimumRPM),
                MonitorFanCurvePoint(temperature: fullCelsius, rpm: maximumRPM),
            ],
            temperature: temperature,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM
        )
    }

    static func target(
        points: [MonitorFanCurvePoint],
        temperature: Double,
        minimumRPM: Double,
        maximumRPM: Double
    ) -> Double {
        let sorted = normalized(points, minimumRPM: minimumRPM, maximumRPM: maximumRPM)
        guard let first = sorted.first, let last = sorted.last else {
            return minimumRPM
        }
        let value: Double
        if temperature <= first.temperature {
            value = first.rpm
        } else if temperature >= last.temperature {
            value = last.rpm
        } else {
            value = zip(sorted, sorted.dropFirst()).first { left, right in
                temperature <= right.temperature
            }.map { left, right in
                let fraction = (temperature - left.temperature) / max(0.001, right.temperature - left.temperature)
                return left.rpm + (right.rpm - left.rpm) * fraction
            } ?? last.rpm
        }
        return min(maximumRPM, max(minimumRPM, value))
    }

    static func normalized(
        _ points: [MonitorFanCurvePoint],
        minimumRPM: Double,
        maximumRPM: Double
    ) -> [MonitorFanCurvePoint] {
        let safeMinimum = max(0, minimumRPM)
        let safeMaximum = max(safeMinimum, maximumRPM)
        var byTemperature: [Double: MonitorFanCurvePoint] = [:]
        for point in points where point.temperature.isFinite && point.rpm.isFinite {
            let temperature = min(
                MonitorFanPolicy.maximumFullCelsius,
                max(MonitorFanPolicy.minimumCurveCelsius, point.temperature.rounded())
            )
            let rpm = min(
                safeMaximum,
                max(safeMinimum, ((point.rpm / 50).rounded() * 50))
            )
            byTemperature[temperature] = MonitorFanCurvePoint(temperature: temperature, rpm: rpm)
        }
        let sorted = byTemperature.values.sorted { $0.temperature < $1.temperature }
        guard sorted.count > MonitorFanPolicy.maximumCurvePointCount else {
            return sorted
        }
        let lastIndex = sorted.count - 1
        let interval = Double(lastIndex) / Double(MonitorFanPolicy.maximumCurvePointCount - 1)
        return (0..<MonitorFanPolicy.maximumCurvePointCount).map { slot in
            sorted[Int((Double(slot) * interval).rounded())]
        }
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
