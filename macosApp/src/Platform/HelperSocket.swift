import Darwin
import Foundation

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

/// 套接字上的按行读写。legacy helper 的请求与回复都是单行 JSON。
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
