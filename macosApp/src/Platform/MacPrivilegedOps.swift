import Foundation
import kmpDomain

/// `PrivilegedOps` 端口的 macOS 实现。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/MacPrivilegedOps.kt`。
/// 与 Kotlin 版的行为一致：
/// - 「已安装」的判据是 socket 文件存在，不是 LaunchDaemon 在跑。
/// - 版本不一致返回 `OUTDATED`，让界面提示用户重装。
/// - 只有 `pmset` 读操作在本地做，写操作一律走 helper。
///
/// Kotlin interface 导出为 Objective-C protocol，实现类必须继承 `NSObject`。
final class MacPrivilegedOps: NSObject, PrivilegedOps {
    private let logger: AppLogger
    private let executablePath: String
    private let client: HelperClient
    private let externalDisplayCount: () -> Int?
    private let leaseId = UUID().uuidString
    private let stateLock = NSLock()
    private let leaseOperationLock = NSLock()
    private let localStatusCacheLock = NSLock()
    private var leaseActive = false
    private var renewTimer: DispatchSourceTimer?
    private var localSleepDisabled: Bool?
    private var localSleepDisabledReadAt: TimeInterval?

    init(
        logger: AppLogger,
        executablePath: String = Bundle.main.executablePath ?? "",
        client: HelperClient = HelperClient(),
        externalDisplayCount: @escaping () -> Int? = {
            MacPowerObservationSource.readExternalDisplayCount()
        }
    ) {
        self.logger = logger
        self.executablePath = executablePath
        self.client = client
        self.externalDisplayCount = externalDisplayCount
        super.init()
    }

    /// 「已安装」的判据是 socket 文件存在，不是 LaunchDaemon 在跑。
    /// 这是 0.4.2 的既有语义：daemon 被 launchd 重启的瞬间不该让界面闪成未安装。
    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: client.socketPath)
    }

    func status() -> HelperStatus {
        guard isInstalled() else { return .notInstalled }
        guard let info = client.versionInfo() else { return .error }
        let sameVersion = info.version == GeneratedReleaseIdentityKt.APP_VERSION
        let sameProtocol = info.protocolVersion == HelperProtocol.protocolVersion
        return sameVersion && sameProtocol ? .installed : .outdated
    }

    func helperVersion() -> String? {
        client.version()
    }

    func install() -> Bool {
        guard !executablePath.isEmpty else {
            logger.warn(message: "Cannot install the privileged helper: unknown executable path", error: nil)
            return false
        }
        return HelperInstaller.install(executablePath: executablePath) { [logger] message in
            logger.info(message: message)
        }
    }

    func uninstall() -> Bool {
        HelperInstaller.uninstall { [logger] message in
            logger.info(message: message)
        }
    }

    func setDisableSleep(disabled: Bool) -> Bool {
        if disabled {
            guard let externalDisplays = externalDisplayCount() else {
                logger.warn(message: "Cannot read external display count", error: nil)
                return false
            }
            leaseOperationLock.lock()
            defer { leaseOperationLock.unlock() }
            let status = client.acquireLidLease(
                leaseId: leaseId,
                externalDisplayCount: externalDisplays
            )
            guard status.leaseActive, status.sleepDisabled?.boolValue == true else {
                logger.warn(
                    message: "Privileged helper did not acquire the lid lease: \(status.error ?? "unknown error")",
                    error: nil
                )
                return false
            }
            stateLock.withLock { leaseActive = true }
            startRenewTimer()
            return true
        }

        stopRenewTimer()
        leaseOperationLock.lock()
        defer { leaseOperationLock.unlock() }
        stateLock.withLock { leaseActive = false }
        let status = client.releaseLidLease(leaseId: leaseId)
        guard status.error == nil, status.sleepDisabled?.boolValue != true else {
            logger.warn(
                message: "Privileged helper did not release the lid lease: \(status.error ?? "SleepDisabled remains set")",
                error: nil
            )
            return false
        }
        return true
    }

    func lidLeaseStatus() -> LidLeaseStatus {
        let remote = client.lidLeaseStatus()
        guard remote.sleepDisabled == nil, let local = cachedLocalSleepDisabled() else {
            return remote
        }
        return LidLeaseStatus(
            available: remote.available,
            protocolVersion: remote.protocolVersion,
            sleepDisabled: KotlinBoolean(bool: local),
            covioOwned: nil,
            activeLeaseCount: remote.activeLeaseCount,
            expiresAtEpochSeconds: remote.expiresAtEpochSeconds,
            error: remote.error
        )
    }

    private func cachedLocalSleepDisabled() -> Bool? {
        localStatusCacheLock.lock()
        if let readAt = localSleepDisabledReadAt,
           Date().timeIntervalSince1970 - readAt < 30 {
            let cached = localSleepDisabled
            localStatusCacheLock.unlock()
            return cached
        }
        localStatusCacheLock.unlock()

        let actual = PmsetReader.sleepDisabled()
        localStatusCacheLock.lock()
        localSleepDisabled = actual
        localSleepDisabledReadAt = Date().timeIntervalSince1970
        localStatusCacheLock.unlock()
        return actual
    }

    private func startRenewTimer() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard renewTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + .seconds(Int(HelperProtocol.leaseRenewSeconds)),
            repeating: .seconds(Int(HelperProtocol.leaseRenewSeconds)),
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in self?.renewLease() }
        renewTimer = timer
        timer.resume()
    }

    private func stopRenewTimer() {
        stateLock.lock()
        let timer = renewTimer
        renewTimer = nil
        stateLock.unlock()
        timer?.cancel()
    }

    private func renewLease() {
        leaseOperationLock.lock()
        defer { leaseOperationLock.unlock() }
        guard stateLock.withLock({ leaseActive }) else { return }
        guard let externalDisplays = externalDisplayCount() else {
            logger.warn(message: "Cannot renew lid lease: external display count is unknown", error: nil)
            return
        }
        let status = client.renewLidLease(
            leaseId: leaseId,
            externalDisplayCount: externalDisplays
        )
        if status.leaseActive, status.sleepDisabled?.boolValue == true {
            return
        }
        logger.warn(
            message: "Cannot renew lid lease: \(status.error ?? "helper state is not active")",
            error: nil
        )
    }

    deinit {
        stopRenewTimer()
        if stateLock.withLock({ leaseActive }) {
            _ = client.releaseLidLease(leaseId: leaseId)
        }
    }

    func hibernateMode() -> KotlinInt? {
        guard let mode = PmsetReader.hibernateMode() else { return nil }
        guard HelperProtocol.supportedHibernateModes.contains(mode) else { return nil }
        return KotlinInt(int: Int32(mode))
    }

    func setHibernateMode(mode: Int32) -> Bool {
        guard HelperProtocol.supportedHibernateModes.contains(Int(mode)) else { return false }
        guard client.setHibernateMode(mode: Int(mode)) else {
            logger.warn(message: "Privileged helper did not accept setHibernateMode(\(mode))", error: nil)
            return false
        }
        return true
    }
}

/// `pmset -g` 的读取。写操作不在这里，只有 helper 能改系统设置。
enum PmsetReader {
    /// 读取当前休眠模式。命令失败、超时或输出不含该键时返回 nil。
    ///
    /// 解析规则住在 `kmpDomain` 的 `PmsetConfigParser` 里，与 Compose 版共用一份。
    static func hibernateMode(timeout: TimeInterval = 5) -> Int? {
        guard let text = readConfiguration(timeout: timeout) else { return nil }
        guard let mode = PmsetConfigParser.shared.hibernateMode(text: text) else { return nil }
        return Int(mode.int32Value)
    }

    /// 读当前 `disablesleep`。helper 协议不兼容时由客户端做只读兜底。
    static func sleepDisabled(timeout: TimeInterval = 5) -> Bool? {
        guard let text = readConfiguration(timeout: timeout) else { return nil }
        return PmsetConfigParser.shared.sleepDisabled(text: text)?.boolValue
    }

    /// 跑 `pmset -g` 并返回全部输出。命令失败或超时返回 nil。
    static func readConfiguration(timeout: TimeInterval = 5) -> String? {
        run(["-g"], timeout: timeout)
    }

    private static func run(_ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // 先把输出读完再 waitUntilExit，否则管道写满会互相卡死。
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }
}
