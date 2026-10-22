import AppKit
import SwiftUI
import XCTest
import kmpDomain
@testable import Covio

/// 为项目说明书生成真实 SwiftUI 组件的证据图。
///
/// 产物写到 `build/guide-evidence/`。测试只渲染现有产品组件，
/// 不改运行时的配置、截图目录或系统设置。
@MainActor
final class GuideEvidenceRenderTests: XCTestCase {
    func testRenderPilotComponentEvidence() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outputDirectory = repositoryRoot.appendingPathComponent("build/guide-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try await render(
            GuideButtonEvidenceView(),
            size: NSSize(width: 720, height: 180),
            output: outputDirectory.appendingPathComponent("button.png")
        )

        let sourceImage = outputDirectory.appendingPathComponent("screenshot-card-source.png")
        try makeScreenshotSource(repositoryRoot: repositoryRoot).write(to: sourceImage, options: .atomic)
        try await render(
            GuideScreenshotCardEvidenceView(path: sourceImage.path),
            size: NSSize(width: 640, height: 420),
            output: outputDirectory.appendingPathComponent("screenshot-card.png"),
            waitMilliseconds: 700
        )
    }

    private func render<Content: View>(
        _ content: Content,
        size: NSSize,
        output: URL,
        waitMilliseconds: UInt64 = 250
    ) async throws {
        let root = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        root.frame = NSRect(origin: .zero, size: size)
        root.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: root.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        window.orderFront(nil)
        root.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(waitMilliseconds))
        root.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1_000)
        try data.write(to: output, options: .atomic)
        window.orderOut(nil)
        window.contentView = nil
    }

    private func makeScreenshotSource(repositoryRoot: URL) throws -> Data {
        let trayEvidence = repositoryRoot.appendingPathComponent(
            "guide/src/content/docs/components/tray-icon/evidence/2026-10-22__macbook-pro__macos-27.0.1__dark__EV-TRAY-001.png"
        )
        let imageURL = FileManager.default.fileExists(atPath: trayEvidence.path)
            ? trayEvidence
            : repositoryRoot.appendingPathComponent("assets/Covio.png")
        let image = try XCTUnwrap(NSImage(contentsOf: imageURL))
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private struct GuideButtonEvidenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MacButton(title: "主要操作", kind: .primary) {}
                MacButton(title: "次要操作", kind: .secondary) {}
                MacButton(title: "清除", kind: .plain) {}
            }

            HStack(spacing: 12) {
                MacButton(title: "不可用", isEnabled: false) {}
                MacButton(title: "不可用主操作", kind: .primary, isEnabled: false) {}
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

@MainActor
private struct GuideScreenshotCardEvidenceView: View {
    let path: String

    var body: some View {
        ZStack {
            MacTheme.canvas
            ScreenshotCardView(
                item: ShelfItem(path: path, addedAtEpochSeconds: 0),
                index: 0,
                reduceMotion: true,
                language: .simplifiedChinese,
                flying: false,
                onCopy: {},
                onPreview: {},
                onMarkup: {},
                onRemove: {},
                onDragBegin: { _, _ in },
                onSaveToWorkspace: {}
            )
            .scaleEffect(2.35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
