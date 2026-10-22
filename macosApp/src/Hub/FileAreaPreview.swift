#if DEBUG
import AppKit
import SwiftUI
import kmpDomain

/// 文件区的确定性调试画面。只用于本地视觉验收，不参与发布构建。
struct FileAreaShowcaseView: View {
    let contentWidth: CGFloat
    let language: AppLanguage

    @State private var selection: FileAreaFilterChoice = .all
    @State private var selectedID = "text"

    var body: some View {
        VStack(alignment: .leading, spacing: FileAreaMetrics.toolbarGap) {
            HStack(spacing: 10) {
                FileFilterMenuView(
                    selection: selection,
                    counts: Dictionary(uniqueKeysWithValues: FileAreaFilterChoice.allCases.map { ($0, count(for: $0)) }),
                    language: language
                ) { choice in
                    selection = choice
                    selectedID = filteredItems.first?.id ?? ""
                }
                Text("\(filteredItems.count) \(ContractCopy.copyHubFilesCountItems.text(for: language))")
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.textSecondary)
                HStack(spacing: 5) {
                    Circle().fill(MacTheme.brand).frame(width: 5, height: 5)
                    Text("\(activeTransferCount) \(ContractCopy.copyHubFilesStatusActive.text(for: language))")
                        .font(.system(size: 9))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(
                        MacTheme.elevated.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .frame(height: FileAreaMetrics.toolbarHeight)

            if let selectedItem {
                FileFocusCardView(
                    item: selectedItem,
                    url: nil,
                    language: language,
                    onAction: { _ in }
                )
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 72), spacing: FileAreaMetrics.quietGap, alignment: .top),
                    count: FileAreaMetrics.quietColumns
                ),
                alignment: .leading,
                spacing: FileAreaMetrics.quietGap
            ) {
                ForEach(quietItems, id: \.id) { item in
                    FileQuietTileView(
                        item: item,
                        url: nil,
                        language: language,
                        onSelect: { selectedID = item.id },
                        onAction: { _ in }
                    )
                }
            }
            .padding(.top, FileAreaMetrics.stageGap)
        }
        .padding(.horizontal, 24)
        .frame(width: contentWidth + 48, height: FileAreaMetrics.areaHeight, alignment: .topLeading)
        .background(Color(red: 0.68, green: 0.64, blue: 0.71))
    }

    private func count(for filter: FileAreaFilterChoice) -> Int {
        FileAreaProjection.shared.filter(items: items, filter: filter.filter).count
    }

    private var filteredItems: [FileAreaItem] {
        FileAreaProjection.shared.filter(items: items, filter: selection.filter)
    }

    private var selectedItem: FileAreaItem? {
        filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first
    }

    private var quietItems: [FileAreaItem] {
        guard let selectedItem else { return filteredItems }
        return filteredItems.filter { $0.id != selectedItem.id }
    }

    private var activeTransferCount: Int {
        items.count {
            $0.availability == FileAreaAvailability.remote ||
                $0.availability == FileAreaAvailability.fetching
        }
    }

    private var items: [FileAreaItem] {
        [
            item("text", .text, "发布说明草稿.txt", pinned: true),
            item("shot-1", .screenshot, "截屏 2026-10-21 14.32.png"),
            item("shot-2", .screenshot, "截屏 2026-10-21 14.28.png"),
            item("pdf", .pdf, "Covio Design Contract v1.3.pdf"),
            item("remote", .image, "iPhone 参考.heic", availability: .remote),
            item("fetching", .file, "交互录屏 03.mov", availability: .fetching),
            item("audio", .audio, "旧录音.m4a", availability: .unavailable),
            item("doc", .file, "客户反馈.zip"),
        ]
    }

    private func item(
        _ id: String,
        _ kind: FileAreaKind,
        _ name: String,
        pinned: Bool = false,
        availability: FileAreaAvailability = FileAreaAvailability.local
    ) -> FileAreaItem {
        let local = availability == FileAreaAvailability.local
        let screenshot = kind == FileAreaKind.screenshot
        let text = kind == FileAreaKind.text
        return FileAreaItem(
            id: id,
            origin: screenshot ? FileAreaOrigin.screenshot : FileAreaOrigin.workspace,
            itemId: id,
            displayName: name,
            kind: kind,
            createdAtEpochSeconds: 1_792_560_000,
            byteSize: screenshot ? 1_887_437 : 1_024,
            originDeviceId: availability == FileAreaAvailability.local ? "" : "iPhone",
            expiresAtEpochSeconds: 0,
            availability: availability,
            pinned: pinned,
            capabilities: FileAreaCapabilities(
                canOpen: local,
                canCopy: local && !text,
                canCopyText: local && text,
                canMarkup: screenshot,
                canDragOut: local,
                canSaveToWorkspace: screenshot,
                canReveal: local && !screenshot,
                canPin: local && !screenshot,
                canRemove: true,
                canDownload: availability == FileAreaAvailability.remote,
                canCancel: availability == FileAreaAvailability.fetching
            )
        )
    }
}

@MainActor
enum FileAreaPreviewRenderer {
    static func render(panelWidth: CGFloat, to path: String) -> Bool {
        let language = AppLanguage.simplifiedChinese
        let contentWidth = panelWidth - HubMetrics.panelPadding * 2
        let view = FileAreaShowcaseView(contentWidth: contentWidth, language: language)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif
