import AppKit
import SwiftUI
import kmpDomain

/// 文件区筛选。Kotlin 的 `FileAreaFilter` 负责数据筛选，这个 Swift 枚举只负责菜单状态。
enum FileAreaFilterChoice: String, CaseIterable, Identifiable {
    case all
    case screenshots
    case files
    case text
    case transfers

    var id: String { rawValue }

    var filter: FileAreaFilter {
        switch self {
        case .all: FileAreaFilter.all
        case .screenshots: FileAreaFilter.screenshots
        case .files: FileAreaFilter.files
        case .text: FileAreaFilter.text
        case .transfers: FileAreaFilter.transfers
        }
    }

    var title: LocalizedCopy {
        switch self {
        case .all: ContractCopy.copyHubFilesFilterAll
        case .screenshots: ContractCopy.copyHubFilesFilterScreenshots
        case .files: ContractCopy.copyHubFilesFilterFiles
        case .text: ContractCopy.copyHubFilesFilterText
        case .transfers: ContractCopy.copyHubFilesFilterTransfers
        }
    }
}

/// 文件区能执行的动作。动作由截图运行时或工作区运行时执行，视图只描述菜单项。
enum FileAreaAction: Hashable {
    case open
    case copy
    case copyText
    case markup
    case saveToWorkspace
    case reveal
    case pin(Bool)
    case remove

    var title: LocalizedCopy {
        switch self {
        case .open: ContractCopy.copyHubFilesActionOpen
        case .copy: ContractCopy.copyHubFilesActionCopy
        case .copyText: ContractCopy.copyHubFilesActionCopyText
        case .markup: ContractCopy.copyHubFilesActionMarkup
        case .saveToWorkspace: ContractCopy.copyHubFilesActionSaveToWorkspace
        case .reveal: ContractCopy.copyHubFilesActionReveal
        case .pin(let pinned):
            pinned ? ContractCopy.copyHubFilesActionUnpin : ContractCopy.copyHubFilesActionPin
        case .remove: ContractCopy.copyHubFilesActionRemove
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .copy: "doc.on.doc"
        case .copyText: "text.alignleft"
        case .markup: "pencil.tip.crop.circle"
        case .saveToWorkspace: "tray.and.arrow.down"
        case .reveal: "folder"
        case .pin: "pin"
        case .remove: "trash"
        }
    }

    var isDestructive: Bool { self == .remove }
    var separatorBefore: Bool { isDestructive }
}

/// 文件区的固定几何。来源是 `component/file-area` 与各子组件合同尺寸。
enum FileAreaMetrics {
    static let areaHeight: CGFloat = 538
    static let toolbarHeight: CGFloat = 28
    static let toolbarGap: CGFloat = 12
    static let focusHeight: CGFloat = 176
    static let quietTileHeight: CGFloat = 146
    static let quietPreviewHeight: CGFloat = 104
    static let quietColumns = 4
    static let quietGap: CGFloat = 14
    static let stageGap: CGFloat = 16
    static let contentCornerRadius: CGFloat = 12
    static let tileCornerRadius: CGFloat = 9

    /// 四列网格的单格宽度。960 点面板对应合同里的 217.5 点。
    static func quietTileWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, (containerWidth - quietGap * CGFloat(quietColumns - 1)) / CGFloat(quietColumns))
    }
}

/// 文件条目的展示文案和动作顺序。这里是纯规则，便于单测。
enum FileAreaPresentation {
    static func typeTitle(for item: FileAreaItem, language: AppLanguage) -> String {
        switch item.kind {
        case FileAreaKind.screenshot: ContractCopy.copyHubFilesFilterScreenshots.text(for: language)
        case FileAreaKind.image: ContractCopy.copyHubFilesKindImage.text(for: language)
        case FileAreaKind.text: ContractCopy.copyHubFilesFilterText.text(for: language)
        case FileAreaKind.pdf: ContractCopy.copyHubFilesKindPdf.text(for: language)
        case FileAreaKind.audio: ContractCopy.copyHubFilesKindAudio.text(for: language)
        default: ContractCopy.copyHubFilesFilterFiles.text(for: language)
        }
    }

    /// 排序后的完整右键菜单。删除永远在最后，并在它前面加分隔线。
    static func contextActions(for item: FileAreaItem) -> [FileAreaAction] {
        var actions: [FileAreaAction] = []
        let capabilities = item.capabilities

        if capabilities.canCopy {
            actions.append(.copy)
        } else if capabilities.canCopyText {
            actions.append(.copyText)
        }
        if capabilities.canOpen { actions.append(.open) }
        if capabilities.canMarkup { actions.append(.markup) }
        if capabilities.canSaveToWorkspace { actions.append(.saveToWorkspace) }
        if capabilities.canReveal { actions.append(.reveal) }
        if capabilities.canPin { actions.append(.pin(item.pinned)) }
        if capabilities.canRemove { actions.append(.remove) }
        return actions
    }

    /// 焦点卡最多显示三个主动作。打开总是主操作。
    static func focusActions(for item: FileAreaItem) -> [FileAreaAction] {
        var actions: [FileAreaAction] = []
        if item.capabilities.canOpen { actions.append(.open) }
        if item.capabilities.canCopy {
            actions.append(.copy)
        } else if item.capabilities.canCopyText {
            actions.append(.copyText)
        }
        if item.capabilities.canMarkup { actions.append(.markup) }
        if item.capabilities.canReveal { actions.append(.reveal) }
        if item.capabilities.canPin && actions.count < 3 { actions.append(.pin(item.pinned)) }
        return Array(actions.prefix(3))
    }

    /// 安静格子只显示一个快捷动作。
    static func quickAction(for item: FileAreaItem) -> FileAreaAction? {
        if item.capabilities.canOpen { return .open }
        if item.capabilities.canCopyText { return .copyText }
        if item.capabilities.canCopy { return .copy }
        if item.capabilities.canMarkup { return .markup }
        return nil
    }

    /// 元数据：大小与加入时间。大小优先用投影值，截图由文件属性补齐。
    static func metadata(for item: FileAreaItem, url: URL?, language: AppLanguage) -> String {
        var parts: [String] = []
        let bytes = item.byteSize > 0 ? item.byteSize : fileSize(url)
        if bytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        if item.createdAtEpochSeconds > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(item.createdAtEpochSeconds))
            parts.append(
                date.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(language.locale)
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    /// 状态文字。颜色不是唯一线索，所以每个状态都有文字。
    static func statusTitle(for item: FileAreaItem, language: AppLanguage) -> String? {
        switch item.availability {
        case FileAreaAvailability.remote: ContractCopy.copyHubFilesStateOnOtherDevice.text(for: language)
        case FileAreaAvailability.fetching: ContractCopy.copyHubFilesStateFetching.text(for: language)
        case FileAreaAvailability.unavailable: ContractCopy.copyHubFilesStateUnavailable.text(for: language)
        default: nil
        }
    }

    /// 焦点卡第二行。远端条目省略本机文件大小，避免让索引看起来像已下载。
    static func subtitle(for item: FileAreaItem, url: URL?, language: AppLanguage) -> String {
        let origin = item.originDeviceId.isEmpty
            ? ContractCopy.copyHubFilesStateLocal.text(for: language)
            : item.originDeviceId
        let detail = statusTitle(for: item, language: language)
            ?? metadata(for: item, url: url, language: language)
        return detail.isEmpty ? origin : "\(origin) · \(detail)"
    }

    static func accessibilityValue(for item: FileAreaItem, url: URL?, language: AppLanguage) -> String {
        let type = typeTitle(for: item, language: language)
        let subtitle = subtitle(for: item, url: url, language: language)
        return "\(type), \(subtitle)"
    }

    /// 搜索同时覆盖名称、来源和类别。筛选仍由 KMP 投影执行。
    static func matches(item: FileAreaItem, query: String, language: AppLanguage) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let fields = [
            item.displayName,
            item.originDeviceId,
            typeTitle(for: item, language: language),
            statusTitle(for: item, language: language) ?? "",
        ]
        return fields.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private static func fileSize(_ url: URL?) -> Int64 {
        guard let url,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return Int64(size)
    }
}

/// 文件区上方的唯一工具行：筛选、数量、实时状态和加入。
struct FileFilterMenuView: View {
    let selection: FileAreaFilterChoice
    let counts: [FileAreaFilterChoice: Int]
    let language: AppLanguage
    let onSelect: (FileAreaFilterChoice) -> Void

    var body: some View {
        Menu {
            ForEach(FileAreaFilterChoice.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label {
                        Text("\(option.title.text(for: language))   \(counts[option, default: 0])")
                    } icon: {
                        if option == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.title.text(for: language))
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .foregroundStyle(MacTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: FileAreaMetrics.toolbarHeight)
            .background(
                MacTheme.elevated.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(selection.title.text(for: language))
        .accessibilityValue("\(counts[selection, default: 0])")
    }
}

/// 空状态与无匹配状态。没有结果时不显示常驻工具行。
struct FileEmptyStateView: View {
    enum State {
        case empty
        case noMatch
    }

    let state: State
    let language: AppLanguage
    let onImport: () -> Void
    let onNewText: () -> Void
    let onClearFilter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: state == .empty ? "plus" : "magnifyingglass")
                .font(.system(size: state == .empty ? 22 : 21, weight: .light))
                .foregroundStyle(state == .empty ? MacTheme.textPrimary : MacTheme.textSecondary)
                .frame(width: 46, height: 46)
                .background(
                    MacTheme.elevated.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .padding(.top, 11)

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
                .padding(.top, 4)

            HStack(spacing: 7) {
                if state == .empty {
                    FileMiniButton(
                        title: ContractCopy.copyHubFilesActionImport.text(for: language),
                        primary: true,
                        action: onImport
                    )
                    FileMiniButton(
                        title: ContractCopy.copyHubFilesActionNewText.text(for: language),
                        primary: false,
                        action: onNewText
                    )
                } else {
                    FileMiniButton(
                        title: ContractCopy.copyHubFilesActionClearFilter.text(for: language),
                        primary: false,
                        action: onClearFilter
                    )
                }
            }
            .padding(.top, 13)

            if state == .empty {
                Text("⌘O  \(ContractCopy.copyHubFilesActionImport.text(for: language))     ⌘N  \(ContractCopy.copyHubFilesActionNewText.text(for: language))")
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.disabledText)
                    .padding(.top, 11)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private var title: String {
        state == .empty
            ? ContractCopy.copyHubFilesEmptyTitle.text(for: language)
            : ContractCopy.copyHubFilesNoMatchTitle.text(for: language)
    }

    private var hint: String {
        state == .empty
            ? ContractCopy.copyHubFilesEmptyHint.text(for: language)
            : ContractCopy.copyHubFilesNoMatchHint.text(for: language)
    }
}

/// 原生右键菜单的内容。删除动作在最后，并使用独立的破坏性样式与分隔线。
struct FileContextMenuView: View {
    let item: FileAreaItem
    let language: AppLanguage
    let onAction: (FileAreaAction) -> Void

    var body: some View {
        ForEach(Array(FileAreaPresentation.contextActions(for: item).enumerated()), id: \.offset) { _, action in
            if action.separatorBefore {
                Divider()
            }
            if action.isDestructive {
                Button(role: .destructive) {
                    onAction(action)
                } label: {
                    Label(action.title.text(for: language), systemImage: action.symbol)
                }
            } else {
                Button {
                    onAction(action)
                } label: {
                    Label(action.title.text(for: language), systemImage: action.symbol)
                }
            }
        }
    }
}

/// 唯一的详细焦点卡。左侧是内容预览，右侧只保留一个标题、一行元数据和最多三个动作。
struct FileFocusCardView: View {
    let item: FileAreaItem
    let url: URL?
    let language: AppLanguage
    let onAction: (FileAreaAction) -> Void

    @State private var hovered = false
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                FilePreviewView(item: item, url: url)
                    .frame(width: geometry.size.width * 0.43)
                    .overlay(alignment: .topLeading) {
                        if item.pinned {
                            FilePinnedBadge(language: language)
                        }
                    }
                    .overlay {
                        FileStatusOverlay(item: item, language: language)
                    }

                details
                    .frame(width: geometry.size.width * 0.57)
            }
            .clipShape(RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous))
            .background(
                (hovered ? MacTheme.elevated.opacity(0.94) : MacTheme.material.opacity(0.86)),
                in: RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous)
                    .strokeBorder(
                        keyboardFocused ? MacTheme.focusRing : MacTheme.divider.opacity(0.68),
                        lineWidth: keyboardFocused ? 2 : 0.7
                    )
            )
        }
        .frame(height: FileAreaMetrics.focusHeight)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { onAction(.open) }
        .contextMenu {
            FileContextMenuView(item: item, language: language, onAction: onAction)
        }
        .fileDragSource(url: url, enabled: item.capabilities.canDragOut)
        .focusable()
        .focused($keyboardFocused)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(FileAreaPresentation.accessibilityValue(for: item, url: url, language: language))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(FileAreaPresentation.typeTitle(for: item, language: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: 0)
                Menu {
                    FileContextMenuView(item: item, language: language, onAction: onAction)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(ContractCopy.copyHubFilesActionMore.text(for: language))
            }

            Text(item.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(2)
                .padding(.top, 5)

            Text(FileAreaPresentation.subtitle(for: item, url: url, language: language))
                .font(.system(size: 9.5))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
                .padding(.top, 4)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(Array(FileAreaPresentation.focusActions(for: item).enumerated()), id: \.offset) { index, action in
                    FileMiniButton(
                        title: action.title.text(for: language),
                        primary: index == 0
                    ) {
                        onAction(action)
                    }
                }
            }

            Text("↵  \(ContractCopy.copyHubFilesActionOpen.text(for: language))   ⌘C  \(copyShortcut)   ⌘⌫  \(ContractCopy.copyHubFilesActionRemove.text(for: language))")
                .font(.system(size: 8))
                .foregroundStyle(MacTheme.disabledText)
                .padding(.top, 7)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }

    private var copyShortcut: String {
        item.capabilities.canCopyText
            ? ContractCopy.copyHubFilesActionCopyText.text(for: language)
            : ContractCopy.copyHubFilesActionCopy.text(for: language)
    }
}

/// 安静网格里的一件内容。默认不显示动作，悬停时只出现一个快捷动作和菜单按钮。
struct FileQuietTileView: View {
    let item: FileAreaItem
    let url: URL?
    let language: AppLanguage
    let onSelect: () -> Void
    let onAction: (FileAreaAction) -> Void

    @State private var hovered = false
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            preview
            Text(item.displayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .topLeading)
            Text(statusText)
                .font(.system(size: 8.3))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10, alignment: .topLeading)
        }
        .frame(height: FileAreaMetrics.quietTileHeight, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2) { onAction(.open) }
        .contextMenu {
            FileContextMenuView(item: item, language: language, onAction: onAction)
        }
        .fileDragSource(url: url, enabled: item.capabilities.canDragOut)
        .focusable()
        .focused($keyboardFocused)
        .overlay(
            RoundedRectangle(cornerRadius: FileAreaMetrics.tileCornerRadius, style: .continuous)
                .strokeBorder(keyboardFocused ? MacTheme.focusRing : .clear, lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(FileAreaPresentation.accessibilityValue(for: item, url: url, language: language))
        .accessibilityAddTraits(.isButton)
    }

    private var preview: some View {
        FilePreviewView(item: item, url: url)
            .frame(maxWidth: .infinity)
            .frame(height: FileAreaMetrics.quietPreviewHeight)
            .clipShape(RoundedRectangle(cornerRadius: FileAreaMetrics.tileCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FileAreaMetrics.tileCornerRadius, style: .continuous)
                    .strokeBorder(
                        hovered ? MacTheme.divider.opacity(0.72) : MacTheme.divider.opacity(0.5),
                        lineWidth: hovered ? 1 : 0.5
                    )
            )
            .overlay(alignment: .topLeading) {
                if item.pinned {
                    FilePinnedBadge(language: language)
                }
            }
            .overlay {
                FileStatusOverlay(item: item, language: language, compact: true)
            }
            .overlay(alignment: .bottom) {
                if hovered {
                    hoverActions
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                }
            }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            if let action = FileAreaPresentation.quickAction(for: item) {
                Button {
                    onAction(action)
                } label: {
                    Text(action.title.text(for: language))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            MacTheme.elevated.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }

            Menu {
                FileContextMenuView(item: item, language: language, onAction: onAction)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .frame(width: 21, height: 19)
                    .background(
                        MacTheme.elevated.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(ContractCopy.copyHubFilesActionMore.text(for: language))
        }
        .frame(height: 25)
        .padding(.vertical, 3)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.52)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var statusText: String {
        if let status = FileAreaPresentation.statusTitle(for: item, language: language) {
            return status
        }
        return FileAreaPresentation.metadata(for: item, url: url, language: language)
    }

    private var statusColor: Color {
        switch item.availability {
        case FileAreaAvailability.remote, FileAreaAvailability.fetching: MacTheme.brand
        default: MacTheme.textSecondary
        }
    }
}

/// 内容预览。截图与图片使用真实缩略图，其它类型使用轻量图形，不读取无关正文。
struct FilePreviewView: View {
    let item: FileAreaItem
    let url: URL?

    var body: some View {
        switch item.kind {
        case FileAreaKind.screenshot, FileAreaKind.image:
            imagePreview
        case FileAreaKind.text:
            textPreview
        case FileAreaKind.pdf:
            documentPreview(label: "PDF", color: Color(red: 0.84, green: 0, blue: 0.08))
        case FileAreaKind.audio:
            audioPreview
        default:
            documentPreview(label: url?.pathExtension.uppercased() ?? "FILE", color: MacTheme.brand)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let url, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            documentPreview(label: "IMG", color: MacTheme.brand)
        }
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TEXT")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(red: 0.6, green: 0.47, blue: 0.16))
            Text(Self.textPreview(url: url))
                .font(.system(size: 9.5))
                .foregroundStyle(Color(red: 0.19, green: 0.18, blue: 0.15))
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Color(red: 1, green: 0.98, blue: 0.91))
    }

    private func documentPreview(label: String, color: Color) -> some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.97)
            VStack(spacing: 5) {
                Image(systemName: item.kind == FileAreaKind.pdf ? "doc.richtext" : "doc")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
    }

    private var audioPreview: some View {
        ZStack {
            Color(red: 0.95, green: 0.94, blue: 0.98)
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array([12, 24, 38, 56, 31, 46, 22, 14].enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(Color(red: 0.46, green: 0.33, blue: 0.72))
                        .frame(width: 4, height: height)
                }
            }
        }
    }

    /// 只读前 2 KB。预览不为了几行字扫描大文件。
    private static func textPreview(url: URL?) -> String {
        guard let url,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 2_048)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// 传输状态只叠加在原条目上，不复制卡片。
private struct FileStatusOverlay: View {
    let item: FileAreaItem
    let language: AppLanguage
    var compact = false

    var body: some View {
        switch item.availability {
        case FileAreaAvailability.remote:
            fullStatus(
                title: ContractCopy.copyHubFilesStateOnOtherDevice.text(for: language),
                detail: compact ? "" : ContractCopy.copyHubFilesActionDownload.text(for: language),
                background: .black.opacity(0.58)
            )
        case FileAreaAvailability.fetching:
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(ContractCopy.copyHubFilesStateFetching.text(for: language))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.black.opacity(compact ? 0.42 : 0.72))
            }
        case FileAreaAvailability.unavailable:
            fullStatus(
                title: ContractCopy.copyHubFilesStateUnavailable.text(for: language),
                detail: compact ? "" : ContractCopy.copyHubFilesErrorMissing.text(for: language),
                background: .black.opacity(0.7)
            )
        default:
            EmptyView()
        }
    }

    private func fullStatus(title: String, detail: String, background: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 7.5))
                    .opacity(0.78)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }
}

private struct FilePinnedBadge: View {
    let language: AppLanguage

    var body: some View {
        Text(ContractCopy.copyHubFilesActionPin.text(for: language))
            .font(.system(size: 7.5, weight: .medium))
            .foregroundStyle(MacTheme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                MacTheme.elevated.opacity(0.86),
                in: Capsule()
            )
            .padding(6)
    }
}

/// 文件区的小动作按钮。高度 24 点，视觉上低于页标题行的常规按钮。
struct FileMiniButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: primary ? .medium : .regular))
                .foregroundStyle(
                    primary
                        ? MacTheme.color(ContractColors.tokenColorTextOnAccent)
                        : MacTheme.textPrimary
                )
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    primary ? MacTheme.brand : MacTheme.elevated.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 只为真实文件挂拖出。远端或不可用条目不会启动空拖拽。
private struct FileDragSourceModifier: ViewModifier {
    let url: URL?
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, let url {
            content.onDrag {
                NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
        } else {
            content
        }
    }
}

private extension View {
    func fileDragSource(url: URL?, enabled: Bool) -> some View {
        modifier(FileDragSourceModifier(url: url, enabled: enabled))
    }
}
