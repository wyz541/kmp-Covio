import AppKit
import XCTest
@testable import Covio

/// Covio 使用一个原生菜单栏状态项。
@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testTheNativeStatusItemIsVisible() {
        let controller = StatusItemController(shell: NotchShellController())
        defer { controller.tearDown() }

        XCTAssertTrue(controller.isVisible)
    }
}
