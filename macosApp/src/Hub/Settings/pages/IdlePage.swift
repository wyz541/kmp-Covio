import SwiftUI

/// 闲置页。
///
/// 顺序：阻止闲置睡眠、充电时也阻止、到点自动取消。
struct IdlePage: View {
    let runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space6) {
            MacCard {
                MacSettingRow(title: ContractCopy.copyIdlePreventIdle.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyIdlePreventIdle.text(for: runtime.language),
                        isOn: Binding(
                            get: { !runtime.appState.idleSleepAvailable },
                            set: { _ in runtime.toggleIdleSleep() }
                        )
                    )
                }
                .settingsRowAnchor(SettingsRowID.idlePrevent)
                MacSettingRow(title: ContractCopy.copyIdleWhileCharging.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyIdleWhileCharging.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.disableIdleSleepInCharging },
                            set: { runtime.setDisableIdleWhileCharging($0) }
                        )
                    )
                }
                .settingsRowAnchor(SettingsRowID.idleCharging)
                if let error = runtime.appState.lastError {
                    MacStatusLine(
                        text: "\(ContractCopy.copyToastError.text(for: runtime.language)) \(error)"
                    )
                }
            }

            MacCard {
                MacSectionTitle(text: ContractCopy.copyIdleCancelAfter.text(for: runtime.language))
                .settingsRowAnchor(SettingsRowID.idleCancel)
                CancellationOptions(language: runtime.language) { runtime.scheduleCancelIdle(seconds: $0) }
                if let remaining = runtime.appState.idleCancelRemainingSeconds {
                    MacStatusLine(
                        text: "\(ContractCopy.copyIdleRemaining.text(for: runtime.language)): "
                            + SettingsFormat.duration(seconds: remaining.int64Value, language: runtime.language)
                    )
                }
            }
        }
    }
}
