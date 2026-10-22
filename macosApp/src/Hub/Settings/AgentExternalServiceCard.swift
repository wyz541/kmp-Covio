import AppKit
import SwiftUI

struct AgentExternalServiceCard: View {
    let runtime: AppRuntime

    @State private var enabled: Bool
    @State private var copied = false

    init(runtime: AppRuntime) {
        self.runtime = runtime
        _enabled = State(initialValue: runtime.agentExternalServiceEnabled)
    }

    var body: some View {
        MacCard {
            MacSectionTitle(text: ContractCopy.copyGeneralExternalAgentTitle.text(for: runtime.language))
            Text(ContractCopy.copyGeneralExternalAgentSummary.text(for: runtime.language))
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            MacSettingRow(
                title: ContractCopy.copyGeneralExternalAgentEnabled.text(for: runtime.language)
            ) {
                MacSwitch(
                    label: ContractCopy.copyGeneralExternalAgentEnabled.text(for: runtime.language),
                    isOn: Binding(
                        get: { enabled },
                        set: {
                            enabled = $0
                            copied = false
                            runtime.setAgentExternalServiceEnabled($0)
                        }
                    )
                )
            }

            if enabled {
                endpointRow
                HStack(spacing: MacTheme.space2) {
                    MacButton(
                        title: ContractCopy.copyGeneralExternalAgentCopyPairing.text(for: runtime.language),
                        isEnabled: runtime.agentExternalService?.endpointURL != nil
                    ) {
                        copyPairing()
                    }
                    MacButton(
                        title: ContractCopy.copyGeneralExternalAgentRotateToken.text(for: runtime.language)
                    ) {
                        copied = false
                        runtime.rotateAgentExternalToken()
                    }
                }
                if copied {
                    MacAlert(
                        message: ContractCopy.copyGeneralExternalAgentCopied.text(for: runtime.language),
                        kind: .success
                    )
                }
                MacAlert(
                    message: ContractCopy.copyGeneralExternalAgentWarning.text(for: runtime.language),
                    kind: .info
                )
            }

            if let error = runtime.agentExternalError ?? runtime.agentExternalService?.lastError {
                MacAlert(message: error, kind: .error)
            }
        }
        .onChange(of: runtime.agentExternalServiceEnabled) { _, next in
            enabled = next
        }
    }

    @ViewBuilder
    private var endpointRow: some View {
        if let endpoint = runtime.agentExternalService?.endpointURL?.absoluteString {
            MacSettingRow(
                title: ContractCopy.copyGeneralExternalAgentEndpoint.text(for: runtime.language)
            ) {
                Text(endpoint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MacTheme.textPrimary)
                    .textSelection(.enabled)
            }
        } else {
            MacStatusLine(
                text: ContractCopy.copyGeneralExternalAgentStarting.text(for: runtime.language)
            )
        }
    }

    private func copyPairing() {
        guard let endpoint = runtime.agentExternalService?.endpointURL?.absoluteString,
              let token = runtime.agentExternalService?.token
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let text = "Endpoint: \(endpoint)\nAuthorization: Bearer \(token)"
        copied = pasteboard.setString(text, forType: .string)
    }
}
