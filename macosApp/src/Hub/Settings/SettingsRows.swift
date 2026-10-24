import AppKit
import Combine
import SwiftUI
import kmpDomain

/// 一行数字输入。
///
/// 输入框自己保存文字，所以可以出现「清空后再输入」这种中间状态。
/// 只有能解析成整数时才回调，`valid` 说明这一点。
struct NumberRow: View {
    let label: String
    let value: Int32
    let onChange: (Int, Bool) -> Void

    @State private var text: String = ""

    var body: some View {
        MacSettingRow(title: label) {
            MacNumberField(label: label, text: $text)
                .onChange(of: text) { _, newValue in
                    onChange(Int(newValue) ?? Int(value), Int(newValue) != nil)
                }
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { _, newValue in
            // 只在外部值与输入框解析结果不同的时候才覆盖，
            // 否则用户每敲一个字符都会被改回去。
            if Int(text) != Int(newValue) { text = String(newValue) }
        }
    }
}

/// 到点自动取消的时长。与 Compose 版 `CancellationOptions` 的取值一致。
struct CancellationOptions: View {
    let language: AppLanguage
    let onSelect: (Int64) -> Void

    /// 单位是秒。每行四个。
    private static let options: [Int64] = [300, 600, 1_800, 3_600, 7_200, 10_800, 43_200, 86_400]

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            ForEach(Array(Self.options.chunked(into: 4).enumerated()), id: \.offset) { _, row in
                HStack(spacing: MacTheme.space2) {
                    ForEach(row, id: \.self) { seconds in
                        MacButton(title: SettingsFormat.duration(seconds: seconds, language: language), kind: .plain) {
                            onSelect(seconds)
                        }
                    }
                }
            }
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// helper 的安装与卸载。
///
/// 只有完整发布身份匹配时显示卸载。其余状态只显示一个修复入口。
struct HelperCard: View {
    let runtime: AppRuntime

    var body: some View {
        MacCard {
            MacSectionTitle(text: ContractCopy.copyAppName.text(for: runtime.language))
            MacStatusLine(text: ContractCopy.copyDialogHelperInstallBody.text(for: runtime.language))
            MacStatusLine(
                text: HelperStatusPresentation.value(runtime.helperStatus, language: runtime.language)
            )

            switch runtime.helperStatus {
            case .match:
                MacButton(
                    title: ContractCopy.copyDialogHelperUnavailableTitle.text(for: runtime.language),
                    isEnabled: !runtime.busy
                ) { runtime.uninstallHelper() }
            // 未安装、版本不符、出错三种情况都给安装按钮：
            // 这四种下 helper 都不能用于写入，用户的动作都是修复。
            default:
                MacButton(
                    title: HelperStatusPresentation.repairTitle.text(for: runtime.language),
                    kind: .primary,
                    isEnabled: !runtime.busy
                ) { runtime.installHelper() }
            }

            if let reason = HelperStatusPresentation.readOnlyReason(
                runtime.helperStatus,
                language: runtime.language
            ) {
                MacAlert(
                    message: reason,
                    kind: .warning
                )
            }
        }
    }
}

/// 剪切板设置。
///
/// Carbon 在快捷键被别的应用占用时静默失败，所以每个动作都要显示
/// 「注册失败」，并把备选组合摆出来让用户换一个。
struct ClipboardCard: View {
    let runtime: AppRuntime

    @State private var permissionGranted = ClipboardPaste.hasAccessibilityPermission

    var body: some View {
        MacCard {
            MacSettingRow(title: ContractCopy.copyClipboardSettingsEnabled.text(for: runtime.language)) {
                MacSwitch(
                    label: ContractCopy.copyClipboardSettingsEnabled.text(for: runtime.language),
                    isOn: Binding(
                        get: { runtime.config.clipboardEnabled },
                        set: { runtime.setClipboardEnabled($0) }
                    )
                )
            }
            .settingsRowAnchor(SettingsRowID.clipboardEnabled)

            MacSectionTitle(text: ContractCopy.copyClipboardSettingsHotKeys.text(for: runtime.language))
            ForEach(ClipboardHotKeyAction.allCases, id: \.rawValue) { action in
                HotKeyRow(action: action, runtime: runtime)
            }
            .settingsRowAnchor(SettingsRowID.clipboardHotKeys)

            MacSectionTitle(text: ContractCopy.copyClipboardSettingsAccessibility.text(for: runtime.language))
            MacStatusLine(
                text: "\(ContractCopy.copyClipboardSettingsAccessibility.text(for: runtime.language)): \(accessibilityText)"
            )
            HStack(spacing: MacTheme.space2) {
                MacButton(title: ContractCopy.copyClipboardSettingsRequestPermission.text(for: runtime.language)) {
                    ClipboardPaste.requestAccessibilityPermission()
                }
                MacButton(title: ContractCopy.copyClipboardActionOpenSettings.text(for: runtime.language)) {
                    ClipboardPaste.openAccessibilitySettings()
                }
            }
            MacAlert(
                message: ContractCopy.copyClipboardSettingsAccessibilityFallback.text(for: runtime.language),
                kind: .info
            )
        }
        // 用户去系统设置里授权之后回到本应用，这里要重新读一次。
        // 授权状态没有通知，只能靠这个时机刷新。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionGranted = ClipboardPaste.hasAccessibilityPermission
        }
    }

    private var accessibilityText: String {
        (permissionGranted ? ContractCopy.copyClipboardSettingsGranted : ContractCopy.copyClipboardSettingsNotGranted)
            .text(for: runtime.language)
    }
}

/// 一个动作的快捷键。失败时在下面挂一条警告。
struct HotKeyRow: View {
    let action: ClipboardHotKeyAction
    let runtime: AppRuntime

    var body: some View {
        // 配置里手写的组合可能不在备选里，这时把它排在最前面，
        // 否则分段控件会显示成第一项，与实际情况不符。
        let current = runtime.clipboard.hotKeySpec(for: action).binding
        let options = action.candidates.contains(current)
            ? action.candidates
            : [current] + action.candidates

        VStack(alignment: .leading, spacing: MacTheme.space1) {
            MacSettingRow(title: title) {
                MacSegmented(
                    options: options.map { displayName(of: $0) },
                    selectedIndex: options.firstIndex(of: current) ?? 0
                ) { index in
                    runtime.setClipboardHotKey(action, to: options[index])
                }
            }
            if runtime.clipboard.hasHotKeyConflict(action) {
                MacAlert(
                    message: ContractCopy.copyClipboardSettingsHotKeyConflict.text(for: runtime.language),
                    kind: .warning
                )
            }
        }
    }

    private var title: String {
        switch action {
        case .pasteStack: ContractCopy.copyClipboardSettingsPasteStackHotKey.text(for: runtime.language)
        case .captureSelection: ContractCopy.copyClipboardSettingsCaptureHotKey.text(for: runtime.language)
        }
    }

    /// 界面上的写法。认不出的组合原样显示，用户还能看出自己写错了。
    private func displayName(of binding: String) -> String {
        GlobalHotKey.Spec(binding: binding, id: action.hotKeyID)?.displayName ?? binding
    }
}

/// 深色唤醒的状态行。
struct DarkWakeStatusView: View {
    let runtime: AppRuntime

    var body: some View {
        let status = runtime.appState.darkWake
        MacSectionTitle(text: ContractCopy.copyGeneralDarkwake.text(for: runtime.language))
        if status.scanning {
            MacStatusLine(text: ContractCopy.copyStateLoading.text(for: runtime.language))
        } else if !status.available {
            MacStatusLine(text: ContractCopy.copyStateEmpty.text(for: runtime.language))
        } else {
            let last = status.lastAtEpochSeconds.map {
                SettingsFormat.wakeTime(epochSeconds: $0.int64Value)
            } ?? ContractCopy.copyStateEmpty.text(for: runtime.language)
            MacStatusLine(text: "\(ContractCopy.copyGeneralDarkwake.text(for: runtime.language)): \(last)")
            MacStatusLine(text: "\(status.lastReason ?? ContractCopy.copyStateEmpty.text(for: runtime.language))")
            MacStatusLine(text: "\(status.count24h)")
        }
    }
}

/// 休眠模式。取值来自 Kotlin 的 `SUPPORTED_HIBERNATE_MODES`，不在这里写死。
struct SleepModeOptions: View {
    let runtime: AppRuntime

    private static let modes: [Int32] = ModelsKt.SUPPORTED_HIBERNATE_MODES
        .map { $0.int32Value }
        .sorted()

    var body: some View {
        MacSegmented(
            options: Self.modes.map { SettingsFormat.sleepModeLabel($0, language: runtime.language) },
            selectedIndex: Self.modes.firstIndex(of: runtime.config.hibernateMode?.int32Value ?? -1) ?? 0
        ) { index in
            runtime.setSleepMode(Self.modes[index])
        }
    }
}

/// 界面语言。取值与 Kotlin 的 `AppLanguage` 一致。
struct LanguageOptions: View {
    let runtime: AppRuntime

    private static let languages: [AppLanguage] = [.english, .simplifiedChinese]

    var body: some View {
        MacSegmented(
            options: [
                ContractCopy.copyGeneralLanguageEnglish.text(for: runtime.language),
                ContractCopy.copyGeneralLanguageChinese.text(for: runtime.language),
            ],
            selectedIndex: Self.languages.firstIndex(of: runtime.language) ?? 0
        ) { index in
            runtime.changeLanguage(Self.languages[index])
        }
    }
}
