import CoreGraphics
import Foundation

/// 读取内建屏幕的公开状态、亮度和分辨率。
///
/// 亮度沿用已经验证过的 DisplayServices 路径。
/// 当前没有可靠的内建屏耗瓦数来源，因此 `powerWatts` 保持 `nil`。
final class MacDisplayReader {
    private let brightnessBackend: ClosedLidBrightnessBackend

    init(brightnessBackend: ClosedLidBrightnessBackend = DisplayServicesBrightnessBackend()) {
        self.brightnessBackend = brightnessBackend
    }

    func read() -> MonitorSnapshot.Display {
        guard let displayID = brightnessBackend.builtInDisplayID() else {
            return MonitorSnapshot.Display(
                state: .offline,
                brightnessPercent: nil,
                powerWatts: nil,
                externalDisplayCount: ExternalDisplayReader.count(),
                pixelWidth: nil,
                pixelHeight: nil,
                refreshRate: nil
            )
        }

        let state = Self.state(
            isOnline: CGDisplayIsOnline(displayID) != 0,
            isAsleep: CGDisplayIsAsleep(displayID) != 0,
            isActive: CGDisplayIsActive(displayID) != 0
        )
        let brightness = try? brightnessBackend.readBrightness(displayID: displayID)
        let mode = CGDisplayCopyDisplayMode(displayID)
        return MonitorSnapshot.Display(
            state: state,
            brightnessPercent: Self.brightnessPercent(from: brightness),
            powerWatts: nil,
            externalDisplayCount: ExternalDisplayReader.count(),
            pixelWidth: mode.map { Int($0.pixelWidth) },
            pixelHeight: mode.map { Int($0.pixelHeight) },
            refreshRate: mode.map(\.refreshRate)
        )
    }

    static func state(
        isOnline: Bool,
        isAsleep: Bool,
        isActive: Bool
    ) -> MonitorSnapshot.Display.State {
        if !isOnline { return .offline }
        if isAsleep { return .asleep }
        return isActive ? .active : .unknown
    }

    static func brightnessPercent(from brightness: Float?) -> Double? {
        guard let brightness, brightness.isFinite else { return nil }
        return min(max(Double(brightness), 0), 1) * 100
    }
}
