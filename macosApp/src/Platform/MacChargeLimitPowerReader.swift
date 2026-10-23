import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.ps
import notify

/// 生产环境的充电策略观察器。
///
/// 只读 IOPS、AppleSmartBattery 和系统热状态。所有动作仍由 MCL 后端执行。
final class MacChargeLimitPowerReader: ChargeLimitPowerReadingSource, @unchecked Sendable {
    private let powerUI: PowerUIChargeReading
    private let calibrationState = DarwinNotificationBool(
        name: "com.apple.system.powersources.chargingtofulloverride"
    )

    init(powerUI: PowerUIChargeReading = SystemPowerUIChargeClient()) {
        self.powerUI = powerUI
    }

    func read() -> ChargeLimitPowerReading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                (description["Type"] as? String)?.caseInsensitiveCompare("InternalBattery") == .orderedSame
            else {
                continue
            }

            let sourceState = description["Power Source State"] as? String ?? ""
            let adapterConnected = batteryRegistryBool("ExternalConnected")
                ?? (sourceState.caseInsensitiveCompare("Battery Power") != .orderedSame)
            let isCharged = description["Is Charged"] as? Bool ?? false
            let percent = rawStateOfCharge() ?? iopsPercent(description)
            let thermalState = ProcessInfo.processInfo.thermalState
            let amperage = batteryRegistryInt("Amperage") ?? 0
            return ChargeLimitPowerReading(
                adapterConnected: adapterConnected,
                batteryPresent: true,
                currentPercent: percent,
                isCharged: isCharged,
                calibrationActive: calibrationState.value,
                systemProtectionActive: thermalState == .serious || thermalState == .critical,
                bypassEngaged: powerUI.bypassEngaged(),
                activelyDischarging: amperage <= -100
            )
        }

        return ChargeLimitPowerReading(
            adapterConnected: batteryRegistryBool("ExternalConnected") ?? false,
            batteryPresent: false,
            currentPercent: nil,
            isCharged: false,
            calibrationActive: calibrationState.value,
            systemProtectionActive: ProcessInfo.processInfo.thermalState == .serious ||
                ProcessInfo.processInfo.thermalState == .critical,
            bypassEngaged: false
        )
    }

    private func iopsPercent(_ description: [String: Any]) -> Int? {
        guard let current = description["Current Capacity"] as? Int,
              let maximum = description["Max Capacity"] as? Int,
              maximum > 0
        else {
            return description["Current Capacity"] as? Int
        }
        return Int((Double(current) * 100 / Double(maximum)).rounded())
    }

    private func rawStateOfCharge() -> Int? {
        guard let current = batteryRegistryInt("AppleRawCurrentCapacity"),
              let maximum = batteryRegistryInt("AppleRawMaxCapacity"),
              maximum > 0
        else {
            return nil
        }
        return Int((Double(current) * 100 / Double(maximum)).rounded())
    }

    private func batteryRegistryInt(_ key: String) -> Int? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }

    private func batteryRegistryBool(_ key: String) -> Bool? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        return (value as? NSNumber)?.boolValue
    }
}

private final class DarwinNotificationBool: @unchecked Sendable {
    private var token: Int32 = 0

    init(name: String) {
        notify_register_check(name, &token)
    }

    deinit {
        if token != 0 {
            notify_cancel(token)
        }
    }

    var value: Bool {
        guard token != 0 else { return false }
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { return false }
        return state != 0
    }
}
