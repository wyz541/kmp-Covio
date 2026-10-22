import Foundation
import MLXLMCommon
import PDFKit

actor AgentFileSearchIndex {
    private struct Identity: Sendable, Equatable {
        let fileId: String
        let size: Int64
        let modifiedAt: TimeInterval
    }

    private struct Chunk: Sendable {
        let text: String
        let page: Int?
        let characterStart: Int
        let characterEnd: Int
    }

    private struct CachedFile: Sendable {
        let identity: Identity
        let kind: FileNamingContentKind
        let chunks: [Chunk]
    }

    private var cache: [String: CachedFile] = [:]
    private let extractor = FileNamingContentExtractor()
    private let chunkSize = 900
    private let overlap = 120

    func search(
        files: [ResolvedAgentFile],
        query: String,
        limit: Int
    ) async -> AgentServiceResult {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return .failure("Search query is required.", code: .invalidArguments)
        }
        let terms = Self.queryTerms(normalizedQuery)
        var scored: [(ResolvedAgentFile, Chunk, String, Int)] = []

        for file in files {
            guard let cached = await indexedFile(file) else { continue }
            for (index, chunk) in cached.chunks.enumerated() {
                let citation = "\(file.fileId)#chunk-\(index + 1)"
                let score = Self.score(
                    text: chunk.text,
                    fileName: file.displayName,
                    query: normalizedQuery,
                    terms: terms
                )
                scored.append((file, chunk, citation, score))
            }
        }
        let positive = scored.filter { $0.3 > 0 }
        let candidates = positive.isEmpty ? scored : positive
        let selected = candidates
            .sorted {
                if $0.3 == $1.3 { return $0.2 < $1.2 }
                return $0.3 > $1.3
            }
            .prefix(min(12, max(1, limit)))

        let values: [JSONValue] = selected.map { file, chunk, citation, score in
            let page: JSONValue = chunk.page.map { .int($0) } ?? .null
            return JSONValue.object([
                "citation": .string(citation),
                "fileId": .string(file.fileId),
                "name": .string(file.displayName),
                "page": page,
                "characterStart": .int(chunk.characterStart),
                "characterEnd": .int(chunk.characterEnd),
                "text": .string(chunk.text),
                "score": .int(score),
            ])
        }
        let citations = selected.map { file, chunk, citation, _ in
            let location = chunk.page.map { " page \($0)" } ?? ""
            return "[\(citation)] \(file.displayName)\(location)"
        }
        let summary = (
            ["Found \(values.count) excerpts from \(Set(selected.map { $0.0.fileId }).count) files."]
                + citations
        ).joined(separator: "\n")
        return AgentServiceResult(
            ok: !values.isEmpty,
            summary: summary,
            data: .object(["chunks": .array(values)]),
            errorCode: values.isEmpty ? .fileUnavailable : nil
        )
    }

    private func indexedFile(_ file: ResolvedAgentFile) async -> CachedFile? {
        let path = file.url.standardizedFileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular
        else {
            return nil
        }
        let identity = Identity(
            fileId: file.fileId,
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modifiedAt: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        )
        let key = path
        if let cached = cache[key], cached.identity == identity {
            return cached
        }
        let indexed = buildIndex(file: file, identity: identity)
        cache[key] = indexed
        return indexed
    }

    private func buildIndex(file: ResolvedAgentFile, identity: Identity) -> CachedFile {
        if let pages = pdfPageChunks(file.url), !pages.isEmpty {
            return CachedFile(identity: identity, kind: .pdf, chunks: pages)
        }
        guard case .success(let extraction) = extractor.extract(
            candidateId: file.fileId,
            fileURL: file.url
        ) else {
            return CachedFile(identity: identity, kind: .unknown, chunks: [])
        }
        return CachedFile(
            identity: identity,
            kind: extraction.kind,
            chunks: chunks(from: extraction.text, page: nil)
        )
    }

    private func pdfPageChunks(_ url: URL) -> [Chunk]? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return nil
        }
        var result: [Chunk] = []
        for pageIndex in 0..<min(document.pageCount, 40) {
            guard let text = document.page(at: pageIndex)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { continue }
            result.append(contentsOf: chunks(from: text, page: pageIndex + 1))
        }
        return result
    }

    private func chunks(from text: String, page: Int?) -> [Chunk] {
        guard !text.isEmpty else { return [] }
        var result: [Chunk] = []
        var start = 0
        while start < text.count {
            let end = min(text.count, start + chunkSize)
            let startIndex = text.index(text.startIndex, offsetBy: start)
            let endIndex = text.index(text.startIndex, offsetBy: end)
            result.append(
                Chunk(
                    text: String(text[startIndex..<endIndex]),
                    page: page,
                    characterStart: start,
                    characterEnd: end
                )
            )
            if end == text.count { break }
            start = max(start + 1, end - overlap)
        }
        return result
    }

    private static func queryTerms(_ query: String) -> [String] {
        let lowered = query.lowercased()
        let words = lowered
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
            .filter { $0.count >= 2 }
        if !words.isEmpty { return Array(Set(words)) }
        let characters = Array(lowered.filter { !$0.isWhitespace })
        guard characters.count >= 2 else { return [lowered] }
        return Array(Set((0..<(characters.count - 1)).map {
            String(characters[$0...($0 + 1)])
        }))
    }

    private static func score(
        text: String,
        fileName: String,
        query: String,
        terms: [String]
    ) -> Int {
        let lowered = text.lowercased()
        var value = lowered.components(separatedBy: query.lowercased()).count - 1
        value *= 8
        if fileName.lowercased().contains(query.lowercased()) { value += 12 }
        for term in terms {
            value += lowered.components(separatedBy: term).count - 1
        }
        return value
    }
}
