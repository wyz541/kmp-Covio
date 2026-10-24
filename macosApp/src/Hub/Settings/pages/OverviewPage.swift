import SwiftUI
import kmpDomain

/// 概览页。
///
/// 顺序：主控卡（总开关与两个立即动作）、helper 卡、状态行。
/// 状态是只读信息，所以排在最后。
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

            HelperCard(runtime: runtime)
                .settingsRowAnchor(SettingsRowID.overviewHelper)

            MacCard {
                MacStatusLine(text: runtime.batteryText())
                MacStatusLine(text: helperText)
                MacStatusLine(
                    text: "\(ContractCopy.copyOverviewHelperVersion.text(for: runtime.language)): \(GeneratedReleaseIdentityKt.APP_VERSION)"
                )
            }
        }
    }

    private var helperText: String {
        switch runtime.helperStatus {
        case .installed: ContractCopy.copyOverviewHelperInstalled.text(for: runtime.language)
        case .notInstalled: ContractCopy.copyOverviewHelperMissing.text(for: runtime.language)
        // Kotlin 枚举导出成类，Swift 看不出它有几种取值，所以要有 default。
        default: ContractCopy.copyStatusItemHelperError.text(for: runtime.language)
        }
    }
}
