import AppKit

/// Covio 的菜单栏模板图标。
///
/// 造型沿用应用图标的“岛条 + 三张吊卡”。图标只有不透明前景，并交给 AppKit
/// 按菜单栏外观着色，所以浅色和深色菜单栏共用同一份图标。
enum CovioStatusIcon {
    /// 设计合同 `states.menuBarAndNotchHub.statusItemStates[0].renderer` 的值。
    static let rendererName = "CovioStatusIcon"

    /// 菜单栏图标的标准逻辑尺寸。
    static let pointSize: CGFloat = 18

    static func makeImage() -> NSImage {
        let image = NSImage(
            size: NSSize(width: pointSize, height: pointSize),
            flipped: true
        ) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(in rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        let scale = min(rect.width, rect.height) / pointSize
        let originX = rect.minX + (rect.width - pointSize * scale) / 2
        let originY = rect.minY + (rect.height - pointSize * scale) / 2

        func point(_ value: CGFloat) -> CGFloat { value * scale }
        func x(_ value: CGFloat) -> CGFloat { originX + point(value) }
        func y(_ value: CGFloat) -> CGFloat { originY + point(value) }

        NSColor.black.setFill()

        let island = NSBezierPath(
            roundedRect: NSRect(
                x: x(2.16),
                y: y(2.52),
                width: point(13.68),
                height: point(3.42)
            ),
            xRadius: point(1.71),
            yRadius: point(1.71)
        )
        island.fill()

        let cardWidth = point(3.6)
        let cardHeight = point(6.12)
        let cardY = y(8.82)
        let stemWidth = point(1)
        let cardXs = [2.88, 7.2, 11.52].map(x)

        for cardX in cardXs {
            let stem = NSBezierPath(
                roundedRect: NSRect(
                    x: cardX + (cardWidth - stemWidth) / 2,
                    y: y(5.94),
                    width: stemWidth,
                    height: point(3.06)
                ),
                xRadius: point(0.5),
                yRadius: point(0.5)
            )
            stem.fill()

            let card = NSBezierPath(
                roundedRect: NSRect(
                    x: cardX,
                    y: cardY,
                    width: cardWidth,
                    height: cardHeight
                ),
                xRadius: point(0.81),
                yRadius: point(0.81)
            )
            card.fill()
        }
    }
}
