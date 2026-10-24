import SwiftUI

/// 合盖页。
///
/// 顺序：合盖即睡、合盖不睡、充电时不睡、电池规则。
/// 三条规则要改 `pmset`，所以没装 helper 时不可用。
struct LidPage: View {
    let runtime: AppRuntime

    /// 合盖策略要改 `pmset`，所以没装 helper 时这几项不可用。
    private var controlsEnabled: Bool { runtime.helperStatus == .match }

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space6) {
            MacCard {
                MacSettingRow(title: ContractCopy.copyLidInstantSleep.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyLidInstantSleep.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.lidSleepImmediateOnClose },
                            set: { runtime.setImmediateLidSleep($0) }
                        )
                    )
                }
                .settingsRowAnchor(SettingsRowID.lidInstant)
                MacSettingRow(title: ContractCopy.copyLidPreventSleep.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyLidPreventSleep.text(for: runtime.language),
                        isOn: Binding(
                            get: { !runtime.appState.lidSleepAvailable },
                            set: { _ in runtime.toggleLidSleep() }
                        ),
                        isEnabled: controlsEnabled
                    )
                }
                .settingsRowAnchor(SettingsRowID.lidPrevent)
                MacSettingRow(title: ContractCopy.copyLidPowerRules.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyLidPowerRules.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.disableLidSleepInCharging },
                            set: { runtime.setDisableLidWhileCharging($0) }
                        ),
                        isEnabled: controlsEnabled
                    )
                }
                .settingsRowAnchor(SettingsRowID.lidPower)
                MacSettingRow(title: ContractCopy.copyLidBatteryRules.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyLidBatteryRules.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.disableLidSleepOnBattery },
                            set: { runtime.setDisableLidOnBattery($0) }
                        ),
                        isEnabled: controlsEnabled
                    )
                }
                .settingsRowAnchor(SettingsRowID.lidBattery)
            }

            if !controlsEnabled {
                MacAlert(
                    message: ContractCopy.copyDialogHelperUnavailableBody.text(for: runtime.language),
                    kind: .warning
                )
            }

            MacAlert(message: ContractCopy.copyLidWarning.text(for: runtime.language), kind: .warning)
        }
    }
}
