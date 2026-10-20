import XCTest
import kmpDomain
@testable import Covio

/// `PrivilegedOps.status()` 的判定。
///
/// 四种状态里 `OUTDATED` 最容易出错：它要在 helper 能应答但版本不对时给出，
/// 而且不能把「连不上」也算成 `OUTDATED`，否则界面会提示用户重装一个没坏的东西。
///
/// 这里不碰系统上真正装的 helper：在一个临时路径上起一个假 helper，
/// 让 `HelperClient` 连过去。被测代码走的是真实的 socket 收发路径。
final class HelperStatusTests: XCTestCase {
    private var directory: URL!
    private var socketPath: String!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("covio-helper-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // socket 路径必须短。`sun_path` 只有 104 字节，而
        // `NSTemporaryDirectory()` 展开后是 `/var/folders/.../T/`，本身就占 50 字节，
        // 再加一层目录名与 UUID 就超了。
        // 所以 socket 直接放在 `/tmp`，只有测试创建的目录放在 `NSTemporaryDirectory()`。
        socketPath = "/tmp/covio-hs-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func ops() -> MacPrivilegedOps {
        MacPrivilegedOps(
            logger: SilentLogger(),
            executablePath: "/tmp/Covio",
            client: HelperClient(socketPath: socketPath, timeoutMillis: 1_000)
        )
    }

    func testNoSocketMeansNotInstalled() {
        XCTAssertEqual(ops().status(), .notInstalled)
        XCTAssertFalse(ops().isInstalled())
    }

    /// helper 应答的版本与本版一致 → 已安装。
    func testMatchingVersionMeansInstalled() throws {
        let helper = try FakeHelper(socketPath: socketPath, version: ModelsKt.APP_VERSION)
        defer { helper.stop() }

        XCTAssertEqual(ops().status(), .installed)
        XCTAssertTrue(ops().isInstalled())
        XCTAssertEqual(ops().helperVersion(), ModelsKt.APP_VERSION)
    }

    /// helper 能应答但版本不同 → OUTDATED。界面据此提示重装。
    func testDifferentVersionMeansOutdated() throws {
        let helper = try FakeHelper(socketPath: socketPath, version: "0.0.1")
        defer { helper.stop() }

        XCTAssertEqual(ops().status(), .outdated)
        XCTAssertTrue(ops().isInstalled(), "socket 在，所以算已安装")
        XCTAssertEqual(ops().helperVersion(), "0.0.1")
    }

    /// socket 文件在但没有进程监听 → ERROR，不是 OUTDATED。
    /// 报 OUTDATED 会让用户去重装一个其实只是没起来的 helper。
    func testSocketWithoutAListenerMeansErrorNotOutdated() throws {
        // 造一个残留的 socket 文件：绑一次再关掉，文件会留下。
        let helper = try FakeHelper(socketPath: socketPath, version: "0.0.1")
        helper.stop()

        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath), "测试前提：socket 文件还在")
        XCTAssertEqual(ops().status(), .error)
    }

    /// `setDisableSleep` 只在 helper 明确回 ok 时返回 true。
    func testSetDisableSleepRequiresAnOkReply() throws {
        let helper = try FakeHelper(socketPath: socketPath, version: ModelsKt.APP_VERSION)
        defer { helper.stop() }

        XCTAssertTrue(ops().setDisableSleep(disabled: true))
        XCTAssertTrue(helper.commands.contains("setDisableSleep"))
    }

    /// helper 不在时不发请求，直接失败。
    func testSetDisableSleepFailsWithoutAHelper() {
        XCTAssertFalse(ops().setDisableSleep(disabled: true))
    }

    func testChargeLimitStatusParsesTheHelperReply() throws {
        let helper = try FakeHelper(socketPath: socketPath, version: ModelsKt.APP_VERSION)
        defer { helper.stop() }

        let client = HelperClient(socketPath: socketPath, timeoutMillis: 1_000)
        let status = try XCTUnwrap(client.chargeLimitStatus())

        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.userLimitPercent, 55)
        XCTAssertEqual(status.targetPercent, 55)
        XCTAssertTrue(status.chargingLatch)
        XCTAssertEqual(status.phase, "charging")
        XCTAssertFalse(status.bypassEngaged)
        XCTAssertEqual(status.originalFeatureState, 0)
        XCTAssertEqual(status.originalLimitPercent, 80)
        XCTAssertEqual(helper.commands.last, "chargeLimitStatus")
    }

    func testChargeLimitCommandsUseTheWireCommandNames() throws {
        let helper = try FakeHelper(socketPath: socketPath, version: ModelsKt.APP_VERSION)
        defer { helper.stop() }

        let client = HelperClient(socketPath: socketPath, timeoutMillis: 1_000)
        XCTAssertTrue(client.setChargeLimit(percent: 55))
        XCTAssertTrue(client.restoreChargeLimit())

        XCTAssertEqual(
            Array(helper.commands.suffix(2)),
            ["chargeLimitConfigure", "chargeLimitRestore"]
        )
    }
}

/// 只在测试里存在的假 helper。
///
/// 绑一个 Unix 域 socket，对每个连接读一行 JSON，回一条 `version` 应答。
/// 用真实的 `HelperRequest` / `HelperReply` 编解码，所以格式与真 helper 一致。
private final class FakeHelper {
    private let descriptor: Int32
    private let thread: Thread
    private let port: FakeHelperState

    /// 收到的命令，按顺序。
    var commands: [String] { port.commands }

    init(socketPath: String, version: String) throws {
        // 全程用局部变量。在 `thread` 赋值前读 `descriptor` 或 `port`
        // 等于读 `self`，Swift 不允许，闭包捕获更不行。
        // 三个存储属性留到最后一并赋值。
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FakeHelperError.socket("socket() failed") }

        guard let address = UnixSocketAddress(path: socketPath) else {
            close(fd)
            throw FakeHelperError.socket("path too long: \(socketPath)")
        }
        let bound = address.withSockaddr { pointer, length in
            Darwin.bind(fd, pointer, length)
        }
        guard bound == 0 else {
            close(fd)
            throw FakeHelperError.socket("bind() failed: \(String(cString: strerror(errno)))")
        }
        guard listen(fd, 8) == 0 else {
            close(fd)
            throw FakeHelperError.socket("listen() failed")
        }

        let state = FakeHelperState()
        state.version = version

        descriptor = fd
        port = state
        thread = Thread { FakeHelper.serve(descriptor: fd, port: state) }
        thread.name = "FakeHelper"
        thread.start()
    }

    func stop() {
        port.stopped = true
        shutdown(descriptor, SHUT_RDWR)
        close(descriptor)
    }

    deinit { stop() }

    private static func serve(descriptor: Int32, port: FakeHelperState) {
        while !port.stopped {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }

            guard let line = UnixSocketIO.readLine(
                client,
                limit: Int(HelperWire.shared.MAX_REQUEST_BYTES)
            ),
                let request = HelperWire.shared.decodeRequest(line: line)
            else { continue }

            port.append(request.command)
            // 用共享层的回复构造器：真 helper 回的字节与它一模一样。
            // `result` 必须显式传：Kotlin 的默认参数值不导出到 Swift。
            let reply: HelperReply
            if request.command == HelperWire.shared.COMMAND_VERSION {
                reply = HelperWire.shared.success(
                    requestId: request.requestId,
                    result: ["version": port.version]
                )
            } else if request.command == HelperWire.shared.COMMAND_CHARGE_LIMIT_STATUS {
                reply = HelperWire.shared.success(
                    requestId: request.requestId,
                    result: [
                        "enabled": "true",
                        "userLimitPercent": "55",
                        "targetPercent": "55",
                        "chargingLatch": "true",
                        "phase": "charging",
                        "bypassEngaged": "false",
                        "originalFeatureState": "0",
                        "originalLimitPercent": "80",
                    ]
                )
            } else {
                reply = HelperWire.shared.success(requestId: request.requestId, result: [:])
            }
            UnixSocketIO.writeAll(client, HelperWire.shared.encodeReply(reply: reply) + "\n")
        }
    }
}

/// 跨线程传一次状态。假 helper 的 accept 循环在后台线程上跑。
private final class FakeHelperState: @unchecked Sendable {
    private let lock = NSLock()
    private var versionStorage = ""
    private var commandsStorage: [String] = []
    private var stoppedStorage = false

    var version: String {
        get { lock.withLock { versionStorage } }
        set { lock.withLock { versionStorage = newValue } }
    }

    var commands: [String] { lock.withLock { commandsStorage } }

    var stopped: Bool {
        get { lock.withLock { stoppedStorage } }
        set { lock.withLock { stoppedStorage = newValue } }
    }

    func append(_ command: String) { lock.withLock { commandsStorage.append(command) } }
}

private enum FakeHelperError: Error {
    case socket(String)
}

private final class SilentLogger: NSObject, AppLogger {
    func info(message: String) {}
    func warn(message: String, error: KotlinThrowable?) {}
    func error(message: String, error: KotlinThrowable?) {}
    func logFile() -> String { "" }
}
