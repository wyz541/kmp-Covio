import AppKit
import Foundation
import kmpDomain

/// SwiftUI 版的运行时。对应 Compose 版的 `AppRuntime`。
///
/// 职责：
/// - 持有全部 Ports 与 `Engine`。
/// - 把引擎状态与配置暴露成可观察属性，界面直接读。
/// - 提供设置页要调用的动作。
///
/// 只跑在主线程。`Engine` 自己加锁，所以后台的端口回调进来也安全。
///
/// 截图挂帘的行为在 `ShelfRuntime` 里，剪贴板属于 M4。
/// `AppRuntime` 负责把配置变化转达给挂帘运行时。
@MainActor
@Observable
final class AppRuntime {
    /// 引擎状态。
    private(set) var appState: AppState
    /// 当前配置。写它一律走 `updateConfig`。
    private(set) var config: AppConfig
    /// 特权 helper 的状态。
    private(set) var helperStatus: HelperStatus = .notInstalled
    /// 一次性提示。界面读完应调用 `clearStatus`。
    private(set) var statusMessage: String?
    /// 有耗时操作在跑。界面据此禁用按钮。
    private(set) var busy = false
    /// 首次启动的引导是否可见。
    private(set) var welcomeVisible: Bool

    /// 界面语言。跟随配置，配置为空时跟随系统。
    var language: AppLanguage { AppLanguage.fromCode(config.language) }

    let logger: AppLogger

    /// 截图挂帘。设置页的开关与截图页签都读它。
    let shelf: ShelfRuntime

    /// 剪切板。Hub 的剪切板页签读它。
    let clipboard: ClipboardRuntime

    /// 共享文件工作区。Hub 的文件页签读它。
    let workspace: WorkspaceRuntime

    /// 电源管理面的真实运行时。
    let powerRuntime: PowerRuntime

    private let configStore: ConfigStore
    /// 挂帘读配置的中间人。理由见 `ShelfBridge`。
    private let shelfBridge: ShelfBridge
    /// 剪切板回报错误的中间人。理由见 `ClipboardBridge`。
    private let clipboardBridge: ClipboardBridge
    private let engine: Engine
    private let powerSource: PowerSource
    private let powerObservationSource: PowerObservationSource
    private let lid: LidSensor
    private let idle: IdleSensor
    private let sleepController: SleepController
    private let sleepWatcher: SleepWatcher
    private let wakeLogReader: WakeLogReader
    private let privileged: PrivilegedOps
    private let loginItem: LoginItem
    private let notifier: Notifier
    private let updateChecker: UpdateChecker
    /// 通知开关的持有者。`MacNotifier` 要一个读开关的闭包，
    /// 那个闭包必须在 `self` 建好之前交出去，所以开关放在这个独立对象里。
    private let notificationGate: NotificationGate

    private let stateForwarder: StateForwarder
    private var tickTimer: Timer?
    private var updateTimer: Timer?
    private var ticks = 0

    /// 每秒一次的心跳间隔。与 Compose 版一致。
    static let tickInterval: TimeInterval = 1
    /// 每多少次心跳刷新一次 helper 状态。与 Compose 版一致：5 秒。
    static let helperRefreshTicks = 5
    /// 启动后多久做第一次自动更新检查。与 Compose 版一致：30 秒。
    static let firstUpdateCheckDelay: TimeInterval = 30

    /// 端口都按协议收。默认值是 macOS 的真实实现，测试传假的。
    init(
        logger: AppLogger? = nil,
        configStore: ConfigStore? = nil,
        power: PowerSource = MacPowerSource(),
        lid: LidSensor = MacLidSensor(),
        idle: IdleSensor = MacIdleSensor(),
        sleepController: SleepController = MacSleepController(),
        sleepWatcher: SleepWatcher = MacSleepWatcher(),
        wakeLogReader: WakeLogReader = PmsetWakeLogReader(),
        privileged: PrivilegedOps? = nil,
        loginItem: LoginItem = MacLoginItem(),
        notifier: Notifier? = nil,
        updateChecker: UpdateChecker = GithubUpdateChecker(),
        powerObservation: PowerObservationSource? = nil,
        shelf: ShelfRuntime? = nil,
        clipboard: ClipboardRuntime? = nil,
        workspace: WorkspaceRuntime? = nil
    ) {
        let resolvedLogger = logger ?? FileAppLogger()
        let resolvedStore = configStore ?? ConfigStore.companion.create(path: AppPaths.configFile.path)

        let resolvedPrivileged = privileged ?? MacPrivilegedOps(logger: resolvedLogger)
        let resolvedPowerObservation = powerObservation ?? MacPowerObservationSource()

        self.logger = resolvedLogger
        self.configStore = resolvedStore
        self.powerSource = power
        self.powerObservationSource = resolvedPowerObservation
        self.lid = lid
        self.idle = idle
        self.sleepController = sleepController
        self.sleepWatcher = sleepWatcher
        self.wakeLogReader = wakeLogReader
        self.privileged = resolvedPrivileged
        self.loginItem = loginItem
        self.notificationGate = NotificationGate()
        self.notifier = notifier ?? MacNotifier(logger: resolvedLogger) { [gate = notificationGate] in
            gate.isEnabled
        }
        self.updateChecker = updateChecker

        // 语言为空说明是首次启动或配置被清过。补上系统语言并立刻落盘，
        // 这样 Compose 版读到的也是同一份。Compose 版的 `AppRuntime` 做同样的事。
        var loaded = resolvedStore.load()
        if loaded.language.isEmpty {
            let draft = ConfigDraft(loaded)
            draft.language = AppLanguage.fromCode(nil).rawValue
            loaded = draft.build()
            resolvedStore.save(config: loaded)
        }

        self.config = loaded
        self.appState = AppRuntime.initialState(enabled: loaded.enabled)
        self.welcomeVisible = loaded.firstRun
        self.notificationGate.isEnabled = loaded.notificationsEnabled

        // 转发器先建好再交给引擎。闭包捕获 `self` 要等全部存储属性赋值完，
        // 所以挂闭包的动作放在引擎之后。
        let forwarder = StateForwarder()
        self.stateForwarder = forwarder

        // 挂帘的闭包同样要在 `self` 建好之前交出去，所以配置读值走这个中间人。
        let bridge = ShelfBridge(config: loaded)
        self.shelfBridge = bridge
        let shelfStore = ShelfStoreClient()
        self.shelf = shelf ?? ShelfRuntime(
            store: shelfStore,
            takeover: ScreenshotTakeoverController(
                store: MacScreenshotPreferenceStore(),
                directory: ShelfPaths.screenshotsDirectory,
                shelfStore: shelfStore
            ),
            environment: ShelfEnvironment(
                isShelfEnabled: { bridge.config.shelfEnabled },
                isTakeoverEnabled: { bridge.config.screenshotInboxEnabled },
                isSoundsEnabled: { bridge.config.shelfSoundsEnabled },
                language: { AppLanguage.fromCode(bridge.config.language) }
            ),
            report: { entry in bridge.report?(entry) }
        )

        // 剪切板同样要先建好中间人。开关与快捷键都读配置。
        let clipboardBridge = ClipboardBridge()
        self.clipboardBridge = clipboardBridge
        self.clipboard = clipboard ?? ClipboardRuntime(
            store: ClipboardStore.companion.create(path: AppPaths.clipboardFile.path),
            imageDirectory: AppPaths.clipboardDirectory,
            environment: ClipboardEnvironment(
                isEnabled: { bridge.config.clipboardEnabled },
                hotKeyBinding: { action in
                    switch action {
                    case .pasteStack: bridge.config.clipboardPasteStackHotKey
                    case .captureSelection: bridge.config.clipboardCaptureHotKey
                    }
                },
                language: { AppLanguage.fromCode(bridge.config.language) }
            ),
            bridge: clipboardBridge
        )

        // 工作区没有配置依赖，也没有要交出去的闭包。直接建。
        self.workspace = workspace ?? WorkspaceRuntime()

        let engine = Engine(
            initialConfig: loaded,
            power: power,
            lid: lid,
            idle: idle,
            sleepController: sleepController,
            sleepWatcher: sleepWatcher,
            privileged: resolvedPrivileged,
            logger: resolvedLogger,
            wakeLogReader: wakeLogReader,
            // 下面这三个闭包由引擎在后台唤醒扫描线程上调用。
            // 标 `@Sendable` 让它们脱离主 actor；不标的话闭包继承 `init` 的隔离，
            // 后台线程一调就撞 `dispatch_assert_queue` 断言。
            clock: { @Sendable in KotlinLong(longLong: AppRuntime.nowMillis()) },
            stateListener: forwarder,
            // 引擎要求这个块跑在别的线程上。Kotlin 的函数类型不是 Sendable，
            // 用 `KotlinBox` 把「按约定跨线程」这件事写在一处。
            wakeScanExecutor: { block in
                let box = KotlinBox(block)
                DispatchQueue.global(qos: .utility).async { _ = box.value() }
            },
            wakeDelay: { @Sendable millis in
                let seconds = Double(millis.int64Value) / 1_000
                if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
            },
            wakeRetryDelayMillis: 1_000,
            wakeRetryCount: 3,
            wakeCacheNowMillis: { @Sendable in KotlinLong(longLong: AppRuntime.nowMillis()) }
        )
        self.engine = engine
        self.powerRuntime = PowerRuntime(
            engine: engine,
            privileged: resolvedPrivileged,
            observationSource: resolvedPowerObservation,
            config: loaded.power
        )

        forwarder.handler = { @Sendable [weak self] state in
            MainActor.assumeIsolated { self?.appState = state }
        }
    }

    // MARK: - 生命周期

    /// 启动引擎与两条后台节奏。可以重复调用，第二次没有副作用。
    func start() {
        guard tickTimer == nil else { return }
        logger.info(message: "Covio \(ModelsKt.APP_VERSION) starting")

        helperStatus = privileged.status()
        syncHibernateMode()
        syncLoginItem()
        engine.start()
        powerRuntime.start()
        syncState()

        // 挂帘的错误要显示在 Hub 上，出口在这里接。
        shelfBridge.report = { [weak self] entry in
            guard let self else { return }
            self.statusMessage = entry.text(for: self.language)
        }
        // 面板反向持有运行时，所以那边用 unowned。
        shelf.panel = ShelfPanelController(
            runtime: shelf,
            language: { [weak self] in
                self?.language ?? AppLanguage.fromCode(nil)
            },
            onSaveToWorkspace: { [weak self] item in
                _ = self?.workspace.save(filesAt: [item.path])
            }
        )
        shelf.start()

        clipboardBridge.report = { [weak self] entry in
            guard let self else { return }
            self.statusMessage = entry.text(for: self.language)
        }
        clipboard.applyConfiguration()

        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.firstUpdateCheckDelay, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.checkForUpdates(manual: false)
                self.updateTimer = Timer.scheduledTimer(
                    withTimeInterval: Double(max(1, self.config.updateCheckIntervalHours)) * 3_600,
                    repeats: true
                ) { _ in
                    MainActor.assumeIsolated { self.checkForUpdates(manual: false) }
                }
            }
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        shelf.stop()
        clipboard.stop()
        powerRuntime.stop()
        engine.stop()
    }

    private func tick() {
        engine.tick(nowMillis: AppRuntime.nowMillis())
        powerRuntime.refresh()
        ticks += 1
        syncState()
        if ticks % Self.helperRefreshTicks == 0 {
            // 心跳里不等待：只读一次当前状态。等待只用在刚装完 helper 的那一刻。
            Task { @MainActor in await refreshHelperStatus() }
        }
    }

    // MARK: - 设置动作。逐个对应 Compose 版 `AppRuntime` 的同名方法。

    func setEnabled(_ enabled: Bool) {
        if !updateConfigDraft({ $0.enabled = enabled }) {
            statusMessage = ContractCopy.copyToastError.text(for: language)
        }
    }

    func setLowBatterySleep(_ enabled: Bool) { write { $0.lowBatteryCapacitySleep = enabled } }

    /// `valid` 为假时不写配置。界面在输入不是数字时传假。
    func setLowBatteryCapacity(_ value: Int, valid: Bool) {
        guard valid else { return }
        write { $0.lowBatteryCapacity = Int32(min(max(value, 0), 100)) }
    }

    func setLowTimeRemaining(_ value: Int, valid: Bool) {
        guard valid else { return }
        write { $0.lowTimeRemainingMinutes = Int32(max(value, 0)) }
    }

    func setDisableIdleWhileCharging(_ enabled: Bool) {
        write { $0.disableIdleSleepInCharging = enabled }
    }

    func setPowerEnabled(_ enabled: Bool) {
        updatePower { copyPower($0, enabled: enabled) }
    }

    func setPowerKeepAwakeOnAdapter(_ enabled: Bool) {
        updatePower { copyPower($0, keepAwakeOnAdapter: enabled) }
    }

    func setPowerKeepAwakeOnBattery(_ enabled: Bool) {
        updatePower { copyPower($0, keepAwakeOnBattery: enabled) }
    }

    func setPowerAllowClosedLid(_ enabled: Bool) {
        guard enabled ? powerRuntime.helperStatus == .installed : true else { return }
        updatePower { copyPower($0, allowClosedLid: enabled) }
    }

    func setPowerPauseClosedLidWithExternalDisplay(_ enabled: Bool) {
        updatePower { copyPower($0, pauseClosedLidWithExternalDisplay: enabled) }
    }

    func setPowerBatteryFloor(_ percent: Int) {
        let floor = min(max(percent, 0), 95)
        updatePower {
            copyPower(
                $0,
                batteryFloorPercent: Int32(floor),
                batteryFloorRecoveryPercent: Int32(min(floor + 5, 100))
            )
        }
    }

    func setPowerYieldOnLowPowerMode(_ enabled: Bool) {
        updatePower { copyPower($0, yieldOnLowPowerMode: enabled) }
    }

    func setPowerHeatGuard(_ enabled: Bool) {
        updatePower { copyPower($0, heatGuardEnabled: enabled) }
    }

    func setPowerClosedLidTimeCapMinutes(_ minutes: Int) {
        updatePower { copyPower($0, closedLidTimeCapMinutes: Int32(min(max(minutes, 30), 1_440))) }
    }

    /// 打开前先确认 helper 在。helper 不在时它改不了 `pmset`，界面会显示成功但实际没生效。
    func setDisableLidWhileCharging(_ enabled: Bool) {
        guard enabled ? lidPolicyAvailable() : true else { return }
        write { $0.disableLidSleepInCharging = enabled }
    }

    func setDisableLidOnBattery(_ enabled: Bool) {
        guard enabled ? lidPolicyAvailable() : true else { return }
        write { $0.disableLidSleepOnBattery = enabled }
    }

    func setDarkWakeAwareness(_ enabled: Bool) { write { $0.darkWakeAwarenessEnabled = enabled } }
    func setImmediateLidSleep(_ enabled: Bool) { write { $0.lidSleepImmediateOnClose = enabled } }
    func setNotifications(_ enabled: Bool) { write { $0.notificationsEnabled = enabled } }
    func setUpdateChecks(_ enabled: Bool) { write { $0.updateCheckEnabled = enabled } }
    func setShelfSounds(_ enabled: Bool) { write { $0.shelfSoundsEnabled = enabled } }

    // 下面三个除了写配置，还要让挂帘运行时重新读开关。

    func setShelfEnabled(_ enabled: Bool) {
        write { $0.shelfEnabled = enabled }
        shelf.applyConfiguration()
    }

    func setScreenshotInbox(_ enabled: Bool) {
        write { $0.screenshotInboxEnabled = enabled }
        shelf.applyConfiguration()
    }

    func setSleepMode(_ mode: Int32) { write { $0.hibernateMode = KotlinInt(int: mode) } }

    func changeLanguage(_ language: AppLanguage) { write { $0.language = language.rawValue } }

    /// 剪切板记录的总开关。关掉时停止监听，并注销两个快捷键。
    func setClipboardEnabled(_ enabled: Bool) {
        write { $0.clipboardEnabled = enabled }
        clipboard.applyConfiguration()
    }

    /// 给一个动作换快捷键。写回配置之后立刻重新注册。
    func setClipboardHotKey(_ action: ClipboardHotKeyAction, to binding: String) {
        switch action {
        case .pasteStack: write { $0.clipboardPasteStackHotKey = binding }
        case .captureSelection: write { $0.clipboardCaptureHotKey = binding }
        }
        clipboard.reloadHotKeys()
    }

    /// 合盖后是否阻止睡眠。开关状态来自引擎，不是配置。
    func toggleLidSleep() {
        engine.setLidSleepAvailable(available: appState.lidSleepAvailable)
        syncState()
    }

    /// 闲置时是否阻止睡眠。开关状态来自引擎的实际断言。
    func toggleIdleSleep() {
        engine.setIdleSleepAvailable(available: !appState.idleSleepAvailable)
        syncState()
    }

    func scheduleCancelIdle(seconds: Int64) { engine.scheduleCancelIdle(afterSeconds: seconds) }
    func scheduleCancelLid(seconds: Int64) { engine.scheduleCancelLid(afterSeconds: seconds) }
    func sleepNow() { engine.sleepNow() }
    func displaySleepNow() { engine.displaySleepNow() }

    func dismissWelcome() {
        welcomeVisible = false
        write { $0.firstRun = false }
    }

    func clearStatus() { statusMessage = nil }

    /// 退出应用。导航栏底部的退出按钮走这里。
    ///
    /// **警告：** 退出会停止全部规则，机器不再按配置自动睡眠。
    /// 按钮排在导航栏底部组最后一项，避免与设置按钮误点。
    ///
    /// 默认实现真的退出。测试注入假闭包，断言被调用即可，
    /// 不必真的结束测试宿主。
    var quitHandler: @MainActor () -> Void = { NSApp.terminate(nil) }

    func requestQuit() { quitHandler() }

    /// 清除配置。下次启动回到默认值。
    ///
    /// **警告：** 会删掉用户全部设置。界面必须先确认。
    func clearConfig() {
        let defaults = ConfigStore.companion.defaults()
        configStore.save(config: defaults)
        config = defaults
        shelfBridge.config = defaults
        _ = engine.updateConfig(newConfig: defaults)
        powerRuntime.updateConfig(defaults.power)
        syncState()
        shelf.applyConfiguration()
        statusMessage = ContractCopy.copyDialogResetTitle.text(for: language)
    }

    // MARK: - helper

    func installHelper() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            let installed = privileged.install()
            await refreshHelperStatus(waitForInstalled: installed)
            busy = false
            let success = helperStatus == .installed
            let entry = success ? ContractCopy.copyOverviewHelperInstalled : ContractCopy.copyDialogHelperUnavailableBody
            statusMessage = entry.text(for: language)
            if success { dismissWelcome() }
        }
    }

    func uninstallHelper() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            let removed = privileged.uninstall()
            helperStatus = .notInstalled
            _ = engine.setLidSleepAvailable(available: true)
            powerRuntime.refreshHelperStatusNow()
            syncState()
            busy = false
            let entry = removed ? ContractCopy.copyOverviewHelperMissing : ContractCopy.copyToastError
            statusMessage = entry.text(for: language)
        }
    }

    /// 等 helper 起来。刚装完 launchd 还没把 socket 建好，立刻查会读到未安装。
    ///
    /// 与 Compose 版 `awaitHelperStatus` 一致：最多等 5 秒，每 200 毫秒查一次。
    private func refreshHelperStatus(waitForInstalled: Bool = false) async {
        var status = privileged.status()
        if waitForInstalled && status != .installed {
            let deadline = Date().addingTimeInterval(5)
            while status != .installed && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
                status = privileged.status()
            }
        }
        guard helperStatus != status else {
            powerRuntime.refreshHelperStatusNow()
            return
        }
        helperStatus = status
        syncState()
        if status == .installed {
            _ = engine.updateConfig(newConfig: config)
        }
        powerRuntime.refreshHelperStatusNow()
    }

    private func lidPolicyAvailable() -> Bool {
        guard helperStatus == .installed else {
            statusMessage = ContractCopy.copyStatusItemHelperError.text(for: language)
            return false
        }
        return true
    }

    // MARK: - 更新

    func checkForUpdates(manual: Bool) {
        let now = AppRuntime.nowEpochSeconds()
        if !manual && !UpdatePolicy.shared.shouldCheck(config: config, nowEpochSeconds: now) { return }
        Task { @MainActor in
            let release = await Self.fetchRelease(updateChecker).value
            let update = UpdatePolicy.shared.selectUpdate(candidate: release, currentVersion: ModelsKt.APP_VERSION)
            write { $0.lastUpdateCheckEpochSeconds = now }
            if let update {
                notifier.notify(
                    title: ContractCopy.copyDialogUpdateTitle.text(for: language),
                    subtitle: "",
                    message: "\(update.version) · \(update.title)",
                    releaseUrl: update.releaseUrl
                )
                if manual, let url = URL(string: update.releaseUrl) {
                    NSWorkspace.shared.open(url)
                }
                statusMessage = "\(ContractCopy.copyDialogUpdateTitle.text(for: language)): \(update.version)"
            } else if manual {
                let entry = release == nil ? ContractCopy.copyToastError : ContractCopy.copyHubUpdateUpToDate
                statusMessage = entry.text(for: language)
            }
        }
    }

    /// `UpdateChecker` 是同步的，放到后台线程跑，避免卡住主线程十秒。
    ///
    /// `UpdateChecker` 是 ObjC 协议，Swift 看不出实现能不能跨线程。
    /// 唯一的实现 `GithubUpdateChecker` 只持有不可变的 URL 与 URLSession，
    /// 两者都线程安全，所以用 `KotlinBox` 显式声明。
    private static func fetchRelease(_ checker: UpdateChecker) async -> KotlinBox<UpdateInfo?> {
        let boxedChecker = KotlinBox(checker)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: KotlinBox(boxedChecker.value.latestRelease()))
            }
        }
    }

    // MARK: - 日志

    func viewLog() {
        let path = logger.logFile()
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// 导出日志。把用户主目录替换成 `~`，导出的文件不泄露用户名。
    func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Covio.log"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            let source = URL(fileURLWithPath: logger.logFile())
            let text = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            try text.replacingOccurrences(of: home, with: "~")
                .write(to: target, atomically: true, encoding: .utf8)
            statusMessage = ContractCopy.copyToastSuccess.text(for: language)
        } catch {
            logger.warn(message: "Cannot export log", error: nil)
            statusMessage = ContractCopy.copyToastError.text(for: language)
        }
    }

    // MARK: - 内部

    /// 改一个配置字段并落盘。
    ///
    /// 引擎拒绝时回滚。拒绝的原因是当前状态下这条规则不成立，
    /// 例如 helper 不在却要接管合盖。
    private func write(_ change: (ConfigDraft) -> Void) {
        updateConfigDraft(change)
    }

    /// 改若干字段并落盘。返回引擎是否接受。
    @discardableResult
    private func updateConfigDraft(_ change: (ConfigDraft) -> Void) -> Bool {
        let draft = ConfigDraft(config)
        change(draft)
        return updateConfig(draft.build())
    }

    @discardableResult
    private func updateConfig(_ newConfig: AppConfig) -> Bool {
        let previous = config
        let normalized = newConfig.normalized()
        config = normalized
        // 挂帘下次读开关时读到的是这一份。
        shelfBridge.config = normalized
        configStore.save(config: normalized)
        let success = engine.updateConfig(newConfig: normalized)
        if !success {
            config = previous
            shelfBridge.config = previous
            configStore.save(config: previous)
            _ = engine.updateConfig(newConfig: previous)
        }
        powerRuntime.updateConfig(config.power)
        syncState()
        return success
    }

    private func updatePower(_ change: (PowerConfig) -> PowerConfig) {
        write { $0.power = change($0.power).normalized() }
    }

    private func copyPower(
        _ value: PowerConfig,
        enabled: Bool? = nil,
        keepAwakeOnAdapter: Bool? = nil,
        keepAwakeOnBattery: Bool? = nil,
        allowClosedLid: Bool? = nil,
        pauseClosedLidWithExternalDisplay: Bool? = nil,
        batteryFloorPercent: Int32? = nil,
        batteryFloorRecoveryPercent: Int32? = nil,
        yieldOnLowPowerMode: Bool? = nil,
        heatGuardEnabled: Bool? = nil,
        closedLidTimeCapMinutes: Int32? = nil
    ) -> PowerConfig {
        PowerConfig(
            enabled: enabled ?? value.enabled,
            keepAwakeOnAdapter: keepAwakeOnAdapter ?? value.keepAwakeOnAdapter,
            keepAwakeOnBattery: keepAwakeOnBattery ?? value.keepAwakeOnBattery,
            allowClosedLid: allowClosedLid ?? value.allowClosedLid,
            pauseClosedLidWithExternalDisplay: pauseClosedLidWithExternalDisplay
                ?? value.pauseClosedLidWithExternalDisplay,
            batteryFloorPercent: batteryFloorPercent ?? value.batteryFloorPercent,
            batteryFloorRecoveryPercent: batteryFloorRecoveryPercent
                ?? value.batteryFloorRecoveryPercent,
            yieldOnLowPowerMode: yieldOnLowPowerMode ?? value.yieldOnLowPowerMode,
            heatGuardEnabled: heatGuardEnabled ?? value.heatGuardEnabled,
            closedLidTimeCapMinutes: closedLidTimeCapMinutes ?? value.closedLidTimeCapMinutes
        )
    }

    /// 把引擎状态读回来，并补上 helper 状态。
    private func syncState() {
        appState = engine.currentState.doCopy(
            battery: engine.currentState.battery,
            lid: engine.currentState.lid,
            enabled: engine.currentState.enabled,
            idleSleepAvailable: engine.currentState.idleSleepAvailable,
            idleSleepPrevention: engine.currentState.idleSleepPrevention,
            lidSleepAvailable: engine.currentState.lidSleepAvailable,
            idleCancelRemainingSeconds: engine.currentState.idleCancelRemainingSeconds,
            lidCancelRemainingSeconds: engine.currentState.lidCancelRemainingSeconds,
            darkWake: engine.currentState.darkWake,
            shelf: engine.currentState.shelf,
            helperStatus: helperStatus,
            lidLeaseStatus: engine.currentState.lidLeaseStatus,
            lastError: engine.currentState.lastError
        )
    }

    /// 开机自启的真实状态以系统为准，不是配置。
    /// 用户在「系统设置」里改过之后，配置里的值就过时了。
    private func syncLoginItem() {
        let actual = loginItem.isEnabled()
        guard actual != config.launchAtLogin else { return }
        updateConfigDraft { $0.launchAtLogin = actual }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let applied = enabled ? loginItem.enable() : loginItem.disable()
        guard applied else {
            statusMessage = ContractCopy.copyToastError.text(for: language)
            return
        }
        write { $0.launchAtLogin = enabled }
    }

    /// 休眠模式的真实值以 `pmset` 为准。
    private func syncHibernateMode() {
        guard let actual = privileged.hibernateMode() else { return }
        guard actual.int32Value != config.hibernateMode?.int32Value else { return }
        write { $0.hibernateMode = KotlinInt(int: actual.int32Value) }
    }

    /// 引擎启动前的状态。全默认，只有 `enabled` 来自配置。
    ///
    /// Kotlin 的 `AppState()` 默认参数不导出，所以这里要写全所有字段。
    static func initialState(enabled: Bool) -> AppState {
        AppState(
            battery: nil,
            lid: .unknown,
            enabled: enabled,
            idleSleepAvailable: true,
            idleSleepPrevention: .none,
            lidSleepAvailable: true,
            idleCancelRemainingSeconds: nil,
            lidCancelRemainingSeconds: nil,
            darkWake: DarkWakeStatus(
                available: false,
                scanning: false,
                lastAtEpochSeconds: nil,
                lastReason: nil,
                count24h: 0
            ),
            shelf: ShelfState(items: [], visible: false, revealed: true, takeoverActive: false),
            helperStatus: .notInstalled,
            lidLeaseStatus: LidLeaseStatus(
                available: false,
                protocolVersion: nil,
                sleepDisabled: nil,
                covioOwned: nil,
                activeLeaseCount: 0,
                expiresAtEpochSeconds: nil,
                error: nil
            ),
            lastError: nil
        )
    }

    /// 当前毫秒时间戳。
    ///
    /// **必须是非隔离的。** 引擎的后台唤醒扫描线程会通过 `clock` 与
    /// `wakeCacheNowMillis` 调它。留在主 actor 上会在那边触发
    /// `dispatch_assert_queue` 断言，进程直接崩。
    nonisolated static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
    nonisolated static func nowEpochSeconds() -> Int64 { Int64(Date().timeIntervalSince1970) }

    /// 实时电池文字。与 Compose 版 `formatBattery` 一致。
    func batteryText() -> String {
        guard let battery = appState.battery else { return ContractCopy.copyStateEmpty.text(for: language) }
        let stateText: String
        switch battery.state {
        case .discharging: stateText = ContractCopy.copyTrayTooltipBattery.text(for: language)
        case .charging: stateText = ContractCopy.copyTrayTooltipCharging.text(for: language)
        // `AC` 是单位记号，不是文案，不进合同。
        case .charged, .acPower: stateText = "AC"
        default: stateText = ContractCopy.copyStateEmpty.text(for: language)
        }
        return "\(battery.percent)% · \(stateText)"
    }
}

/// `AppConfig` 的可变草稿。
///
/// Kotlin 的 data class 在 Swift 里字段全只读，没有 `copy` 之外的改法。
/// 全部字段的 `doCopy` 写十遍会出错，所以集中到这里。
/// 加字段时只改这一处。
final class ConfigDraft {
    var schemaVersion: Int32
    var language: String
    var enabled: Bool
    var launchAtLogin: Bool
    var lowBatteryCapacitySleep: Bool
    var lowBatteryCapacity: Int32
    var lowTimeRemainingMinutes: Int32
    var disableIdleSleepInCharging: Bool
    var disableLidSleepInCharging: Bool
    var disableLidSleepOnBattery: Bool
    var darkWakeAwarenessEnabled: Bool
    var lidSleepImmediateOnClose: Bool
    var notificationsEnabled: Bool
    var updateCheckEnabled: Bool
    var updateCheckIntervalHours: Int32
    var lastUpdateCheckEpochSeconds: Int64
    var hibernateMode: KotlinInt?
    var firstRun: Bool
    var shelfEnabled: Bool
    var screenshotInboxEnabled: Bool
    var shelfSoundsEnabled: Bool
    var clipboardEnabled: Bool
    var clipboardPasteStackHotKey: String
    var clipboardCaptureHotKey: String
    var power: PowerConfig

    init(_ config: AppConfig) {
        schemaVersion = config.schemaVersion
        language = config.language
        enabled = config.enabled
        launchAtLogin = config.launchAtLogin
        lowBatteryCapacitySleep = config.lowBatteryCapacitySleep
        lowBatteryCapacity = config.lowBatteryCapacity
        lowTimeRemainingMinutes = config.lowTimeRemainingMinutes
        disableIdleSleepInCharging = config.disableIdleSleepInCharging
        disableLidSleepInCharging = config.disableLidSleepInCharging
        disableLidSleepOnBattery = config.disableLidSleepOnBattery
        darkWakeAwarenessEnabled = config.darkWakeAwarenessEnabled
        lidSleepImmediateOnClose = config.lidSleepImmediateOnClose
        notificationsEnabled = config.notificationsEnabled
        updateCheckEnabled = config.updateCheckEnabled
        updateCheckIntervalHours = config.updateCheckIntervalHours
        lastUpdateCheckEpochSeconds = config.lastUpdateCheckEpochSeconds
        hibernateMode = config.hibernateMode
        firstRun = config.firstRun
        shelfEnabled = config.shelfEnabled
        screenshotInboxEnabled = config.screenshotInboxEnabled
        shelfSoundsEnabled = config.shelfSoundsEnabled
        clipboardEnabled = config.clipboardEnabled
        clipboardPasteStackHotKey = config.clipboardPasteStackHotKey
        clipboardCaptureHotKey = config.clipboardCaptureHotKey
        power = config.power
    }

    func build() -> AppConfig {
        AppConfig(
            schemaVersion: schemaVersion,
            language: language,
            enabled: enabled,
            launchAtLogin: launchAtLogin,
            lowBatteryCapacitySleep: lowBatteryCapacitySleep,
            lowBatteryCapacity: lowBatteryCapacity,
            lowTimeRemainingMinutes: lowTimeRemainingMinutes,
            disableIdleSleepInCharging: disableIdleSleepInCharging,
            disableLidSleepInCharging: disableLidSleepInCharging,
            disableLidSleepOnBattery: disableLidSleepOnBattery,
            darkWakeAwarenessEnabled: darkWakeAwarenessEnabled,
            lidSleepImmediateOnClose: lidSleepImmediateOnClose,
            notificationsEnabled: notificationsEnabled,
            updateCheckEnabled: updateCheckEnabled,
            updateCheckIntervalHours: updateCheckIntervalHours,
            lastUpdateCheckEpochSeconds: lastUpdateCheckEpochSeconds,
            hibernateMode: hibernateMode,
            firstRun: firstRun,
            shelfEnabled: shelfEnabled,
            screenshotInboxEnabled: screenshotInboxEnabled,
            shelfSoundsEnabled: shelfSoundsEnabled,
            clipboardEnabled: clipboardEnabled,
            clipboardPasteStackHotKey: clipboardPasteStackHotKey,
            clipboardCaptureHotKey: clipboardCaptureHotKey,
            power: power
        )
    }
}

/// 引擎状态的转发。
///
/// `StateListener` 在引擎线程上被调用，所以这里立刻跳回主线程。
/// 不跳的话 SwiftUI 会在后台线程改可观察属性。
private final class StateForwarder: NSObject, StateListener {
    /// 引擎启动前是 nil。运行时在 `init` 末尾挂上。
    ///
    /// 标 `@Sendable` 是为了能在 `onState` 里把它带进主线程队列。
    /// 闭包体只改主线程上的可观察属性，所以是安全的。
    var handler: (@MainActor @Sendable (AppState) -> Void)?

    func onState(state: AppState) {
        // 先取出闭包再跨线程。直接捕获 `self` 会让 Swift 认为整个转发器
        // 都跨了线程，而它只该带走这一个闭包。
        // 闭包自身标了 `@Sendable`，所以这是允许的。
        guard let handler else { return }
        let box = KotlinBox(state)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler(box.value) }
        }
    }
}

/// 跨线程传一个 Kotlin 的不可变对象。
///
/// Kotlin 的 data class 导出到 Swift 后字段全只读，跨线程传是安全的，
/// 但 Swift 看不到这一点。用它把这件事写在一处，
/// 而不是在每个调用点撒 `@unchecked Sendable`。
final class KotlinBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) { self.value = value }
}

/// 通知开关的持有者。
///
/// `MacNotifier` 在构造时要一个读开关的闭包，而那个闭包必须先于 `self` 存在。
/// 所以开关放在这个独立对象里，运行时每次写配置时同步它。
final class NotificationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false

    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }
}

/// 晾衣线读配置与回报错误的中间人。
///
/// `ShelfRuntime` 的环境闭包要在 `self` 全部属性赋值完之前交出去，
/// 那时还不能捕获 `self`。所以配置副本与错误出口先放在这个独立对象上，
/// 与 `NotificationGate` 同一个理由。
@MainActor
final class ShelfBridge {
    var config: AppConfig
    /// 错误出口。`AppRuntime` 在 `start()` 里接上。
    ///
    /// 挂帘自己不改 `statusMessage`：状态提示由运行时统一管。
    var report: ((LocalizedCopy) -> Void)?

    init(config: AppConfig) {
        self.config = config
    }
}
