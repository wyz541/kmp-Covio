import AppKit
import XCTest
@testable import Covio

/// 菜单栏默认图标的尺寸、模板模式和实际覆盖率。
@MainActor
final class CovioStatusIconTests: XCTestCase {
    func testTheIconUsesTheMenuBarPointSizeAndTemplateMode() {
        let image = CovioStatusIcon.makeImage()

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
    }

    func testTheIconHasInkAndTransparentMargins() throws {
        let image = CovioStatusIcon.makeImage()
        let side = Int(CovioStatusIcon.pointSize)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var opaquePixels = 0
        for y in 0..<side {
            for x in 0..<side where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                opaquePixels += 1
            }
        }

        XCTAssertGreaterThan(opaquePixels, 30, "图标没有可辨认的前景")
        XCTAssertLessThan(opaquePixels, side * side / 2, "图标不该铺满菜单栏命中区")
        let cornerAlpha = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.alphaComponent)
        XCTAssertEqual(cornerAlpha, 0, accuracy: 0.01)
    }
}
