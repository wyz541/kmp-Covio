import Foundation
import kmpDomain

/// 特权 helper 的 Unix 域套接字客户端。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/helper/HelperClient.kt`。
/// 行为差异只有一处：Kotlin 版用非阻塞 channel 加 selector 做超时，
/// 这里用 `SO_SNDTIMEO` 与 `SO_RCVTIMEO`，由内核负责超时。
/// 对外语义一致：超时或失败返回 nil，不抛异常。
///
/// 线上格式与校验在共享层的 `HelperWire`，两端的客户端发同样的字节。
final class HelperClient: @unchecked Sendable {
    /// helper 的 socket 路径。`PrivilegedOps` 用它判断「装没装」，
    /// 测试也用它指向一个临时的假 helper。
    let socketPath: String
    private let timeout: TimeInterval

    init(socketPath: String = HelperProtocol.socketPath, timeoutMillis: Int = 2_000) {
        self.socketPath = socketPath
        self.timeout = TimeInterval(timeoutMillis) / 1_000
    }

    func request(
        command: String,
        payload: [String: String] = [:],
        protocolVersion: String = HelperProtocol.protocolVersion,
        timeoutMillis: Int? = nil
    ) -> HelperReply? {
        let requestTimeout = timeoutMillis.map { TimeInterval($0) / 1_000 } ?? timeout
        guard requestTimeout > 0 else { return nil }
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }

        let request = HelperRequest(
            version: protocolVersion,
            requestId: UUID().uuidString,
            command: command,
            payload: payload
        )
        return transact(
            HelperWire.shared.encodeRequest(request: request) + "\n",
            timeout: requestTimeout
        )?.reply
    }

    /// 使用 v1 `version` 探测 helper，并保留 socket 对端 PID 供签名校验。
    func versionProbe() -> HelperVersionProbe? {
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }
        let request = HelperRequest(
            version: "1",
            requestId: UUID().uuidString,
            command: HelperWire.shared.COMMAND_VERSION,
            payload: [:]
        )
        guard let transaction = transact(
            HelperWire.shared.encodeRequest(request: request) + "\n",
            timeout: timeout
        ), transaction.reply.ok
        else {
            return nil
        }
        return HelperVersionProbe(
            result: transaction.reply.result ?? [:],
            peerPID: transaction.peerPID
        )
    }

    /// 使用 v1 `version` 探测旧 helper。新 helper 保留这一条只读兼容路径。
    func versionInfo() -> HelperVersionInfo? {
        guard let probe = versionProbe(), let version = probe.result["version"] else {
            return nil
        }
        return HelperVersionInfo(
            version: version,
            protocolVersion: probe.result["protocolVersion"]
        )
    }

    func version() -> String? { versionInfo()?.version }

    func acquireLidLease(leaseId: String, externalDisplayCount: Int) -> LidLeaseStatus {
        leaseRequest(
            command: HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE,
            leaseId: leaseId,
            externalDisplayCount: externalDisplayCount
        )
    }

    func renewLidLease(leaseId: String, externalDisplayCount: Int) -> LidLeaseStatus {
        leaseRequest(
            command: HelperWire.shared.COMMAND_LID_LEASE_RENEW,
            leaseId: leaseId,
            externalDisplayCount: externalDisplayCount
        )
    }

    func releaseLidLease(leaseId: String) -> LidLeaseStatus {
        lidLeaseStatus(from: request(
            command: HelperWire.shared.COMMAND_LID_LEASE_RELEASE,
            payload: ["leaseId": leaseId]
        ))
    }

    func lidLeaseStatus() -> LidLeaseStatus {
        lidLeaseStatus(from: request(command: HelperWire.shared.COMMAND_LID_LEASE_STATUS))
    }

    func setHibernateMode(mode: Int) -> Bool {
        request(command: "setHibernateMode", payload: ["mode": String(mode)])?.ok == true
    }

    func setDisableSleep(disabled: Bool) -> Bool {
        request(command: "setDisableSleep", payload: ["disabled": disabled ? "true" : "false"])?.ok == true
    }

    private func leaseRequest(
        command: String,
        leaseId: String,
        externalDisplayCount: Int
    ) -> LidLeaseStatus {
        lidLeaseStatus(from: request(
            command: command,
            payload: [
                "leaseId": leaseId,
                "externalDisplayCount": String(externalDisplayCount),
            ]
        ))
    }

    private func lidLeaseStatus(from reply: HelperReply?) -> LidLeaseStatus {
        guard let reply else {
            return LidLeaseStatus(
                available: FileManager.default.fileExists(atPath: socketPath),
                protocolVersion: HelperProtocol.protocolVersion,
                sleepDisabled: nil,
                covioOwned: nil,
                activeLeaseCount: 0,
                expiresAtEpochSeconds: nil,
                error: "Helper did not respond"
            )
        }
        guard reply.ok else {
            return LidLeaseStatus(
                available: true,
                protocolVersion: HelperProtocol.protocolVersion,
                sleepDisabled: nil,
                covioOwned: nil,
                activeLeaseCount: 0,
                expiresAtEpochSeconds: nil,
                error: reply.error
            )
        }
        let result = reply.result ?? [:]
        return LidLeaseStatus(
            available: true,
            protocolVersion: result["protocolVersion"] ?? HelperProtocol.protocolVersion,
            sleepDisabled: boolValue(result["sleepDisabled"]).map { KotlinBoolean(bool: $0) },
            covioOwned: boolValue(result["covioOwned"]).map { KotlinBoolean(bool: $0) },
            activeLeaseCount: Int32(result["activeLeaseCount"] ?? "0") ?? 0,
            expiresAtEpochSeconds: Int64(result["expiresAtEpochSeconds"] ?? "").map { KotlinLong(longLong: $0) },
            error: nil
        )
    }

    private func boolValue(_ value: String?) -> Bool? {
        switch value {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    func chargeLimitStatus() -> ChargeLimitHelperStatus? {
        guard let reply = request(command: "chargeLimitStatus", timeoutMillis: 3_000), reply.ok,
              let enabled = reply.result?["enabled"].flatMap(Bool.init)
        else {
            return nil
        }
        return ChargeLimitHelperStatus(
            enabled: enabled,
            userLimitPercent: reply.result?["userLimitPercent"].flatMap(Int.init),
            targetPercent: reply.result?["targetPercent"].flatMap(Int.init),
            chargingLatch: reply.result?["chargingLatch"].flatMap(Bool.init) ?? false,
            phase: reply.result?["phase"] ?? "unknown",
            bypassEngaged: reply.result?["bypassEngaged"].flatMap(Bool.init) ?? false,
            originalFeatureState: reply.result?["originalFeatureState"].flatMap(Int.init),
            originalLimitPercent: reply.result?["originalLimitPercent"].flatMap(Int.init),
            originalOptimizedChargingEnabled: reply.result?["originalOptimizedChargingEnabled"]
                .flatMap(Bool.init),
            activeDischargeEnabled: reply.result?["activeDischarge"].flatMap(Bool.init) ?? false,
            activeDischargeSupported: reply.result?["activeDischargeSupported"]
                .flatMap(Bool.init) ?? false
        )
    }

    func setChargeLimit(percent: Int, activeDischarge: Bool) -> Bool {
        request(
            command: "chargeLimitConfigure",
            payload: [
                "percent": String(percent),
                "activeDischarge": activeDischarge ? "true" : "false",
            ],
            timeoutMillis: 20_000
        )?.ok == true
    }

    func setChargeLimit(percent: Int) -> Bool {
        setChargeLimit(percent: percent, activeDischarge: false)
    }

    func restoreChargeLimit() -> Bool {
        request(command: "chargeLimitRestore", timeoutMillis: 20_000)?.ok == true
    }

    // MARK: - 私有

    private func transact(_ line: String, timeout: TimeInterval) -> HelperTransaction? {
        let descriptor = connect(timeout: timeout)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let peerPID = HelperSignature.peerPID(of: descriptor)

        guard UnixSocketIO.writeAll(descriptor, line) else { return nil }
        guard let response = UnixSocketIO.readLine(
            descriptor,
            limit: Int(HelperWire.shared.MAX_REPLY_BYTES)
        ) else { return nil }
        guard let reply = HelperWire.shared.decodeReply(line: response) else { return nil }
        return HelperTransaction(reply: reply, peerPID: peerPID)
    }

    private func connect(timeout: TimeInterval) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return -1 }

        var noSigPipe: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )

        // 秒与微秒分开设，内核到点就返回，不需要自己算 deadline。
        var limit = timeval(
            tv_sec: Int(timeout),
            tv_usec: suseconds_t((timeout - Double(Int(timeout))) * 1_000_000)
        )
        let limitSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, limitSize)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, limitSize)

        guard let address = UnixSocketAddress(path: socketPath) else {
            close(descriptor)
            return -1
        }
        let result = address.withSockaddr { pointer, length in
            Darwin.connect(descriptor, pointer, length)
        }
        guard result == 0 else {
            close(descriptor)
            return -1
        }
        return descriptor
    }
}

private struct HelperTransaction {
    let reply: HelperReply
    let peerPID: pid_t?
}

struct HelperVersionInfo {
    let version: String
    let protocolVersion: String?
}

struct HelperVersionProbe {
    let result: [String: String]
    let peerPID: pid_t?
}

/// 充电上限 helper 客户端端口。测试替换这个端口，避免连接真实 helper。
protocol ChargeLimitClientProtocol: Sendable {
    func chargeLimitStatus() -> ChargeLimitHelperStatus?
    func setChargeLimit(percent: Int, activeDischarge: Bool) -> Bool
    func restoreChargeLimit() -> Bool
}

extension HelperClient: ChargeLimitClientProtocol {}

/// `HelperClient.chargeLimitStatus()` 解析后的结果。
struct ChargeLimitHelperStatus: Equatable, Sendable {
    let enabled: Bool
    let userLimitPercent: Int?
    let targetPercent: Int?
    let chargingLatch: Bool
    let phase: String
    let bypassEngaged: Bool
    let originalFeatureState: Int?
    let originalLimitPercent: Int?
    let originalOptimizedChargingEnabled: Bool?
    var activeDischargeEnabled: Bool = false
    var activeDischargeSupported: Bool = false
}

/// `sockaddr_un` 的构造与长度计算集中在这里，调用方不用碰 C 指针。
struct UnixSocketAddress {
    private var storage: sockaddr_un
    /// 实际用到的长度。`sun_path` 之后的字节没有意义，不能算进去。
    private let length: socklen_t

    init?(path: String) {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        // 末尾要留一个字节放结束符。
        guard bytes.count < capacity else { return nil }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                for (index, byte) in bytes.enumerated() {
                    buffer[index] = CChar(bitPattern: byte)
                }
                buffer[bytes.count] = 0
            }
        }
        storage = address
        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 0
        length = socklen_t(pathOffset + bytes.count + 1)
    }

    /// 把地址交给 `bind` 或 `connect`。
    func withSockaddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = storage
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, length) }
        }
    }
}

/// 套接字上的按行读写。helper 的请求与回复都是单行 JSON。
enum UnixSocketIO {
    /// 读到换行或对端关闭为止。返回 nil 表示超过上限。
    static func readLine(_ descriptor: Int32, limit: Int) -> String? {
        var output = [UInt8]()
        var byte: UInt8 = 0
        while output.count < limit {
            let count = Darwin.read(descriptor, &byte, 1)
            if count <= 0 {
                guard !output.isEmpty else { return nil }
                return String(bytes: output, encoding: .utf8)
            }
            if byte == UInt8(ascii: "\n") {
                return String(bytes: output, encoding: .utf8)
            }
            output.append(byte)
        }
        return nil
    }

    @discardableResult
    static func writeAll(_ descriptor: Int32, _ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
            }
            if written <= 0 { return false }
            offset += written
        }
        return true
    }
}

// MARK: - Fan control

struct FanControlHelperStatus: Equatable, Sendable {
    let active: Bool
    let mode: String
    let controlTemperature: Double?
    let leaseRemainingSeconds: Int
    let error: String?
}

struct FanControlCommandResult: Equatable, Sendable {
    let ok: Bool
    let message: String?
    let status: FanControlHelperStatus?
}

extension HelperClient {
    func fanControlStatus() -> FanControlHelperStatus? {
        guard let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_STATUS,
            timeoutMillis: 2_000
        ), reply.ok else { return nil }
        return Self.fanControlStatus(from: reply.result ?? [:])
    }

    func configureFanControl(_ configuration: MonitorFanConfiguration) -> FanControlCommandResult {
        let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: configuration.helperPayload(),
            timeoutMillis: 30_000
        )
        return FanControlCommandResult(
            ok: reply?.ok == true,
            message: reply?.error,
            status: reply?.result.map(Self.fanControlStatus)
        )
    }

    func keepAliveFanControl() -> FanControlHelperStatus? {
        guard let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_KEEP_ALIVE,
            timeoutMillis: 2_000
        ), reply.ok else { return nil }
        return Self.fanControlStatus(from: reply.result ?? [:])
    }

    func restoreFanControl() -> FanControlCommandResult {
        let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_RESTORE,
            timeoutMillis: 5_000
        )
        return FanControlCommandResult(
            ok: reply?.ok == true,
            message: reply?.error,
            status: reply?.result.map(Self.fanControlStatus)
        )
    }

    private static func fanControlStatus(from result: [String: String]) -> FanControlHelperStatus {
        FanControlHelperStatus(
            active: result["active"] == "true",
            mode: result["mode"] ?? "system",
            controlTemperature: result["controlTemperature"].flatMap(Double.init),
            leaseRemainingSeconds: result["leaseRemainingSeconds"].flatMap(Int.init) ?? 0,
            error: result["error"]
        )
    }
}

/// Keeps the helper lease alive while Covio is running.
/// The helper restores system control by itself if this process stops.
final class FanControlLeaseKeeper: @unchecked Sendable {
    static let shared = FanControlLeaseKeeper()

    private let queue = DispatchQueue(label: "com.wyz.covio.fan-control-lease")
    private let client: HelperClient
    private var timer: DispatchSourceTimer?

    init(client: HelperClient = HelperClient()) {
        self.client = client
    }

    func start() {
        queue.async { [weak self] in
            guard let self, timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(
                deadline: .now() + .seconds(Int(MonitorFanPolicy.heartbeatSeconds)),
                repeating: .seconds(Int(MonitorFanPolicy.heartbeatSeconds))
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                guard HelperReleaseInspector.inspect(client: self.client).allowsPrivilegedWrites else {
                    return
                }
                _ = self.client.keepAliveFanControl()
            }
            source.resume()
            timer = source
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// Called on normal app termination. A crash is covered by the helper lease.
    func stopAndRestore() {
        queue.sync {
            timer?.cancel()
            timer = nil
            _ = client.restoreFanControl()
        }
    }
}
