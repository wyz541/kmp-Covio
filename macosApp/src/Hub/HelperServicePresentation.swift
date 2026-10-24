import Foundation

/// SMAppService 生命周期状态的界面文案。
enum HelperServicePresentation {
    static func value(_ state: HelperServiceState, language: AppLanguage) -> String {
        switch state {
        case .legacy:
            ContractCopy.copyHelperServiceLegacy.text(for: language)
        case .notRegistered:
            ContractCopy.copyHelperServiceNotRegistered.text(for: language)
        case .enabled:
            ContractCopy.copyHelperServiceEnabled.text(for: language)
        case .requiresApproval:
            ContractCopy.copyHelperServiceRequiresApproval.text(for: language)
        case .notFound:
            ContractCopy.copyHelperServiceNotFound.text(for: language)
        case .unsupported:
            ContractCopy.copyHelperServiceUnsupported.text(for: language)
        case .error(let message):
            "\(ContractCopy.copyHelperServiceError.text(for: language)): \(message)"
        }
    }

    static func actionTitle(_ state: HelperServiceState, language: AppLanguage) -> String? {
        state == .requiresApproval
            ? ContractCopy.copyClipboardActionOpenSettings.text(for: language)
            : nil
    }
}
