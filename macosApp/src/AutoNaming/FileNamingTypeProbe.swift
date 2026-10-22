import Foundation
import UniformTypeIdentifiers

/// 联合扩展名、UTType 和文件头判断内容类别。
struct FileNamingTypeProbe: Sendable {
    private static let codeExtensions: Set<String> = [
        "swift", "kt", "kts", "java", "c", "h", "cc", "cpp", "cxx", "hpp",
        "m", "mm", "py", "pyw", "js", "jsx", "ts", "tsx", "rs", "go",
        "rb", "php", "cs", "fs", "fsx", "sh", "zsh", "bash", "fish",
        "html", "htm", "css", "scss", "sass", "less", "sql", "graphql",
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "jsonl", "yaml", "yml", "toml",
        "xml", "csv", "tsv", "log", "ini", "cfg", "conf", "env", "rtf",
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff",
        "webp", "bmp",
    ]

    func observe(_ url: URL, maximumHeaderBytes: Int = 4_096) throws -> FileNamingTypeObservation {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: maximumHeaderBytes) ?? Data()
        let extensionName = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: extensionName)

        if header.starts(with: Data("%PDF-".utf8)) {
            return .init(kind: .pdf, evidence: ["pdf-magic"])
        }
        if Self.isImageMagic(header) {
            return .init(kind: .image, evidence: ["image-magic"])
        }
        if extensionName == "pdf" || type?.conforms(to: .pdf) == true {
            return .init(kind: .pdf, evidence: ["pdf-type"])
        }
        if Self.imageExtensions.contains(extensionName) || type?.conforms(to: .image) == true {
            return .init(kind: .image, evidence: ["image-type"])
        }
        if Self.codeExtensions.contains(extensionName) || type?.conforms(to: .sourceCode) == true {
            return .init(kind: .code, evidence: ["code-extension"])
        }

        guard let decoded = Self.decodeTextPrefix(header) else {
            return .init(kind: .unknown, evidence: ["binary-header"])
        }
        if Self.textExtensions.contains(extensionName) || type?.conforms(to: .text) == true {
            return .init(kind: .text, evidence: ["text-type"])
        }

        let signals = Self.structuredSignals(in: decoded)
        if signals.count >= 2 {
            return .init(kind: .mixed, evidence: Set(["text-header"] + signals.map { "signal-\($0)" }))
        }
        return .init(kind: .text, evidence: ["text-header"])
    }

    private static func isImageMagic(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        if bytes.count >= 8, Array(bytes[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
            return true
        }
        if bytes.count >= 3, Array(bytes[0..<3]) == [0xFF, 0xD8, 0xFF] {
            return true
        }
        if bytes.count >= 6 {
            let prefix = String(bytes: bytes[0..<6], encoding: .ascii)
            if prefix == "GIF87a" || prefix == "GIF89a" {
                return true
            }
        }
        if bytes.count >= 4 {
            let prefix = Array(bytes[0..<4])
            if prefix == [0x49, 0x49, 0x2A, 0x00] || prefix == [0x4D, 0x4D, 0x00, 0x2A] {
                return true
            }
            if prefix == [0x42, 0x4D, 0x00, 0x00] {
                return true
            }
        }
        if bytes.count >= 12 {
            if Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46] &&
                Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] {
                return true
            }
            let brand = String(bytes: bytes[8..<12], encoding: .ascii)
            if Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70],
               ["heic", "heix", "hevc", "mif1", "msf1", "avif"].contains(brand) {
                return true
            }
        }
        return false
    }

    private static func decodeTextPrefix(_ data: Data) -> String? {
        guard !data.isEmpty else { return "" }
        if data.contains(0) && !data.starts(with: [0xFF, 0xFE]) && !data.starts(with: [0xFE, 0xFF]) {
            return nil
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        return nil
    }

    private static func structuredSignals(in text: String) -> Set<String> {
        let lower = text.lowercased()
        var signals = Set<String>()
        if lower.contains("\"subject\"") || lower.hasPrefix("subject:") || lower.contains("\nsubject:") {
            signals.insert("email")
        }
        if lower.contains("\"from\"") || lower.contains("\nfrom:") {
            signals.insert("email")
        }
        if (lower.contains("\"test\"") || lower.contains("\"status\"") || lower.contains("\"model\"")) &&
            (lower.contains("{") && lower.contains("}")) {
            signals.insert("json")
        }
        if lower.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#, options: .regularExpression) != nil {
            signals.insert("log")
        }
        if lower.contains("# ") || lower.contains("\n## ") {
            signals.insert("markdown")
        }
        return signals
    }
}
