import SwiftUI

/// 概览页。
///
/// 顺序：主控卡（总开关与两个立即动作）、状态行。
/// Helper 属于 Covio 全局运行能力，不在设置页单独显示。
struct OverviewPage: View {
    let runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space6) {
            MacCard {
                MacSettingRow(title: ContractCopy.copyOverviewRulesMaster.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyOverviewRulesMaster.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.enabled },
                            set: { runtime.setEnabled($0) }
                        )
                    )
                }
                .settingsRowAnchor(SettingsRowID.overviewMaster)
                HStack(spacing: MacTheme.space2) {
                    MacButton(
                        title: ContractCopy.copyOverviewActionSleepNow.text(for: runtime.language),
                        kind: .primary
                    ) { runtime.sleepNow() }
                    MacButton(title: ContractCopy.copyOverviewActionDisplayOff.text(for: runtime.language)) {
                        runtime.displaySleepNow()
                    }
                }
            }

            MacCard {
                MacStatusLine(text: runtime.batteryText())
            }
        }
    }
}
