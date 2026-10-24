import XCTest
@testable import Covio

/// Popover 活动状态的计数规则。
@MainActor
final class HubPopoverCoordinatorTests: XCTestCase {
    func testActivityChangesOnlyWhenTheFirstAndLastPopoverChange() {
        let coordinator = HubPopoverCoordinator()
        var changes: [Bool] = []
        coordinator.onActivityChanged = { changes.append($0) }

        coordinator.setPresented(true, id: "power")
        coordinator.setPresented(true, id: "fan")
        coordinator.setPresented(false, id: "power")
        XCTAssertEqual(changes, [true])
        XCTAssertTrue(coordinator.hasActivePopover)

        coordinator.setPresented(false, id: "fan")
        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(coordinator.hasActivePopover)
    }

    func testRepeatedReportsAreIdempotent() {
        let coordinator = HubPopoverCoordinator()

        coordinator.setPresented(true, id: "fan")
        coordinator.setPresented(true, id: "fan")
        XCTAssertTrue(coordinator.hasActivePopover)

        coordinator.setPresented(false, id: "fan")
        coordinator.setPresented(false, id: "fan")
        XCTAssertFalse(coordinator.hasActivePopover)
    }

    func testEachDismissalRequestIsDistinct() {
        let coordinator = HubPopoverCoordinator()

        coordinator.requestDismissal()
        let first = coordinator.dismissalRequest
        coordinator.requestDismissal()

        XCTAssertEqual(coordinator.dismissalRequest, first + 1)
    }
}
