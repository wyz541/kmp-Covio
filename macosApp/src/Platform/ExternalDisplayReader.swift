import CoreGraphics

/// 读取当前在线外接屏数量。app 与 root helper 共用。
enum ExternalDisplayReader {
    static func count() -> Int? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        if count == 0 {
            return 0
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).reduce(into: 0) { total, display in
            if CGDisplayIsBuiltin(display) == 0 {
                total += 1
            }
        }
    }
}
