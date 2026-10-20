import AppKit
import kmpDomain

/// 应用代理。装配 Notch Shell、菜单栏图标与全局快捷键。
///
/// `Info.plist` 的 `LSUIElement` 是 true，所以这是一个没有 Dock 图标与主菜单的代理应用。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 运行时。引擎与端口都由它持有。
    ///
    /// 单实例检查通过之后才创建，避免第二个进程去动 shared 的配置文件。
    private var runtime: AppRuntime?
    private let shell = NotchShellController()
    private var statusItemController: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var instanceLock: SingleInstanceLock?
    #if DEBUG
    private var monitorPreview: MonitorPreviewWindowController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement 已经让进程成为代理应用。这里显式再设一次，防止从 Xcode 直接运行时不一致。
        NSApp.setActivationPolicy(.accessory)

        // 调试构建可以用环境变量换玻璃底材，便于同一次构建对照截图。
        GlassSurfaceMode.applyEnvironmentOverride()
        MacTheme.applyEnvironmentOverride()

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await MonitorSnapshotRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_DETAIL_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await MonitorPowerDetailRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_MONITOR_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let preview = MonitorPreviewWindowController()
            monitorPreview = preview
            preview.showWindow(nil)
            return
        }
        #endif

        // 测试进程不是真实实例，不参与单实例仲裁。
        // 真实应用在跑时仲裁会失败，那会把整个测试套件终止掉。
        if !LaunchEnvironment.isRunningTests() {
            // 单实例。Compose 版用 app.lock，本版用 app.swiftui.lock，两版可以同时运行。
            let lock = SingleInstanceLock()
            guard lock.acquire() else {
                NSLog("Covio 已经在运行。本进程退出。")
                NSApp.terminate(nil)
                return
            }
            instanceLock = lock
        }

        AppPaths.ensureSupportDirectory()

        let runtime = AppRuntime()
        self.runtime = runtime
        shell.runtime = runtime
        // 工作台配置落盘。文件不存在时 `load()` 给默认值，所以首次启动就有六块组件。
        shell.workbench.attach(
            store: WorkbenchStore.companion.create(path: AppPaths.workbenchFile.path)
        )
        // 测试进程里不启动运行时。`start()` 会连真实的存储与系统设置：
        // 它打开真实的截图接管并改写 `com.apple.screencapture`，还会写真实 `shelf.json`。
        // 界面装配照旧，所以 `testHostApplicationRunsTheShell` 仍然有效。
        // 测试要的运行时由测试自己用假实现构造。
        if !LaunchEnvironment.isRunningTests() {
            runtime.start()
        }

        shell.start()
        statusItemController = StatusItemController(shell: shell, runtime: runtime)

        // Control+Option+T 打开或收起 Hub。
        let hotKey = GlobalHotKey { [weak self] in
            self?.shell.toggle()
        }
        if !hotKey.register() {
            // Carbon 在快捷键冲突时静默失败。计划的 M4 要求设置页暴露这个状态。
            NSLog("Control+Option+T 注册失败。快捷键可能已被其它应用占用。")
        }
        self.hotKey = hotKey
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
        statusItemController?.tearDown()
        // 先停引擎。它会撤销 `pmset` 的改动，必须在进程退出前跑完。
        runtime?.stop()
        shell.stop()
        instanceLock?.release()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
