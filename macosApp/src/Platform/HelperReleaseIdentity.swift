import CryptoKit
import Darwin
import Foundation
import Security
import kmpDomain

/// 读取当前进程可携带的完整发布身份。
///
/// helper 在进程启动时缓存这个值。app 更新磁盘上的文件后，仍在运行的旧 helper
/// 继续报告启动时的身份，不会把新文件误报成当前进程身份。
enum HelperReleaseIdentitySource {
    // KMP data class 在 Swift 侧没有 Sendable 标注。这个值启动后不可变。
    nonisolated(unsafe) static let daemonIdentity: HelperReleaseIdentity? = makeIdentity(
        helperExecutablePath: ownExecutablePath
    )

    nonisolated(unsafe) static let expectedAppIdentity: HelperReleaseIdentity? = makeIdentity(
        helperExecutablePath: bundledHelperExecutablePath
    )

    static var bundledHelperExecutablePath: String? {
        guard let executable = Bundle.main.executablePath else { return nil }
        let candidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/CovioHelper")
            .path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : executable
    }

    private static var ownExecutablePath: String? {
        Bundle.main.executablePath
    }

    private static func makeIdentity(helperExecutablePath: String?) -> HelperReleaseIdentity? {
        guard let helperExecutablePath,
              let sha256 = sha256File(path: helperExecutablePath)
        else {
            return nil
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let gitCommit = (info["CovioGitCommit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseId = (info["CovioReleaseId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return HelperReleaseHandshake.shared.parse(
            result: [
                "releaseId": releaseId ?? "",
                "productVersion": GeneratedReleaseIdentity.productVersion,
                "buildNumber": String(GeneratedReleaseIdentity.buildNumber),
                "gitCommit": gitCommit ?? "",
                "protocolVersion": String(GeneratedReleaseIdentity.helperProtocolVersion),
                "helperSHA256": sha256,
                "channel": GeneratedReleaseIdentity.channel,
            ]
        )
    }

    private static func sha256File(path: String) -> String? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        var hasher = SHA256()
        do {
            while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 一次完整握手。调用方只根据返回状态决定是否开放特权写入。
enum HelperReleaseInspector {
    static func inspect(
        client: HelperClient,
        expectedIdentity: HelperReleaseIdentity? = HelperReleaseIdentitySource.expectedAppIdentity,
        expectedExecutablePath: String? = HelperReleaseIdentitySource.bundledHelperExecutablePath,
        isTrusted: (pid_t?, String) -> Bool = {
            HelperCodeTrust.isTrusted(peerPID: $0, expectedExecutablePath: $1)
        }
    ) -> HelperStatus {
        guard FileManager.default.fileExists(atPath: client.socketPath) else { return .missing }
        guard let probe = client.versionProbe() else { return .untrusted }
        guard let observed = HelperReleaseHandshake.shared.parse(result: probe.result) else {
            return HelperReleaseHandshake.shared.hasIdentityFields(result: probe.result)
                ? .untrusted
                : .outdated
        }
        guard let expectedIdentity, let expectedExecutablePath else { return .untrusted }
        return HelperReleaseHandshake.shared.classify(
            expected: expectedIdentity,
            observed: observed,
            signatureTrusted: isTrusted(probe.peerPID, expectedExecutablePath)
        )
    }
}

/// 验证 socket 对端确实是当前发布包中的 helper 可执行文件。
enum HelperCodeTrust {
    static func isTrusted(peerPID: pid_t?, expectedExecutablePath: String) -> Bool {
        guard let peerPID, peerPID > 0 else { return false }
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: peerPID)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              let actualPath = executablePath(pid: peerPID)
        else {
            return false
        }
        return canonicalPath(actualPath) == canonicalPath(expectedExecutablePath)
    }

    private static func executablePath(pid: pid_t) -> String? {
        // libproc.h 定义的上限是 4096，但该常量没有导入 Swift。
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
