import Foundation
import ServiceManagement
import kmpDomain

/// `SMAppService` 生命周期状态。发布身份握手状态仍由 `HelperStatus` 表示。
enum HelperServiceState: Equatable, Sendable {
    case legacy
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unsupported
    case error(String)

    var allowsXPC: Bool { self == .enabled }
}

protocol SMAppServiceBacking: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

protocol HelperServiceManaging: AnyObject {
    var state: HelperServiceState { get }
    var lastError: String? { get }
    var hasRegisteredService: Bool { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

final class RealSMAppServiceBacking: SMAppServiceBacking {
    private let service = SMAppService.daemon(plistName: HelperProtocol.daemonPlistName)

    var status: SMAppService.Status { service.status }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

/// app 对系统 daemon 生命周期的唯一入口。
final class SMAppHelperServiceManager: HelperServiceManaging, @unchecked Sendable {
    static let shared = SMAppHelperServiceManager()

    private let backing: any SMAppServiceBacking
    private let legacyPlistPath: String
    private let legacySocketPath: String
    private let openSettings: () -> Void
    private let errorLock = NSLock()
    private var lastErrorStorage: String?
    private var registrationPendingStorage = false

    init(
        backing: any SMAppServiceBacking = RealSMAppServiceBacking(),
        legacyPlistPath: String = HelperProtocol.plistPath,
        legacySocketPath: String = HelperProtocol.socketPath,
        openSettings: @escaping () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        }
    ) {
        self.backing = backing
        self.legacyPlistPath = legacyPlistPath
        self.legacySocketPath = legacySocketPath
        self.openSettings = openSettings
    }

    var state: HelperServiceState {
        if let lastError { return .error(lastError) }
        // 旧 LaunchDaemon 与新 daemon 使用同一 Label。只要 legacy plist 或 socket
        // 还在，就必须继续走 legacy transport，直到一次迁移完整清除旧安装。
        if legacyExists { return .legacy }
        switch backing.status {
        case .enabled:
            clearRegistrationPending()
            return .enabled
        case .requiresApproval:
            clearRegistrationPending()
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            if registrationPending { return .requiresApproval }
            return .notRegistered
        @unknown default:
            return .unsupported
        }
    }

    var lastError: String? {
        errorLock.withLock { lastErrorStorage }
    }

    var hasRegisteredService: Bool {
        backing.status == .enabled || backing.status == .requiresApproval
    }

    func register() throws {
        setLastError(nil)
        do {
            try backing.register()
            errorLock.withLock { registrationPendingStorage = true }
        } catch {
            setLastError(error.localizedDescription)
            throw HelperServiceError.registration(error)
        }
    }

    func unregister() throws {
        setLastError(nil)
        do {
            try backing.unregister()
            errorLock.withLock { registrationPendingStorage = false }
        } catch {
            setLastError(error.localizedDescription)
            throw HelperServiceError.unregistration(error)
        }
    }

    func openSystemSettings() {
        openSettings()
    }

    private var legacyExists: Bool {
        FileManager.default.fileExists(atPath: legacyPlistPath)
            || FileManager.default.fileExists(atPath: legacySocketPath)
    }

    private func setLastError(_ value: String?) {
        errorLock.withLock { lastErrorStorage = value }
    }

    private var registrationPending: Bool {
        errorLock.withLock { registrationPendingStorage }
    }

    private func clearRegistrationPending() {
        errorLock.withLock { registrationPendingStorage = false }
    }
}

enum HelperServiceError: LocalizedError {
    case registration(Error)
    case unregistration(Error)

    var errorDescription: String? {
        switch self {
        case .registration(let error):
            "Cannot register CovioHelper: \(error.localizedDescription)"
        case .unregistration(let error):
            "Cannot unregister CovioHelper: \(error.localizedDescription)"
        }
    }
}
