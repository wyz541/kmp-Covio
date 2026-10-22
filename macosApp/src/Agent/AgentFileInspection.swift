import AppKit
import Foundation
import MLXLMCommon
import PDFKit

struct AgentAuthorizedFile: Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let url: URL
}

enum AgentFileReference: Sendable, Equatable {
    case workspace(String)
    case attachment(String)

    init?(fileId: String) {
        if fileId.hasPrefix("workspace:") {
            let value = String(fileId.dropFirst("workspace:".count))
            guard value.count == 64,
                  value.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
            else { return nil }
            self = .workspace(value)
            return
        }
        if fileId.hasPrefix("attachment:") {
            let value = String(fileId.dropFirst("attachment:".count))
            guard UUID(uuidString: value) != nil else { return nil }
            self = .attachment(value)
            return
        }
        return nil
    }
}

@MainActor
final class AgentAttachmentStore {
    private(set) var files: [AgentAuthorizedFile] = []
    private var securityScopedURLs: [String: URL] = [:]

    @discardableResult
    func authorize(_ urls: [URL]) -> [AgentAuthorizedFile] {
        var added: [AgentAuthorizedFile] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            guard Self.isRegularNonSymlinkFile(standardized) else { continue }
            if let existing = files.first(where: { $0.url == standardized }) {
                added.append(existing)
                continue
            }
            let id = "attachment:\(UUID().uuidString.lowercased())"
            if standardized.startAccessingSecurityScopedResource() {
                securityScopedURLs[id] = standardized
            }
            let file = AgentAuthorizedFile(
                id: id,
                displayName: standardized.lastPathComponent,
                url: standardized
            )
            files.append(file)
            added.append(file)
        }
        return added
    }

    func revoke(_ fileId: String) {
        guard let index = files.firstIndex(where: { $0.id == fileId }) else { return }
        securityScopedURLs.removeValue(forKey: fileId)?.stopAccessingSecurityScopedResource()
        files.remove(at: index)
    }

    func clear() {
        for url in securityScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs = [:]
        files = []
    }

    func file(id: String) -> AgentAuthorizedFile? {
        files.first { $0.id == id }
    }

    deinit {
        for url in securityScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private static func isRegularNonSymlinkFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

struct ResolvedAgentFile: Sendable, Equatable {
    let fileId: String
    let displayName: String
    let url: URL
}

struct AgentFileInspector: Sendable {
    let extractor: FileNamingContentExtractor

    init(extractor: FileNamingContentExtractor = FileNamingContentExtractor()) {
        self.extractor = extractor
    }

    func inspect(
        _ file: ResolvedAgentFile,
        maxCharacters: Int
    ) -> AgentServiceResult {
        let limit = min(20_000, max(500, maxCharacters))
        let result = extractor.extract(
            candidateId: file.fileId,
            fileURL: file.url
        )
        switch result {
        case .failure(let failure):
            let code: AgentServiceErrorCode = failure.error == .unsupportedType
                ? .unsupportedFileType
                : .fileUnavailable
            return AgentServiceResult(
                ok: false,
                summary: "Could not inspect \(file.displayName): \(failure.detail)",
                data: .object([
                    "fileId": .string(file.fileId),
                    "name": .string(file.displayName),
                    "error": .string(failure.error.rawValue),
                ]),
                errorCode: code
            )
        case .success(let extraction):
            let text = String(extraction.text.prefix(limit))
            var data: [String: JSONValue] = [
                "fileId": .string(file.fileId),
                "name": .string(file.displayName),
                "kind": .string(extraction.kind.rawValue),
                "quality": .string(extraction.quality.rawValue),
                "sources": .array(
                    extraction.sources.map(\.rawValue).sorted().map(JSONValue.string)
                ),
                "warnings": .array(
                    extraction.warnings.map(\.rawValue).sorted().map(JSONValue.string)
                ),
                "text": .string(text),
                "characterCount": .int(extraction.text.count),
                "truncated": .bool(text.count < extraction.text.count),
                "imageCount": .int(extraction.images.count),
                "untrusted": .bool(true),
            ]
            let pages = Self.pdfPages(fileURL: file.url, maxCharacters: limit)
            if !pages.isEmpty {
                data["pages"] = .array(pages)
            }
            return AgentServiceResult(
                ok: true,
                summary: "Inspected \(file.displayName) as \(extraction.kind.rawValue).",
                data: .object(data)
            )
        }
    }

    private static func pdfPages(fileURL: URL, maxCharacters: Int) -> [JSONValue] {
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            return []
        }
        var remaining = maxCharacters
        var pages: [JSONValue] = []
        for index in 0..<min(document.pageCount, 8) {
            guard remaining > 0, let page = document.page(at: index) else { break }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }
            let excerpt = String(text.prefix(remaining))
            remaining -= excerpt.count
            pages.append(.object([
                "page": .int(index + 1),
                "text": .string(excerpt),
            ]))
        }
        return pages
    }
}
