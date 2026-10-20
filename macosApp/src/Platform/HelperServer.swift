import Foundation
import kmpDomain

/// 特权 helper 的服务端。以 `Covio --helper` 启动，由 LaunchDaemon 以 root 运行。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/helper/HelperServer.kt`。
/// 请求来自本机 Unix 域套接字。每个连接先校验 uid，再校验命令白名单。
/// 充电命令还要校验调用方代码签名。
/// 现有设置命令交给 `/usr/bin/pmset`，充电命令交给 MCL 后端。
/// 套接字是 OS 调用，所以这一层在两端各有一份，这是规范允许的重复。
enum HelperServer {
    private static let peerAuthorizer: HelperPeerAuthorizing = CodeSignaturePeerAuthorizer()
    private static let chargeLimitRuntime = ChargeLimitRuntimeController(
        backend: ChargeLimitMCLController(
            preferences: CFPreferencesChargeLimitStore(),
            stateStore: ChargeLimitStateStore(
                url: URL(fileURLWithPath: HelperProtocol.helperDirectory)
                    .appendingPathComponent("charge-limit")
                    .appendingPathComponent("state.json")
            )
        ),
        powerReader: MacChargeLimitPowerReader(),
        stateStore: ChargeLimitRuntimeStateStore(
            url: URL(fileURLWithPath: HelperProtocol.helperDirectory)
                .appendingPathComponent("charge-limit")
                .appendingPathComponent("runtime.json")
        )
    )
    private static let chargeLimitHandler = ChargeLimitHelperCommandHandler(
        runtime: chargeLimitRuntime
    )

    /// 阻塞运行，直到进程被信号终止。返回进程退出码。
    static func run() -> Int32 {
        let log = HelperLog()
        if case .failure(let failure) = chargeLimitRuntime.resumeOnStartup() {
            log.error("Charge limit runtime failed to resume: \(failure)")
        }
        var terminationSources: [DispatchSourceSignal] = []
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                let restored: Bool
                if case .success = chargeLimitRuntime.restore() {
                    restored = true
                } else {
                    restored = false
                    log.error("Charge limit restore failed during helper termination")
                }
                exit(restored ? 0 : 1)
            }
            source.resume()
            terminationSources.append(source)
        }
        defer { terminationSources.forEach { $0.cancel() } }
        do {
            try serve(log: log)
            return 0
        } catch {
            log.error("Helper failed", error)
            return 1
        }
    }

    private static func serve(log: HelperLog) throws {
        try prepareSocketFile()

        let serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { throw HelperError.socket("socket() failed") }
        defer { close(serverSocket) }

        guard let address = UnixSocketAddress(path: HelperProtocol.socketPath) else {
            throw HelperError.socket("Socket path is too long")
        }
        let bindResult = address.withSockaddr { pointer, length in
            Darwin.bind(serverSocket, pointer, length)
        }
        guard bindResult == 0 else { throw HelperError.socket("bind() failed") }

        guard listen(serverSocket, 16) == 0 else { throw HelperError.socket("listen() failed") }
        // 任意用户可连，uid 在连接后校验。socket 文件本身没有机密内容。
        chmod(HelperProtocol.socketPath, mode_t(HelperWire.shared.SOCKET_PERMISSIONS))
        log.info("Helper listening on \(HelperProtocol.socketPath)")

        while true {
            let client = accept(serverSocket, nil, nil)
            // 被信号打断时 accept 返回负数，继续等下一个连接。
            guard client >= 0 else { continue }
            DispatchQueue.global().async {
                handleClient(client, log: log)
            }
        }
    }

    private static func prepareSocketFile() throws {
        let directory = HelperProtocol.helperDirectory
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        // 上次异常退出会留下过期的 socket 文件，先删掉，否则 bind 失败。
        unlink(HelperProtocol.socketPath)
    }

    /// 处理一个连接。会关闭 `client`。
    ///
    /// 协议部分（解码、校验、回复构造、pmset 参数）全部在共享层，
    /// 这里只做三件宿主才能做的事：看 uid、跑进程、写回包。
    static func handleClient(_ client: Int32, log: HelperLog) {
        defer { close(client) }
        do {
            guard let peerUid = peerUid(of: client) else {
                log.info("Rejected helper request: cannot determine peer uid")
                write(reply: HelperWire.shared.failure(requestId: "", message: "Cannot determine peer uid"), to: client)
                return
            }
            guard let allowed = allowedUid(), peerUid == allowed else {
                log.info("Rejected helper request from uid=\(peerUid)")
                write(reply: HelperWire.shared.failure(requestId: "", message: "Peer uid is not allowed"), to: client)
                return
            }

            guard let line = UnixSocketIO.readLine(
                client,
                limit: Int(HelperWire.shared.MAX_REQUEST_BYTES)
            ) else {
                return
            }
            guard let request = HelperWire.shared.decodeRequest(line: line) else {
                write(reply: HelperWire.shared.failure(requestId: "", message: "Invalid JSON request"), to: client)
                return
            }
            if let validationError = HelperWire.shared.validate(request: request) {
                write(
                    reply: HelperWire.shared.failure(
                        requestId: request.requestId,
                        message: validationError
                    ),
                    to: client
                )
                return
            }

            if HelperWire.shared.isChargeLimitCommand(command: request.command) {
                guard peerAuthorizer.isAuthorized(descriptor: client) else {
                    log.info("Rejected charge command from an unsigned client")
                    write(
                        reply: HelperWire.shared.failure(
                            requestId: request.requestId,
                            message: "Peer signature is not allowed"
                        ),
                        to: client
                    )
                    return
                }
                if let reply = chargeLimitHandler.handle(request) {
                    write(reply: reply, to: client)
                    return
                }
            }

            let reply: HelperReply
            if let arguments = HelperWire.shared.pmsetArguments(request: request) {
                reply = runPmset(requestId: request.requestId, arguments: arguments)
            } else if request.command == HelperWire.shared.COMMAND_VERSION {
                reply = HelperWire.shared.versionReply(requestId: request.requestId)
            } else {
                // 白名单外的命令在校验那一步就被拒绝了，这里只是兜底。
                reply = HelperWire.shared.failure(requestId: request.requestId, message: "Command is not allowed")
            }
            write(reply: reply, to: client)
        }
    }

    // MARK: - 私有

    private static func peerUid(of descriptor: Int32) -> uid_t? {
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(descriptor, &uid, &gid) == 0 else { return nil }
        return uid
    }

    private static func allowedUid() -> uid_t? {
        guard let text = try? String(contentsOfFile: HelperProtocol.allowedUidPath, encoding: .utf8) else {
            return nil
        }
        guard let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return uid_t(value)
    }

    /// 跑一条 `pmset` 命令。
    ///
    /// 参数与退出码的判定都在共享层。进程启动失败只有本宿主知道原因，
    /// 所以那一句文案留在本地。
    private static func runPmset(requestId: String, arguments: [String]) -> HelperReply {
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
            return HelperWire.shared.failure(requestId: requestId, message: error.localizedDescription)
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return HelperWire.shared.pmsetReply(
            requestId: requestId,
            exitCode: process.terminationStatus,
            output: String(data: output, encoding: .utf8) ?? ""
        )
    }

    private static func write(reply: HelperReply, to descriptor: Int32) {
        UnixSocketIO.writeAll(descriptor, HelperWire.shared.encodeReply(reply: reply) + "\n")
    }
}

enum HelperError: Error {
    case socket(String)
}

/// helper 自己的日志。写到 `/Library/Application Support/Covio/helper.log`。
///
/// 不用 `os.Logger`，因为 LaunchDaemon 的输出已经从 plist 重定向到这里，
/// 保持单一文件便于用户上报问题。
///
/// 多个连接线程会同时写。`NSLock` 串行化写入，所以标记 `@unchecked Sendable`。
final class HelperLog: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()

    init(path: String = HelperProtocol.logPath) {
        self.path = path
    }

    func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    func error(_ message: String, _ error: Error? = nil) {
        var text = message
        if let error { text += ": \(error)" }
        write(level: "ERROR", message: text)
    }

    private func write(level: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
