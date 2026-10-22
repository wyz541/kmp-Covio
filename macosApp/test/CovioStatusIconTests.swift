import AppKit
import XCTest
@testable import Covio

/// 菜单栏默认图标的资源、缓存、尺寸和实际覆盖率。
@MainActor
final class CovioStatusIconTests: XCTestCase {
    func testTheIconUsesCachedPreRenderedPixels() {
        let image = CovioStatusIcon.makeImage()

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(image.isTemplate)
        XCTAssertTrue(image === CovioStatusIcon.makeImage())

        let pixelSizes = Set(image.representations.map {
            "\($0.pixelsWide)x\($0.pixelsHigh)"
        })
        XCTAssertTrue(pixelSizes.contains("18x18"))
        XCTAssertTrue(pixelSizes.contains("36x36"))
    }

    func testTheIconHasColorAndTransparentMargins() throws {
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
        var hasColor = false
        for y in 0..<side {
            for x in 0..<side {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.5 else {
                    continue
                }
                opaquePixels += 1
                hasColor = hasColor || abs(pixel.redComponent - pixel.blueComponent) > 0.08
            }
        }

        XCTAssertGreaterThan(opaquePixels, 30, "图标没有可辨认的前景")
        XCTAssertLessThan(opaquePixels, side * side / 2, "图标不该铺满菜单栏命中区")
        XCTAssertTrue(hasColor, "拟物图标应保留品牌蓝色")
        let cornerAlpha = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.alphaComponent)
        XCTAssertEqual(cornerAlpha, 0, accuracy: 0.01)
    }
}
