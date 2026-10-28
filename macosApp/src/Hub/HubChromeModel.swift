import Foundation
import Observation
import SwiftUI

/// Hub 外壳的共享状态。
///
/// 左侧导航栏、顶部胶囊与页内容读同一份选中态，所以放进一个可观察对象。
/// 测试直接改这个对象，不构建视图。与 `AppRuntime` 同一手法。
///
/// 持有者是 `NotchShellController`，所以面板收起再展开时状态不丢。
@MainActor
@Observable
final class HubChromeModel {
    /// 搜索框里的文字。
    var searchText = ""

    /// 当前选中的剪切板条目。面板收到 Escape 时，用它判断是否先清除选中态。
    var clipboardSelectionID: String?

    /// 设置页当前的分节。
    var settingsSection: SettingsSection = .overview

    /// 要高亮的设置行锚点。搜索跳转后亮一会儿。
    private(set) var highlightedRowID: String?

    /// 要滚动到的设置行锚点。每次跳转都会换一个新值，视图据此再滚一次。
    private(set) var scrollTarget: String?

    /// 跳转序号。滚动目标与上一次相同时，`scrollTarget` 不变，
    /// 视图不会重新滚动，所以滚动由这个序号驱动。
    private(set) var revealCount = 0

    private var highlightTask: Task<Void, Never>?

    /// 切到某个设置分节。胶囊的分段切换与搜索跳转都走这里。
    func select(_ section: SettingsSection) {
        settingsSection = section
    }

    /// 当前查询命中的设置项。
    func results(language: AppLanguage) -> [SettingsSearchHit] {
        SettingsSearchIndex.search(searchText, language: language)
    }

    /// 跳到一个搜索命中：切到设置页签、切到该分节、滚到该行、高亮一会儿。
    ///
    /// 切页签由调用方做，因为页签住在 `NotchShellController`。
    /// `reduceMotion` 为真时高亮不闪，只描边，时长不变。
    func reveal(_ hit: SettingsSearchHit, clearSearch: Bool = true) {
        settingsSection = hit.section
        highlightedRowID = hit.rowID
        scrollTarget = hit.rowID
        revealCount += 1
        if clearSearch { searchText = "" }

        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SettingsSearchIndex.highlightDuration))
            guard !Task.isCancelled else { return }
            self?.highlightedRowID = nil
        }
    }

    /// 清掉高亮。Esc 与面板收起时调用。
    func clearHighlight() {
        highlightTask?.cancel()
        highlightTask = nil
        highlightedRowID = nil
    }

    /// 清空搜索。Esc 先做这件事，查询已经是空的时候才收起面板。
    func clearSearch() {
        searchText = ""
    }

    /// 清除剪切板选中态。切离剪切板页签时也调用。
    func clearClipboardSelection() {
        clipboardSelectionID = nil
    }

    /// Escape 的分段行为。先清搜索，再清剪切板选中态，最后才收起面板。
    ///
    /// 返回值表示这一步是否已经处理完。真表示调用方不该收起面板。
    /// 用户想退出搜索或选中态，不是每次都收起整个面板。
    /// 面板收到 Escape 的那一段见 `HubPanel.keyDown`。
    func handleEscape() -> Bool {
        if !searchText.isEmpty {
            clearSearch()
            return true
        }
        if clipboardSelectionID != nil {
            clearClipboardSelection()
            return true
        }
        return false
    }
}
