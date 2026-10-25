import Foundation
import kmpDomain

/// 安装、迁移与卸载特权 helper。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/helper/HelperInstaller.kt`。
/// 生成的 shell 脚本与 plist 来自共享模块的 `HelperInstallScript`，
/// 所以 0.4.2 装上的 helper 可以被本版卸载，反之亦然。
///
/// 新安装只使用 `SMAppService`。Legacy 安装脚本只用于移除旧 LaunchDaemon。
///
/// **警告：** 移除 legacy helper 会用 `osascript` 请求管理员权限。
/// 只有检测到旧 LaunchDaemon 时才会走这条路径。
enum HelperInstaller {
    enum InstallResult: Equatable {
        case enabled
        case requiresApproval
        case failed(String)

        var registered: Bool {
            switch self {
            case .enabled, .requiresApproval: true
            case .failed: false
            }
        }
    }

    /// 恢复旧 helper 的活动状态，移除 legacy LaunchDaemon，再注册签名 daemon。
    static func migrateAndRegister(
        serviceManager: any HelperServiceManaging = SMAppHelperServiceManager.shared,
        logger: (String) -> Void = { _ in }
    ) -> InstallResult {
        let client = HelperClient()
        let previousState = serviceManager.state
        let expectsRunningHelper = previousState == .enabled
            || FileManager.default.fileExists(atPath: HelperProtocol.socketPath)
        guard restorePrivilegedState(
            using: client,
            expectRunningHelper: expectsRunningHelper,
            logger: logger
        ) else {
            return .failed("Cannot restore privileged state before helper migration")
        }

        if serviceManager.hasRegisteredService {
            do {
                logger("Unregistering the previous SMAppService helper")
                try serviceManager.unregister()
            } catch {
                logger(error.localizedDescription)
                return .failed(error.localizedDescription)
            }
        }

        if FileManager.default.fileExists(atPath: HelperProtocol.plistPath) {
            logger("Removing the legacy LaunchDaemon")
            guard removeLegacyInstallation(logger: logger) else {
                return .failed("Cannot remove the legacy LaunchDaemon")
            }
        }

        do {
            logger("Registering CovioHelper with SMAppService")
            try serviceManager.register()
        } catch {
            logger(error.localizedDescription)
            return .failed(error.localizedDescription)
        }

        switch serviceManager.state {
        case .enabled:
            return .enabled
        case .requiresApproval, .notRegistered:
            return .requiresApproval
        case .notFound:
            return .failed("SMAppService cannot find the bundled daemon plist")
        case .legacy:
            return .failed("The legacy LaunchDaemon still exists")
        case .unsupported:
            return .failed("This macOS version cannot manage the helper daemon")
        case .error(let message):
            return .failed(message)
        }
    }

    /// 保持旧的维护命令入口。新路径不再安装 legacy daemon。
    static func install(executablePath _: String, logger: (String) -> Void = { _ in }) -> Bool {
        migrateAndRegister(logger: logger).registered
    }

    /// 安装事务已经完成前置状态恢复。这里只替换 daemon 注册，不再访问旧 helper。
    static func registerForInstallTransaction(
        serviceManager: any HelperServiceManaging = SMAppHelperServiceManager.shared,
        legacyPlistPath: String = HelperProtocol.plistPath,
        logger: (String) -> Void = { _ in }
    ) -> InstallResult {
        if FileManager.default.fileExists(atPath: legacyPlistPath) {
            return .failed("Legacy helper must be removed before the install transaction")
        }
        if serviceManager.hasRegisteredService {
            do {
                logger("Unregistering the previous SMAppService helper")
                try serviceManager.unregister()
            } catch {
                logger(error.localizedDescription)
                return .failed(error.localizedDescription)
            }
        }
        do {
            logger("Registering the transaction helper with SMAppService")
            try serviceManager.register()
        } catch {
            logger(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
        switch serviceManager.state {
        case .enabled:
            return .enabled
        case .requiresApproval, .notRegistered:
            return .requiresApproval
        case .notFound:
            return .failed("SMAppService cannot find the bundled daemon plist")
        case .legacy:
            return .failed("The legacy LaunchDaemon still exists")
        case .unsupported:
            return .failed("This macOS version cannot manage the helper daemon")
        case .error(let message):
            return .failed(message)
        }
    }

    static func uninstall(
        serviceManager: any HelperServiceManaging = SMAppHelperServiceManager.shared,
        logger: (String) -> Void = { _ in }
    ) -> Bool {
        let client = HelperClient()
        let state = serviceManager.state
        let expectsRunningHelper = state == .enabled
            || FileManager.default.fileExists(atPath: HelperProtocol.socketPath)
        guard restorePrivilegedState(
            using: client,
            expectRunningHelper: expectsRunningHelper,
            logger: logger
        ) else {
            return false
        }
        if serviceManager.hasRegisteredService {
            do {
                logger("Unregistering CovioHelper")
                try serviceManager.unregister()
            } catch {
                logger(error.localizedDescription)
                return false
            }
        }

        if FileManager.default.fileExists(atPath: HelperProtocol.plistPath) {
            return removeLegacyInstallation(logger: logger)
        }
        return true
    }

    /// 在升级、卸载或迁移前恢复 helper 持有的系统状态。
    static func restorePrivilegedState(
        using client: HelperClient,
        expectRunningHelper: Bool = false,
        logger: (String) -> Void = { _ in }
    ) -> Bool {
        let chargeStatus = client.chargeLimitStatus()
        if expectRunningHelper && chargeStatus == nil {
            logger("Cannot continue: helper charge status is unavailable")
            return false
        }
        if chargeStatus?.enabled == true {
            logger("Restoring charge limit before helper change")
            guard client.restoreChargeLimit() else {
                logger("Cannot continue: charge limit restore failed")
                return false
            }
            logger("Charge limit restored")
        }
        let fanStatus = client.fanControlStatus()
        if expectRunningHelper && fanStatus == nil {
            logger("Cannot continue: helper fan status is unavailable")
            return false
        }
        if fanStatus?.active == true {
            logger("Restoring system fan control before helper change")
            guard client.restoreFanControl().ok else {
                logger("Cannot continue: fan control restore failed")
                return false
            }
        }
        return true
    }

    /// 卸载前恢复原 MCL。失败时保留 helper 和状态文件，避免丢失恢复凭据。
    static func restoreChargeLimitIfNeeded(
        using client: any ChargeLimitClientProtocol,
        logger: (String) -> Void = { _ in }
    ) -> Bool {
        guard let status = client.chargeLimitStatus(), status.enabled else { return true }
        logger("Restoring charge limit before helper change")
        guard client.restoreChargeLimit() else {
            logger("Cannot continue: charge limit restore failed")
            return false
        }
        logger("Charge limit restored")
        return true
    }

    /// 安装脚本。可单独测试，不需要管理员权限。
    ///
    /// 四个参数都显式传给共享层：Kotlin 的默认参数值不导出到 Swift。
    static func installScript(
        executablePath: String,
        uid: String = currentUid(),
        version: String = GeneratedReleaseIdentityKt.APP_VERSION,
        clientRequirement: String? = nil
    ) -> String {
        HelperInstallScript.shared.installScript(
            executablePath: executablePath,
            uid: uid,
            version: version,
            clientRequirement: clientRequirement
        )
    }

    /// 卸载脚本。先验证充电状态已清除，再清 `disablesleep`。
    static func uninstallScript() -> String {
        HelperInstallScript.shared.uninstallScript()
    }

    static func plistText(executablePath: String) -> String {
        HelperInstallScript.shared.plistText(executablePath: executablePath)
    }

    /// 当前用户的 uid。写进 `allowed_uid`，helper 用它拒绝其他用户的连接。
    static func currentUid() -> String {
        String(getuid())
    }

    // MARK: - 私有

    private static func removeLegacyInstallation(logger: (String) -> Void) -> Bool {
        logger("Removing legacy privileged helper")
        return runWithAdministrator(uninstallScript())
    }

    private static func runWithAdministrator(_ shellScript: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(HelperInstallScript.shared.appleScriptEscaped(script: shellScript))\" with administrator privileges",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return false
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            FileHandle.standardError.write(output)
            return false
        }
        return true
    }
}
