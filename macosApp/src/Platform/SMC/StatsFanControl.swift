import Foundation

// Adapted from exelban/stats `SMC/smc.swift` at
// 7d3f70dcd6a07177d0a529a1b907021eef740158.
// Copyright (c) 2019 Serhiy Mytrovtsiy. MIT License.
// See THIRD_PARTY_NOTICES.md.

/// Stats fan modes. `auto3` is another system-controlled mode.
enum StatsFanMode: Int, Codable, Sendable {
    case automatic = 0
    case forced = 1
    case auto3 = 3

    var isAutomatic: Bool {
        self == .automatic || self == .auto3
    }
}

enum StatsFanModeResolver {
    static func modeKey(
        for fanIndex: Int,
        availableKeys: Set<String>,
        appleSilicon: Bool
    ) -> String? {
        guard fanIndex >= 0 else { return nil }
        let upper = "F\(fanIndex)Md"
        if appleSilicon, availableKeys.contains("F0md") {
            let lower = "F\(fanIndex)md"
            if availableKeys.contains(lower) { return lower }
        }
        return availableKeys.contains(upper) ? upper : nil
    }

    static func normalizedMode(
        rawValue: Int,
        appleSilicon: Bool,
        fanIndex: Int,
        fansModeBits: Int?
    ) -> StatsFanMode? {
        if appleSilicon {
            guard let mode = StatsFanMode(rawValue: rawValue) else { return nil }
            return mode.isAutomatic ? .automatic : .forced
        }
        guard let fansModeBits else { return nil }
        let forced = (fansModeBits & (1 << fanIndex)) != 0
        return forced ? .forced : .automatic
    }
}

protocol StatsFanSMC: AnyObject {
    func keyInfo(_ key: SMCAccessKey) throws -> SMCAccessKeyInfo
    func read(_ key: SMCAccessKey) throws -> Data
    func write(_ key: SMCAccessKey, data: Data) throws
}

extension SMCAccess: StatsFanSMC {}

/// Fan-control subset copied from exelban/stats.
///
/// Covio keeps its helper, lease, curve and write-drift protection around this
/// class. The SMC mode, target and reset semantics come from Stats.
final class StatsFanControl {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private static let maximumFanID = 9
    private let smc: any StatsFanSMC
    private let availableKeys: Set<String>
    private let appleSilicon: Bool
    private var heldFans: Set<Int> = []

    init(
        access: any StatsFanSMC,
        allKeys: [SMCAccessKey],
        appleSilicon: Bool = StatsFanControl.isAppleSilicon
    ) {
        smc = access
        availableKeys = Set(allKeys.map(\.description))
        self.appleSilicon = appleSilicon
    }

    var holdingCount: Int { heldFans.count }

    func isHolding(_ index: Int) -> Bool { heldFans.contains(index) }

    func hold(_ index: Int) throws {
        guard !heldFans.contains(index) else { return }
        try setMode(index, mode: .forced)
        heldFans.insert(index)
    }

    /// A held fan can be returned to system control by macOS. Reapply the
    /// Stats forced mode before the next target write.
    func ensureHeld(_ index: Int) throws {
        guard heldFans.contains(index) else {
            try hold(index)
            return
        }
        if currentMode(for: index) != .forced {
            try setMode(index, mode: .forced)
        }
    }

    func writeTarget(_ index: Int, rpm: Double) throws {
        guard rpm.isFinite else {
            throw SMCAccessError.badData("Invalid fan target \(rpm)")
        }
        try setFanSpeed(index, speed: Int(max(0, rpm).rounded()))
    }

    func release(_ index: Int) throws {
        try setMode(index, mode: .automatic)
        heldFans.remove(index)
        if heldFans.isEmpty {
            try resetFanControl()
        }
    }

    func releaseAll() throws {
        var firstError: Error?
        var remainingFans: Set<Int> = []
        for index in heldFans.sorted() {
            do {
                try setMode(index, mode: .automatic)
            } catch {
                remainingFans.insert(index)
                if firstError == nil { firstError = error }
            }
        }
        heldFans = remainingFans
        if remainingFans.isEmpty {
            do {
                try resetFanControl()
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    func currentMode(for fanIndex: Int) -> StatsFanMode? {
        do {
            if appleSilicon {
                guard let keyName = modeKey(for: fanIndex),
                      let raw = try? readInt(named: keyName)
                else { return nil }
                return StatsFanModeResolver.normalizedMode(
                    rawValue: raw,
                    appleSilicon: true,
                    fanIndex: fanIndex,
                    fansModeBits: nil
                )
            }
            let bits = try readInt(named: "FS! ")
            return StatsFanModeResolver.normalizedMode(
                rawValue: 0,
                appleSilicon: false,
                fanIndex: fanIndex,
                fansModeBits: bits
            )
        } catch {
            return nil
        }
    }

    func setMode(_ fanIndex: Int, mode: StatsFanMode) throws {
        guard (0...Self.maximumFanID).contains(fanIndex) else {
            throw SMCAccessError.badData("Invalid fan id \(fanIndex)")
        }

        if appleSilicon {
            if mode == .forced {
                try unlockFanControl(fanID: fanIndex)
                return
            }

            if let keyName = modeKey(for: fanIndex) {
                var modeData = try read(named: keyName)
                if modeData.first != 0 {
                    modeData[modeData.startIndex] = 0
                    try writeWithRetry(named: keyName, data: modeData)
                }
            }

            let targetName = "F\(fanIndex)Tg"
            var targetData = try read(named: targetName)
            for offset in 0..<min(4, targetData.count) {
                targetData[targetData.startIndex + offset] = 0
            }
            try writeWithRetry(named: targetName, data: targetData)
            return
        }

        let modeKeyName = "F\(fanIndex)Md"
        if availableKeys.contains(modeKeyName) {
            var modeData = try read(named: modeKeyName)
            if !modeData.isEmpty {
                modeData[modeData.startIndex] = UInt8(clamping: mode.rawValue)
                try smc.write(try key(named: modeKeyName), data: modeData)
            }
        }

        let bitsKeyName = "FS! "
        var bitsData = try read(named: bitsKeyName)
        guard bitsData.count >= 2 else {
            throw SMCAccessError.badData("FS! data is too short")
        }
        let fansMode = UInt16(bitsData[bitsData.startIndex]) << 8
            | UInt16(bitsData[bitsData.startIndex + 1])
        let fanBit = UInt16(1) << UInt16(fanIndex)
        let newMode = mode.isAutomatic ? fansMode & ~fanBit : fansMode | fanBit
        if fansMode != newMode {
            bitsData[bitsData.startIndex] = UInt8(newMode >> 8)
            bitsData[bitsData.startIndex + 1] = UInt8(newMode & 0xFF)
            try smc.write(try key(named: bitsKeyName), data: bitsData)
        }
    }

    func setFanSpeed(_ fanIndex: Int, speed: Int) throws {
        guard (0...Self.maximumFanID).contains(fanIndex), speed >= 0 else {
            throw SMCAccessError.badData("Invalid fan id or speed")
        }

        var targetSpeed = speed
        if let maximum = try? readDouble(named: "F\(fanIndex)Mx"),
           targetSpeed > Int(maximum) {
            targetSpeed = Int(maximum)
        }

        if appleSilicon, currentMode(for: fanIndex) != .forced {
            try unlockFanControl(fanID: fanIndex)
        }

        let targetName = "F\(fanIndex)Tg"
        let targetKey = try key(named: targetName)
        let info = try smc.keyInfo(targetKey)
        let type = info.typeName.trimmingCharacters(in: .whitespaces)
        let encoded: Data
        switch type {
        case "flt":
            encoded = SMCValue.floatBytes(Double(targetSpeed))
        case "fpe2":
            guard targetSpeed <= 16_383 else {
                throw SMCAccessError.badData("Fan speed exceeds fpe2 range")
            }
            encoded = SMCValue.fpe2Bytes(Double(targetSpeed))
        default:
            throw SMCAccessError.badData("Unsupported fan target type \(info.typeName)")
        }

        let current = try smc.read(targetKey)
        var output = current
        for offset in 0..<min(encoded.count, output.count) {
            output[output.startIndex + offset] = encoded[encoded.startIndex + offset]
        }
        if type == "fpe2" {
            for offset in encoded.count..<min(4, output.count) {
                output[output.startIndex + offset] = 0
            }
        }
        if appleSilicon {
            try writeWithRetry(named: targetName, data: output)
        } else {
            try smc.write(targetKey, data: output)
        }
    }

    func resetFanControl() throws {
        if availableKeys.contains("Ftst"), var value = try? read(named: "Ftst") {
            guard !value.isEmpty else { return }
            if value[value.startIndex] == 0 { return }
            value[value.startIndex] = 0
            try writeWithRetry(named: "Ftst", data: value)
            return
        }

        let count = try readInt(named: "FNum")
        guard count > 0, count <= Self.maximumFanID + 1 else {
            throw SMCAccessError.badData("Invalid fan count \(count)")
        }
        var firstError: Error?
        for index in 0..<count {
            guard let modeName = modeKey(for: index) else { continue }
            do {
                var modeData = try read(named: modeName)
                guard !modeData.isEmpty, modeData[modeData.startIndex] != 0 else { continue }
                modeData[modeData.startIndex] = 0
                try writeWithRetry(named: modeName, data: modeData)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func modeKey(for fanIndex: Int) -> String? {
        StatsFanModeResolver.modeKey(
            for: fanIndex,
            availableKeys: availableKeys,
            appleSilicon: appleSilicon
        )
    }

    private func unlockFanControl(fanID: Int) throws {
        guard let modeName = modeKey(for: fanID) else {
            throw SMCAccessError.keyNotFound("F\(fanID)Md")
        }
        var modeData = try read(named: modeName)
        guard !modeData.isEmpty else {
            throw SMCAccessError.badData("Empty fan mode")
        }
        modeData[modeData.startIndex] = 1
        do {
            try smc.write(try key(named: modeName), data: modeData)
            return
        } catch {
            // Direct mode write failed. Try the Stats Ftst unlock path.
        }

        guard availableKeys.contains("Ftst") else {
            throw SMCAccessError.keyNotFound("Ftst")
        }
        var ftst = try read(named: "Ftst")
        guard !ftst.isEmpty else {
            throw SMCAccessError.badData("Empty Ftst")
        }
        if ftst[ftst.startIndex] == 1 {
            try retryModeWrite(fanID: fanID, maxAttempts: 20)
            return
        }

        ftst[ftst.startIndex] = 1
        try writeWithRetry(named: "Ftst", data: ftst, maxAttempts: 100)
        Thread.sleep(forTimeInterval: 3)
        try retryModeWrite(fanID: fanID, maxAttempts: 300)
    }

    private func retryModeWrite(fanID: Int, maxAttempts: Int) throws {
        guard let modeName = modeKey(for: fanID) else {
            throw SMCAccessError.keyNotFound("F\(fanID)Md")
        }
        var modeData = try read(named: modeName)
        guard !modeData.isEmpty else {
            throw SMCAccessError.badData("Empty fan mode")
        }
        modeData[modeData.startIndex] = 1
        try writeWithRetry(
            named: modeName,
            data: modeData,
            maxAttempts: maxAttempts,
            delay: 0.1
        )
    }

    private func writeWithRetry(
        named name: String,
        data: Data,
        maxAttempts: Int = 10,
        delay: TimeInterval = 0.05
    ) throws {
        let target = try key(named: name)
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                try smc.write(target, data: data)
                return
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }
        throw lastError ?? SMCAccessError.badData("SMC write failed for \(name)")
    }

    private func key(named name: String) throws -> SMCAccessKey {
        guard let key = SMCAccessKey(name) else {
            throw SMCAccessError.badData("Invalid SMC key \(name)")
        }
        return key
    }

    private func read(named name: String) throws -> Data {
        try smc.read(try key(named: name))
    }

    private func readInt(named name: String) throws -> Int {
        let target = try key(named: name)
        let info = try smc.keyInfo(target)
        guard let value = SMCValue.decode(
            try smc.read(target),
            typeName: info.typeName
        ).intValue else {
            throw SMCAccessError.badData("Cannot decode \(name)")
        }
        return value
    }

    private func readDouble(named name: String) throws -> Double {
        let target = try key(named: name)
        let info = try smc.keyInfo(target)
        guard let value = SMCValue.decode(
            try smc.read(target),
            typeName: info.typeName
        ).doubleValue else {
            throw SMCAccessError.badData("Cannot decode \(name)")
        }
        return value
    }
}
