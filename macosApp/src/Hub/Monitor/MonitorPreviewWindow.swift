#if DEBUG
import AppKit
import SwiftUI

/// 调试构建的独立监控窗口。
///
/// 全量运行时会在系统唤醒回调里执行已有逻辑。这个入口绕过运行时，
/// 只用来检查 `MonitorTabView` 的真实布局和读数。
struct MonitorPreviewRoot: View {
    private let language = AppLanguage.simplifiedChinese
    let snapshot: MonitorSnapshot
    let history: MonitorHistory
    let runsSampling: Bool

    init(
        snapshot: MonitorSnapshot = .empty,
        history: MonitorHistory = MonitorHistory(),
        runsSampling: Bool = true
    ) {
        self.snapshot = snapshot
        self.history = history
        self.runsSampling = runsSampling
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetrics.pageHeadingGap) {
            PaneHeading(
                title: ContractCopy.copyHubTabDevices.text(for: language),
                summary: ContractCopy.copyHubTabDevicesSummary.text(for: language)
            )
            MonitorTabView(
                language: language,
                initialSnapshot: snapshot,
                initialHistory: history,
                runsSampling: runsSampling
            )
            .frame(height: HubMetrics.monitorBodyHeight)
        }
        .padding(HubMetrics.panelPadding)
        .frame(width: HubMetrics.panelWidth, height: HubMetrics.monitorBodyHeight + 92)
        .background(MacTheme.canvas)
    }
}

@MainActor
enum MonitorSnapshotRenderer {
    static func render(to path: String) async -> Bool {
        let sampler = MonitorSampler()
        var history = MonitorHistory()
        var snapshot = MonitorSnapshot.empty
        for index in 0..<24 {
            snapshot = await sampler.sample()
            history.append(snapshot)
            guard index < 23 else { continue }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }

        // ImageRenderer 不能合成 `.glassEffect`。截图时临时换成常规材质，
        // 布局与内容不变，只替代无法离屏渲染的玻璃层。
        let previousMode = GlassSurfaceMode.current
        GlassSurfaceMode.current = .material
        defer { GlassSurfaceMode.current = previousMode }

        let renderer = ImageRenderer(
            content: MonitorPreviewRoot(
                snapshot: snapshot,
                history: history,
                runsSampling: false
            )
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
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

@MainActor
final class MonitorPreviewWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HubMetrics.panelWidth,
                height: HubMetrics.monitorBodyHeight + 92
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Covio Monitor Preview"
        window.contentView = NSHostingView(rootView: MonitorPreviewRoot())
        window.center()
        super.init(window: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
#endif
