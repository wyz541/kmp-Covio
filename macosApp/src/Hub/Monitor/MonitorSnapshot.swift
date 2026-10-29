import Foundation

/// 一次监控采样的完整快照。
///
/// 每个模块独立可选。某个接口读取失败时，只有对应的卡片进入不可用状态。
struct MonitorSnapshot: Equatable, Sendable {
    struct CPU: Equatable, Sendable {
        let usage: Double
        let perCore: [Double]
        let loadAverage: Double
        let coreCount: Int
        let uptime: TimeInterval
    }

    struct GPU: Equatable, Sendable {
        let usage: Double
        let memoryUsed: Double
        let model: String
    }

    enum MemoryPressure: String, Equatable, Sendable {
        case normal
        case warning
        case critical
    }

    struct Memory: Equatable, Sendable {
        let used: Double
        let total: Double
        let swapUsed: Double
        let pressure: MemoryPressure
    }

    struct Disk: Equatable, Sendable {
        let used: Double
        let free: Double
        let total: Double
        let readRate: Double
        let writeRate: Double
    }

    struct Network: Equatable, Sendable {
        let downloadRate: Double
        let uploadRate: Double
        let interfaceName: String
    }

    enum BatteryState: String, Equatable, Sendable {
        case discharging
        case charging
        case charged
        case acPower
        case unknown
    }

    struct Battery: Equatable, Sendable {
        let percent: Double
        let state: BatteryState
        let remaining: TimeInterval?
    }

    /// 当前内建屏幕的公开读数。
    ///
    /// `powerWatts` 只在存在可靠测量来源时填写。
    /// 不把系统总功耗或背光电流换算值当作显示器功耗。
    struct Display: Equatable, Sendable {
        enum State: String, Equatable, Sendable {
            case active
            case asleep
            case offline
            case unknown
        }

        let state: State
        let brightnessPercent: Double?
        let powerWatts: Double?
        let externalDisplayCount: Int?
        let pixelWidth: Int?
        let pixelHeight: Int?
        let refreshRate: Double?

        static let empty = Display(
            state: .unknown,
            brightnessPercent: nil,
            powerWatts: nil,
            externalDisplayCount: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            refreshRate: nil
        )
    }

    enum ThermalState: String, Equatable, Sendable {
        case nominal
        case fair
        case serious
        case critical
    }

    let cpu: CPU?
    let gpu: GPU?
    let memory: Memory?
    let disk: Disk?
    let network: Network?
    let battery: Battery?
    let power: Power?
    let display: Display?
    let fan: MonitorFanReading?
    let thermal: ThermalState
    let sampledAt: Date

    static let empty = MonitorSnapshot(
        cpu: nil,
        gpu: nil,
        memory: nil,
        disk: nil,
        network: nil,
        battery: nil,
        power: nil,
        display: nil,
        fan: nil,
        thermal: .nominal,
        sampledAt: .distantPast
    )

    /// 使用电池时降低采样频率。台式机与接电源时保持快速刷新。
    var isOnBattery: Bool {
        power?.supply == .battery || battery?.state == .discharging
    }

    /// 电源卡片有独立的 1 秒采样循环。这个函数只替换电源数据。
    func replacingPower(_ power: Power) -> MonitorSnapshot {
        MonitorSnapshot(
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            disk: disk,
            network: network,
            battery: battery,
            power: power,
            display: display,
            fan: fan,
            thermal: thermal,
            sampledAt: sampledAt
        )
    }

    func replacingDisplay(_ display: Display) -> MonitorSnapshot {
        MonitorSnapshot(
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            disk: disk,
            network: network,
            battery: battery,
            power: power,
            display: display,
            fan: fan,
            thermal: thermal,
            sampledAt: sampledAt
        )
    }
}

/// 采样节奏。用户正在看监控页时才运行。
enum MonitorCadence {
    static let pluggedIn: TimeInterval = 1
    static let onBattery: TimeInterval = 5

    static func interval(for snapshot: MonitorSnapshot) -> TimeInterval {
        snapshot.isOnBattery ? onBattery : pluggedIn
    }
}

/// 数值格式化。单位沿用 Stats 的十进制换算。
enum MonitorFormat {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction.clamped(to: 0...1) * 100).rounded()))%"
    }

    static func bytes(_ value: Double) -> String {
        let magnitude = max(0, value)
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = magnitude
        var unitIndex = 0
        while scaled >= 1_000, unitIndex < units.count - 1 {
            scaled /= 1_000
            unitIndex += 1
        }
        return "\(number(scaled)) \(units[unitIndex])"
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        "\(bytes(bytesPerSecond))/s"
    }

    static func load(_ value: Double) -> String {
        String(format: "%.2f", max(0, value))
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    private static func number(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}

/// 由累计计数器计算速率。
enum MonitorRate {
    static func perSecond(
        current: UInt64?,
        previous: UInt64?,
        elapsed: TimeInterval
    ) -> Double {
        guard let current, let previous, current >= previous, elapsed > 0 else { return 0 }
        return Double(current - previous) / elapsed
    }
}

/// 固定长度的采样历史。满了以后丢最旧的一点。
struct MonitorHistory: Equatable, Sendable {
    let capacity: Int
    private(set) var cpu: [Double] = []
    private(set) var gpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var disk: [Double] = []
    private(set) var download: [Double] = []
    private(set) var upload: [Double] = []
    private(set) var battery: [Double] = []
    private(set) var fanTemperature: [Double] = []
    private(set) var fanRPM: [Double] = []

    init(capacity: Int = 60) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ snapshot: MonitorSnapshot, fanControlTemperature: Double? = nil) {
        Self.append(snapshot.cpu?.usage, to: &cpu, capacity: capacity)
        Self.append(snapshot.gpu?.usage, to: &gpu, capacity: capacity)
        if let memoryReading = snapshot.memory, memoryReading.total > 0 {
            Self.append(memoryReading.used / memoryReading.total, to: &memory, capacity: capacity)
        }
        if let diskReading = snapshot.disk {
            Self.append(diskReading.readRate + diskReading.writeRate, to: &disk, capacity: capacity)
        }
        Self.append(snapshot.network?.downloadRate, to: &download, capacity: capacity)
        Self.append(snapshot.network?.uploadRate, to: &upload, capacity: capacity)
        Self.append(snapshot.battery.map { $0.percent / 100 }, to: &battery, capacity: capacity)
        Self.append(
            fanControlTemperature ?? snapshot.fan?.maximumTemperature,
            to: &fanTemperature,
            capacity: capacity
        )
        Self.append(snapshot.fan?.units.map(\.rpm).max(), to: &fanRPM, capacity: capacity)
    }

    mutating func reset() {
        cpu.removeAll(keepingCapacity: true)
        gpu.removeAll(keepingCapacity: true)
        memory.removeAll(keepingCapacity: true)
        disk.removeAll(keepingCapacity: true)
        download.removeAll(keepingCapacity: true)
        upload.removeAll(keepingCapacity: true)
        battery.removeAll(keepingCapacity: true)
        fanTemperature.removeAll(keepingCapacity: true)
        fanRPM.removeAll(keepingCapacity: true)
    }

    private static func append(_ value: Double?, to values: inout [Double], capacity: Int) {
        guard var current = value, current.isFinite else { return }
        current = max(0, current)
        values.append(current)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }
}
