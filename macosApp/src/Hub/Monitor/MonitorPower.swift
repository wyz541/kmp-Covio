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
        let chargePowerWatts: Double?
        let timeToFullSeconds: TimeInterval?
        let batteryHealthPercent: Double?
        let topApps: [TopApp]
        let events: [MonitorPowerEvent]
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
            chargePowerWatts: nil,
            timeToFullSeconds: nil,
            batteryHealthPercent: nil,
            topApps: [],
            events: [],
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

/// 电源卡片的一分钟历史点。
struct MonitorPowerMinutePoint: Identifiable, Equatable, Sendable {
    let minuteStart: Date
    let watts: Double?
    let temperatureCelsius: Double?
    let sampleCount: Int

    var id: TimeInterval { minuteStart.timeIntervalSince1970 }
}

/// 电源卡片的历史窗口。
///
/// 折叠态保留最近 60 个一秒样本。详情区保留最近 30 个一分钟聚合点。
/// 两种视图使用同一次采样，温度和功耗不会出现不同来源。
struct MonitorPowerHistory: Equatable, Sendable {
    static let windowMinutes = 30
    static let recentCapacity = 60

    private(set) var recentPower: [Double] = []
    private(set) var recentTemperature: [Double] = []

    private var completedMinutes: [MonitorPowerMinutePoint] = []
    private var activeMinuteStart: Date?
    private var activePowerSum = 0.0
    private var activePowerCount = 0
    private var activeTemperatureSum = 0.0
    private var activeTemperatureCount = 0
    private var activeSampleCount = 0

    mutating func append(_ power: MonitorSnapshot.Power, at date: Date = Date()) {
        if let watts = power.watts, watts.isFinite, watts >= 0 {
            recentPower.append(watts)
            if recentPower.count > Self.recentCapacity {
                recentPower.removeFirst(recentPower.count - Self.recentCapacity)
            }
        }
        if let temperature = power.temperatureCelsius,
           temperature.isFinite {
            recentTemperature.append(temperature)
            if recentTemperature.count > Self.recentCapacity {
                recentTemperature.removeFirst(recentTemperature.count - Self.recentCapacity)
            }
        }

        guard power.watts != nil || power.temperatureCelsius != nil else { return }
        let minuteStart = Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
        if activeMinuteStart != minuteStart {
            finalizeActiveMinute()
            activeMinuteStart = minuteStart
        }

        activeSampleCount += 1
        if let watts = power.watts, watts.isFinite, watts >= 0 {
            activePowerSum += watts
            activePowerCount += 1
        }
        if let temperature = power.temperatureCelsius,
           temperature.isFinite {
            activeTemperatureSum += temperature
            activeTemperatureCount += 1
        }
        prune(at: date)
    }

    var minutePoints: [MonitorPowerMinutePoint] {
        var points = completedMinutes
        if let active = activePoint {
            points.append(active)
        }
        return points.sorted { $0.minuteStart < $1.minuteStart }
    }

    mutating func reset() {
        self = MonitorPowerHistory()
    }

    private var activePoint: MonitorPowerMinutePoint? {
        guard let activeMinuteStart, activeSampleCount > 0 else { return nil }
        return MonitorPowerMinutePoint(
            minuteStart: activeMinuteStart,
            watts: activePowerCount > 0 ? activePowerSum / Double(activePowerCount) : nil,
            temperatureCelsius: activeTemperatureCount > 0
                ? activeTemperatureSum / Double(activeTemperatureCount)
                : nil,
            sampleCount: activeSampleCount
        )
    }

    private mutating func finalizeActiveMinute() {
        guard let point = activePoint else {
            activeMinuteStart = nil
            return
        }
        completedMinutes.append(point)
        activeMinuteStart = nil
        activePowerSum = 0
        activePowerCount = 0
        activeTemperatureSum = 0
        activeTemperatureCount = 0
        activeSampleCount = 0
    }

    private mutating func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-TimeInterval(Self.windowMinutes * 60))
        completedMinutes.removeAll { $0.minuteStart < cutoff }
    }
}

/// 一条供电状态变更事件。
struct MonitorPowerEvent: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case connected
        case disconnected
        case fullyCharged
    }

    let kind: Kind
    let at: Date

    var id: String { "\(kind.rawValue)-\(at.timeIntervalSince1970)" }
}

/// 近 24 小时的供电事件窗口。
struct MonitorPowerEventHistory: Equatable, Sendable {
    static let windowSeconds: TimeInterval = 24 * 60 * 60

    private(set) var events: [MonitorPowerEvent]
    private var lastSupply: MonitorSnapshot.Power.Supply?
    private var lastPercent: Double?

    init(events: [MonitorPowerEvent] = []) {
        self.events = events.sorted { $0.at < $1.at }
    }

    mutating func replace(events: [MonitorPowerEvent]) {
        self.events = events.sorted { $0.at < $1.at }
    }

    mutating func observe(
        supply: MonitorSnapshot.Power.Supply,
        batteryPercent: Double?,
        at date: Date
    ) -> [MonitorPowerEvent] {
        defer {
            lastSupply = supply
            lastPercent = batteryPercent
            prune(at: date)
        }
        guard let previous = lastSupply, previous != .unknown, supply != .unknown else {
            return events
        }

        let wasAdapter = previous == .charging || previous == .adapter
        let isAdapter = supply == .charging || supply == .adapter
        if !wasAdapter, isAdapter {
            events.append(MonitorPowerEvent(kind: .connected, at: date))
        } else if wasAdapter, supply == .battery {
            events.append(MonitorPowerEvent(kind: .disconnected, at: date))
        }

        if isAdapter,
           let percent = batteryPercent,
           percent >= 99.5,
           (lastPercent ?? 0) < 99.5 {
            events.append(MonitorPowerEvent(kind: .fullyCharged, at: date))
        }
        return events
    }

    mutating func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-Self.windowSeconds)
        events.removeAll { $0.at < cutoff }
    }
}

/// 展开详情区的裁剪策略。
///
/// 高度不足时从 P4 向 P0 顺序隐藏。P0 始终保留。
enum MonitorPowerDetailLayoutPolicy {
    static let fullHeight: CGFloat = 800
    static let withoutEventsHeight: CGFloat = 660
    static let withoutChargingHeight: CGFloat = 560
    static let withoutEstimateHeight: CGFloat = 430
    static let withoutHistoryHeight: CGFloat = 300

    struct Visibility: Equatable, Sendable {
        let showsTopApps: Bool
        let showsHistory: Bool
        let showsEstimate: Bool
        let showsCharging: Bool
        let showsEvents: Bool
    }

    static func resolve(height: CGFloat) -> Visibility {
        if height >= fullHeight {
            return Visibility(
                showsTopApps: true,
                showsHistory: true,
                showsEstimate: true,
                showsCharging: true,
                showsEvents: true
            )
        }
        if height >= withoutEventsHeight {
            return Visibility(
                showsTopApps: true,
                showsHistory: true,
                showsEstimate: true,
                showsCharging: true,
                showsEvents: false
            )
        }
        if height >= withoutChargingHeight {
            return Visibility(
                showsTopApps: true,
                showsHistory: true,
                showsEstimate: true,
                showsCharging: false,
                showsEvents: false
            )
        }
        if height >= withoutEstimateHeight {
            return Visibility(
                showsTopApps: true,
                showsHistory: true,
                showsEstimate: false,
                showsCharging: false,
                showsEvents: false
            )
        }
        if height >= withoutHistoryHeight {
            return Visibility(
                showsTopApps: true,
                showsHistory: false,
                showsEstimate: false,
                showsCharging: false,
                showsEvents: false
            )
        }
        return Visibility(
            showsTopApps: true,
            showsHistory: false,
            showsEstimate: false,
            showsCharging: false,
            showsEvents: false
        )
    }
}

/// 电源卡片的格式化与阈值。
enum MonitorPowerFormat {
    static let lowBatteryPercent = 20.0
    static let criticalBatteryPercent = 5.0
    static let highTemperatureCelsius = 45.0
    static let powerRefreshSeconds: TimeInterval = 1
    static let estimateRefreshSeconds: TimeInterval = 10
    static let detailAnimationSeconds: TimeInterval = 0.22

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

    static func eventTime(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .simplifiedChinese ? "MM-dd HH:mm" : "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    static func batterySupply(
        adapterConnected: Bool,
        isCharging: Bool,
        isCharged: Bool,
        hasBattery: Bool
    ) -> MonitorSnapshot.Power.Supply {
        if adapterConnected {
            return hasBattery && isCharging ? .charging : .adapter
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
