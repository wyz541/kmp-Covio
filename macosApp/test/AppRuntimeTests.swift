import XCTest
import kmpDomain
@testable import Covio

/// `AppRuntime` 的设置动作。
///
/// 每个动作都要落盘，所以每条用例都指向一个临时目录，
/// 断言既看内存里的 `config`，也看文件里的内容。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/ui/AppRuntime.kt`。
@MainActor
final class AppRuntimeTests: XCTestCase {
    private var directory: URL!
    private var runtime: AppRuntime!
    private var privileged: FakePrivilegedOps!
    private var chargeLimitClient: FakeChargeLimitClient!
    private var loginItem: FakeLoginItem!
    private var notifier: FakeNotifier!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // 停掉心跳。忘了停会让计时器在下一个用例里继续跑。
        runtime?.stop()
        runtime = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private var configFile: URL { directory.appendingPathComponent("config.json") }

    /// 建一个运行时。端口全用假的，不碰真实系统。
    ///
    /// `engineStarted` 为假时心跳不启动。只有需要 helper 状态的用例才启动它。
    ///
    /// helper 装没装要在构造前定好：`start()` 只在第一次调用时读状态，
    /// 之后再改假端口就晚了。
    @discardableResult
    private func makeRuntime(engineStarted: Bool = false, helperInstalled: Bool = false) -> AppRuntime {
        privileged = FakePrivilegedOps()
        privileged.installed = helperInstalled
        chargeLimitClient = FakeChargeLimitClient()
        loginItem = FakeLoginItem()
        notifier = FakeNotifier()
        let created = AppRuntime(
            logger: MemoryLogger(),
            configStore: ConfigStore.companion.create(path: configFile.path),
            power: FakePower(),
            lid: FakeLid(),
            idle: FakeIdle(),
            sleepController: FakeSleepController(),
            sleepWatcher: FakeSleepWatcher(),
            wakeLogReader: WakeLogStore(nil),
            privileged: privileged,
            chargeLimitClient: chargeLimitClient,
            loginItem: loginItem,
            notifier: notifier,
            updateChecker: FakeUpdateChecker(),
            shelf: makeShelf(),
            workspace: makeWorkspace()
        )
        runtime = created
        if engineStarted { created.start() }
        return created
    }

    /// 挂帘运行时。存储、系统偏好、监视器全指向临时目录或假实现。
    ///
    /// 不接替身的话，`start()` 会去动真实的 `~/Library/Application Support/Covio`，
    /// 还会监视用户的桌面。
    private func makeShelf() -> ShelfRuntime {
        let store = ShelfStoreClient(
            path: directory.appendingPathComponent("shelf.json").path
        )
        return ShelfRuntime(
            store: store,
            takeover: ScreenshotTakeoverController(
                store: FakeShelfPreferences(),
                directory: directory.appendingPathComponent("Screenshots", isDirectory: true),
                shelfStore: store
            ),
            environment: ShelfEnvironment(
                isShelfEnabled: { false },
                isTakeoverEnabled: { false },
                isSoundsEnabled: { false },
                isFullScreenSpaceActive: { false },
                reduceMotion: { false },
                language: { CopyLocale.language },
                pointerLocation: { .zero },
                now: { 0 }
            ),
            sound: FakeShelfSound(),
            watcherFactory: FakeWatcherFactory().factory
        )
    }

    /// 工作区运行时。索引指向临时目录，打开与显示都不动真实系统。
    ///
    /// 不接替身的话，构造时的一次清理会去动真实的 `~/Library/Application Support/Covio/Workspace`，
    /// 并删掉用户过期的内容。理由同 [makeShelf]。
    private func makeWorkspace() -> WorkspaceRuntime {
        var environment = WorkspaceEnvironment()
        environment.open = { _ in }
        environment.reveal = { _ in }
        return WorkspaceRuntime(
            client: WorkspaceStoreClient(directory: directory.path),
            environment: environment
        )
    }

    /// 读出落盘的 JSON。断言用。
    private func savedJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: configFile)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 等一个异步动作收尾。`installHelper` 与 `uninstallHelper` 都开任务。
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - 首次启动

    /// 配置文件不存在时写出一份默认配置，并补上系统语言。
    ///
    /// 语言留空会让 Compose 版也读到空值，所以构造时就补齐并落盘。
    func testFirstLaunchFillsInTheSystemLanguage() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: configFile.path))
        let created = makeRuntime()

        XCTAssertEqual(created.config.language, CopyLocale.language.rawValue)
        XCTAssertFalse(created.config.language.isEmpty)
        XCTAssertEqual(try savedJSON()["language"] as? String, CopyLocale.language.rawValue)
    }

    /// 首次启动显示欢迎页。用户关掉之后写回 `firstRun`。
    func testWelcomeIsDismissedOnlyOnce() throws {
        let created = makeRuntime()
        XCTAssertTrue(created.welcomeVisible)

        created.dismissWelcome()

        XCTAssertFalse(created.welcomeVisible)
        XCTAssertEqual(try savedJSON()["firstRun"] as? Bool, false)
    }

    // MARK: - 数值字段的边界

    /// 电池百分比夹在 0 到 100。
    func testLowBatteryCapacityIsClamped() throws {
        let created = makeRuntime()

        created.setLowBatteryCapacity(150, valid: true)
        XCTAssertEqual(created.config.lowBatteryCapacity, 100)
        XCTAssertEqual(try savedJSON()["lowBatteryCapacity"] as? Int, 100)

        created.setLowBatteryCapacity(-5, valid: true)
        XCTAssertEqual(created.config.lowBatteryCapacity, 0)

        created.setLowBatteryCapacity(20, valid: true)
        XCTAssertEqual(created.config.lowBatteryCapacity, 20)
    }

    /// 输入框内容不是数字时界面传 `valid: false`，此时配置不动。
    func testInvalidNumberIsIgnored() throws {
        let created = makeRuntime()
        created.setLowBatteryCapacity(30, valid: true)

        created.setLowBatteryCapacity(0, valid: false)
        created.setLowTimeRemaining(0, valid: false)

        XCTAssertEqual(created.config.lowBatteryCapacity, 30)
        XCTAssertEqual(created.config.lowTimeRemainingMinutes, 10)
    }

    /// 剩余分钟数只夹下界。
    func testLowTimeRemainingIsClampedAtZero() throws {
        let created = makeRuntime()

        created.setLowTimeRemaining(-30, valid: true)
        XCTAssertEqual(created.config.lowTimeRemainingMinutes, 0)

        created.setLowTimeRemaining(45, valid: true)
        XCTAssertEqual(created.config.lowTimeRemainingMinutes, 45)
        // 落盘的键名是 0.4.2 用的那个。
        XCTAssertEqual(try savedJSON()["lowTimeRemaining"] as? Int, 45)
    }

    // MARK: - 语言

    /// 换语言立刻落盘，界面文案跟着换。
    func testLanguageChangeIsPersisted() throws {
        let created = makeRuntime()

        created.changeLanguage(.simplifiedChinese)

        XCTAssertEqual(created.language, .simplifiedChinese)
        XCTAssertEqual(created.config.language, "zh-CN")
        XCTAssertEqual(try savedJSON()["language"] as? String, "zh-CN")

        created.changeLanguage(.english)
        XCTAssertEqual(created.language, .english)
        XCTAssertEqual(try savedJSON()["language"] as? String, "en")
    }

    // MARK: - 休眠模式

    /// 三种受支持的模式都写得进去。
    func testSupportedSleepModesAreAccepted() throws {
        let created = makeRuntime()

        for mode in [Int32(0), 3, 25] {
            created.setSleepMode(mode)
            XCTAssertEqual(created.config.hibernateMode?.int32Value, mode)
            XCTAssertEqual(try savedJSON()["hibernateMode"] as? Int, Int(mode))
        }
    }

    /// 不受支持的模式被 `normalized()` 丢掉，落盘的是空值。
    func testUnsupportedSleepModeIsDropped() throws {
        let created = makeRuntime()
        created.setSleepMode(3)

        created.setSleepMode(7)

        XCTAssertNil(created.config.hibernateMode)
        XCTAssertTrue(try savedJSON()["hibernateMode"] is NSNull)
    }

    // MARK: - 合盖开关与 helper

    /// helper 没装时不许打开合盖开关。
    ///
    /// 打开它要改 `pmset`，而只有 helper 有 root。让开关亮着会骗用户。
    func testLidSwitchIsRefusedWithoutTheHelper() throws {
        let created = makeRuntime(engineStarted: true)
        XCTAssertEqual(created.helperStatus, .notInstalled)

        created.setDisableLidWhileCharging(true)
        created.setDisableLidOnBattery(true)

        XCTAssertFalse(created.config.disableLidSleepInCharging)
        XCTAssertFalse(created.config.disableLidSleepOnBattery)
        XCTAssertNotNil(created.statusMessage, "拒绝时必须给用户一句话")
    }

    /// helper 在时开关正常。
    func testLidSwitchIsAcceptedWithTheHelper() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        XCTAssertEqual(created.helperStatus, .installed)

        created.setDisableLidWhileCharging(true)

        XCTAssertTrue(created.config.disableLidSleepInCharging)
        XCTAssertEqual(try savedJSON()["disableLidSleepInCharging"] as? Bool, true)
    }

    /// 关掉开关不需要 helper。用户总是能撤销一个已经生效的限制。
    func testLidSwitchCanAlwaysBeTurnedOff() throws {
        let created = makeRuntime(engineStarted: true)

        created.setDisableLidWhileCharging(false)
        created.setDisableLidOnBattery(false)

        XCTAssertFalse(created.config.disableLidSleepInCharging)
        XCTAssertNil(created.statusMessage)
    }

    /// 闲置开关不经过 helper，直接写。
    func testIdleSwitchDoesNotNeedTheHelper() throws {
        let created = makeRuntime(engineStarted: true)

        created.setDisableIdleWhileCharging(true)

        XCTAssertTrue(created.config.disableIdleSleepInCharging)
        XCTAssertNil(created.statusMessage)
    }

    /// 闲置开关按真实断言状态切换，连续两次回到原状态。
    func testIdleToggleUsesTheActualAssertionState() {
        let created = makeRuntime(engineStarted: true)

        created.toggleIdleSleep()
        XCTAssertFalse(created.appState.idleSleepAvailable)
        XCTAssertEqual(created.appState.idleSleepPrevention, .system)

        created.toggleIdleSleep()
        XCTAssertTrue(created.appState.idleSleepAvailable)
        XCTAssertEqual(created.appState.idleSleepPrevention, .none)
    }

    /// 装 helper 成功后收起欢迎页，并给出成功提示。
    func testInstallHelperSucceeds() async throws {
        let created = makeRuntime(helperInstalled: true)

        created.installHelper()
        await waitUntil { !created.busy }

        XCTAssertEqual(created.helperStatus, .installed)
        XCTAssertEqual(created.statusMessage, ContractCopy.copyOverviewHelperInstalled.text(for: created.language))
        XCTAssertFalse(created.welcomeVisible, "装好之后欢迎页要让位")
    }

    /// 卸载 helper 之后状态回到未安装，并撤销合盖限制。
    func testUninstallHelperClearsTheLidPolicy() async throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        created.setDisableLidWhileCharging(true)
        XCTAssertTrue(created.config.disableLidSleepInCharging)

        created.uninstallHelper()
        await waitUntil { !created.busy }

        XCTAssertEqual(created.helperStatus, .notInstalled)
        XCTAssertTrue(created.appState.lidSleepAvailable, "helper 走了就限制不住了，状态要如实反映")
    }

    // MARK: - 充电上限

    func testApplyChargeLimitPersistsOnlyAfterHelperAccepts() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)

        XCTAssertTrue(created.applyChargeLimit(85))

        XCTAssertEqual(chargeLimitClient.setValues, [85])
        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 85)
        XCTAssertEqual(try savedJSON()["chargeLimitEnabled"] as? Bool, true)
        XCTAssertEqual(try savedJSON()["chargeLimitPercent"] as? Int, 85)
    }

    func testRestoreChargeLimitClearsTheSavedIntent() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        XCTAssertTrue(created.applyChargeLimit(85))

        XCTAssertTrue(created.restoreChargeLimit())

        XCTAssertEqual(chargeLimitClient.restoreCalls, 1)
        XCTAssertFalse(created.config.chargeLimitEnabled)
    }

    func testFailedChargeLimitApplyDoesNotPersistTheIntent() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.setResult = false

        XCTAssertFalse(created.applyChargeLimit(85))

        XCTAssertFalse(created.config.chargeLimitEnabled)
        XCTAssertNotNil(created.statusMessage)
    }

    // MARK: - 清除配置

    /// 清除配置会删掉用户全部设置，回到默认值。
    ///
    /// **警告：** 界面必须先确认。这里只测数据，测不了确认框。
    func testClearConfigRestoresDefaults() throws {
        let created = makeRuntime()
        created.setLowBatteryCapacity(42, valid: true)
        created.changeLanguage(.english)
        created.setSleepMode(25)

        created.clearConfig()

        let defaults = ConfigStore.companion.defaults()
        XCTAssertEqual(created.config.lowBatteryCapacity, defaults.lowBatteryCapacity)
        XCTAssertEqual(created.config.hibernateMode?.int32Value, defaults.hibernateMode?.int32Value)
        XCTAssertEqual(created.config.firstRun, defaults.firstRun)
        XCTAssertNotNil(created.statusMessage)
    }

    func testClearConfigRestoresAnActiveChargeLimitFirst() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        XCTAssertTrue(created.applyChargeLimit(85))

        created.clearConfig()

        XCTAssertEqual(chargeLimitClient.restoreCalls, 1)
        XCTAssertFalse(created.config.chargeLimitEnabled)
    }

    func testFailedChargeLimitRestorePreventsClearingConfig() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        XCTAssertTrue(created.applyChargeLimit(85))
        chargeLimitClient.restoreResult = false

        created.clearConfig()

        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 85)
        XCTAssertEqual(chargeLimitClient.restoreCalls, 1)
        XCTAssertNotNil(created.statusMessage)
    }

    // MARK: - 开关分组

    /// 挂帘相关的开关现在只写配置。行为属于 M3。
    ///
    /// 这条用例是给 M3 的锚点：接上行为时它会失败，提醒把注释一起改掉。
    func testShelfSwitchesOnlyWriteConfig() throws {
        let created = makeRuntime()

        created.setShelfEnabled(false)
        created.setScreenshotInbox(false)
        created.setShelfSounds(false)

        XCTAssertFalse(created.config.shelfEnabled)
        XCTAssertFalse(created.config.screenshotInboxEnabled)
        XCTAssertFalse(created.config.shelfSoundsEnabled)
        XCTAssertEqual(try savedJSON()["shelfEnabled"] as? Bool, false)
    }

    /// 剩下的开关逐条写进对应的键。
    func testRemainingSwitchesWriteTheirOwnKeys() throws {
        let created = makeRuntime()

        created.setEnabled(false)
        created.setLowBatterySleep(false)
        created.setDarkWakeAwareness(false)
        created.setImmediateLidSleep(false)
        created.setNotifications(false)
        created.setUpdateChecks(false)

        let json = try savedJSON()
        XCTAssertEqual(json["enabled"] as? Bool, false)
        XCTAssertEqual(json["lowBatteryCapacitySleep"] as? Bool, false)
        XCTAssertEqual(json["darkWakeAwarenessEnabled"] as? Bool, false)
        XCTAssertEqual(json["lidSleepImmediateOnClose"] as? Bool, false)
        XCTAssertEqual(json["notificationsEnabled"] as? Bool, false)
        XCTAssertEqual(json["updateCheckEnabled"] as? Bool, false)
    }

    /// 提示语可以清掉。
    func testStatusMessageCanBeCleared() throws {
        let created = makeRuntime(engineStarted: true)
        created.setDisableLidWhileCharging(true)
        XCTAssertNotNil(created.statusMessage)

        created.clearStatus()

        XCTAssertNil(created.statusMessage)
    }

    /// 退出走注入的闭包。
    ///
    /// 默认实现真的调 `NSApp.terminate`，测试里换成假闭包，
    /// 否则宿主应用会被结束，剩下的用例都跑不到。
    func testRequestQuitCallsTheInjectedHandler() throws {
        let created = makeRuntime()
        var quits = 0
        created.quitHandler = { quits += 1 }

        created.requestQuit()
        created.requestQuit()

        XCTAssertEqual(quits, 2)
    }
}

private final class FakeChargeLimitClient: ChargeLimitClientProtocol, @unchecked Sendable {
    var status: ChargeLimitHelperStatus?
    var setResult = true
    var restoreResult = true
    var setValues: [Int] = []
    var restoreCalls = 0

    func chargeLimitStatus() -> ChargeLimitHelperStatus? { status }

    func setChargeLimit(percent: Int) -> Bool {
        setValues.append(percent)
        return setResult
    }

    func restoreChargeLimit() -> Bool {
        restoreCalls += 1
        return restoreResult
    }
}

/// 假的登录项。开机自启要写 `~/Library/LaunchAgents`，测试不能碰。
final class FakeLoginItem: NSObject, LoginItem {
    var enabled = false

    func isEnabled() -> Bool { enabled }

    func enable() -> Bool {
        enabled = true
        return true
    }

    func disable() -> Bool {
        enabled = false
        return true
    }
}

/// 假的通知器。测试不能真的弹通知。
final class FakeNotifier: NSObject, Notifier {
    private(set) var notifications: [(title: String, message: String)] = []

    func notify(title: String, subtitle: String, message: String, releaseUrl: String?) {
        notifications.append((title: title, message: message))
    }
}

/// 假的更新检查器。不发网络请求。
final class FakeUpdateChecker: NSObject, UpdateChecker {
    var release: UpdateInfo?

    func latestRelease() -> UpdateInfo? { release }
}
