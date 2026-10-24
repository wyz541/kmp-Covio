import AppKit
import XCTest
@testable import Covio

/// 备用状态项只在品牌胶囊不可见时显示。
@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testTheFallbackStatusItemIsVisibleOnlyWithoutTheCapsule() {
        let controller = StatusItemController(
            shell: NotchShellController(),
            capsuleVisible: true
        )
        defer { controller.tearDown() }

        XCTAssertFalse(controller.isVisible)

        controller.sync(capsuleVisible: false)
        XCTAssertTrue(controller.isVisible)

        controller.sync(capsuleVisible: true)
        XCTAssertFalse(controller.isVisible)
    }
}
