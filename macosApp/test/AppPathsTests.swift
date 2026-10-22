import XCTest
@testable import Covio

/// 两版共存的路径测试。
///
/// M1 的完成判据要求 Compose 版与 SwiftUI 版可以同时运行。
/// 两版共用数据目录与 `config.json`，只有 lock 文件名不同。
final class AppPathsTests: XCTestCase {
    func testSupportDirectoryMatchesTheComposeVersion() {
        // 与 core/src/com/wyz/covio/Models.kt 的 APP_ID 一致。
        XCTAssertEqual(AppPaths.appID, "com.wyz.covio")
        XCTAssertTrue(AppPaths.supportDirectory.path.hasSuffix("Application Support/com.wyz.covio"))
    }

    func testSupportDirectoryCanBeIsolatedForBundleVerification() {
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-support-\(UUID().uuidString)", isDirectory: true)
        let actual = AppPaths.supportDirectory(
            environment: ["COVIO_SUPPORT_DIR": expected.path]
        )
        XCTAssertEqual(actual.path, expected.path)
    }

    func testBothVersionsUseDifferentLockFiles() {
        XCTAssertNotEqual(AppPaths.lockFile, AppPaths.composeLockFile)
        XCTAssertEqual(AppPaths.lockFile.lastPathComponent, "app.swiftui.lock")
        XCTAssertEqual(AppPaths.composeLockFile.lastPathComponent, "app.lock")
    }

    func testBothVersionsShareTheSameConfigFile() {
        // M2 要求 config.json 与 0.4.2 双向兼容，所以必须指向同一个文件。
        XCTAssertEqual(AppPaths.configFile.lastPathComponent, "config.json")
        XCTAssertEqual(AppPaths.configFile.deletingLastPathComponent(), AppPaths.supportDirectory)
    }

    func testEnsureSupportDirectoryCreatesTheFolder() throws {
        XCTAssertTrue(AppPaths.ensureSupportDirectory())
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: AppPaths.supportDirectory.path,
            isDirectory: &isDirectory
        )
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
    }

    /// 同一进程重复取锁是幂等的。
    func testLockIsReentrantWithinOneProcess() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: url) }

        let lock = SingleInstanceLock(url: url)
        XCTAssertTrue(lock.acquire())
        XCTAssertTrue(lock.isAcquired)
        XCTAssertTrue(lock.acquire(), "同一实例重复取锁应该直接成功")

        lock.release()
        XCTAssertFalse(lock.isAcquired)
    }

    /// 锁被另一个实例持有时取锁失败。`flock` 按打开的文件描述算，所以同一进程的
    /// 两次 `open()` 也会互斥。
    func testLockIsExclusiveAcrossDescriptors() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = SingleInstanceLock(url: url)
        XCTAssertTrue(first.acquire())

        let second = SingleInstanceLock(url: url)
        XCTAssertFalse(second.acquire(), "第二个实例不应该拿到锁")

        first.release()
        XCTAssertTrue(second.acquire(), "锁释放后第二个实例应该能拿到")
        second.release()
    }

    /// 两版共存的直接证明：同时持有两个 lock 文件。
    func testBothVersionsCanHoldTheirLocksAtTheSameTime() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-coexist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let swiftUI = SingleInstanceLock(url: directory.appendingPathComponent(AppPaths.swiftUILockFileName))
        let compose = SingleInstanceLock(url: directory.appendingPathComponent(AppPaths.composeLockFileName))

        XCTAssertTrue(swiftUI.acquire(), "SwiftUI 版应该拿到自己的锁")
        XCTAssertTrue(compose.acquire(), "Compose 版应该能同时拿到自己的锁")
        XCTAssertTrue(swiftUI.isAcquired)
        XCTAssertTrue(compose.isAcquired)

        // 但同一版仍然只有一个实例。
        let secondSwiftUI = SingleInstanceLock(
            url: directory.appendingPathComponent(AppPaths.swiftUILockFileName)
        )
        XCTAssertFalse(secondSwiftUI.acquire(), "SwiftUI 版的第二个实例不应该拿到锁")

        swiftUI.release()
        compose.release()
    }
}
