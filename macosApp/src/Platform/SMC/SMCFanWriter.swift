import Foundation

/// Adapted from MacFanControl's `FanWriter` (MIT).
/// Apple Silicon uses `F%dMd` plus `F%dTg`. Intel uses `F%dMn`.
final class SMCFanWriter {
    private let smc: SMCAccess
    private let keys: Set<String>
    private var modeKeyCache: [Int: String] = [:]
    private var ftstApplied = false
    private var heldFans: Set<Int> = []
    private var originalMinimum: [Int: Data] = [:]
    private var originalMode: [Int: Int] = [:]

    init(access: SMCAccess, allKeys: [SMCAccessKey]? = nil) {
        smc = access
        keys = Set((allKeys ?? access.allKeys()).map(\.description))
    }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    var holdingCount: Int { heldFans.count }

    func isHolding(_ index: Int) -> Bool {
        heldFans.contains(index)
    }

    func hold(_ index: Int) throws {
        guard !heldFans.contains(index) else { return }
        if Self.isAppleSilicon {
            originalMode[index] = originalMode[index] ?? readMode(index)
            do {
                try writeMode(index, value: 1)
            } catch {
                if let key = SMCAccessKey("Ftst") {
                    try? smc.write(key, data: SMCValue.uint8Bytes(1))
                    ftstApplied = true
                }
                try retryUntilDone(timeout: 10) { [self] in
                    try writeMode(index, value: 1)
                    return readMode(index) == 1
                }
            }
        } else if originalMinimum[index] == nil,
                  let key = SMCAccessKey("F\(index)Mn") {
            originalMinimum[index] = try? smc.read(key)
        }
        heldFans.insert(index)
    }

    func writeTarget(_ index: Int, rpm: Double) throws {
        if Self.isAppleSilicon {
            guard let key = SMCAccessKey("F\(index)Tg") else {
                throw SMCAccessError.keyNotFound("F\(index)Tg")
            }
            try smc.write(key, data: SMCValue.floatBytes(rpm))
        } else {
            guard let key = SMCAccessKey("F\(index)Mn") else {
                throw SMCAccessError.keyNotFound("F\(index)Mn")
            }
            try smc.write(key, data: SMCValue.fpe2Bytes(rpm))
        }
    }

    func release(_ index: Int) {
        heldFans.remove(index)
        if Self.isAppleSilicon {
            if let modeKey = modeKey(for: index), let key = SMCAccessKey(modeKey) {
                let original = originalMode[index] ?? 0
                try? smc.write(key, data: SMCValue.uint8Bytes(original))
            }
            if ftstApplied && heldFans.isEmpty, let key = SMCAccessKey("Ftst") {
                try? smc.write(key, data: SMCValue.uint8Bytes(0))
                ftstApplied = false
            }
        } else if let original = originalMinimum[index],
                  let key = SMCAccessKey("F\(index)Mn") {
            try? smc.write(key, data: original)
        }
    }

    func releaseAll() {
        let indices = heldFans
        for index in indices {
            release(index)
        }
        heldFans.removeAll()
        originalMode.removeAll()
        originalMinimum.removeAll()
    }

    private func readMode(_ index: Int) -> Int {
        guard let modeKey = modeKey(for: index), let key = SMCAccessKey(modeKey) else {
            return -1
        }
        return (try? smc.readInt(key)) ?? -1
    }

    private func modeKey(for index: Int) -> String? {
        if let cached = modeKeyCache[index] { return cached }
        let upper = "F\(index)Md"
        let lower = "F\(index)md"
        let key = keys.contains(upper) ? upper : (keys.contains(lower) ? lower : nil)
        if let key { modeKeyCache[index] = key }
        return key
    }

    private func writeMode(_ index: Int, value: Int) throws {
        guard let modeKey = modeKey(for: index), let key = SMCAccessKey(modeKey) else {
            throw SMCAccessError.keyNotFound("F\(index)Md")
        }
        try smc.write(key, data: SMCValue.uint8Bytes(value))
    }

    private func retryUntilDone(
        timeout: TimeInterval,
        interval: TimeInterval = 0.1,
        _ body: () throws -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                if try body() { return }
            } catch {
                lastError = error
            }
            Thread.sleep(forTimeInterval: interval)
        }
        if let lastError {
            throw lastError
        }
        throw SMCAccessError.badData("Fan mode change timed out")
    }
}
