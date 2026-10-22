import Darwin
import Foundation
import Security

/// helper 的调用方签名校验。
enum HelperSignature {
    /// 当前进程的 designated requirement。安装 helper 时写入 root-owned 文件。
    static func currentRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement
        else {
            return nil
        }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            return nil
        }
        return text as String
    }

    /// 判断一个进程是否满足指定的 designated requirement。
    static func isAuthorized(pid: pid_t, requirementText: String) -> Bool {
        guard !requirementText.isEmpty else { return false }
        var code: SecCode?
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: pid),
        ] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &requirement
        ) == errSecSuccess,
            let requirement
        else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// 读取 Unix 域 socket 的对端进程号。
    static func peerPID(of descriptor: Int32) -> pid_t? {
        var pid = pid_t(0)
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0 else {
            return nil
        }
        return pid
    }
}

/// helper 的连接授权端口。测试可以替换授权器，不需要真实签名。
protocol HelperPeerAuthorizing: Sendable {
    func isAuthorized(descriptor: Int32) -> Bool
}

/// 从 root-owned 文件读取客户端 requirement，再校验对端进程。
final class CodeSignaturePeerAuthorizer: HelperPeerAuthorizing, @unchecked Sendable {
    private let requirementPath: String

    init(requirementPath: String = HelperProtocol.clientRequirementPath) {
        self.requirementPath = requirementPath
    }

    func isAuthorized(descriptor: Int32) -> Bool {
        guard let requirement = try? String(contentsOfFile: requirementPath, encoding: .utf8),
              let pid = HelperSignature.peerPID(of: descriptor)
        else {
            return false
        }
        return HelperSignature.isAuthorized(
            pid: pid,
            requirementText: requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
