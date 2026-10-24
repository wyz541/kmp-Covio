import AppKit
import SwiftUI
import XCTest
@testable import Covio

/// 菜单栏胶囊的落位。
///
/// 位置由系统给不出：状态项由系统排，居中不了，刘海区也放不下，所以自己开窗。
/// 这里守的是「窗口落在屏幕内、让开刘海、菜单栏不可见时不出现」。
@MainActor
final class MenuBarCapsuleTests: XCTestCase {
    /// 本机内建屏的实测值。见 `docs/adr/adr-0001-macos-ui-swiftui.md` 实测 8。
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1085),
        safeAreaTop: 32,
        notch: CGRect(x: 771.5, y: 1085, width: 185, height: 32)
    )

    private let notchless = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
        safeAreaTop: 0,
        notch: nil
    )

    /// 全屏 Space：菜单栏藏起来了。
    private let fullScreen = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0,
        notch: nil
    )

    private let capsule = CGSize(width: 60, height: HubMetrics.menuBarCapsuleHeight)

    // MARK: - 落位

    /// 刘海屏上胶囊贴在刘海右侧，让开刘海那一条。
    func testTheCapsuleSitsBesideTheNotch() throws {
        let rect = notched.menuBarCapsuleRect(capsuleWidth: capsule.width, capsuleHeight: capsule.height)
        let notch = try XCTUnwrap(notched.notch)
        XCTAssertGreaterThanOrEqual(rect.minX, notch.maxX)
        XCTAssertEqual(rect.minX, notch.maxX + ScreenGeometry.capsuleNotchGap, accuracy: 0.001)
    }

    /// 非刘海屏上胶囊居中。
    func testTheCapsuleIsCenteredOnANotchlessScreen() {
        let rect = notchless.menuBarCapsuleRect(capsuleWidth: capsule.width, capsuleHeight: capsule.height)
        XCTAssertEqual(rect.midX, notchless.frame.midX, accuracy: 0.001)
    }

    /// 胶囊必须落在屏幕内，否则窗口会跑到屏幕外面。
    func testTheCapsuleStaysInsideTheScreen() {
        for geometry in [notched, notchless] {
            let rect = geometry.menuBarCapsuleRect(capsuleWidth: capsule.width, capsuleHeight: capsule.height)
            XCTAssertTrue(geometry.frame.contains(rect), "胶囊超出了屏幕")
        }
    }

    /// 胶囊竖直居中在菜单栏那一条里，不压到下面的窗口。
    func testTheCapsuleSitsInsideTheMenuBar() {
        for geometry in [notched, notchless] {
            let rect = geometry.menuBarCapsuleRect(capsuleWidth: capsule.width, capsuleHeight: capsule.height)
            XCTAssertLessThanOrEqual(rect.maxY, geometry.frame.maxY + 0.001)
            XCTAssertGreaterThanOrEqual(rect.minY, geometry.visibleFrame.maxY - 0.001)
            // 居中：上下留的空一样。
            XCTAssertEqual(
                geometry.frame.maxY - rect.maxY,
                rect.minY - geometry.visibleFrame.maxY,
                accuracy: 0.001
            )
        }
    }

    /// 刘海很宽、右边放不下时改放左边。
    func testAWideNotchPushesTheCapsuleToTheLeft() {
        let geometry = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 900, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 768),
            safeAreaTop: 32,
            notch: CGRect(x: 380, y: 768, width: 460, height: 32)
        )
        let rect = geometry.menuBarCapsuleRect(capsuleWidth: capsule.width, capsuleHeight: capsule.height)
        XCTAssertLessThanOrEqual(rect.maxX, 380)
        XCTAssertTrue(geometry.frame.contains(rect))
    }

    // MARK: - 菜单栏高度

    /// 菜单栏高度从 `visibleFrame` 与 `frame` 的差算出来，不写死。
    func testTheMenuBarHeightIsMeasuredFromTheScreen() {
        XCTAssertEqual(notched.menuBarHeight, 32, accuracy: 0.001)
        XCTAssertEqual(notchless.menuBarHeight, 25, accuracy: 0.001)
    }

    /// 全屏 Space 里量不出菜单栏高度，回落到一个至少放得下胶囊的值。
    func testTheMenuBarHeightFallsBackWhenItIsHidden() {
        XCTAssertFalse(fullScreen.isMenuBarVisible)
        XCTAssertGreaterThanOrEqual(fullScreen.menuBarHeight, HubMetrics.menuBarCapsuleHeight)
    }

    // MARK: - 窗口矩形

    /// 窗口比胶囊大一圈悬停余量，指针滑到边上也算进来了。
    func testTheWindowIsLargerThanTheCapsuleByTheHoverInset() {
        let rect = MenuBarCapsulePanel.windowRect(for: capsule, on: notched)
        XCTAssertEqual(rect.width, capsule.width + HubMetrics.menuBarCapsuleHoverInset * 2, accuracy: 0.001)
        XCTAssertEqual(rect.height, capsule.height + HubMetrics.menuBarCapsuleHoverInset * 2, accuracy: 0.001)
    }

    /// 拿不到屏幕几何时窗口仍然有尺寸，不至于开出一个零大小的窗口。
    func testTheWindowHasASizeWithoutGeometry() {
        let rect = MenuBarCapsulePanel.windowRect(for: capsule, on: nil)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
    }

    /// 窗口只包住胶囊，不铺满菜单栏。铺满会挡住菜单栏项与别的状态项。
    func testTheWindowDoesNotCoverTheWholeMenuBar() {
        for geometry in [notched, notchless] {
            let rect = MenuBarCapsulePanel.windowRect(for: capsule, on: geometry)
            XCTAssertLessThan(rect.width, geometry.frame.width / 4, "胶囊窗口太宽，会挡住别的菜单栏项")
        }
    }

    // MARK: - 真窗口的落位

    /// 开一个真窗口，用完关掉。
    ///
    /// 不关的话它会留在 `NSApp.windows` 里，把
    /// `NotchShellControllerTests.testHostApplicationShowsTheMenuBarCapsule` 的计数弄乱。
    private func makePanel() -> MenuBarCapsulePanel {
        let panel = MenuBarCapsulePanel()
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// 窗口里画胶囊的那个宿主视图，以及它在屏幕坐标里的矩形。
    ///
    /// 按类型找，不假设层级：内容视图是不是一层容器是内部结构，不是被守护的契约。
    private func capsuleFrame(in panel: MenuBarCapsulePanel) throws -> CGRect {
        let root = try XCTUnwrap(panel.contentView)
        root.layoutSubtreeIfNeeded()

        let host: NSView
        if let direct = root as? NSHostingView<MenuBarCapsule> {
            host = direct
        } else {
            host = try XCTUnwrap(
                root.subviews.first { $0 is NSHostingView<MenuBarCapsule> },
                "窗口里没有画胶囊的宿主视图"
            )
        }
        // `convert(_:to: nil)` 给的是窗口坐标，加上窗口原点才是屏幕坐标。
        return host.convert(host.bounds, to: nil).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    /// 窗口就停在 `place(on:)` 算出来的那个矩形上。
    ///
    /// 这一条只守得住「窗口尺寸跟着 `capsuleSize` 走」。
    /// 真机上那个「窗口被内容视图的内在尺寸缩掉」的毛病要窗口上屏才复现，
    /// 单元测试里窗口没显示，量不到，只能在真机上验收。
    func testTheWindowStaysWhereItWasPlaced() {
        let panel = makePanel()
        defer { panel.close() }

        panel.place(on: notched)
        panel.contentView?.layoutSubtreeIfNeeded()

        let expected = MenuBarCapsulePanel.windowRect(for: panel.capsuleSize, on: notched)
        XCTAssertEqual(panel.frame.minX, expected.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY, expected.minY, accuracy: 0.5)
        XCTAssertEqual(panel.frame.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, expected.height, accuracy: 0.5)
    }

    /// 胶囊左边缘离刘海右边缘正好一个 `capsuleNotchGap`。
    ///
    /// 窗口比胶囊宽一圈悬停余量，所以窗口贴到刘海边上是对的，
    /// 但胶囊本身必须让出那 6 点。之前胶囊压在刘海边上，就是这一条挂了。
    func testTheCapsuleClearsTheNotchByTheGap() throws {
        let panel = makePanel()
        defer { panel.close() }

        panel.place(on: notched)
        let notch = try XCTUnwrap(notched.notch)
        let capsule = try capsuleFrame(in: panel)

        XCTAssertEqual(capsule.minX, notch.maxX + ScreenGeometry.capsuleNotchGap, accuracy: 0.5)
    }

    /// 胶囊铺满窗口减去四周的悬停余量。余量是给指针的，不该画出来。
    func testTheCapsuleFillsTheWindowInsideTheHoverInset() throws {
        let panel = makePanel()
        defer { panel.close() }

        let capsule = try capsuleFrame(in: panel)
        let inset = HubMetrics.menuBarCapsuleHoverInset

        XCTAssertEqual(capsule.width, panel.frame.width - inset * 2, accuracy: 0.5)
        XCTAssertEqual(capsule.height, panel.frame.height - inset * 2, accuracy: 0.5)
        XCTAssertEqual(capsule.width, panel.capsuleSize.width, accuracy: 0.5)
    }

    // MARK: - 点击

    func testAPrimaryClickOpensTheHub() throws {
        let panel = makePanel()
        defer { panel.close() }
        var primaryClicks = 0
        var secondaryClicks = 0
        panel.onClick = { primaryClicks += 1 }
        panel.onSecondaryClick = { secondaryClicks += 1 }

        try sendMouseUp(to: panel, type: .leftMouseUp)

        XCTAssertEqual(primaryClicks, 1)
        XCTAssertEqual(secondaryClicks, 0)
    }

    func testARightClickOpensTheMenu() throws {
        let panel = makePanel()
        defer { panel.close() }
        var primaryClicks = 0
        var secondaryClicks = 0
        panel.onClick = { primaryClicks += 1 }
        panel.onSecondaryClick = { secondaryClicks += 1 }

        try sendMouseUp(to: panel, type: .rightMouseUp)

        XCTAssertEqual(primaryClicks, 0)
        XCTAssertEqual(secondaryClicks, 1)
    }

    func testAControlClickOpensTheMenu() throws {
        let panel = makePanel()
        defer { panel.close() }
        var primaryClicks = 0
        var secondaryClicks = 0
        panel.onClick = { primaryClicks += 1 }
        panel.onSecondaryClick = { secondaryClicks += 1 }

        try sendMouseUp(to: panel, type: .leftMouseUp, modifiers: [.control])

        XCTAssertEqual(primaryClicks, 0)
        XCTAssertEqual(secondaryClicks, 1)
    }

    private func sendMouseUp(
        to panel: MenuBarCapsulePanel,
        type: NSEvent.EventType,
        modifiers: NSEvent.ModifierFlags = []
    ) throws {
        panel.place(on: notched)
        let point = NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let view = try XCTUnwrap(panel.contentView?.hitTest(point))
        if type == .rightMouseUp {
            view.rightMouseUp(with: event)
        } else {
            view.mouseUp(with: event)
        }
    }
}
