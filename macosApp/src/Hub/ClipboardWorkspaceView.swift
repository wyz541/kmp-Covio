import AppKit
import SwiftUI

/// 剪切板工作区的固定尺寸。
enum ClipboardWorkspaceMetrics {
    /// 筛选栏高度。
    static let controlHeight: CGFloat = 30
    /// 筛选栏与内容之间的间距。
    static let gap: CGFloat = MacTheme.space2
    /// 列表与详情之外的固定高度。
    static let boardHeight: CGFloat = 430
    /// 内容区域高度。
    static var splitHeight: CGFloat { boardHeight - controlHeight - gap }
    /// 列表默认宽度。
    static let listWidth: CGFloat = 340
    /// 详情区最小宽度。
    static let previewMinWidth: CGFloat = 430
}

/// 剪切板工作区：按时间排序的列表、类型筛选与详情预览。
///
/// 搜索来自顶栏当前页搜索，不在页内重复放置搜索框。
/// 列表使用系统选择态；详情区固定承载预览和主要动作。
struct ClipboardWorkspaceBoard<TrailingControl: View>: View {
    let data: ClipboardWorkspaceData
    let language: AppLanguage
    let searchText: String
    let initiallySelectedID: String?
    @Binding var selectedID: String?
    let onClearSearch: () -> Void
    let onPrimary: (ClipboardWorkspaceItem) -> Void
    let onAction: (ClipboardWorkspaceItem, ClipboardWorkspaceAction) -> Void
    let trailingControl: TrailingControl

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: ClipboardWorkspaceFilter = .all

    init(
        data: ClipboardWorkspaceData,
        language: AppLanguage,
        searchText: String,
        initiallySelectedID: String? = nil,
        selectedID: Binding<String?>,
        onClearSearch: @escaping () -> Void,
        onPrimary: @escaping (ClipboardWorkspaceItem) -> Void,
        onAction: @escaping (ClipboardWorkspaceItem, ClipboardWorkspaceAction) -> Void,
        @ViewBuilder trailingControl: () -> TrailingControl
    ) {
        self.data = data
        self.language = language
        self.searchText = searchText
        self.initiallySelectedID = initiallySelectedID
        self._selectedID = selectedID
        self.onClearSearch = onClearSearch
        self.onPrimary = onPrimary
        self.onAction = onAction
        self.trailingControl = trailingControl()
    }

    private var visibleItems: [ClipboardWorkspaceItem] {
        data.items(query: searchText, filter: filter, language: language)
    }

    private var visibleSections: [ClipboardWorkspaceSection] {
        data.sections(query: searchText, filter: filter, language: language)
    }

    private var visibleItemIDs: [String] {
        visibleItems.map(\.id)
    }

    private var selectedItem: ClipboardWorkspaceItem? {
        guard let selectedID else { return nil }
        return visibleItems.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClipboardWorkspaceMetrics.gap) {
            controlBar
            HSplitView {
                listPane
                    .frame(
                        minWidth: 280,
                        idealWidth: ClipboardWorkspaceMetrics.listWidth,
                        maxWidth: 380,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                detailPane
                    .frame(
                        minWidth: ClipboardWorkspaceMetrics.previewMinWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
            }
            .frame(height: ClipboardWorkspaceMetrics.splitHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: ClipboardWorkspaceMetrics.boardHeight, alignment: .topLeading)
        .onAppear { reconcileSelection(preferInitial: true) }
        .onChange(of: visibleItemIDs) { _, _ in reconcileSelection(preferInitial: false) }
    }

    private var controlBar: some View {
        HStack(spacing: MacTheme.space2) {
            Menu {
                ForEach(ClipboardWorkspaceFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        if filter == option {
                            Label(option.title(for: language), systemImage: "checkmark")
                        } else {
                            Text(option.title(for: language))
                        }
                    }
                }
            } label: {
                HStack(spacing: MacTheme.space1) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                    Text(filter.title(for: language))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(MacTheme.textPrimary)
                .padding(.horizontal, MacTheme.space3)
                .frame(height: ClipboardWorkspaceMetrics.controlHeight)
                .background(
                    MacTheme.elevated,
                    in: RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
                        .strokeBorder(MacTheme.divider, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .accessibilityLabel(filter.title(for: language))

            Text(itemCountText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
            trailingControl
        }
        .frame(height: ClipboardWorkspaceMetrics.controlHeight)
    }

    private var itemCountText: String {
        let unit = ContractCopy.copyHubFilesCountItems.text(for: language)
        return "\(visibleItems.count) \(unit)"
    }

    private var listPane: some View {
        Group {
            if data.allItems(language: language).isEmpty {
                emptyState
            } else if visibleSections.isEmpty {
                noMatchState
            } else {
                List(selection: $selectedID) {
                    ForEach(visibleSections) { section in
                        Section {
                            ForEach(section.items) { item in
                                ClipboardListRow(
                                    item: item,
                                    language: language,
                                    onPrimary: { onPrimary(item) },
                                    onAction: { onAction(item, $0) }
                                )
                                    .tag(item.id)
                                    .contextMenu {
                                        ClipboardActionMenuItems(
                                            item: item,
                                            language: language,
                                            onAction: onAction
                                        )
                                    }
                            }
                        } header: {
                            Text(section.kind.title(for: language))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(MacTheme.surface.opacity(0.62))
                .environment(\.defaultMinListRowHeight, 46)
                .onKeyPress(.return) {
                    guard let selectedItem else { return .ignored }
                    onPrimary(selectedItem)
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard let selectedItem else { return .ignored }
                    onAction(selectedItem, .remove)
                    return .handled
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.8), lineWidth: 1)
        )
    }

    private var detailPane: some View {
        Group {
            if let selectedItem {
                ClipboardDetailPane(
                    item: selectedItem,
                    language: language,
                    onPrimary: { onPrimary(selectedItem) },
                    onAction: { action in onAction(selectedItem, action) }
                )
                .id(selectedItem.id)
                .transition(detailTransition)
            } else {
                VStack(spacing: MacTheme.space2) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(ContractCopy.copyClipboardPreviewEmpty.text(for: language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacTheme.surface.opacity(0.4))
                .transition(detailTransition)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.8), lineWidth: 1)
        )
        .animation(detailAnimation, value: selectedID)
    }

    private var emptyState: some View {
        VStack(spacing: MacTheme.space2) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(ContractCopy.copyClipboardEmpty.text(for: language))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.surface.opacity(0.6))
    }

    private var noMatchState: some View {
        VStack(spacing: MacTheme.space1) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(ContractCopy.copyClipboardNoMatchTitle.text(for: language))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
            Text(ContractCopy.copyClipboardNoMatchHint.text(for: language))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(filter.title(for: language))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            if !searchText.isEmpty {
                Button(ContractCopy.copyClipboardActionClearSearch.text(for: language)) {
                    onClearSearch()
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.surface.opacity(0.6))
    }

    private func reconcileSelection(preferInitial: Bool) {
        let ids = visibleItems.map(\.id)
        if let selectedID, ids.contains(selectedID) {
            return
        }
        if preferInitial, let initiallySelectedID, ids.contains(initiallySelectedID) {
            selectedID = initiallySelectedID
            return
        }
        selectedID = ids.first
    }

    private var detailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: 4))
    }

    private var detailAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.12 : 0.16)
    }
}

/// 时间列表里的一行。
private struct ClipboardListRow: View {
    let item: ClipboardWorkspaceItem
    let language: AppLanguage
    let onPrimary: () -> Void
    let onAction: (ClipboardWorkspaceAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        HStack(spacing: MacTheme.space2) {
            ClipboardItemGlyph(item: item, size: .list)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title(for: language))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(listSubtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.brand)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(
            hovered ? MacTheme.brand.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: MacTheme.smallRadius, style: .continuous)
        )
        .onHover { hovered = $0 }
        .animation(
            reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.12),
            value: hovered
        )
        .onTapGesture(count: 2, perform: onPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title(for: language))
        .accessibilityValue(item.accessibilityValue(for: language))
        .accessibilityHint(item.accessibilityHint(for: language))
        .accessibilityAction(named: Text(item.primaryTitle(for: language))) {
            onPrimary()
        }
        .accessibilityActions {
            ForEach(item.secondaryActions, id: \.self) { action in
                Button(item.actionTitle(action, language: language)) {
                    onAction(action)
                }
            }
        }
    }

    private var listSubtitle: String {
        let time = ClipboardWorkspaceTime.text(item.createdAtEpochSeconds, language: language)
        return "\(item.metadata(for: language)) · \(time)"
    }

}

/// 选中条目的详情。
private struct ClipboardDetailPane: View {
    let item: ClipboardWorkspaceItem
    let language: AppLanguage
    let onPrimary: () -> Void
    let onAction: (ClipboardWorkspaceAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                previewBody
                    .padding(MacTheme.space4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
            Divider()
            footer
        }
        .background(MacTheme.surface.opacity(0.55))
    }

    private var header: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.actionFill)
                .frame(width: 28, height: 28)
                .background(
                    MacTheme.actionFill.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: MacTheme.smallRadius, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MacTheme.space1) {
                    Text(item.kind.title(for: language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if item.kind == .screenshots {
                        Text(ContractCopy.copyClipboardKindDedicated.text(for: language))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(MacTheme.brand)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(MacTheme.brand.opacity(0.12), in: Capsule())
                    }
                }
                Text(item.title(for: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(primaryTitle) {
                onPrimary()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MacTheme.color(ContractColors.tokenColorTextOnAccent))
            .padding(.horizontal, MacTheme.space3)
            .frame(height: 28)
            .background(
                MacTheme.actionFill,
                in: RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
            )
            Menu {
                ClipboardActionMenuItems(
                    item: item,
                    language: language,
                    onAction: { _, action in onAction(action) }
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        MacTheme.elevated,
                        in: RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.controlRadius, style: .continuous)
                            .strokeBorder(MacTheme.divider, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(ContractCopy.copyHubFilesActionMore.text(for: language))
        }
        .padding(MacTheme.space3)
    }

    @ViewBuilder
    private var previewBody: some View {
        if item.kind == .images || item.kind == .screenshots {
            imagePreview
        } else if item.kind == .files {
            filePreview
        } else if item.clipItem?.kind == .color {
            colorPreview
        } else {
            textPreview
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = NSImage(contentsOfFile: item.filePath) {
            VStack(alignment: .leading, spacing: MacTheme.space3) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 230)
                    .background(
                        MacTheme.elevated,
                        in: RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                            .strokeBorder(MacTheme.divider, lineWidth: 1)
                    )
                if !item.detailText.isEmpty {
                    Text(item.detailText)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        } else {
            fallbackPreview
        }
    }

    @ViewBuilder
    private var filePreview: some View {
        if item.filePaths.isEmpty {
            fallbackPreview
        } else {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                ForEach(item.filePaths, id: \.self) { path in
                    HStack(spacing: MacTheme.space2) {
                        Image(systemName: "doc")
                            .foregroundStyle(MacTheme.actionFill)
                            .frame(width: 20)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    @ViewBuilder
    private var colorPreview: some View {
        let value = item.detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(spacing: MacTheme.space3) {
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .fill(Color(nsColor: MacTheme.nsColor(hex: value)))
                .frame(width: 72, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                        .strokeBorder(MacTheme.divider, lineWidth: 1)
                )
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(MacTheme.textPrimary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        if item.detailText.isEmpty {
            fallbackPreview
        } else {
            Text(item.detailText)
                .font(
                    .system(
                        size: item.clipItem?.kind == .link ? 12 : 11,
                        design: item.clipItem?.kind == .link ? .monospaced : .default
                    )
                )
                .foregroundStyle(MacTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fallbackPreview: some View {
        VStack(spacing: MacTheme.space2) {
            Image(systemName: "eye.slash")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(ContractCopy.copyStateEmpty.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var footer: some View {
        HStack(spacing: MacTheme.space3) {
            Text(item.metadata(for: language))
            Spacer(minLength: 0)
            Text(ClipboardWorkspaceTime.text(item.createdAtEpochSeconds, language: language))
            if item.pinned {
                Label(
                    ContractCopy.copyClipboardActionPin.text(for: language),
                    systemImage: "pin.fill"
                )
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, MacTheme.space3)
        .frame(height: 30)
    }

    private var primaryTitle: String {
        item.primaryTitle(for: language)
    }
}

private enum ClipboardGlyphSize {
    case list
}

private struct ClipboardItemGlyph: View {
    let item: ClipboardWorkspaceItem
    let size: ClipboardGlyphSize

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: dimension.width, height: dimension.height)
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size == .list ? 12 : 14, weight: .medium))
                .foregroundStyle(MacTheme.actionFill)
                .frame(width: dimension.width, height: dimension.height)
                .background(
                    MacTheme.actionFill.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }

    private var dimension: CGSize {
        switch size {
        case .list: CGSize(width: 34, height: 30)
        }
    }

    private var image: NSImage? {
        guard item.kind == .images || item.kind == .screenshots else { return nil }
        return NSImage(contentsOfFile: item.filePath)
    }

    private var symbol: String {
        switch item {
        case .screenshot:
            "camera.viewfinder"
        case .clip(let clip):
            switch clip.kind {
            case .files:
                switch URL(fileURLWithPath: clip.filePath).pathExtension.lowercased() {
                case "pdf": "doc.richtext"
                case "zip", "rar", "7z": "archivebox"
                case "md", "txt": "doc.text"
                default: "doc"
                }
            case .link:
                "link"
            case .color:
                "paintpalette"
            case .image:
                "photo"
            case .text:
                "text.alignleft"
            default:
                "doc"
            }
        }
    }
}

private struct ClipboardActionMenuItems: View {
    let item: ClipboardWorkspaceItem
    let language: AppLanguage
    let onAction: (ClipboardWorkspaceItem, ClipboardWorkspaceAction) -> Void

    var body: some View {
        ForEach(item.secondaryActions, id: \.self) { action in
            if action == .remove {
                Divider()
            }
            actionButton(action)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: ClipboardWorkspaceAction) -> some View {
        if action == .remove {
            Button(role: .destructive) {
                onAction(item, action)
            } label: {
                actionLabel(action)
            }
        } else {
            Button {
                onAction(item, action)
            } label: {
                actionLabel(action)
            }
        }
    }

    private func actionLabel(_ action: ClipboardWorkspaceAction) -> some View {
        Label(
            item.actionTitle(action, language: language),
            systemImage: actionSymbol(action)
        )
    }

    private func actionSymbol(_ action: ClipboardWorkspaceAction) -> String {
        if action == .togglePin, item.pinned {
            return "pin.slash"
        }
        return action.symbol
    }
}

/// 列表和详情共用的时刻文本。
enum ClipboardWorkspaceTime {
    static func text(_ epochSeconds: Int64, language: AppLanguage, now: Date = .now) -> String {
        guard epochSeconds > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let formatter = DateFormatter()
        formatter.locale = language.locale
        if Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }
}
