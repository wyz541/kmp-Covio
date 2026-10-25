import Foundation

/// 判断当前进程是不是 XCTest 宿主。
///
/// XCTest 把测试包注进被测应用进程（ADR-001 实测 16），`applicationDidFinishLaunching`
/// 会照跑一遍。启动路径上有两件事会改用户机器的真实状态：单实例仲裁和运行时启动。
/// 两者都按这里的结论让开。
///
/// 判据两条：XCTest 注入配置时设的环境变量，以及已经加载进进程的 XCTest 类。
/// scheme 的 TestAction 不设环境变量，所以第二条不能省。
///
/// 两个输入都做成参数，测试才能在真实宿主进程里正反两种情形都断言一次。
enum LaunchEnvironment {
    static func isRunningTests(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isClassLoaded: (String) -> Bool = { NSClassFromString($0) != nil }
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || isClassLoaded("XCTestCase")
    }

    static func isSlimInstallProfile(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if arguments.contains("--test-profile=slim-install") {
            return true
        }
        guard let index = arguments.firstIndex(of: "--test-profile"),
              arguments.indices.contains(index + 1)
        else { return false }
        return arguments[index + 1] == "slim-install"
    }
}
