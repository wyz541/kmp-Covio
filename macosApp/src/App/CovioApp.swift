import SwiftUI
import kmpDomain

/// 应用入口。
///
/// 三条维护命令在 SwiftUI 起来之前分流，它们都不需要界面：
/// - `--helper`：特权 helper 本体，由 LaunchDaemon 以 root 启动。
/// - `--install-helper` / `--uninstall-helper`：迁移脚本用它走真实的安装路径，
///   而不是在脚本里重抄一遍安装步骤。
/// - `--helper-version`：问 helper 自己的版本号，迁移脚本用它判断是否 OUTDATED。
///
/// Hub 是 NSPanel，由 `AppDelegate` 与 `NotchShellController` 管理。
/// 这里不提供任何窗口。`Settings` 场景是让 `App` 协议有一个非空 `Scene` 的最小写法。
@main
enum CovioMain {
    static func main() {
        let arguments = CommandLine.arguments

        if arguments.contains(HelperProtocol.helperArgument) {
            exit(HelperServer.run())
        }
        if arguments.contains(MaintenanceCommand.installHelper) {
            exit(HelperInstaller.install(executablePath: executablePath, logger: log) ? 0 : 1)
        }
        if arguments.contains(MaintenanceCommand.uninstallHelper) {
            exit(HelperInstaller.uninstall(logger: log) ? 0 : 1)
        }
        if arguments.contains(MaintenanceCommand.helperVersion) {
            exit(printHelperVersion())
        }
        if arguments.contains(MaintenanceCommand.helperProtocolVersion) {
            exit(printHelperProtocolVersion())
        }
        CovioApp.main()
    }

    /// 当前可执行文件的绝对路径。它会写进 LaunchDaemon plist。
    private static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    /// 诊断信息写 stderr，stdout 留给 `--helper-version` 的结果。
    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// 打印 helper 自己报告的应用版本号。
    ///
    /// 退出码：0 成功，1 连不上 helper。
    /// 版本是否等于本版由调用方比较，脚本里比更清楚。
    private static func printHelperVersion() -> Int32 {
        guard let version = HelperClient().version() else {
            log("Helper did not report a version")
            return 1
        }
        print(version)
        return 0
    }

    /// 打印 helper 自己报告的协议版本号。
    private static func printHelperProtocolVersion() -> Int32 {
        guard let protocolVersion = HelperClient().versionInfo()?.protocolVersion else {
            log("Helper did not report a protocol version")
            return 1
        }
        print(protocolVersion)
        return 0
    }
}

/// 迁移与排查用的命令行开关。只影响启动分流，不影响正常运行。
enum MaintenanceCommand {
    /// 安装特权 helper。会弹出管理员授权对话框。
    static let installHelper = "--install-helper"
    /// 卸载特权 helper。会弹出管理员授权对话框。
    static let uninstallHelper = "--uninstall-helper"
    /// 打印 helper 报告的应用版本号。
    static let helperVersion = "--helper-version"
    /// 打印 helper 报告的协议版本号。
    static let helperProtocolVersion = "--helper-protocol-version"
}

struct CovioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
