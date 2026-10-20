import Foundation
import kmpDomain

/// 特权 helper 的安装契约：路径、命令行参数与命令白名单。
///
/// 权威在共享模块的 `HelperContract.kt`。这里直接读 Kotlin 的值，不另抄一份：
/// 抄两份必然漂移，而漂移的表现是「客户端发得出、服务端不认」。
///
/// 协议本身（编解码、校验、回复构造）在共享模块的 `HelperWire.kt`。
/// 调用点直接用 `HelperWire.shared`，见 `HelperServer` 与 `HelperClient`。
///
/// `HelperContractMirrorTests` 会检查这些值确实是 Kotlin 的。
enum HelperProtocol {
    static var protocolVersion: String { HelperContractKt.HELPER_PROTOCOL_VERSION }

    /// 以 helper 身份启动的命令行参数。
    static var helperArgument: String { HelperContractKt.HELPER_ARGUMENT }

    static var socketPath: String { HelperContractKt.HELPER_SOCKET_PATH }
    static var helperDirectory: String { HelperContractKt.HELPER_DIRECTORY }
    static var allowedUidPath: String { HelperContractKt.HELPER_ALLOWED_UID_PATH }
    static var versionPath: String { HelperContractKt.HELPER_VERSION_PATH }
    static var appPathFile: String { HelperContractKt.HELPER_APP_PATH_FILE }
    static var sleepOwnerPath: String { HelperContractKt.HELPER_SLEEP_OWNER_PATH }
    static var sleepOwnerValue: String { HelperContractKt.HELPER_SLEEP_OWNER_VALUE }
    static var leaseDurationSeconds: Int64 { HelperContractKt.HELPER_LEASE_DURATION_SECONDS }
    static var leaseRenewSeconds: Int64 { HelperContractKt.HELPER_LEASE_RENEW_SECONDS }
    static var logPath: String { HelperContractKt.HELPER_LOG_PATH }
    static var plistPath: String { HelperContractKt.HELPER_PLIST_PATH }
    static var launchDaemonLabel: String { HelperContractKt.HELPER_LAUNCH_DAEMON_LABEL }

    static var allowedCommands: Set<String> { HelperContractKt.HELPER_ALLOWED_COMMANDS }

    /// 允许的休眠模式。取自 Kotlin 侧，避免两处白名单漂移。
    static var supportedHibernateModes: Set<Int> {
        Set(ModelsKt.SUPPORTED_HIBERNATE_MODES.map(\.intValue))
    }
}
