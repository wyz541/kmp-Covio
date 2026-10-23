import Foundation
import IOKit

/// 辅助放电端口。只允许写 SMC `CHIE`，不开放其他 SMC 键。
protocol ChargeLimitActiveDischargePort: Sendable {
    func capability() -> Bool
    func isEngaged() -> Bool?
    func engage() -> Bool
    func release() -> Bool
}

/// macOS 27 真机验证过的辅助放电路径。
///
/// `CHIE=0x08` 让适配器旁路，Mac 使用电池。
/// `CHIE=0x00` 恢复系统供电路径。
final class SMCChargeLimitActiveDischarge: ChargeLimitActiveDischargePort, @unchecked Sendable {
    private enum Command {
        static let readBytes: UInt8 = 5
        static let writeBytes: UInt8 = 6
        static let readKeyInfo: UInt8 = 9
        static let selector: UInt32 = 2
    }

    private struct KeyData {
        struct Vers {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }

        struct PLimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private static let key = "CHIE"
    private static let discharge = UInt8(0x08)
    private static let normal = UInt8(0x00)
    private static let writableMask = UInt8(0x40)
    private let lock = NSLock()

    func capability() -> Bool {
        lock.withLock {
            guard let connection = Self.open(),
                  let info = Self.info(connection, key: Self.key)
            else { return false }
            defer { IOServiceClose(connection) }
            return info.keyInfo.dataSize == 1 && info.keyInfo.dataAttributes & Self.writableMask != 0
        }
    }

    func isEngaged() -> Bool? {
        lock.withLock {
            guard let connection = Self.open() else { return nil }
            defer { IOServiceClose(connection) }
            return Self.read(connection, key: Self.key) == [Self.discharge]
        }
    }

    func engage() -> Bool {
        set(Self.discharge)
    }

    func release() -> Bool {
        set(Self.normal)
    }

    private func set(_ value: UInt8) -> Bool {
        lock.withLock {
            guard let connection = Self.open() else { return false }
            defer { IOServiceClose(connection) }
            guard Self.write(connection, key: Self.key, value: value) else { return false }
            return Self.read(connection, key: Self.key) == [value]
        }
    }

    private static func fourCC(_ value: String) -> UInt32 {
        value.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func open() -> io_connect_t? {
        for name in ["AppleSMCKeysEndpoint", "AppleSMC"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            guard service != MACH_PORT_NULL else { continue }
            defer { IOObjectRelease(service) }
            var connection: io_connect_t = 0
            if IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess {
                return connection
            }
        }
        return nil
    }

    private static func call(_ connection: io_connect_t, input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.size
        let result = IOConnectCallStructMethod(
            connection,
            Command.selector,
            &input,
            MemoryLayout<KeyData>.size,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }
        return output
    }

    private static func info(_ connection: io_connect_t, key: String) -> KeyData? {
        var input = KeyData()
        input.key = fourCC(key)
        input.data8 = Command.readKeyInfo
        guard let output = call(connection, input: &input), output.result == 0 else { return nil }
        return output
    }

    private static func read(_ connection: io_connect_t, key: String) -> [UInt8]? {
        guard let metadata = info(connection, key: key) else { return nil }
        var input = KeyData()
        input.key = fourCC(key)
        input.keyInfo.dataSize = metadata.keyInfo.dataSize
        input.keyInfo.dataType = metadata.keyInfo.dataType
        input.data8 = Command.readBytes
        guard let output = call(connection, input: &input), output.result == 0 else { return nil }
        return withUnsafeBytes(of: output.bytes) {
            Array($0.prefix(Int(metadata.keyInfo.dataSize)))
        }
    }

    private static func write(_ connection: io_connect_t, key: String, value: UInt8) -> Bool {
        guard let metadata = info(connection, key: key),
              metadata.keyInfo.dataSize == 1
        else { return false }
        var input = KeyData()
        input.key = fourCC(key)
        input.keyInfo.dataSize = metadata.keyInfo.dataSize
        input.keyInfo.dataType = metadata.keyInfo.dataType
        input.data8 = Command.writeBytes
        input.bytes.0 = value
        guard let output = call(connection, input: &input) else { return false }
        return output.result == 0
    }
}
