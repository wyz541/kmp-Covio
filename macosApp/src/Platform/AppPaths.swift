import Foundation

/// 应用用到的文件路径。
///
/// 与 Compose 版的 `core/src/com/wyz/covio/ConfigStore.kt` 和
/// `app/src/com/wyz/covio/app/platform/SingleInstanceLock.kt` 保持一致：
/// 数据目录都是 `~/Library/Application Support/com.wyz.covio/`。
///
/// 唯一的差别是 lock 文件名。计划的 M1 完成判据要求两版能同时运行，
/// 所以 SwiftUI 版用 `app.swiftui.lock`，Compose 版继续用 `app.lock`。
enum AppPaths {
    /// 与 `core/src/com/wyz/covio/Models.kt` 的 `APP_ID` 一致。
    static let appID = "com.wyz.covio"

    /// Compose 版用的 lock 文件名。
    static let composeLockFileName = "app.lock"
    /// SwiftUI 版用的 lock 文件名。两版不同，所以可以同时运行。
    static let swiftUILockFileName = "app.swiftui.lock"

    /// `~/Library/Application Support/com.wyz.covio`。
    ///
    /// 调试构建可用 `COVIO_SUPPORT_DIR` 指向隔离目录。
    /// 真机验收因此能同时运行第二个实例，不碰正在使用的配置与锁。
    static var supportDirectory: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["COVIO_SUPPORT_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let root = base.first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent(appID, isDirectory: true)
    }

    /// 两版共用的配置文件。M2 要求它与 0.4.2 双向兼容。
    static var configFile: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    /// 工作台配置。工作区顺序与首页组件都在这里。
    ///
    /// 权威在 `kmpDomain` 的 `WorkbenchStore.defaultWorkbenchPath()`，这里跟着它走。
    /// 与 `config.json` 分两个文件：工作台配置损坏时只回退布局，不动用户设置。
    static var workbenchFile: URL {
        supportDirectory.appendingPathComponent("workbench.json")
    }

    /// SwiftUI 版的单实例锁文件。
    static var lockFile: URL {
        supportDirectory.appendingPathComponent(swiftUILockFileName)
    }

    /// Compose 版的单实例锁文件。只用于文档与迁移脚本。
    static var composeLockFile: URL {
        supportDirectory.appendingPathComponent(composeLockFileName)
    }

    /// 剪切板条目的落盘目录。
    ///
    /// 与晾衣线同一个写法：用 `Covio` 而不是 `com.wyz.covio`，
    /// 二进制文件都放在 `~/Library/Application Support/Covio/` 下。
    /// 权威在 `kmpDomain` 的 `ClipboardStore.defaultDirectory()`，这里跟着它走。
    static var clipboardDirectory: URL {
        let root = supportDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Covio", isDirectory: true)
        return root.appendingPathComponent("Clipboard", isDirectory: true)
    }

    /// 剪切板状态文件。
    static var clipboardFile: URL {
        clipboardDirectory.appendingPathComponent("clipboard.json")
    }

    /// 确保数据目录存在。
    @discardableResult
    static func ensureSupportDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }
}
