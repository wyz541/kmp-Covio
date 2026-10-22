import AppKit
import SwiftUI
import UniformTypeIdentifiers
import kmpDomain

/// 文件页签。工作区条目的列表。
///
/// 一行一条条目。左边是类型图标与名称，右边是这一条的动作。
/// 放入文件与清理过期在页标题行右端，见 [FilesHeadingActions]。
/// 失败与说明留在页内，因为它属于内容。
///
/// 内容只读工作区的索引与内容目录，不引用用户的原文件路径。
struct FilesTabView: View {
    let workspace: WorkspaceRuntime
    let autoNaming: AutoNamingRuntime
    let policy: FileNamingPolicy
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            if autoNaming.stage == .idle {
                content

                if let notice {
                    MacAlert(message: notice, kind: noticeKind)
                }
            } else {
                AutoNamingPreviewView(runtime: autoNaming, language: language)
            }
        }
        // 内边距由内容列给，这里不再加一层。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            intake(providers)
        }
    }

    @ViewBuilder
    private var content: some View {
        if workspace.entries.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: MacTheme.space2) {
            Image(systemName: "folder")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(ContractCopy.copyHubFilesEmpty.text(for: language))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(ContractCopy.copyHubFilesHint.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: MacTheme.space2) {
                ForEach(workspace.entries, id: \.entryId) { entry in
                    FilesRow(
                        entry: entry,
                        hasContent: workspace.contentURL(entry.entryId) != nil,
                        language: language,
                        onOpen: { workspace.open(entry.entryId) },
                        onReveal: { workspace.reveal(entry.entryId) },
                        onPin: { workspace.togglePin(entry.entryId) },
                        onRemove: { workspace.remove(entry.entryId) }
                    )
                }
            }
            .padding(MacTheme.space2)
        }
        .frame(height: Self.listHeight)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
    }

    /// 当前要提示的那一条。错误优先于说明。
    private var notice: String? {
        if let error = workspace.errorMessage {
            return error.text(for: language)
        }
        if let info = workspace.infoMessage {
            return info.text(for: language)
        }
        return nil
    }

    private var noticeKind: MacAlertKind {
        workspace.errorMessage == nil ? .info : .error
    }

    /// 接收拖进来的文件。
    ///
    /// 只取 `fileURL`。读取在后台，读完回主线程放入。
    /// 不等读取结果：等待会卡住主线程的绘图。
    private func intake(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                guard let url = FilesTabView.fileURL(from: item) else { return }
                Task { @MainActor in
                    workspace.intake(urls: [url])
                }
            }
        }
        return accepted
    }

    /// 从拖放项里取出文件地址。系统两种都给过：URL 与 data。
    private nonisolated static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }

    /// 列表高度。`HubMetrics.filesPageContentHeight` 按它相加。
    nonisolated static let listHeight: CGFloat = 268

    /// 提示条的高度：`MacAlert` 的上下内边距加一行 11 点文字。
    nonisolated static let noticeHeight: CGFloat = 40

    /// 列表与提示条之间的间距。`HubMetrics` 按它相加。
    nonisolated static let noticeGap: CGFloat = MacTheme.space3
}

/// 文件页的胶囊动作：放入文件、清理过期、占用。
struct FilesHeadingActions: View {
    let workspace: WorkspaceRuntime
    let autoNaming: AutoNamingRuntime
    let policy: FileNamingPolicy
    let language: AppLanguage

    var body: some View {
        HStack(spacing: MacTheme.space2) {
            MacButton(
                title: ContractCopy.copyAutoNamingActionAutoName.text(for: language),
                kind: .primary,
                isEnabled: autoNaming.stage == .idle && !autoNaming.busy,
                action: chooseAutoNameFiles
            )
            MacButton(
                title: ContractCopy.copyHubFilesActionImport.text(for: language),
                kind: .plain,
                action: chooseFiles
            )
            MacButton(
                title: ContractCopy.copyHubFilesActionSweep.text(for: language),
                isEnabled: !workspace.entries.isEmpty
            ) {
                workspace.sweep()
            }
            MacStatusLine(text: statusText)
        }
    }

    /// 占用与上限。文案取合同，数字与单位由 `ByteCountFormatter` 给。
    private var statusText: String {
        let used = ByteCountFormatter.string(fromByteCount: workspace.totalBytes, countStyle: .file)
        let limit = ByteCountFormatter.string(fromByteCount: workspace.policy.maxTotalBytes, countStyle: .file)
        return "\(ContractCopy.copyHubFilesUsage.text(for: language)) \(used) / \(limit)"
    }

    /// 选择要自动命名的原始文件。文件留在原目录。
    private func chooseAutoNameFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        Task {
            await autoNaming.analyze(urls: panel.urls, policy: policy)
        }
    }

    /// 打开系统文件选择面板。多选。
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        workspace.intake(urls: panel.urls)
    }
}

/// 工作区的一条条目。
private struct FilesRow: View {
    let entry: WorkspaceEntry
    let hasContent: Bool
    let language: AppLanguage
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onPin: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MacTheme.space3) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: Self.thumb, height: Self.thumb)

            details
            Spacer(minLength: 0)
            controls
        }
        .padding(MacTheme.space2)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.smallRadius, style: .continuous)
                .fill(MacTheme.elevated)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: MacTheme.space1) {
                if entry.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(MacTheme.brand)
                }
                Text(entry.displayName.isEmpty ? entry.entryId : entry.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(MacTheme.textPrimary)
            }
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var controls: some View {
        HStack(spacing: MacTheme.space1) {
            MacButton(
                title: ContractCopy.copyHubFilesActionOpen.text(for: language),
                kind: .plain,
                isEnabled: hasContent,
                action: onOpen
            )
            MacButton(
                title: ContractCopy.copyHubFilesActionReveal.text(for: language),
                kind: .plain,
                isEnabled: hasContent,
                action: onReveal
            )
            MacButton(
                title: (entry.pinned ? ContractCopy.copyHubFilesActionUnpin : ContractCopy.copyHubFilesActionPin)
                    .text(for: language),
                kind: .plain,
                action: onPin
            )
            MacButton(
                title: ContractCopy.copyHubFilesActionRemove.text(for: language),
                kind: .plain,
                action: onRemove
            )
        }
    }

    /// 大小、过期时间与来源设备。三段之间用间隔号分开。
    ///
    /// 本机没有内容时改为说明这一条只剩索引。
    private var subtitle: String {
        var parts: [String] = []
        if hasContent {
            parts.append(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file))
            if entry.expiresAtEpochSeconds > 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(entry.expiresAtEpochSeconds))
                parts.append(date.formatted(date: .abbreviated, time: .omitted))
            }
        } else {
            parts.append(ContractCopy.copyHubFilesErrorMissing.text(for: language))
        }
        if !entry.originDeviceId.isEmpty {
            parts.append(entry.originDeviceId)
        }
        return parts.joined(separator: " · ")
    }

    /// 类型图标。只按类别，不看扩展名。
    private var symbol: String {
        if entry.kind == WorkspaceKind.image { return "photo" }
        if entry.kind == WorkspaceKind.audio { return "waveform" }
        if entry.kind == WorkspaceKind.pdf { return "doc.richtext" }
        if entry.kind == WorkspaceKind.text { return "text.alignleft" }
        return "doc"
    }

    private static let thumb: CGFloat = 30
}
