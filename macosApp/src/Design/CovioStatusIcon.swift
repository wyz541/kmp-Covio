import AppKit

/// Covio 的菜单栏拟物图标。
///
/// 图形由 `scripts/generate-status-icon.swift` 预渲染成 1× 与 2× 位图。
/// 运行时只缓存并复用 `NSImage`，不计算渐变、阴影或路径。
@MainActor
enum CovioStatusIcon {
    /// 设计合同 `states.menuBarAndNotchHub.statusItemStates[0].assetName` 的值。
    static let assetName = "CovioStatusIcon"

    /// 菜单栏图标的标准逻辑尺寸。
    static let pointSize: CGFloat = 18

    private static let cachedImage: NSImage = loadImage()

    static func makeImage() -> NSImage {
        cachedImage
    }

    private static func loadImage() -> NSImage {
        let image = NSImage(named: assetName) ?? fallbackImage
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = false
        return image
    }

    /// 资源缺失时保留一个可见入口，避免状态项变成空白。
    private static var fallbackImage: NSImage {
        let image = NSImage(
            systemSymbolName: "menubar.rectangle",
            accessibilityDescription: nil
        ) ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.isTemplate = true
        return image
    }
}
