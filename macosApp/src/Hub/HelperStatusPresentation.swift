import Foundation
import kmpDomain

/// Helper 握手状态在界面上的唯一文案映射。
enum HelperStatusPresentation {
    static func value(_ status: HelperStatus, language: AppLanguage) -> String {
        switch status {
        case .match:
            ContractCopy.copyOverviewHelperInstalled.text(for: language)
        case .missing:
            ContractCopy.copyOverviewHelperMissing.text(for: language)
        case .outdated:
            ContractCopy.copyStatusItemHelperOutdated.text(for: language)
        case .identityMismatch:
            ContractCopy.copyStatusItemHelperIdentityMismatch.text(for: language)
        case .untrusted:
            ContractCopy.copyStatusItemHelperUntrusted.text(for: language)
        default:
            ContractCopy.copyStatusItemHelperError.text(for: language)
        }
    }

    static func readOnlyReason(_ status: HelperStatus, language: AppLanguage) -> String? {
        status == .match ? nil : ContractCopy.copyStatusItemHelperSafeMode.text(for: language)
    }

    static var repairTitle: LocalizedCopy { ContractCopy.copyMonitorFanInstallHelper }
}
