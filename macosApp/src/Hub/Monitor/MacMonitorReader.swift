import Darwin
import Foundation
@preconcurrency import IOKit
import SystemConfiguration
import kmpDomain

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

    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUInfoCount: mach_msg_type_number_t = 0
    private var previousCPULoad = host_cpu_load_info()
    private var hasPreviousCPULoad = false
    private var previousDisk: DiskCounters?
    private var previousNetwork: NetworkCounters?

    func read() -> MonitorSnapshot {
        let memory = readMemory()
        return MonitorSnapshot(
            cpu: readCPU(),
            gpu: readGPU(),
            memory: memory,
            disk: readDisk(),
            network: readNetwork(),
            battery: readBattery(),
            thermal: readThermal(),
            sampledAt: Date()
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

    // MARK: - Battery

    private func readBattery() -> MonitorSnapshot.Battery? {
        guard let battery = MacPowerSource.readBattery() else { return nil }
        return MonitorSnapshot.Battery(
            percent: Double(battery.percent),
            state: batteryState(battery.state),
            remaining: battery.remainingSeconds.map { TimeInterval($0.int64Value) }
        )
    }

    private func batteryState(_ state: PowerState) -> MonitorSnapshot.BatteryState {
        switch state {
        case .discharging: .discharging
        case .charging: .charging
        case .charged: .charged
        case .acPower: .acPower
        default: .unknown
        }
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

    private func number(_ value: Any?) -> UInt64 {
        switch value {
        case let value as NSNumber: value.uint64Value
        case let value as UInt64: value
        case let value as Int: UInt64(max(0, value))
        case let value as Int64: UInt64(max(0, value))
        default: 0
        }
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
}
