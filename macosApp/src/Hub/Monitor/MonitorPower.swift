import Foundation

extension MonitorSnapshot {
    /// Monitor 页的电源卡片数据。
    ///
    /// 每个读数独立可选。任一接口失败时，只有对应读数显示占位符。
    struct Power: Equatable, Sendable {
        enum Supply: String, Equatable, Sendable {
            case battery
            case charging
            case adapter
            case unknown
        }

        struct TopApp: Identifiable, Equatable, Sendable {
            let id: String
            let name: String
            let energyMilliwattHours: Double
            let share: Double
            let bundlePath: String?
        }

        let supply: Supply
        let hasBattery: Bool
        let batteryPercent: Double?
        let temperatureCelsius: Double?
        let watts: Double?
        let averageWatts: Double?
        let remainingSeconds: TimeInterval?
        let topApps: [TopApp]
        let batteryDataAvailable: Bool
        let powerDataAvailable: Bool
        let energyDataAvailable: Bool

        var hasReadFailure: Bool {
            guard hasBattery else { return false }
            return !batteryDataAvailable || !powerDataAvailable
        }

        static let empty = Power(
            supply: .unknown,
            hasBattery: false,
            batteryPercent: nil,
            temperatureCelsius: nil,
            watts: nil,
            averageWatts: nil,
            remainingSeconds: nil,
            topApps: [],
            batteryDataAvailable: false,
            powerDataAvailable: false,
            energyDataAvailable: false
        )
    }
}

/// 近 10 个电源功耗样本的平均值。
struct MonitorPowerAverage: Equatable, Sendable {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int = 10) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return average }
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
        return average
    }

    mutating func reset() {
        values.removeAll(keepingCapacity: true)
    }

    var average: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// 一个进程的累计能耗采样。
struct MonitorProcessEnergySample: Equatable, Sendable {
    let processIdentifier: Int32
    let applicationID: String
    let applicationName: String
    let bundlePath: String?
    let cumulativeNanojoules: UInt64
}

/// 按应用聚合的近 60 分钟能耗。
///
/// 进程的 `ri_energy_nj` 是累计值。每次采样只把增量放进当前分钟桶，
/// 所以内存占用与采样次数无关，只与窗口内出现的应用数量有关。
struct MonitorEnergyWindow: Equatable, Sendable {
    static let windowMinutes = 60

    private struct Previous: Equatable, Sendable {
        let applicationID: String
        let cumulativeNanojoules: UInt64
    }

    private struct AppInfo: Equatable, Sendable {
        var name: String
        var bundlePath: String?
    }

    private var previous: [Int32: Previous] = [:]
    private var buckets: [String: [Int: Double]] = [:]
    private var appInfo: [String: AppInfo] = [:]

    mutating func update(
        samples: [MonitorProcessEnergySample],
        at date: Date
    ) -> [MonitorSnapshot.Power.TopApp] {
        let minute = Int(date.timeIntervalSince1970 / 60)
        var currentPIDs = Set<Int32>()

        for sample in samples {
            currentPIDs.insert(sample.processIdentifier)
            appInfo[sample.applicationID] = AppInfo(
                name: sample.applicationName,
                bundlePath: sample.bundlePath
            )

            if let old = previous[sample.processIdentifier],
               old.applicationID == sample.applicationID,
               sample.cumulativeNanojoules >= old.cumulativeNanojoules {
                let joules = Double(sample.cumulativeNanojoules - old.cumulativeNanojoules) / 1_000_000_000
                let milliwattHours = joules / 3.6
                if milliwattHours.isFinite, milliwattHours > 0 {
                    buckets[sample.applicationID, default: [:]][minute, default: 0] += milliwattHours
                }
            }

            previous[sample.processIdentifier] = Previous(
                applicationID: sample.applicationID,
                cumulativeNanojoules: sample.cumulativeNanojoules
            )
        }

        previous = previous.filter { currentPIDs.contains($0.key) }
        let oldestMinute = minute - Self.windowMinutes + 1
        for appID in Array(buckets.keys) {
            buckets[appID] = buckets[appID]?.filter { $0.key >= oldestMinute }
            if buckets[appID]?.isEmpty == true {
                buckets.removeValue(forKey: appID)
            }
        }

        let totals = buckets.mapValues { $0.values.reduce(0, +) }
        let total = totals.values.reduce(0, +)
        guard total > 0 else { return [] }

        return totals.compactMap { appID, energy in
            guard let info = appInfo[appID], energy > 0 else { return nil }
            return MonitorSnapshot.Power.TopApp(
                id: appID,
                name: info.name,
                energyMilliwattHours: energy,
                share: min(1, max(0, energy / total)),
                bundlePath: info.bundlePath
            )
        }
        .sorted {
            if $0.energyMilliwattHours == $1.energyMilliwattHours {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.energyMilliwattHours > $1.energyMilliwattHours
        }
        .prefix(3)
        .map { $0 }
    }
}

/// 电源卡片的降级策略。
///
/// 隐藏顺序固定为 Top3、预计可使用时间、功耗。
enum MonitorPowerLayoutPolicy {
    static let fullHeight: CGFloat = 170
    static let withoutTopAppsHeight: CGFloat = 132
    static let withoutRemainingHeight: CGFloat = 104

    struct Visibility: Equatable, Sendable {
        let showsTopApps: Bool
        let showsRemaining: Bool
        let showsPower: Bool
    }

    static func resolve(height: CGFloat) -> Visibility {
        if height >= fullHeight {
            return Visibility(showsTopApps: true, showsRemaining: true, showsPower: true)
        }
        if height >= withoutTopAppsHeight {
            return Visibility(showsTopApps: false, showsRemaining: true, showsPower: true)
        }
        if height >= withoutRemainingHeight {
            return Visibility(showsTopApps: false, showsRemaining: false, showsPower: true)
        }
        return Visibility(showsTopApps: false, showsRemaining: false, showsPower: false)
    }
}

/// 电源卡片的格式化与阈值。
enum MonitorPowerFormat {
    static let lowBatteryPercent = 20.0
    static let criticalBatteryPercent = 5.0
    static let highTemperatureCelsius = 45.0
    static let powerRefreshSeconds: TimeInterval = 1
    static let estimateRefreshSeconds: TimeInterval = 10

    private static let posix = Locale(identifier: "en_US_POSIX")

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(min(100, max(0, value)).rounded()))%"
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f ℃", locale: posix, value)
    }

    static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f W", locale: posix, max(0, value))
    }

    static func remaining(_ seconds: TimeInterval?, language: AppLanguage) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        let remainder = minutes % 60
        switch language {
        case .simplifiedChinese:
            return "\(hours) 小时 \(remainder) 分钟"
        case .english:
            return "\(hours)h \(remainder)m"
        }
    }

    static func energy(_ milliwattHours: Double) -> String {
        guard milliwattHours.isFinite, milliwattHours > 0 else { return "—" }
        if milliwattHours < 0.1 { return "<0.1 mWh" }
        return String(format: "%.1f mWh", locale: posix, milliwattHours)
    }

    static func share(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    static func batterySupply(
        adapterConnected: Bool,
        isCharging: Bool,
        isCharged: Bool,
        hasBattery: Bool
    ) -> MonitorSnapshot.Power.Supply {
        if adapterConnected {
            return hasBattery && (isCharging || !isCharged) ? .charging : .adapter
        }
        return hasBattery ? .battery : .unknown
    }

    static func aggregateBatteryPercent(
        currentCapacities: [Double],
        maximumCapacities: [Double]
    ) -> Double? {
        let totalMaximum = maximumCapacities.reduce(0, +)
        guard maximumCapacities.count == currentCapacities.count, totalMaximum > 0 else {
            return nil
        }
        let totalCurrent = currentCapacities.reduce(0, +)
        return min(100, max(0, totalCurrent / totalMaximum * 100))
    }

    static func batteryTemperatureCelsius(raw: Double) -> Double? {
        guard raw > 0 else { return nil }
        let value = raw / 100
        guard value.isFinite, value >= -20, value <= 120 else { return nil }
        return value
    }

    static func watts(fromMilliwatts value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value) / 1_000
    }

    static func estimatedRemainingSeconds(
        capacityWattHours: Double?,
        percent: Double?,
        averageWatts: Double?
    ) -> TimeInterval? {
        guard let capacityWattHours,
              let percent,
              let averageWatts,
              capacityWattHours > 0,
              percent > 0,
              averageWatts > 0.05
        else { return nil }
        let remainingWattHours = capacityWattHours * min(100, max(0, percent)) / 100
        return remainingWattHours / averageWatts * 3_600
    }
}
