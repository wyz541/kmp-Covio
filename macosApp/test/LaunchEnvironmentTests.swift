import XCTest
@testable import Covio

/// 启动路径让开测试进程的判据测试。
///
/// XCTest 把测试包注进被测应用进程（ADR-001 实测 16），`AppDelegate` 的启动路径会照跑一遍。
/// 命中判据时单实例仲裁与运行时启动都让开。漏判的代价是测试改用户的真实截图设置。
final class LaunchEnvironmentTests: XCTestCase {
    /// 真实的宿主进程必须判成测试进程。这一条是判据本身的回归关断点。
    func testRealTestHostIsDetected() {
        XCTAssertTrue(LaunchEnvironment.isRunningTests())
    }

    /// scheme 的 TestAction 不设环境变量，所以类加载这一条顶上来。
    func testLoadedXCTestClassIsEnough() {
        let detected = LaunchEnvironment.isRunningTests(environment: [:], isClassLoaded: { $0 == "XCTestCase" })
        XCTAssertTrue(detected)
    }

    func testEnvironmentVariableIsEnough() {
        let detected = LaunchEnvironment.isRunningTests(
            environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"],
            isClassLoaded: { _ in false }
        )
        XCTAssertTrue(detected)
    }

    /// 普通启动不能被误判。误判会让真实应用跳过单实例仲裁。
    func testOrdinaryLaunchIsNotATestHost() {
        XCTAssertFalse(LaunchEnvironment.isRunningTests(environment: [:], isClassLoaded: { _ in false }))
    }

    func testSlimInstallProfileUsesASeparateArgument() {
        XCTAssertTrue(
            LaunchEnvironment.isSlimInstallProfile(
                arguments: ["Covio", "--test-profile", "slim-install"]
            )
        )
    }

    func testSlimInstallProfileAcceptsTheEqualsForm() {
        XCTAssertTrue(
            LaunchEnvironment.isSlimInstallProfile(
                arguments: ["Covio", "--test-profile=slim-install"]
            )
        )
    }

    func testOrdinaryLaunchDoesNotOpenTheSlimInstallProfile() {
        XCTAssertFalse(LaunchEnvironment.isSlimInstallProfile(arguments: ["Covio"]))
        XCTAssertFalse(
            LaunchEnvironment.isSlimInstallProfile(arguments: ["Covio", "--test-profile", "other"])
        )
    }
}
