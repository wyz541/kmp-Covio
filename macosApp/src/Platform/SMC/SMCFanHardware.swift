import Foundation

struct SMCTemperatureReading: Equatable, Sendable, Identifiable {
    let key: String
    let celsius: Double

    var id: String { key }
}

struct SMCFanReading: Equatable, Sendable, Identifiable {
    let index: Int
    let rpm: Double
    let minimumRPM: Double
    let maximumRPM: Double
    let targetRPM: Double
    let mode: Int

    var id: Int { index }
}

struct SMCFanReadingSnapshot: Equatable, Sendable {
    let temperatures: [SMCTemperatureReading]
    let fans: [SMCFanReading]

    var maximumTemperature: Double? {
        temperatures.map(\.celsius).max()
    }
}

final class SMCFanReader {
    private let smc: SMCAccess
    private let temperatureKeys: [SMCAccessKey]
    private let availableKeys: Set<String>
    private let appleSilicon: Bool
    private var lastValidFanMaximums: [Int: Double] = [:]

    convenience init() throws {
        let access = try SMCAccess()
        self.init(access: access)
    }

    init(access: SMCAccess, allKeys: [SMCAccessKey]? = nil) {
        smc = access
        let keys = allKeys ?? access.allKeys()
        availableKeys = Set(keys.map(\.description))
        appleSilicon = StatsFanControl.isAppleSilicon
        temperatureKeys = keys.filter { $0.description.hasPrefix("T") }
    }

    static func temperatureSourceReadings(
        for sensors: [SMCTemperatureReading],
        appleSilicon: Bool = StatsFanControl.isAppleSilicon
    ) -> [MonitorFanTemperatureSource: Double] {
        var values: [MonitorFanTemperatureSource: Double] = [:]
        for sensor in sensors {
            guard let source = temperatureSource(for: sensor.key, appleSilicon: appleSilicon) else {
                continue
            }
            values[source] = max(values[source] ?? sensor.celsius, sensor.celsius)
        }
        return values
    }

    static func temperatureSource(
        for key: String,
        appleSilicon: Bool
    ) -> MonitorFanTemperatureSource? {
        if key == "TB0T" || key == "TB1T" || key == "TB2T" || key == "TB3T" {
            return .battery
        }

        if appleSilicon {
            if key.hasPrefix("Tg") { return .gpu }
        } else if key.hasPrefix("TG") || key == "TCGC" {
            return .gpu
        }

        let isNumericCore = key.count == 4
            && key.hasPrefix("TC")
            && key.dropFirst(2).allSatisfy(\.isNumber)
        if key == "TCMz" || key == "TCMb" || key.hasPrefix("Tp")
            || key.hasPrefix("Te") || key.hasPrefix("Tf") || isNumericCore {
            return .cpu
        }
        return nil
    }

    static func controlSensorKeys(for sensors: [SMCTemperatureReading], allKeys: [String]) -> [String] {
        let available = Set(allKeys)
        let coreKeys = allKeys.filter { key in
            key.hasPrefix("Tp") || key.range(of: #"^TC\d\d$"#, options: .regularExpression) != nil
        }
        var selected = coreKeys
        for preferred in ["TCMz", "TCMb", "TC0P", "TC0D"] where available.contains(preferred) {
            selected.append(preferred)
            break
        }
        selected.append(contentsOf: allKeys.filter { key in
            key.range(of: #"^TG[0-9]"#, options: .regularExpression) != nil
        })
        if selected.isEmpty {
            selected = allKeys.filter { $0.hasPrefix("T") }.sorted().prefix(8).map(\.self)
        }
        let valid = selected.filter { key in sensors.contains { $0.key == key } }
        return valid.isEmpty ? sensors.prefix(8).map(\.key) : valid
    }

    func read(sensorKeys: Set<String>? = nil) -> SMCFanReadingSnapshot {
        let sensors = readTemperatures(sensorKeys: sensorKeys)
        let fans = (try? readFans()) ?? []
        return SMCFanReadingSnapshot(temperatures: sensors, fans: fans)
    }

    func readTemperatures(sensorKeys: Set<String>? = nil) -> [SMCTemperatureReading] {
        let keys = temperatureKeys.filter { key in
            sensorKeys?.contains(key.description) ?? true
        }
        var readings: [SMCTemperatureReading] = []
        readings.reserveCapacity(keys.count)
        for key in keys {
            guard let value = try? smc.readValue(key),
                  let celsius = value.doubleValue,
                  celsius > 0,
                  celsius < 110
            else { continue }
            readings.append(SMCTemperatureReading(key: key.description, celsius: celsius))
        }
        return readings.sorted { $0.celsius > $1.celsius }
    }

    func readFans() throws -> [SMCFanReading] {
        guard let fanCountKey = SMCAccessKey("FNum") else { return [] }
        let count = try smc.readValue(fanCountKey).intValue ?? 0
        guard count > 0, count < 16 else { return [] }

        var fans: [SMCFanReading] = []
        fans.reserveCapacity(count)
        for index in 0..<count {
            let minimum = readFanDouble(index: index, suffix: "Mn", attempts: 2) ?? 0
            let maximumSample = readFanDouble(index: index, suffix: "Mx", attempts: 3)
            let maximum = Self.validFanMaximum(maximumSample, minimum: minimum)
                ?? lastValidFanMaximums[index]
            guard let maximum else { continue }
            lastValidFanMaximums[index] = maximum

            var rpm = readFanDouble(index: index, suffix: "Ac") ?? 0
            if minimum > 500, rpm < minimum * 0.5 {
                for _ in 0..<2 {
                    Thread.sleep(forTimeInterval: 0.05)
                    rpm = readFanDouble(index: index, suffix: "Ac") ?? rpm
                    if rpm >= minimum * 0.5 { break }
                }
            }
            fans.append(SMCFanReading(
                index: index,
                rpm: max(0, rpm),
                minimumRPM: max(0, minimum),
                maximumRPM: maximum,
                targetRPM: max(0, readFanDouble(index: index, suffix: "Tg") ?? 0),
                mode: readFanMode(index: index) ?? -1
            ))
        }
        return fans
    }

    /// Stats treats mode 3 as system automatic.
    private func readFanMode(index: Int) -> Int? {
        if appleSilicon {
            guard let modeName = StatsFanModeResolver.modeKey(
                for: index,
                availableKeys: availableKeys,
                appleSilicon: true
            ), let key = SMCAccessKey(modeName), let raw = try? smc.readInt(key)
            else { return nil }
            return StatsFanModeResolver.normalizedMode(
                rawValue: raw,
                appleSilicon: true,
                fanIndex: index,
                fansModeBits: nil
            )?.rawValue
        }

        guard let key = SMCAccessKey("FS! "), let raw = try? smc.readInt(key) else {
            return nil
        }
        return StatsFanModeResolver.normalizedMode(
            rawValue: 0,
            appleSilicon: false,
            fanIndex: index,
            fansModeBits: raw
        )?.rawValue
    }

    static func validFanMaximum(_ value: Double?, minimum: Double) -> Double? {
        guard let value,
              value.isFinite,
              value > max(0, minimum),
              value <= MonitorFanPolicy.maximumRPM
        else { return nil }
        return value
    }

    private func readFanDouble(
        index: Int,
        suffix: String,
        attempts: Int = 1
    ) -> Double? {
        guard let key = SMCAccessKey("F\(index)\(suffix)") else { return nil }
        for attempt in 0..<max(1, attempts) {
            if let value = try? smc.readDouble(key) {
                return value
            }
            if attempt + 1 < attempts {
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
        return nil
    }

}

enum SMCTemperatureName {
    private static let known: [String: (zh: String, en: String)] = [
        "TCMz": ("CPU 峰值", "CPU Peak"),
        "TCMb": ("CPU 平均", "CPU Average"),
        "TCMc": ("CPU P 核峰值", "CPU P-core Peak"),
        "TC0P": ("CPU 邻近", "CPU Proximity"),
        "TC0D": ("CPU 核心", "CPU Core"),
        "TC0E": ("CPU 核心", "CPU Core"),
        "TC0F": ("CPU 核心", "CPU Core"),
        "TC0H": ("CPU 散热片", "CPU Heatsink"),
        "TC0C": ("CPU 核心", "CPU Core"),
        "TC1C": ("CPU 核心 1", "CPU Core 1"),
        "TC2C": ("CPU 核心 2", "CPU Core 2"),
        "TC3C": ("CPU 核心 3", "CPU Core 3"),
        "TC4C": ("CPU 核心 4", "CPU Core 4"),
        "TC5C": ("CPU 核心 5", "CPU Core 5"),
        "TC6C": ("CPU 核心 6", "CPU Core 6"),
        "TC7C": ("CPU 核心 7", "CPU Core 7"),
        "TC8C": ("CPU 核心 8", "CPU Core 8"),
        "TCSA": ("CPU 系统代理", "CPU System Agent"),
        "TG0P": ("GPU 邻近", "GPU Proximity"),
        "TG0D": ("GPU 核心", "GPU Core"),
        "TG0H": ("GPU 散热片", "GPU Heatsink"),
        "TG1D": ("GPU2 核心", "GPU2 Core"),
        "TG1P": ("GPU2 邻近", "GPU2 Proximity"),
        "Tm0P": ("内存", "Memory"),
        "TM0P": ("内存", "Memory"),
        "TM0A": ("内存 A", "Memory A"),
        "TM0B": ("内存 B", "Memory B"),
        "TMVR": ("内存 VRM", "Memory VRM"),
        "TN0D": ("北桥", "Northbridge"),
        "TN1D": ("北桥 2", "Northbridge 2"),
        "TS0P": ("南桥", "Southbridge"),
        "TB0T": ("电池 1", "Battery 1"),
        "TB1T": ("电池 2", "Battery 2"),
        "TB2T": ("电池 3", "Battery 3"),
        "TB3T": ("电池 4", "Battery 4"),
        "TP0P": ("电源", "Power"),
        "TP1P": ("电源 2", "Power 2"),
        "TPCD": ("电源二极管", "Power Diode"),
        "TAOL": ("环境", "Ambient"),
        "TaLP": ("环境", "Ambient"),
        "TA0P": ("环境", "Ambient"),
        "TA1P": ("环境 2", "Ambient 2"),
        "TaSP": ("环境（睡眠）", "Ambient (Sleep)"),
        "Ts0S": ("掌托左", "Palm Rest Left"),
        "Ts1S": ("掌托右", "Palm Rest Right"),
        "Ts0P": ("掌托", "Palm Rest"),
        "Ts1P": ("掌托 2", "Palm Rest 2"),
        "TCXC": ("扩充槽", "Expansion Slot"),
        "TH0P": ("HDD", "HDD"),
        "TH0a": ("出风口 a", "Exhaust a"),
        "TH0b": ("出风口 b", "Exhaust b"),
        "TH1a": ("出风口 c", "Exhaust c"),
        "TH1b": ("出风口 d", "Exhaust d"),
        "TH0x": ("出风口 e", "Exhaust e"),
        "TW0P": ("无线网卡", "Wi-Fi"),
        "TL0P": ("雷电", "Thunderbolt"),
        "TI0P": ("雷电", "Thunderbolt"),
        "TI1P": ("雷电 2", "Thunderbolt 2"),
        "TD0P": ("SSD 控制器", "SSD Controller"),
        "TDRD": ("SSD 二极管", "SSD Diode"),
        "TD3P": ("NAND", "NAND"),
        "TO0P": ("光学驱动器", "Optical Drive"),
        "TVEP": ("视频", "Video"),
        "TVM0": ("显存", "Video Memory"),
    ]

    private static let prefixes: [(String, (zh: String, en: String))] = [
        ("TC", ("CPU", "CPU")),
        ("Tp", ("CPU", "CPU")),
        ("TG", ("GPU", "GPU")),
        ("Tg", ("GPU", "GPU")),
        ("TM", ("内存", "Memory")),
        ("Tm", ("内存", "Memory")),
        ("TB", ("电池", "Battery")),
        ("TA", ("环境", "Ambient")),
        ("Ta", ("环境", "Ambient")),
        ("TH", ("散热", "Thermal")),
        ("Ts", ("掌托", "Palm Rest")),
        ("TW", ("无线", "Wireless")),
    ]

    static func displayName(for key: String, language: AppLanguage) -> String {
        let chinese = language != .english
        if let name = known[key] {
            return chinese ? name.zh : name.en
        }
        for (prefix, name) in prefixes where key.hasPrefix(prefix) {
            return "\(chinese ? name.zh : name.en) \(key.dropFirst(2))"
        }
        return key
    }

    static func matches(_ key: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return key.localizedCaseInsensitiveContains(trimmed)
            || displayName(for: key, language: .simplifiedChinese)
                .localizedCaseInsensitiveContains(trimmed)
            || displayName(for: key, language: .english)
                .localizedCaseInsensitiveContains(trimmed)
    }

    static var knownKeys: Set<String> { Set(known.keys) }
}
