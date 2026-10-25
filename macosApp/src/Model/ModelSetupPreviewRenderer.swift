#if DEBUG
import AppKit
import SwiftUI

private struct ModelSetupPreviewRoot: View {
    let model: ModelSetupRuntime
    let language = AppLanguage.simplifiedChinese

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space4) {
            PaneHeading(
                title: ContractCopy.copyModelSetupTitle.text(for: language),
                summary: ContractCopy.copyModelSetupSummary.text(for: language)
            )
            ModelSetupInlineCard(model: model, language: language, purpose: .agent)
            ModelSetupSettingsCard(model: model, language: language)
        }
        .padding(HubMetrics.panelPadding)
        .frame(width: HubMetrics.panelWidth, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

private actor PreviewModelInstaller: LocalModelInstalling {
    func status(for tier: LocalModelTier) throws -> LocalModelDownloadStatus {
        throw LocalModelDownloadFailure(code: .sourceUnavailable, detail: "Preview")
    }

    func download(tier: LocalModelTier) async throws -> VerifiedLocalModelPackage {
        throw LocalModelDownloadFailure(code: .sourceUnavailable, detail: "Preview")
    }

    func pause() -> LocalModelDownloadStatus? { nil }
    func reset(tier: LocalModelTier) throws {}
}

@MainActor
enum ModelSetupPreviewRenderer {
    static func render(to path: String) async -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-model-setup-preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = LocalModelPackageRegistryStore(path: root.appendingPathComponent("registry.json"))
        let packages = root.appendingPathComponent("Packages", isDirectory: true)
        let model = ModelSetupRuntime(
            installer: PreviewModelInstaller(),
            registry: registry,
            statusStore: LocalModelDownloadStatusStore(
                roots: LocalModelDownloadRoots(
                    downloadsDirectory: root.appendingPathComponent("Downloads", isDirectory: true),
                    packagesDirectory: packages
                )
            ),
            packagesDirectory: packages
        )
        let previousMode = GlassSurfaceMode.current
        GlassSurfaceMode.current = .material
        defer { GlassSurfaceMode.current = previousMode }

        let size = NSSize(width: HubMetrics.panelWidth, height: 1_220)
        let hosting = NSHostingView(rootView: ModelSetupPreviewRoot(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            window.orderOut(nil)
            return false
        }
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif
