import XCTest
@testable import Covio

final class GlassSurfaceTests: XCTestCase {
    func testThePlateDefaultsToLiquidGlass() {
        XCTAssertEqual(GlassSurfaceMode.plateDefaultMode, .glass)
    }
}
