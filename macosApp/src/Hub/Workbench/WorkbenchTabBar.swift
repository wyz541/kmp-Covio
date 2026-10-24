import SwiftUI

/// 顶栏上的一个工作区。
///
/// 视图不直接拿 `PaneInstance`：那是 Kotlin 的类，名字随时可能被配置改掉。
/// 这里只留画一条页签要用的三样。
struct PaneItem: Identifiable, Equatable, Sendable {
    let id: String
    let tab: HubTab
    /// 已经解析好的显示名。用户改过名就是用户的名字。
    let title: String

    var glyph: String { tab.glyph }
}

/// 页签拖动排序的换算。
///
/// 一次拖动里 `onChanged` 连着来，`translation` 是从起点累计的。
/// 所以每次都只补上「这一次新跨过的条数」，不把累计值重算一遍：
/// 重算会把已经挪过的位置再挪一次，页签冲过头。
struct TabReorderState {
    /// 已经补过的条数。
    private(set) var applied = 0
    /// 跨过一条页签要拖多少点。
    private let step: CGFloat

    init(step: CGFloat) {
        self.step = step
    }

    /// 这一次该往哪边挪几条。零表示还没跨过一条。
    mutating func delta(forTranslation width: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        let steps = Int(width / step)
        defer { applied = steps }
        return steps - applied
    }

    /// 松手，下一次拖动从头计。
    mutating func reset() {
        applied = 0
    }
}

/// 挂帘顶部的横向页签栏。合同 `component/tab-bar`，`nativeSize` 是 960 × 46。
///
/// 左端固定是首页入口，紧挨着搜索框，中间是工作区页签，右端是当前页的动作。
/// 导航按钮使用原生 Liquid Glass 按钮样式。选中态用强调色着色玻璃。
/// 指针反馈与键盘焦点反馈由 SwiftUI 原生玻璃按钮提供。
/// 编辑模式里页签前面加拖动把手，横向拖过 84 点换一次位置。
struct WorkbenchTabBar: View {
    let panes: [PaneItem]
    let destination: HubDestination
    let isEditing: Bool
    @Binding var searchText: String
    let language: AppLanguage
    let pageAction: LocalizedCopy
    let reduceMotion: Bool
    let onHome: () -> Void
    let onSelect: (String) -> Void
    let onReorder: (Int, Int) -> Void
    let onPageAction: () -> Void
    /// 指针进出某个目的地。切换判定住在 `WorkbenchModel` 里，这里只转达。
    ///
    /// 顶栏上表示「去哪里」的两处 —— 首页入口与工作区页签 —— 都报。
    /// 搜索框与右端的动作按钮不报：它们表示「做什么」，滑过不该换页。
    let onHover: (HubDestination, Bool) -> Void

    /// 正在拖的页签 id，与这一次拖动已经挪过的条数。
    @State private var reorderID: String?
    @State private var reorder = TabReorderState(step: HubMetrics.tabReorderStep)
    /// 指针当前所在的导航按钮。未选中按钮只在指针进入时显示玻璃。
    @State private var hoveredTarget: NavigationGlassTarget?
    /// 键盘焦点所在的导航按钮。焦点态同样显示玻璃。
    @FocusState private var focusedTarget: NavigationGlassTarget?

    var body: some View {
        HStack(spacing: HubMetrics.tabBarItemGap) {
            homeEntry
            searchField
            tabStrip
            pageActionButton
        }
        .padding(.horizontal, HubMetrics.tabBarHPadding)
        .frame(width: HubMetrics.tabBarWidth, height: HubMetrics.tabBarHeight)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ContractCopy.copyNavRailLabel.text(for: language))
    }

    // MARK: - 首页入口

    /// 固定在左端，不参与排序，也不随页签滚动。
    private var homeEntry: some View {
        let isSelected = destination == .home
        return Button(action: onHome) {
            Text("▦")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? MacTheme.accent : MacTheme.textPrimary)
                .frame(width: HubMetrics.homeEntryWidth, height: HubMetrics.homeEntryHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedTarget, equals: .home)
        .workbenchNavigationGlass(navigationGlass(for: .home, isSelected: isSelected))
        .animation(selectionAnimation, value: isSelected)
        .accessibilityLabel(ContractCopy.copyHubActionHome.text(for: language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { inside in
            hoveredTarget = inside ? .home : nil
            onHover(.home, inside)
        }
    }

    // MARK: - 搜索

    private var searchField: some View {
        HStack(spacing: MacTheme.space1) {
            Text("⌕")
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.textSecondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .disabled(isEditing)
        }
        .padding(.horizontal, MacTheme.space2)
        .frame(width: HubMetrics.searchFieldWidth, height: HubMetrics.searchFieldHeight)
        .background(
            isEditing ? Color.primary.opacity(0.06) : MacTheme.elevated,
            in: RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
        .accessibilityLabel(placeholder)
    }

    private var placeholder: String {
        ContractCopy.copyNavSearchPlaceholder.text(for: language)
    }

    // MARK: - 页签

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: HubMetrics.tabGap) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { _, pane in
                    tab(pane)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tab(_ pane: PaneItem) -> some View {
        let isSelected = destination == .pane(id: pane.id)
        return Button {
            guard !isEditing else { return }
            onSelect(pane.id)
        } label: {
            HStack(spacing: MacTheme.space1) {
                if isEditing {
                    Text("⣿")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(pane.glyph)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? MacTheme.accent : MacTheme.textSecondary)
                    .accessibilityHidden(true)
                Text(pane.title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, HubMetrics.tabHPadding)
            .frame(height: HubMetrics.tabHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedTarget, equals: .pane(pane.id))
        .workbenchNavigationGlass(navigationGlass(for: .pane(pane.id), isSelected: isSelected))
        .animation(selectionAnimation, value: isSelected)
        .accessibilityLabel(pane.title)
        .accessibilityHint(pane.tab.summary.text(for: language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { inside in
            hoveredTarget = inside ? .pane(pane.id) : nil
            onHover(.pane(id: pane.id), inside)
        }
        .gesture(isEditing ? reorderGesture(pane: pane) : nil)
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch)
    }

    private func navigationGlass(for target: NavigationGlassTarget, isSelected: Bool) -> Glass {
        if isSelected {
            return .clear.tint(MacTheme.accent.opacity(0.35)).interactive()
        }
        if hoveredTarget == target || focusedTarget == target {
            return .clear.interactive()
        }
        return .identity
    }

    /// 编辑模式里的拖动排序。跨过一条页签的宽度就换一次位置。
    ///
    /// 每次都按 id 重新找当前下标：上一次换位之后页签已经挪了，
    /// 用闭包里那个旧下标会越挪越偏。
    private func reorderGesture(pane: PaneItem) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if reorderID != pane.id {
                    reorderID = pane.id
                    reorder.reset()
                }
                let delta = reorder.delta(forTranslation: value.translation.width)
                guard delta != 0,
                      !panes.isEmpty,
                      let current = panes.firstIndex(where: { $0.id == pane.id })
                else { return }
                let target = (current + delta).clamped(to: 0...(panes.count - 1))
                guard target != current else { return }
                onReorder(current, target)
            }
            .onEnded { _ in
                reorderID = nil
                reorder.reset()
            }
    }

    // MARK: - 当前页的动作

    private var pageActionButton: some View {
        Button(action: onPageAction) {
            Text(pageAction.text(for: language))
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, HubMetrics.actionHPadding)
                .frame(minWidth: HubMetrics.actionButtonMinWidth, minHeight: HubMetrics.tabHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedTarget, equals: .pageAction)
        .workbenchNavigationGlass(navigationGlass(for: .pageAction, isSelected: false))
        .accessibilityLabel(pageAction.text(for: language))
        .onHover { hoveredTarget = $0 ? .pageAction : nil }
    }
}

private enum NavigationGlassTarget: Hashable {
    case home
    case pane(String)
    case pageAction
}

/// 顶栏本身已经是玻璃。按钮只在选中、悬停或聚焦时叠 clear 玻璃。
private struct WorkbenchNavigationGlass: ViewModifier {
    let glass: Glass

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: .capsule)
    }
}

private extension View {
    func workbenchNavigationGlass(_ glass: Glass) -> some View {
        modifier(WorkbenchNavigationGlass(glass: glass))
    }
}
