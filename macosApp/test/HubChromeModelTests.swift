import XCTest
@testable import Covio

/// Hub 外壳状态的行为。
///
/// 外壳的几何由 `HubMetricsTests` 与 `ScreenGeometryTests` 覆盖，搜索的匹配
/// 由 `SettingsSearchIndexTests` 覆盖。这里覆盖把两者接起来的那一层：
/// Escape 的分段行为，以及搜索跳转改动的状态。
///
/// 不构建视图。面板收到 Escape 的那一段在 `ShellPanelTests`。
@MainActor
final class HubChromeModelTests: XCTestCase {
    // MARK: - Escape 的分段行为

    /// 第一次 Escape 只清搜索。
    func testEscapeClearsTheSearchFirst() {
        let chrome = HubChromeModel()
        chrome.searchText = "休眠"

        XCTAssertTrue(chrome.handleEscape(), "有查询时这一步应该已经处理完")
        XCTAssertEqual(chrome.searchText, "")
    }

    /// 查询已经是空的时候，交给调用方收起面板。
    func testEscapeLeavesTheCollapseToTheCaller() {
        let chrome = HubChromeModel()

        XCTAssertFalse(chrome.handleEscape(), "查询为空时该由调用方收起面板")
        XCTAssertEqual(chrome.searchText, "")
    }

    /// 两次 Escape 合起来就是「先清查询，再收起」。
    func testTheSecondEscapeHandsOverTheCollapse() {
        let chrome = HubChromeModel()
        chrome.searchText = "休眠"

        XCTAssertTrue(chrome.handleEscape(), "第一次应该清查询")
        XCTAssertFalse(chrome.handleEscape(), "第二次应该收起面板")
    }

    /// 剪切板有选中项时，空查询下的 Escape 先清选中态。
    func testEscapeClearsTheClipboardSelectionBeforeCollapse() {
        let chrome = HubChromeModel()
        chrome.clipboardSelectionID = "clip:1"

        XCTAssertTrue(chrome.handleEscape(), "有选中项时这一步应该已经处理完")
        XCTAssertNil(chrome.clipboardSelectionID)
        XCTAssertFalse(chrome.handleEscape(), "选中态清空后才收起面板")
    }

    /// 剪切板搜索和选中态同时存在时，两次 Escape 依次清掉它们。
    func testEscapeClearsSearchThenClipboardSelection() {
        let chrome = HubChromeModel()
        chrome.searchText = "Safari"
        chrome.clipboardSelectionID = "clip:1"

        XCTAssertTrue(chrome.handleEscape())
        XCTAssertEqual(chrome.searchText, "")
        XCTAssertEqual(chrome.clipboardSelectionID, "clip:1")

        XCTAssertTrue(chrome.handleEscape())
        XCTAssertNil(chrome.clipboardSelectionID)
        XCTAssertFalse(chrome.handleEscape(), "两步清完后才收起面板")
    }

    // MARK: - 搜索跳转

    /// 跳转改分节、换锚点、清查询，并记一次跳转序号。
    ///
    /// 序号驱动滚动：连着两次跳同一行时，`scrollTarget` 不变，视图不会重滚。
    func testRevealJumpsAndClearsTheSearch() throws {
        let chrome = HubChromeModel()
        chrome.searchText = "休眠"
        let hit = try XCTUnwrap(
            SettingsSearchIndex.search("休眠", language: .simplifiedChinese)
                .first { $0.rowID == SettingsRowID.generalSleepMode }
        )

        chrome.reveal(hit)

        XCTAssertEqual(chrome.settingsSection, .general)
        XCTAssertEqual(chrome.highlightedRowID, SettingsRowID.generalSleepMode)
        XCTAssertEqual(chrome.scrollTarget, SettingsRowID.generalSleepMode)
        XCTAssertEqual(chrome.revealCount, 1)
        XCTAssertEqual(chrome.searchText, "", "跳转后查询要清掉")

        // 同一个目标再跳一次：锚点不变，序号要变。
        chrome.reveal(hit)
        XCTAssertEqual(chrome.revealCount, 2)

        chrome.clearHighlight()
        XCTAssertNil(chrome.highlightedRowID)
    }

    /// 保留查询的跳转。用户连着选几条结果时用得到。
    func testRevealCanKeepTheSearch() throws {
        let chrome = HubChromeModel()
        chrome.searchText = "休眠"
        let hit = try XCTUnwrap(
            SettingsSearchIndex.search("休眠", language: .simplifiedChinese).first
        )

        chrome.reveal(hit, clearSearch: false)

        XCTAssertEqual(chrome.searchText, "休眠")
    }

    /// 分节切换由胶囊驱动，只改分节，不动搜索。
    func testSelectChangesOnlyTheSection() {
        let chrome = HubChromeModel()
        chrome.searchText = "休眠"

        chrome.select(.battery)

        XCTAssertEqual(chrome.settingsSection, .battery)
        XCTAssertEqual(chrome.searchText, "休眠")
    }
}
