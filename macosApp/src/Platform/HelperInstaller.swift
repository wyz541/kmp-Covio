import Foundation
import kmpDomain

/// 安装与卸载特权 helper。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/helper/HelperInstaller.kt`。
/// 生成的 shell 脚本与 plist 来自共享模块的 `HelperInstallScript`，
/// 所以 0.4.2 装上的 helper 可以被本版卸载，反之亦然。
///
/// **警告：** 安装会用 `osascript` 请求管理员权限。脚本以 root 运行，
/// 会写入 `/Library/LaunchDaemons`。调用前先确认用户已经同意。
enum HelperInstaller {
    /// 安装 helper 并启动 LaunchDaemon。
    /// - Parameter executablePath: 应用可执行文件的绝对路径。
    ///   它写进 plist 的 `ProgramArguments[0]`，也是 helper 进程自己的路径。
    static func install(executablePath: String, logger: (String) -> Void = { _ in }) -> Bool {
        let requirement = HelperSignature.currentRequirement()
        if requirement == nil {
            logger("Cannot determine the client signature requirement; charge control will stay unavailable.")
        }
        let script = installScript(
            executablePath: executablePath,
            clientRequirement: requirement
        )
        logger("Installing privileged helper")
        return runWithAdministrator(script)
    }

    static func uninstall(logger: (String) -> Void = { _ in }) -> Bool {
        let script = uninstallScript()
        logger("Uninstalling privileged helper")
        return runWithAdministrator(script)
    }

    /// 安装脚本。可单独测试，不需要管理员权限。
    ///
    /// 四个参数都显式传给共享层：Kotlin 的默认参数值不导出到 Swift。
    static func installScript(
        executablePath: String,
        uid: String = currentUid(),
        version: String = ModelsKt.APP_VERSION,
        clientRequirement: String? = nil
    ) -> String {
        HelperInstallScript.shared.installScript(
            executablePath: executablePath,
            uid: uid,
            version: version,
            clientRequirement: clientRequirement
        )
    }

    /// 卸载脚本。先清 `disablesleep`，否则删掉 helper 后这个标志没人能清。
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
