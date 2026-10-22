import Foundation

struct FileNamingTextExtractor: Sendable {
    let policy: FileNamingExtractionPolicy

    func extract(
        candidateId: String,
        fileURL: URL,
        kind: FileNamingContentKind,
        sources: Set<FileNamingExtractionSource>
    ) -> FileNamingExtractionResult {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            data = try handle.read(upToCount: policy.maxTextBytes) ?? Data()
        } catch {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .unreadableInput,
                    detail: error.localizedDescription
                )
            )
        }

        guard !data.isEmpty else {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .emptyContent,
                    detail: "Text input is empty."
                )
            )
        }

        guard let decoded = Self.decode(data), !decoded.contains("\0") else {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .unreadableInput,
                    detail: "Text encoding is not UTF-8 or UTF-16."
                )
            )
        }

        let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .emptyContent,
                    detail: "Text input contains whitespace only."
                )
            )
        }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
        let truncated = fileSize > data.count
        return .success(
            FileNamingExtraction(
                candidateId: candidateId,
                fileURL: fileURL,
                kind: kind,
                text: text,
                images: [],
                sources: sources.union([.fileText]),
                quality: truncated ? .medium : .high,
                warnings: truncated ? [.truncatedInput] : []
            )
        )
    }

    private static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf16LittleEndian) {
            return text
        }
        if let text = String(data: data, encoding: .utf16BigEndian) {
            return text
        }
        return nil
    }
}
