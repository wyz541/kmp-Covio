import Foundation

/// 文件命名前的内容提取入口。
///
/// 先检查文件身份和类型，再选择文本、PDF 或图片提取器。
/// 所有读取都在调用线程同步完成；UI 层负责放到后台队列。
struct FileNamingContentExtractor: Sendable {
    let policy: FileNamingExtractionPolicy
    private let probe = FileNamingTypeProbe()

    init(policy: FileNamingExtractionPolicy = .init()) {
        self.policy = policy
    }

    func extract(candidateId: String, fileURL: URL) -> FileNamingExtractionResult {
        let values: URLResourceValues
        do {
            values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
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
        if values.isSymbolicLink == true {
            return failure(candidateId, fileURL, .symbolicLinkUnsupported)
        }
        guard values.isRegularFile == true else {
            return failure(candidateId, fileURL, .notRegularFile)
        }

        let observation: FileNamingTypeObservation
        do {
            observation = try probe.observe(fileURL)
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

        switch observation.kind {
        case .text:
            return FileNamingTextExtractor(policy: policy).extract(
                candidateId: candidateId,
                fileURL: fileURL,
                kind: .text,
                sources: [.contentSniff]
            )
        case .code:
            return FileNamingTextExtractor(policy: policy).extract(
                candidateId: candidateId,
                fileURL: fileURL,
                kind: .code,
                sources: [.contentSniff]
            )
        case .pdf:
            return FileNamingPDFExtractor(policy: policy).extract(candidateId: candidateId, fileURL: fileURL)
        case .image:
            return FileNamingImageExtractor(policy: policy).extract(candidateId: candidateId, fileURL: fileURL)
        case .mixed:
            return extractMixed(candidateId: candidateId, fileURL: fileURL)
        case .unknown:
            return failure(candidateId, fileURL, .unsupportedType)
        }
    }

    private func extractMixed(candidateId: String, fileURL: URL) -> FileNamingExtractionResult {
        let text = FileNamingTextExtractor(policy: policy).extract(
            candidateId: candidateId,
            fileURL: fileURL,
            kind: .mixed,
            sources: [.contentSniff]
        )
        guard case .success(let extraction) = text else { return text }
        return .success(
            FileNamingExtraction(
                candidateId: extraction.candidateId,
                fileURL: extraction.fileURL,
                kind: .mixed,
                text: extraction.text,
                images: extraction.images,
                sources: extraction.sources,
                quality: .medium,
                warnings: extraction.warnings.union([.mixedContent])
            )
        )
    }

    private func failure(
        _ candidateId: String,
        _ fileURL: URL,
        _ error: FileNamingExtractionError
    ) -> FileNamingExtractionResult {
        .failure(
            FileNamingExtractionFailure(
                candidateId: candidateId,
                fileURL: fileURL,
                error: error,
                detail: error.localizedDescription
            )
        )
    }
}

