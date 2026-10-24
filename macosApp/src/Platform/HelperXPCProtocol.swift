import Foundation

/// app 与 helper 之间唯一的 XPC 方法。
///
/// 请求与回复继续使用共享层的单行 JSON 协议。这样 legacy socket 迁移期间
/// 两套 transport 共用同一套校验、命令白名单和测试向量。
@objc protocol CovioHelperXPCProtocol {
    func transact(_ requestLine: String, withReply reply: @escaping (String?) -> Void)
}
