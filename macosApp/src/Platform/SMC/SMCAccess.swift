import Darwin
import Foundation
import IOKit

// Adapted from MacFanControl's SMCKit (MIT).
// Source: https://github.com/skydeadpeng/MacFanControl
// The app uses a smaller internal surface and keeps all SMC calls on one queue.

enum SMCAccessError: Error, CustomStringConvertible {
    case serviceNotFound
    case cannotOpen(Int)
    case callFailed(Int)
    case keyNotFound(String)
    case notPrivileged
    case badData(String)

    var description: String {
        switch self {
        case .serviceNotFound:
            return "AppleSMC service not found"
        case .cannotOpen(let code):
            return String(format: "Cannot open AppleSMC (0x%x)", code)
        case .callFailed(let code):
            if code == 0xE00002C2 {
                return "SMC write requires root privileges"
            }
            return String(format: "SMC call failed (0x%x)", code)
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .notPrivileged:
            return "SMC write requires root privileges"
        case .badData(let message):
            return "Invalid SMC data: \(message)"
        }
    }
}

struct SMCAccessKey: Hashable, CustomStringConvertible {
    let raw: UInt32

    init(raw: UInt32) {
        self.raw = raw
    }

    init?(_ text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count == 4 else { return nil }
        raw = (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }

    var description: String {
        let bytes: [UInt8] = [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "%08x", raw)
    }

    func replacingFirstCharacter(with digit: Int) -> SMCAccessKey {
        SMCAccessKey(raw: (raw & 0x00FF_FFFF) | (UInt32(UInt8(48 + digit)) << 24))
    }
}

struct SMCAccessKeyInfo {
    let dataSize: UInt32
    let dataType: UInt32

    var typeName: String {
        SMCAccessKey(raw: dataType).description
    }
}

final class SMCAccess {
    private var connection: io_connect_t = IO_OBJECT_NULL

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { throw SMCAccessError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var newConnection: io_connect_t = IO_OBJECT_NULL
        let result = IOServiceOpen(service, mach_task_self_, 0, &newConnection)
        guard result == kIOReturnSuccess else {
            throw SMCAccessError.cannotOpen(Int(result))
        }
        connection = newConnection
    }

    deinit {
        if connection != IO_OBJECT_NULL {
            IOServiceClose(connection)
        }
    }

    private enum Layout {
        static let total = 80
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let command = 42
        static let data32 = 44
        static let bytes = 48
    }

    private enum Command {
        static let readBytes: UInt8 = 5
        static let writeBytes: UInt8 = 6
        static let readIndex: UInt8 = 8
        static let readKeyInfo: UInt8 = 9
    }

    func keyInfo(_ key: SMCAccessKey) throws -> SMCAccessKeyInfo {
        let output = try call { input in
            input.store32(key.raw, at: Layout.key)
            input[Layout.command] = Command.readKeyInfo
        }
        return SMCAccessKeyInfo(
            dataSize: output.load32(Layout.dataSize),
            dataType: output.load32(Layout.dataType)
        )
    }

    func read(_ key: SMCAccessKey) throws -> Data {
        let info = try keyInfo(key)
        guard info.dataSize > 0, info.dataSize <= 32 else {
            throw SMCAccessError.badData("size=\(info.dataSize) for \(key)")
        }
        let output = try call { input in
            input.store32(key.raw, at: Layout.key)
            input.store32(info.dataSize, at: Layout.dataSize)
            input[Layout.command] = Command.readBytes
        }
        return Data(output[Layout.bytes ..< Layout.bytes + Int(info.dataSize)])
    }

    func write(_ key: SMCAccessKey, data: Data) throws {
        guard !data.isEmpty, data.count <= 32 else {
            throw SMCAccessError.badData("write size \(data.count)")
        }
        _ = try call { input in
            input.store32(key.raw, at: Layout.key)
            input.store32(UInt32(data.count), at: Layout.dataSize)
            input[Layout.command] = Command.writeBytes
            for (index, byte) in data.enumerated() {
                input[Layout.bytes + index] = byte
            }
        }
    }

    func keyCount() throws -> Int {
        guard let key = SMCAccessKey("#KEY"), let data = try? read(key), data.count == 4 else {
            throw SMCAccessError.badData("#KEY")
        }
        return Int(data[0]) << 24
            | Int(data[1]) << 16
            | Int(data[2]) << 8
            | Int(data[3])
    }

    func key(at index: Int) throws -> SMCAccessKey {
        let output = try call { input in
            input[Layout.command] = Command.readIndex
            input.store32(UInt32(index), at: Layout.data32)
        }
        return SMCAccessKey(raw: output.load32(Layout.key))
    }

    func allKeys() -> [SMCAccessKey] {
        guard let count = try? keyCount() else { return [] }
        var keys: [SMCAccessKey] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            if let key = try? key(at: index) {
                keys.append(key)
            }
        }
        return keys
    }

    func readValue(_ key: SMCAccessKey) throws -> SMCValue {
        let info = try keyInfo(key)
        return SMCValue.decode(try read(key), typeName: info.typeName)
    }

    func readDouble(_ key: SMCAccessKey) throws -> Double {
        guard let value = try readValue(key).doubleValue else {
            throw SMCAccessError.badData("Cannot decode \(key)")
        }
        return value
    }

    func readInt(_ key: SMCAccessKey) throws -> Int {
        guard let value = try readValue(key).intValue else {
            throw SMCAccessError.badData("Cannot decode \(key)")
        }
        return value
    }

    private func call(_ prepare: (inout [UInt8]) -> Void) throws -> [UInt8] {
        var input = [UInt8](repeating: 0, count: Layout.total)
        var output = [UInt8](repeating: 0, count: Layout.total)
        prepare(&input)
        var outputSize = Layout.total
        let result = input.withUnsafeMutableBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputBuffer.baseAddress,
                    Layout.total,
                    outputBuffer.baseAddress,
                    &outputSize
                )
            }
        }
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPrivileged {
                throw SMCAccessError.notPrivileged
            }
            throw SMCAccessError.callFailed(Int(result))
        }
        return output
    }
}

enum SMCValue {
    case double(Double, type: String)
    case int(Int, type: String)
    case raw(Data, type: String)

    var doubleValue: Double? {
        switch self {
        case .double(let value, _): value
        case .int(let value, _): Double(value)
        case .raw: nil
        }
    }

    var intValue: Int? {
        switch self {
        case .double(let value, _): Int(value.rounded())
        case .int(let value, _): value
        case .raw: nil
        }
    }

    static func decode(_ data: Data, typeName: String) -> SMCValue {
        let type = typeName.trimmingCharacters(in: .whitespaces)
        switch type {
        case "flt":
            guard data.count >= 4 else { return .raw(data, type: typeName) }
            let bits = UInt32(data[data.startIndex])
                | UInt32(data[data.startIndex + 1]) << 8
                | UInt32(data[data.startIndex + 2]) << 16
                | UInt32(data[data.startIndex + 3]) << 24
            return .double(Double(Float(bitPattern: bits)), type: typeName)
        case "fpe2":
            let bytes = [UInt8](data.prefix(4))
            if bytes.count == 2 {
                let raw = UInt32(bytes[0]) << 8 | UInt32(bytes[1])
                return .double(Double(raw) / 4, type: typeName)
            }
            if bytes.count == 4 {
                let raw = UInt32(bytes[0]) << 24
                    | UInt32(bytes[1]) << 16
                    | UInt32(bytes[2]) << 8
                    | UInt32(bytes[3])
                return .double(Double(raw) / 16_384, type: typeName)
            }
            return .raw(data, type: typeName)
        case "sp78":
            guard data.count >= 2 else { return .raw(data, type: typeName) }
            let integer = Int(Int8(bitPattern: data[data.startIndex]))
            let fraction = Double(data[data.startIndex + 1]) / 256
            return .double(Double(integer) + fraction, type: typeName)
        case "fp5f":
            guard data.count >= 2 else { return .raw(data, type: typeName) }
            let raw = Int(Int16(
                bitPattern: UInt16(data[data.startIndex]) << 8 | UInt16(data[data.startIndex + 1])
            ))
            return .double(Double(raw) / 320, type: typeName)
        case "sp5a":
            guard data.count >= 2 else { return .raw(data, type: typeName) }
            let raw = Int(UInt16(data[data.startIndex]) << 8 | UInt16(data[data.startIndex + 1]))
            return .double(Double(raw >> 9) + Double(raw & 0x1FF) / 512, type: typeName)
        case "ioft":
            guard data.count >= 4 else { return .raw(data, type: typeName) }
            var value: UInt64 = 0
            for (index, byte) in data.prefix(8).enumerated() {
                value |= UInt64(byte) << (8 * index)
            }
            return .double(Double(value) / 65_536, type: typeName)
        case "ui8", "flag", "ui8 ":
            guard let byte = data.first else { return .raw(data, type: typeName) }
            return .int(Int(byte), type: typeName)
        case "ui16":
            guard data.count >= 2 else { return .raw(data, type: typeName) }
            let raw = UInt16(data[data.startIndex]) << 8 | UInt16(data[data.startIndex + 1])
            return .int(Int(raw), type: typeName)
        case "ui32":
            guard data.count >= 4 else { return .raw(data, type: typeName) }
            let raw = UInt32(data[data.startIndex]) << 24
                | UInt32(data[data.startIndex + 1]) << 16
                | UInt32(data[data.startIndex + 2]) << 8
                | UInt32(data[data.startIndex + 3])
            return .int(Int(raw), type: typeName)
        default:
            return .raw(data, type: typeName)
        }
    }

    static func floatBytes(_ value: Double) -> Data {
        let bits = Float(value).bitPattern
        return Data([
            UInt8(truncatingIfNeeded: bits),
            UInt8(truncatingIfNeeded: bits >> 8),
            UInt8(truncatingIfNeeded: bits >> 16),
            UInt8(truncatingIfNeeded: bits >> 24),
        ])
    }

    static func fpe2Bytes(_ value: Double) -> Data {
        let raw = UInt16(clamping: Int(value * 4))
        return Data([UInt8(raw >> 8), UInt8(raw & 0xFF)])
    }

    static func uint8Bytes(_ value: Int) -> Data {
        Data([UInt8(clamping: value)])
    }
}

private extension Array where Element == UInt8 {
    mutating func store32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    func load32(_ offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
