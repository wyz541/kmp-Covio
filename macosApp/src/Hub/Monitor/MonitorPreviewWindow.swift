#if DEBUG
import AppKit
import SwiftUI
import kmpDomain

/// 调试构建的独立监控窗口。
///
/// 全量运行时会在系统唤醒回调里执行已有逻辑。这个入口绕过运行时，
/// 只用来检查 `MonitorTabView` 的真实布局和读数。
struct MonitorPreviewRoot: View {
    private let language = AppLanguage.simplifiedChinese
    let snapshot: MonitorSnapshot
    let history: MonitorHistory
    let powerHistory: MonitorPowerHistory
    let runsSampling: Bool
    let startsInPower: Bool
    let powerModel: (any PowerManagementModel)?

    init(
        snapshot: MonitorSnapshot = .empty,
        history: MonitorHistory = MonitorHistory(),
        powerHistory: MonitorPowerHistory = MonitorPowerHistory(),
        runsSampling: Bool = true,
        startsInPower: Bool = false,
        powerModel: (any PowerManagementModel)? = nil
    ) {
        self.snapshot = snapshot
        self.history = history
        self.powerHistory = powerHistory
        self.runsSampling = runsSampling
        self.startsInPower = startsInPower
        self.powerModel = powerModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetrics.pageHeadingGap) {
            PaneHeading(
                title: ContractCopy.copyHubTabDevices.text(for: language),
                summary: ContractCopy.copyHubTabDevicesSummary.text(for: language)
            )
            MonitorTabView(
                language: language,
                powerModel: powerModel,
                initialSnapshot: snapshot,
                initialHistory: history,
                initialPowerHistory: powerHistory,
                runsSampling: runsSampling,
                startsInPower: startsInPower
            )
            .frame(height: HubMetrics.monitorBodyHeight)
        }
        .padding(HubMetrics.panelPadding)
        .frame(width: HubMetrics.panelWidth, height: HubMetrics.monitorBodyHeight + 92)
        .background(MacTheme.canvas)
    }
}

/// 电源管理面的固定样本。只用于调试预览，不执行系统动作。
@MainActor
@Observable
final class PowerPreviewModel: PowerManagementModel {
    let language = AppLanguage.simplifiedChinese
    var powerConfig: PowerConfig
    var observation: PowerObservation
    var snapshot: PowerSnapshot
    var decision: PowerDecision
    var helperStatus: HelperStatus = .installed
    var executionError: String?
    var hasManualSession = true
    var sessionMode: PowerRuntime.SessionMode? = .lid
    var remainingSeconds: Int64? = 2_700
    var appState: AppState = AppRuntime.initialState(enabled: true)
    var statusMessage: String?
    var busy = false

    init() {
        powerConfig = PowerConfig(
            enabled: true,
            keepAwakeOnAdapter: true,
            keepAwakeOnBattery: false,
            allowClosedLid: true,
            pauseClosedLidWithExternalDisplay: true,
            batteryFloorPercent: 15,
            batteryFloorRecoveryPercent: 20,
            yieldOnLowPowerMode: true,
            heatGuardEnabled: true,
            closedLidTimeCapMinutes: 240
        )
        let sampleObservation = PowerObservation(
            batteryPercent: KotlinInt(int: 84),
            hasBattery: KotlinBoolean(bool: true),
            powerState: .acPower,
            externalDisplayCount: KotlinInt(int: 0),
            lidState: .open,
            thermalState: .nominal,
            lowPowerModeEnabled: KotlinBoolean(bool: false)
        )
        observation = sampleObservation
        snapshot = PowerSnapshot(
            observation: sampleObservation,
            helperStatus: .installed,
            sleepDisabled: KotlinBoolean(bool: false),
            covioOwnsSleepDisabled: KotlinBoolean(bool: false)
        )
        decision = PowerDecision(
            preventUserIdleSystemSleep: true,
            preventUserIdleDisplaySleep: true,
            preventLidSleep: true,
            appliedLeaseLevel: .closedLid,
            activeLeaseIds: ["power/session/preview"],
            automaticRuleApplied: false,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
    }

    func setPowerEnabled(_ enabled: Bool) { powerConfig = copyPower(enabled: enabled) }
    func setPowerKeepAwakeOnAdapter(_ enabled: Bool) { powerConfig = copyPower(adapter: enabled) }
    func setPowerKeepAwakeOnBattery(_ enabled: Bool) { powerConfig = copyPower(battery: enabled) }
    func setPowerAllowClosedLid(_ enabled: Bool) { powerConfig = copyPower(lid: enabled) }
    func setPowerPauseClosedLidWithExternalDisplay(_ enabled: Bool) { powerConfig = copyPower(external: enabled) }
    func setPowerYieldOnLowPowerMode(_ enabled: Bool) { powerConfig = copyPower(lowPower: enabled) }
    func setPowerHeatGuard(_ enabled: Bool) { powerConfig = copyPower(heat: enabled) }
    func setPowerBatteryFloor(_ percent: Int) { powerConfig = copyPower(floor: Int32(percent)) }
    func setPowerClosedLidTimeCapMinutes(_ minutes: Int) { powerConfig = copyPower(cap: Int32(minutes)) }

    func startSession(mode: PowerRuntime.SessionMode, duration: PowerRuntime.SessionDuration) -> Bool {
        hasManualSession = true
        sessionMode = mode
        remainingSeconds = duration.seconds
        let level: HoldLeaseLevel = switch mode {
        case .system: .system
        case .display: .systemAndDisplay
        case .lid: .closedLid
        }
        decision = PowerDecision(
            preventUserIdleSystemSleep: true,
            preventUserIdleDisplaySleep: level != .system,
            preventLidSleep: level == .closedLid,
            appliedLeaseLevel: level,
            activeLeaseIds: ["power/session/preview"],
            automaticRuleApplied: false,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
        return true
    }

    func endSession() {
        hasManualSession = false
        sessionMode = nil
        remainingSeconds = nil
        decision = PowerDecision(
            preventUserIdleSystemSleep: true,
            preventUserIdleDisplaySleep: false,
            preventLidSleep: false,
            appliedLeaseLevel: nil,
            activeLeaseIds: [],
            automaticRuleApplied: true,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
    }

    func installHelper() {
        helperStatus = .installed
        statusMessage = ContractCopy.copyOverviewHelperInstalled.text(for: language)
    }

    private func copyPower(
        enabled: Bool? = nil,
        adapter: Bool? = nil,
        battery: Bool? = nil,
        lid: Bool? = nil,
        external: Bool? = nil,
        lowPower: Bool? = nil,
        heat: Bool? = nil,
        floor: Int32? = nil,
        cap: Int32? = nil
    ) -> PowerConfig {
        PowerConfig(
            enabled: enabled ?? powerConfig.enabled,
            keepAwakeOnAdapter: adapter ?? powerConfig.keepAwakeOnAdapter,
            keepAwakeOnBattery: battery ?? powerConfig.keepAwakeOnBattery,
            allowClosedLid: lid ?? powerConfig.allowClosedLid,
            pauseClosedLidWithExternalDisplay: external ?? powerConfig.pauseClosedLidWithExternalDisplay,
            batteryFloorPercent: floor ?? powerConfig.batteryFloorPercent,
            batteryFloorRecoveryPercent: min((floor ?? powerConfig.batteryFloorPercent) + 5, 100),
            yieldOnLowPowerMode: lowPower ?? powerConfig.yieldOnLowPowerMode,
            heatGuardEnabled: heat ?? powerConfig.heatGuardEnabled,
            closedLidTimeCapMinutes: cap ?? powerConfig.closedLidTimeCapMinutes
        )
    }
}

@MainActor
enum MonitorSnapshotRenderer {
    static func render(to path: String) async -> Bool {
        let sampler = MonitorSampler()
        var history = MonitorHistory()
        var powerHistory = MonitorPowerHistory()
        var snapshot = MonitorSnapshot.empty
        // 能耗窗口要跨过第一次 10 秒基线，截图才会显示真实的 Top3。
        for index in 0..<26 {
            snapshot = await sampler.sample()
            history.append(snapshot)
            if let power = snapshot.power {
                powerHistory.append(power)
            }
            guard index < 25 else { continue }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return false
            }
        }

        // ImageRenderer 不能合成 `.glassEffect`。截图时临时换成常规材质，
        // 布局与内容不变，只替代无法离屏渲染的玻璃层。
        let previousMode = GlassSurfaceMode.current
        GlassSurfaceMode.current = .material
        defer { GlassSurfaceMode.current = previousMode }

        let colorScheme: ColorScheme = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark" ? .dark : .light
        let renderer = ImageRenderer(
            content: MonitorPreviewRoot(
                snapshot: snapshot,
                history: history,
                powerHistory: powerHistory,
                runsSampling: false
            )
            .environment(\.colorScheme, colorScheme)
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
enum MonitorPowerDetailRenderer {
    static func render(to path: String) async -> Bool {
        let sampler = MonitorSampler()
        var powerHistory = MonitorPowerHistory()
        var power = MonitorSnapshot.Power.empty
        for index in 0..<26 {
            power = await sampler.samplePowerOnly()
            powerHistory.append(power)
            guard index < 25 else { continue }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return false
            }
        }

        let colorScheme: ColorScheme = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark" ? .dark : .light
        let content = MonitorPowerDetailPanel(
            power: power,
            history: powerHistory,
            language: .simplifiedChinese,
            reduceMotion: false,
            runtime: nil,
            onOpenApp: { _ in },
            onClose: {}
        )
        .environment(\.colorScheme, colorScheme)
        .padding(24)
        .background(MacTheme.canvas)

        let renderer = ImageRenderer(content: content)
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
    init(startsInPower: Bool = false, powerModel: (any PowerManagementModel)? = nil) {
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
        window.title = startsInPower ? "Covio Power Preview" : "Covio Monitor Preview"
        window.appearance = HubAppearance.panel
        window.contentView = NSHostingView(
            rootView: MonitorPreviewRoot(startsInPower: startsInPower, powerModel: powerModel)
        )
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
