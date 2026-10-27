import Foundation
import SwiftUI

/// Markdown 列表类型。
enum ClipboardMarkdownListStyle: Equatable {
    case ordered
    case unordered
}

/// Markdown 列表中的一项。
struct ClipboardMarkdownListItem: Equatable {
    let ordinal: Int
    let blocks: [ClipboardMarkdownBlock]
}

/// 详情区可渲染的 Markdown 块。
indirect enum ClipboardMarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, content: AttributedString)
    case codeBlock(language: String?, content: String)
    case list(style: ClipboardMarkdownListStyle, items: [ClipboardMarkdownListItem])
    case blockQuote([ClipboardMarkdownBlock])
    case thematicBreak
    case unsupported(AttributedString)
}

/// 一份解析后的 Markdown 文档。`source` 始终保留原始文本。
struct ClipboardMarkdownDocument: Equatable {
    let source: String
    let blocks: [ClipboardMarkdownBlock]
    let usesMarkdown: Bool

    init(source: String) {
        self.source = source

        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let attributed = try? AttributedString(markdown: source, options: options) else {
            blocks = [.paragraph(AttributedString(source))]
            usesMarkdown = false
            return
        }

        let runs = Self.runs(from: attributed)
        blocks = Self.blocks(from: runs)
        usesMarkdown = runs.contains { $0.usesMarkdown }
    }

    private struct Run {
        let content: AttributedString
        let intents: [PresentationIntent.IntentType]
        let usesMarkdown: Bool
    }

    private static func runs(from attributed: AttributedString) -> [Run] {
        let formatting: InlinePresentationIntent = [
            .stronglyEmphasized,
            .emphasized,
            .code,
            .strikethrough,
        ]

        return attributed.runs.map { sourceRun in
            let sourceLink = sourceRun.link
            let sourceImageURL = sourceRun.imageURL
            let inlineIntent = sourceRun.inlinePresentationIntent
            var content = AttributedString(attributed[sourceRun.range])

            for run in Array(content.runs) {
                content[run.range].presentationIntent = nil
                content[run.range].imageURL = nil
                content[run.range].alternateDescription = nil
                if !isAllowedLink(run.link) {
                    content[run.range].link = nil
                }
            }

            let hasNonParagraphBlock = sourceRun.presentationIntent?.components.last.map {
                if case .paragraph = $0.kind { return false }
                return true
            } ?? false
            let hasInlineFormatting = inlineIntent.map {
                !$0.isDisjoint(with: formatting)
            } ?? false
            let usesMarkdown = hasNonParagraphBlock
                || hasInlineFormatting
                || sourceLink != nil
                || sourceImageURL != nil

            return Run(
                content: content,
                intents: sourceRun.presentationIntent?.components ?? [],
                usesMarkdown: usesMarkdown
            )
        }
    }

    private static func blocks(from runs: [Run]) -> [ClipboardMarkdownBlock] {
        groupedByOuterIntent(runs).compactMap(block(from:))
    }

    private static func groupedByOuterIntent(_ runs: [Run]) -> [[Run]] {
        group(runs) { $0.intents.last?.identity }
    }

    private static func groupedByListItem(_ runs: [Run]) -> [[Run]] {
        group(runs) { run in
            guard run.intents.count >= 2 else { return nil }
            if case .listItem = run.intents[run.intents.count - 2].kind {
                return run.intents[run.intents.count - 2].identity
            }
            return nil
        }
    }

    private static func group(
        _ runs: [Run],
        by identity: (Run) -> Int?
    ) -> [[Run]] {
        var groups: [[Run]] = []
        var current: [Run] = []
        var currentIdentity: Int?

        for run in runs {
            let nextIdentity = identity(run)
            if !current.isEmpty, nextIdentity != currentIdentity {
                groups.append(current)
                current = []
            }
            current.append(run)
            currentIdentity = nextIdentity
        }

        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    private static func block(from runs: [Run]) -> ClipboardMarkdownBlock? {
        guard let outer = runs.first?.intents.last else {
            return paragraph(from: runs)
        }

        switch outer.kind {
        case .paragraph:
            return paragraph(from: runs)
        case .header(let level):
            return .heading(level: level, content: content(from: runs))
        case .codeBlock(let languageHint):
            return .codeBlock(language: languageHint, content: codeText(from: runs))
        case .unorderedList:
            return list(from: runs, style: .unordered)
        case .orderedList:
            return list(from: runs, style: .ordered)
        case .blockQuote:
            let inner = runs.map { run in
                Run(
                    content: run.content,
                    intents: Array(run.intents.dropLast()),
                    usesMarkdown: run.usesMarkdown
                )
            }
            return .blockQuote(blocks(from: inner))
        case .thematicBreak:
            return .thematicBreak
        default:
            return .unsupported(content(from: runs))
        }
    }

    private static func paragraph(from runs: [Run]) -> ClipboardMarkdownBlock? {
        let content = content(from: runs)
        return content.characters.isEmpty ? nil : .paragraph(content)
    }

    private static func list(
        from runs: [Run],
        style: ClipboardMarkdownListStyle
    ) -> ClipboardMarkdownBlock? {
        let items = groupedByListItem(runs).compactMap { itemRuns -> ClipboardMarkdownListItem? in
            guard let firstRun = itemRuns.first,
                  firstRun.intents.count >= 2
            else { return nil }

            let itemIntent = firstRun.intents[firstRun.intents.count - 2]
            guard case .listItem(let ordinal) = itemIntent.kind else { return nil }

            let inner = itemRuns.map { run in
                Run(
                    content: run.content,
                    intents: Array(run.intents.dropLast(2)),
                    usesMarkdown: run.usesMarkdown
                )
            }
            return ClipboardMarkdownListItem(ordinal: ordinal, blocks: blocks(from: inner))
        }

        return items.isEmpty ? nil : .list(style: style, items: items)
    }

    private static func content(from runs: [Run]) -> AttributedString {
        runs.reduce(into: AttributedString()) { result, run in
            result.append(run.content)
        }
    }

    private static func codeText(from runs: [Run]) -> String {
        let text = String(content(from: runs).characters)
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    private static func isAllowedLink(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

/// 剪切板文本详情的 Markdown 渲染。
struct ClipboardMarkdownView: View {
    private let document: ClipboardMarkdownDocument

    init(source: String) {
        document = ClipboardMarkdownDocument(source: source)
    }

    var body: some View {
        if document.usesMarkdown, !document.blocks.isEmpty {
            ClipboardMarkdownBlocksView(blocks: document.blocks, spacing: MacTheme.space2)
                .accessibilityElement(children: .contain)
        } else {
            Text(document.source)
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ClipboardMarkdownBlocksView: View {
    let blocks: [ClipboardMarkdownBlock]
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ClipboardMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let content):
            text(content, size: 11, lineSpacing: 3)
        case .heading(let level, let content):
            text(content, size: headingSize(level), weight: .semibold)
                .accessibilityAddTraits(.isHeader)
        case .codeBlock(let language, let content):
            codeBlock(language: language, content: content)
        case .list(let style, let items):
            list(style: style, items: items)
        case .blockQuote(let blocks):
            HStack(alignment: .top, spacing: MacTheme.space2) {
                Capsule()
                    .fill(MacTheme.brand.opacity(0.5))
                    .frame(width: 2)
                    .accessibilityHidden(true)
                ClipboardMarkdownBlocksView(blocks: blocks, spacing: MacTheme.space2)
            }
        case .thematicBreak:
            Rectangle()
                .fill(MacTheme.divider)
                .frame(height: 1)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
        case .unsupported(let content):
            text(content, size: 11, lineSpacing: 3)
        }
    }

    private func text(
        _ content: AttributedString,
        size: CGFloat,
        weight: Font.Weight = .regular,
        lineSpacing: CGFloat = 0
    ) -> some View {
        Text(styledInlineCode(content, size: size))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(MacTheme.textPrimary)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
            .tint(MacTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(
        style: ClipboardMarkdownListStyle,
        items: [ClipboardMarkdownListItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.space1) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: MacTheme.space1) {
                    Text(marker(style: style, ordinal: item.ordinal))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MacTheme.textSecondary)
                        .frame(width: style == .ordered ? 22 : 12, alignment: .trailing)
                        .accessibilityHidden(true)
                    ClipboardMarkdownBlocksView(blocks: item.blocks, spacing: MacTheme.space1)
                }
            }
        }
    }

    private func codeBlock(language: String?, content: String) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.space1) {
            if let language, !language.isEmpty, language != "<none>" {
                Text(language)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(MacTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .scrollIndicators(.never)
        }
        .padding(MacTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MacTheme.elevated.opacity(0.72),
            in: RoundedRectangle(cornerRadius: MacTheme.smallRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.smallRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
    }

    private func styledInlineCode(_ content: AttributedString, size: CGFloat) -> AttributedString {
        var styled = content
        for run in styled.runs {
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                continue
            }
            styled[run.range].font = .system(size: size, design: .monospaced)
            styled[run.range].backgroundColor = MacTheme.textSecondary.opacity(0.14)
        }
        return styled
    }

    private func marker(style: ClipboardMarkdownListStyle, ordinal: Int) -> String {
        switch style {
        case .ordered:
            "\(max(1, ordinal))."
        case .unordered:
            "•"
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 20
        case 2: 18
        case 3: 16
        case 4: 14
        case 5: 12.5
        default: 11.5
        }
    }
}
