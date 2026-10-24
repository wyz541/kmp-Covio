import AppKit
import CoreGraphics
import Darwin
import Foundation
@preconcurrency import IOKit
import SystemConfiguration

/// macOS 公开接口的监控读取器。
///
/// 指标口径参考 `exelban/stats` 的 commit
/// `573145558badb690728e39f3b2dcdb490e2ea731`。这里不包含它的运行时代码。
/// 读取在 `MonitorSampler` actor 内串行执行，因此内部计数状态不需要加锁。
final class MacMonitorReader {
    private struct DiskCounters {
        let read: UInt64
        let write: UInt64
        let time: UInt64
    }

    private struct NetworkCounters {
        let interfaceName: String
        let received: UInt64
        let sent: UInt64
        let time: UInt64
    }

    private struct BatteryRegistryMetrics {
        let temperatureCelsius: Double?
        let capacityWattHours: Double?
        let batteryPowerMilliwatts: Double?
        let systemPowerMilliwatts: Double?
        let chargePowerMilliwatts: Double?
        let healthPercent: Double?
    }

    private struct IOPSBatteryAggregate {
        let hasBattery: Bool
        let percent: Double?
        let supply: MonitorSnapshot.Power.Supply
        let isCharged: Bool
        let timeToEmptySeconds: TimeInterval?
        let timeToFullSeconds: TimeInterval?
    }

    private struct AppIdentity: Equatable {
        let id: String
        let name: String
        let bundlePath: String?
    }

    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0
    private var previousCPULoad = host_cpu_load_info()
    private var hasPreviousCPULoad = false
    private var previousDisk: DiskCounters?
    private var previousNetwork: NetworkCounters?
    private var powerAverage = MonitorPowerAverage()
    private var previousPowerSupply: MonitorSnapshot.Power.Supply?
    private var energyWindow = MonitorEnergyWindow()
    private var lastEnergyScanAt = Date.distantPast
    private var lastEnergyApps: [MonitorSnapshot.Power.TopApp] = []
    private var energyDataAvailable = false
    private var identityCache: [Int32: AppIdentity] = [:]
    private var mainApplications: [AppIdentity] = []
    private var lastIdentityRefreshAt = Date.distantPast
    private let powerEventStore = MonitorPowerEventStore()
    private lazy var fanReader: SMCFanReader? = try? SMCFanReader()
    private var lastFanReading: MonitorFanReading?
    private var lastFanReadAt = Date.distantPast

    func read() -> MonitorSnapshot {
        let memory = readMemory()
        let reading = readPower(includeTopApps: true)
        return MonitorSnapshot(
            cpu: readCPU(),
            gpu: readGPU(),
            memory: memory,
            disk: readDisk(),
            network: readNetwork(),
            battery: reading.battery,
            power: reading.power,
            fan: readFan(),
            thermal: readThermal(),
            sampledAt: Date()
        )
    }

    /// 电源卡片每秒只读 IOPS、IOKit 与能耗窗口，不重复扫描无关指标。
    func readPowerOnly() -> MonitorSnapshot.Power {
        readPower(includeTopApps: true).power
    }

    /// SMC 温度键较多，翻页和帮助浮层都不需要每秒重读全部传感器。
    private func readFan() -> MonitorFanReading? {
        guard let fanReader else { return nil }
        let now = Date()
        if now.timeIntervalSince(lastFanReadAt) < 2, let lastFanReading {
            return lastFanReading
        }

        let snapshot = fanReader.read()
        guard !snapshot.temperatures.isEmpty else { return nil }
        let reading = MonitorFanReading(
            temperatures: snapshot.temperatures.map {
                MonitorFanReading.Temperature(key: $0.key, celsius: $0.celsius)
            },
            units: snapshot.fans.map {
                MonitorFanReading.Unit(
                    index: $0.index,
                    rpm: $0.rpm,
                    minimumRPM: $0.minimumRPM,
                    maximumRPM: $0.maximumRPM,
                    targetRPM: $0.targetRPM,
                    mode: $0.mode
                )
            }
        )
        lastFanReadAt = now
        lastFanReading = reading
        return reading
    }

    /// 读取一条历史样本。
    ///
    /// 这个路径跳过进程扫描、top app、应用身份和路径解析。
    /// 读取失败时保留空值，不写零值。
    func readHistory(
        at date: Date,
        monotonicNanoseconds: UInt64,
        bootID: String,
        kind: MonitorHistorySample.Kind = .periodic
    ) -> MonitorHistorySample {
        let memory = readMemory()
        let reading = readPower(includeTopApps: false)
        let cpu = readCPU()
        let gpu = readGPU()
        let disk = readDisk()
        let network = readNetwork()
        let thermal = readThermal()
        let battery = reading.battery
        let power = reading.power

        let powerSource: MonitorHistorySample.PowerSource
        switch power.supply {
        case .adapter, .charging:
            powerSource = .ac
        case .battery:
            powerSource = .battery
        case .unknown:
            powerSource = .unknown
        }

        let memoryPressure: MonitorHistorySample.MemoryPressure? = memory.map { value in
            switch value.pressure {
            case .normal: return .normal
            case .warning: return .warning
            case .critical: return .critical
            }
        }

        let displayState = CGDisplayIsAsleep(CGMainDisplayID()) != 0
            ? MonitorHistorySample.DisplayState.off
            : .on
        let lidState: MonitorHistorySample.LidState
        switch MacLidSensor.readClamshellState() {
        case .open: lidState = .open
        case .closed: lidState = .closed
        case .unknown: lidState = .unknown
        default: lidState = .unknown
        }

        let isBattery = powerSource == .battery
        let requiredValuesPresent = cpu != nil
            && memory != nil
            && disk != nil
            && network != nil
            && power != nil

        return MonitorHistorySample(
            sampledAt: date,
            monotonicNanoseconds: monotonicNanoseconds,
            bootID: bootID,
            powerSource: powerSource,
            thermalState: {
                switch thermal {
                case .nominal: .nominal
                case .fair: .fair
                case .serious: .serious
                case .critical: .critical
                }
            }(),
            cpuUsage: cpu?.usage,
            cpuLoad1: cpu?.loadAverage,
            cpuCoreCount: cpu?.coreCount,
            gpuUsage: gpu?.usage,
            gpuMemoryBytes: gpu?.memoryUsed,
            memoryUsedBytes: memory?.used,
            memoryTotalBytes: memory?.total,
            memoryPressure: memoryPressure,
            swapUsedBytes: memory?.swapUsed,
            diskReadBytesPerSecond: disk?.readRate,
            diskWriteBytesPerSecond: disk?.writeRate,
            diskUsedBytes: disk?.used,
            diskFreeBytes: disk?.free,
            networkReceiveBytesPerSecond: network?.downloadRate,
            networkTransmitBytesPerSecond: network?.uploadRate,
            batteryPercent: battery?.percent,
            batteryTemperatureCelsius: power.temperatureCelsius,
            batteryHealthPercent: power.batteryHealthPercent,
            systemPowerWatts: isBattery ? nil : power.watts,
            batteryPowerWatts: isBattery ? power.watts : nil,
            displayState: displayState,
            lidState: lidState,
            kind: kind,
            quality: requiredValuesPresent ? .complete : .partial
        )
    }

    // MARK: - CPU

    private func readCPU() -> MonitorSnapshot.CPU? {
        let usage = readCPULoad()
        let perCore = readPerCoreUsage()
        let coreCount = perCore.isEmpty ? ProcessInfo.processInfo.processorCount : perCore.count
        return MonitorSnapshot.CPU(
            usage: usage,
            perCore: perCore,
            loadAverage: readLoadAverage(),
            coreCount: coreCount,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func readCPULoad() -> Double {
        var current = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &current) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer {
            previousCPULoad = current
            hasPreviousCPULoad = true
        }
        guard hasPreviousCPULoad else { return 0 }

        let user = Double(current.cpu_ticks.0 &- previousCPULoad.cpu_ticks.0)
        let system = Double(current.cpu_ticks.1 &- previousCPULoad.cpu_ticks.1)
        let idle = Double(current.cpu_ticks.2 &- previousCPULoad.cpu_ticks.2)
        let nice = Double(current.cpu_ticks.3 &- previousCPULoad.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(1, max(0, (user + system + nice) / total))
    }

    private func readPerCoreUsage() -> [Double] {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return [] }

        var values: [Double] = []
        if let previousCPUInfo, previousCPUInfoCount == cpuInfoCount {
            values.reserveCapacity(Int(cpuCount))
            for index in 0..<Int(cpuCount) {
                let user = UInt32(bitPattern: cpuInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_USER)])
                    &- UInt32(bitPattern: previousCPUInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_USER)])
                let system = UInt32(bitPattern: cpuInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_SYSTEM)])
                    &- UInt32(bitPattern: previousCPUInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_SYSTEM)])
                let nice = UInt32(bitPattern: cpuInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_NICE)])
                    &- UInt32(bitPattern: previousCPUInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_NICE)])
                let idle = UInt32(bitPattern: cpuInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_IDLE)])
                    &- UInt32(bitPattern: previousCPUInfo[Int(CPU_STATE_MAX) * index + Int(CPU_STATE_IDLE)])
                let inUse = UInt64(user) + UInt64(system) + UInt64(nice)
                let total = inUse + UInt64(idle)
                values.append(total == 0 ? 0 : Double(inUse) / Double(total))
            }
        }

        if let previousCPUInfo {
            let size = MemoryLayout<integer_t>.stride * Int(previousCPUInfoCount)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: previousCPUInfo),
                vm_size_t(size)
            )
        }
        previousCPUInfo = cpuInfo
        previousCPUInfoCount = cpuInfoCount
        return values
    }

    private func readLoadAverage() -> Double {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, 3) > 0 else { return 0 }
        return values[0]
    }

    // MARK: - Memory

    private func readMemory() -> MonitorSnapshot.Memory? {
        guard let total = readUInt64Sysctl("hw.memsize"), total > 0 else { return nil }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = Double(sysconf(_SC_PAGESIZE))
        let active = Double(stats.active_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize
        let used = max(0, active + inactive + speculative + wired + compressed - purgeable - external)

        return MonitorSnapshot.Memory(
            used: min(used, Double(total)),
            total: Double(total),
            swapUsed: readSwapUsed(),
            pressure: readMemoryPressure()
        )
    }

    private func readSwapUsed() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used)
    }

    private func readMemoryPressure() -> MonitorSnapshot.MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }

    // MARK: - GPU

    private func readGPU() -> MonitorSnapshot.GPU? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            if let property = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            ), let statistics = property.takeRetainedValue() as? [String: Any] {
                let usage = Double(number(statistics["Device Utilization %"])) / 100
                var memory = Double(number(statistics["In use system memory"]))
                if memory == 0 {
                    memory = Double(number(statistics["Alloc system memory"]))
                }
                return MonitorSnapshot.GPU(
                    usage: min(1, max(0, usage)),
                    memoryUsed: max(0, memory),
                    model: registryString(service, key: "model") ?? "GPU"
                )
            }
        }
        return nil
    }

    // MARK: - Disk

    private func readDisk() -> MonitorSnapshot.Disk? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]), let totalValue = values.volumeTotalCapacity,
            let freeValue = values.volumeAvailableCapacityForImportantUsage,
            totalValue > 0
        else { return nil }

        let total = Double(totalValue)
        let free = min(total, max(0, Double(freeValue)))
        let used = max(0, total - free)
        let counters = readDiskCounters()
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = elapsedSeconds(now: now, previous: previousDisk?.time)
        let readRate = MonitorRate.perSecond(
            current: counters?.read,
            previous: previousDisk?.read,
            elapsed: elapsed
        )
        let writeRate = MonitorRate.perSecond(
            current: counters?.write,
            previous: previousDisk?.write,
            elapsed: elapsed
        )
        if let counters {
            previousDisk = DiskCounters(read: counters.read, write: counters.write, time: now)
        }
        return MonitorSnapshot.Disk(
            used: used,
            free: free,
            total: total,
            readRate: readRate,
            writeRate: writeRate
        )
    }

    private func readDiskCounters() -> (read: UInt64, write: UInt64)? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var selected: (read: UInt64, write: UInt64)?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let property = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            ), let statistics = property.takeRetainedValue() as? [String: Any] else { continue }
            let read = number(statistics["Bytes (Read)"])
            let write = number(statistics["Bytes (Written)"])
            if selected == nil || read + write > selected!.read + selected!.write {
                selected = (read, write)
            }
        }
        return selected
    }

    // MARK: - Network

    private func readNetwork() -> MonitorSnapshot.Network? {
        let counters = readNetworkCounters()
        guard let counters else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        let sameInterface = previousNetwork?.interfaceName == counters.interfaceName
        let elapsed = elapsedSeconds(now: now, previous: sameInterface ? previousNetwork?.time : nil)
        let download = MonitorRate.perSecond(
            current: counters.received,
            previous: sameInterface ? previousNetwork?.received : nil,
            elapsed: elapsed
        )
        let upload = MonitorRate.perSecond(
            current: counters.sent,
            previous: sameInterface ? previousNetwork?.sent : nil,
            elapsed: elapsed
        )
        previousNetwork = NetworkCounters(
            interfaceName: counters.interfaceName,
            received: counters.received,
            sent: counters.sent,
            time: now
        )
        return MonitorSnapshot.Network(
            downloadRate: download,
            uploadRate: upload,
            interfaceName: counters.interfaceName
        )
    }

    private func readNetworkCounters() -> (interfaceName: String, received: UInt64, sent: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var counters: [String: (received: UInt64, sent: UInt64)] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = pointer {
            let entry = interface.pointee
            if let data = entry.ifa_data {
                let network = data.assumingMemoryBound(to: if_data.self).pointee
                let name = String(cString: entry.ifa_name)
                counters[name] = (UInt64(network.ifi_ibytes), UInt64(network.ifi_obytes))
            }
            pointer = entry.ifa_next
        }

        let primary = primaryInterfaceName()
        if let primary, let value = counters[primary] {
            return (primary, value.received, value.sent)
        }

        let excluded = ["lo", "utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "wg", "awdl", "llw", "bridge", "ap", "anpi"]
        let fallback = counters
            .filter { name, _ in !excluded.contains(where: name.hasPrefix) }
            .max { lhs, rhs in
                lhs.value.received + lhs.value.sent < rhs.value.received + rhs.value.sent
            }
        guard let fallback else { return nil }
        return (fallback.key, fallback.value.received, fallback.value.sent)
    }

    private func primaryInterfaceName() -> String? {
        guard let value = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) else {
            return nil
        }
        return (value as? [String: Any])?["PrimaryInterface"] as? String
    }

    // MARK: - Power

    private func readPower(includeTopApps: Bool) -> (
        power: MonitorSnapshot.Power,
        battery: MonitorSnapshot.Battery?
    ) {
        let now = Date()
        let iops = readIOPSBattery()
        let registry = readBatteryRegistryMetrics()
        let measuredWatts: Double?

        switch iops.supply {
        case .battery:
            measuredWatts = MonitorPowerFormat.watts(fromMilliwatts: registry.batteryPowerMilliwatts)
        case .charging, .adapter, .unknown:
            measuredWatts = MonitorPowerFormat.watts(fromMilliwatts: registry.systemPowerMilliwatts)
        }

        if previousPowerSupply != iops.supply, iops.supply == .battery {
            powerAverage.reset()
        }
        previousPowerSupply = iops.supply
        let averageWatts = powerAverage.append(measuredWatts)

        let calculatedRemaining = MonitorPowerFormat.estimatedRemainingSeconds(
            capacityWattHours: registry.capacityWattHours,
            percent: iops.percent,
            averageWatts: averageWatts
        )
        let remaining = iops.supply == .battery
            ? (calculatedRemaining ?? iops.timeToEmptySeconds)
            : nil
        let topApps = includeTopApps ? readEnergyUsage(at: now) : []
        let isAdapter = iops.supply == .charging || iops.supply == .adapter

        let power = MonitorSnapshot.Power(
            supply: iops.supply,
            hasBattery: iops.hasBattery,
            batteryPercent: iops.percent,
            temperatureCelsius: registry.temperatureCelsius,
            watts: measuredWatts,
            averageWatts: averageWatts,
            remainingSeconds: remaining,
            chargePowerWatts: isAdapter
                ? MonitorPowerFormat.watts(fromMilliwatts: registry.chargePowerMilliwatts)
                : nil,
            timeToFullSeconds: isAdapter ? iops.timeToFullSeconds : nil,
            batteryHealthPercent: registry.healthPercent,
            topApps: topApps,
            events: powerEventStore.observe(
                supply: iops.supply,
                batteryPercent: iops.percent,
                at: now
            ),
            batteryDataAvailable: iops.hasBattery
                && iops.percent != nil
                && registry.temperatureCelsius != nil,
            powerDataAvailable: measuredWatts != nil,
            energyDataAvailable: energyDataAvailable
        )

        let battery = iops.percent.map { percent in
            MonitorSnapshot.Battery(
                percent: percent,
                state: batteryState(for: iops),
                remaining: iops.supply == .battery ? remaining : nil
            )
        }

        return (power, battery)
    }

    private func readIOPSBattery() -> IOPSBatteryAggregate {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return IOPSBatteryAggregate(
                hasBattery: false,
                percent: nil,
                supply: .unknown,
                isCharged: false,
                timeToEmptySeconds: nil,
                timeToFullSeconds: nil
            )
        }

        let provider = IOPSGetProvidingPowerSourceType(blob)?
            .takeUnretainedValue() as String? ?? ""
        let sources = IOPSCopyPowerSourcesList(blob)?
            .takeRetainedValue() as? [CFTypeRef] ?? []

        var currentCapacities: [Double] = []
        var maximumCapacities: [Double] = []
        var hasBattery = false
        var isCharging = false
        var isCharged = true
        var adapterConnected = provider.caseInsensitiveCompare("AC Power") == .orderedSame
        var timeToEmptySeconds: TimeInterval?
        var timeToFullSeconds: TimeInterval?

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let type = description["Type"] as? String ?? ""
            guard type.caseInsensitiveCompare("InternalBattery") == .orderedSame else { continue }

            hasBattery = true
            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = description["Max Capacity"] as? Int ?? 0
            currentCapacities.append(Double(max(0, current)))
            maximumCapacities.append(Double(max(0, maximum)))
            isCharging = isCharging || (description["Is Charging"] as? Bool ?? false)
            isCharged = isCharged && (description["Is Charged"] as? Bool ?? false)

            let powerState = description["Power Source State"] as? String ?? ""
            adapterConnected = adapterConnected
                || powerState.caseInsensitiveCompare("AC Power") == .orderedSame

            if powerState.caseInsensitiveCompare("Battery Power") == .orderedSame,
               timeToEmptySeconds == nil,
               let minutes = description["Time to Empty"] as? Int,
               minutes > 0,
               minutes < 65_535 {
                timeToEmptySeconds = TimeInterval(minutes) * 60
            }
            if powerState.caseInsensitiveCompare("AC Power") == .orderedSame,
               timeToFullSeconds == nil,
               let minutes = description["Time to Full Charge"] as? Int,
               minutes > 0,
               minutes < 65_535 {
                timeToFullSeconds = TimeInterval(minutes) * 60
            }
        }

        let percent = MonitorPowerFormat.aggregateBatteryPercent(
            currentCapacities: currentCapacities,
            maximumCapacities: maximumCapacities
        )
        let batteryProvider = provider.caseInsensitiveCompare("Battery Power") == .orderedSame
        let supply = MonitorPowerFormat.batterySupply(
            adapterConnected: adapterConnected,
            isCharging: isCharging,
            isCharged: isCharged || (percent ?? 0) >= 99.5,
            hasBattery: hasBattery || batteryProvider
        )

        return IOPSBatteryAggregate(
            hasBattery: hasBattery,
            percent: percent,
            supply: supply,
            isCharged: hasBattery && isCharged,
            timeToEmptySeconds: timeToEmptySeconds,
            timeToFullSeconds: timeToFullSeconds
        )
    }

    private func batteryState(for battery: IOPSBatteryAggregate) -> MonitorSnapshot.BatteryState {
        switch battery.supply {
        case .battery: .discharging
        case .charging: .charging
        case .adapter: battery.isCharged ? .charged : .acPower
        case .unknown: .unknown
        }
    }

    private func readBatteryRegistryMetrics() -> BatteryRegistryMetrics {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return BatteryRegistryMetrics(
                temperatureCelsius: nil,
                capacityWattHours: nil,
                batteryPowerMilliwatts: nil,
                systemPowerMilliwatts: nil,
                chargePowerMilliwatts: nil,
                healthPercent: nil
            )
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return BatteryRegistryMetrics(
                temperatureCelsius: nil,
                capacityWattHours: nil,
                batteryPowerMilliwatts: nil,
                systemPowerMilliwatts: nil,
                chargePowerMilliwatts: nil,
                healthPercent: nil
            )
        }
        defer { IOObjectRelease(iterator) }

        var temperatureCelsius: Double?
        var capacityWattHours = 0.0
        var fullChargeCapacity = 0.0
        var designCapacity = 0.0
        var batteryPowerMilliwatts: Double?
        var systemPowerMilliwatts: Double?
        var chargePowerMilliwatts: Double?

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let voltage = registryNumber(service, key: "AppleRawBatteryVoltage")
                ?? registryNumber(service, key: "Voltage")
            if let data = registryDictionary(service, key: "BatteryData"),
               let voltage,
               voltage > 0 {
                let currentFullCharge = Double(number(data["FullChargeCapacity"]))
                let currentDesignCapacity = Double(number(data["DesignCapacity"]))
                fullChargeCapacity += currentFullCharge
                designCapacity += currentDesignCapacity
                if currentFullCharge > 0 {
                    capacityWattHours += currentFullCharge * voltage / 1_000_000
                }
            }

            if let temperature = readBatteryTemperature(service, depth: 0) {
                temperatureCelsius = max(temperatureCelsius ?? temperature, temperature)
            }

            if let measuredChargePower = readChargePowerMilliwatts(service, depth: 0) {
                chargePowerMilliwatts = max(
                    chargePowerMilliwatts ?? 0,
                    measuredChargePower
                )
            }

            if let telemetry = registryDictionary(service, key: "PowerTelemetryData") {
                let systemLoad = number(telemetry["SystemLoad"])
                let systemPowerIn = number(telemetry["SystemPowerIn"])
                let measuredSystem = systemLoad > 0 ? systemLoad : systemPowerIn
                if measuredSystem > 0 {
                    systemPowerMilliwatts = max(systemPowerMilliwatts ?? 0, Double(measuredSystem))
                }

                if let rawBatteryPower = signedNumber(telemetry["BatteryPower"]),
                   abs(rawBatteryPower) > 0 {
                    batteryPowerMilliwatts = max(
                        batteryPowerMilliwatts ?? 0,
                        abs(rawBatteryPower)
                    )
                }
            }

            if batteryPowerMilliwatts == nil,
               let amperage = registryNumber(service, key: "Amperage"),
               let voltage,
               amperage != 0,
               voltage > 0 {
                batteryPowerMilliwatts = abs(amperage * voltage / 1_000)
            }
        }

        let healthPercent = designCapacity > 0
            ? min(100, max(0, fullChargeCapacity / designCapacity * 100))
            : nil
        return BatteryRegistryMetrics(
            temperatureCelsius: temperatureCelsius,
            capacityWattHours: capacityWattHours > 0 ? capacityWattHours : nil,
            batteryPowerMilliwatts: batteryPowerMilliwatts,
            systemPowerMilliwatts: systemPowerMilliwatts,
            chargePowerMilliwatts: chargePowerMilliwatts,
            healthPercent: healthPercent
        )
    }

    private func readBatteryTemperature(_ service: io_object_t, depth: Int) -> Double? {
        guard depth <= 6 else { return nil }
        var maximum: Double?

        if let raw = registryNumber(service, key: "Temperature"),
           let value = MonitorPowerFormat.batteryTemperatureCelsius(raw: raw) {
            maximum = value
        }

        if let data = registryDictionary(service, key: "BatteryData") {
            for key in ["Temperature", "VirtualTemperature"] {
                if let raw = signedNumber(data[key]),
                   let value = MonitorPowerFormat.batteryTemperatureCelsius(raw: raw) {
                    maximum = max(maximum ?? value, value)
                }
            }
        }

        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else {
            return maximum
        }
        defer { IOObjectRelease(children) }

        var child = IOIteratorNext(children)
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
            if let value = readBatteryTemperature(child, depth: depth + 1) {
                maximum = max(maximum ?? value, value)
            }
        }
        return maximum
    }

    private func readChargePowerMilliwatts(_ service: io_object_t, depth: Int) -> Double? {
        guard depth <= 6 else { return nil }
        if let data = registryDictionary(service, key: "ChargerData"),
           let current = signedNumber(data["ChargingCurrent"]),
           let voltage = signedNumber(data["ChargingVoltage"]),
           current > 0,
           voltage > 0 {
            return current * voltage / 1_000
        }
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(children) }

        var child = IOIteratorNext(children)
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
            if let value = readChargePowerMilliwatts(child, depth: depth + 1) {
                return value
            }
        }
        return nil
    }

    // MARK: - Energy

    private func readEnergyUsage(at now: Date) -> [MonitorSnapshot.Power.TopApp] {
        let elapsed = now.timeIntervalSince(lastEnergyScanAt)
        guard lastEnergyScanAt == .distantPast
            || elapsed >= MonitorPowerFormat.estimateRefreshSeconds
        else { return lastEnergyApps }

        refreshApplicationIdentitiesIfNeeded(at: now)
        let samples = readProcessEnergySamples(at: now)
        lastEnergyApps = energyWindow.update(samples: samples, at: now)
        lastEnergyScanAt = now
        energyDataAvailable = !samples.isEmpty
        return lastEnergyApps
    }

    private func readProcessEnergySamples(at now: Date) -> [MonitorProcessEnergySample] {
        var pids = [pid_t](repeating: 0, count: 16_384)
        let count = proc_listallpids(
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard count > 0 else { return [] }

        var samples: [MonitorProcessEnergySample] = []
        samples.reserveCapacity(Int(count))

        for pid in pids.prefix(Int(count)) where pid > 1 {
            var usage = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard result == 0, usage.ri_energy_nj > 0 else { continue }

            let identity = resolveApplicationIdentity(pid: pid, at: now)
            samples.append(
                MonitorProcessEnergySample(
                    processIdentifier: pid,
                    applicationID: identity.id,
                    applicationName: identity.name,
                    bundlePath: identity.bundlePath,
                    cumulativeNanojoules: usage.ri_energy_nj
                )
            )
        }
        return samples
    }

    private func refreshApplicationIdentitiesIfNeeded(at now: Date) {
        guard now.timeIntervalSince(lastIdentityRefreshAt) >= 30 else { return }
        lastIdentityRefreshAt = now
        identityCache.removeAll(keepingCapacity: true)

        mainApplications = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let name = app.localizedName, !name.isEmpty else { return nil }
            let bundlePath = app.bundleURL?.path
            let id = bundlePath ?? app.bundleIdentifier ?? name
            return AppIdentity(id: id, name: name, bundlePath: bundlePath)
        }
    }

    private func resolveApplicationIdentity(pid: Int32, at now: Date) -> AppIdentity {
        if let cached = identityCache[pid] { return cached }

        let running = NSRunningApplication(processIdentifier: pid)
        let executable = executablePath(for: pid)
        let directBundle = executable.flatMap(containingApplicationPath)
            ?? running?.bundleURL?.path
        let runningName = running?.localizedName

        let identity: AppIdentity
        if let directBundle {
            identity = AppIdentity(
                id: directBundle,
                name: bundleName(for: directBundle) ?? runningName ?? URL(fileURLWithPath: directBundle).deletingPathExtension().lastPathComponent,
                bundlePath: directBundle
            )
        } else if let runningName,
                  let main = mainApplications.first(where: { runningName.hasPrefix($0.name) }) {
            identity = main
        } else if let executable {
            identity = AppIdentity(
                id: "process:\(executable)",
                name: runningName ?? URL(fileURLWithPath: executable).lastPathComponent,
                bundlePath: nil
            )
        } else {
            identity = AppIdentity(
                id: "pid:\(pid)",
                name: runningName ?? "PID \(pid)",
                bundlePath: nil
            )
        }

        identityCache[pid] = identity
        return identity
    }

    private func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func containingApplicationPath(from executable: String) -> String? {
        guard let range = executable.range(of: ".app/") else { return nil }
        let end = executable.index(range.lowerBound, offsetBy: 4)
        return String(executable[..<end])
    }

    private func bundleName(for path: String) -> String? {
        guard let bundle = Bundle(path: path) else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
    }

    // MARK: - System

    private func readThermal() -> MonitorSnapshot.ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    // MARK: - Helpers

    private func elapsedSeconds(now: UInt64, previous: UInt64?) -> TimeInterval {
        guard let previous, now >= previous else { return 0 }
        return Double(now - previous) / 1_000_000_000
    }

    private func readUInt64Sysctl(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private func registryString(_ service: io_object_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return property.takeRetainedValue() as? String
    }

    private func registryDictionary(_ service: io_object_t, key: String) -> [String: Any]? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return property.takeRetainedValue() as? [String: Any]
    }

    private func registryNumber(_ service: io_object_t, key: String) -> Double? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return signedNumber(property.takeRetainedValue())
    }

    private func number(_ value: Any?) -> UInt64 {
        switch value {
        case let value as NSNumber: value.uint64Value
        case let value as UInt64: value
        case let value as Int: UInt64(max(0, value))
        case let value as Int64: UInt64(max(0, value))
        default: 0
        }
    }

    private func signedNumber(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber: value.doubleValue
        case let value as Double: value
        case let value as Float: Double(value)
        case let value as Int: Double(value)
        case let value as Int64: Double(value)
        case let value as UInt64: Double(value)
        default: nil
        }
    }
}

/// 供电事件的本地持久化。
///
/// 只保存事件类型和时间。数据留在本机，不上传。
private final class MonitorPowerEventStore {
    private static let key = "monitor.power.events.v1"

    private let defaults: UserDefaults
    private var history: MonitorPowerEventHistory

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let events = try? JSONDecoder().decode([MonitorPowerEvent].self, from: data) {
            history = MonitorPowerEventHistory(events: events)
        } else {
            history = MonitorPowerEventHistory()
        }
    }

    func observe(
        supply: MonitorSnapshot.Power.Supply,
        batteryPercent: Double?,
        at date: Date
    ) -> [MonitorPowerEvent] {
        let previous = history.events
        let events = history.observe(
            supply: supply,
            batteryPercent: batteryPercent,
            at: date
        )
        if events != previous,
           let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Self.key)
        }
        return events
    }
}

/// 串行采样。视图离开时 `.task` 被取消，actor 不会继续持有采样任务。
actor MonitorSampler {
    private let reader: MacMonitorReader

    init(reader: MacMonitorReader = MacMonitorReader()) {
        self.reader = reader
    }

    func sample() -> MonitorSnapshot {
        reader.read()
    }

    func samplePowerOnly() -> MonitorSnapshot.Power {
        reader.readPowerOnly()
    }
}
