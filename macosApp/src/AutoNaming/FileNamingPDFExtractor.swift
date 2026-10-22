import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct FileNamingPDFExtractor: Sendable {
    let policy: FileNamingExtractionPolicy

    func extract(candidateId: String, fileURL: URL) -> FileNamingExtractionResult {
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize > policy.maxPDFBytes {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .fileTooLarge,
                    detail: "PDF exceeds \(policy.maxPDFBytes) bytes."
                )
            )
        }
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .pdfUnreadable,
                    detail: "PDFKit cannot open the document."
                )
            )
        }

        let textPageCount = min(document.pageCount, policy.maxPDFTextPages)
        let text = (0..<textPageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .collapsedFileNamingWhitespace()
        if text.count >= policy.minimumOCRCharacters {
            return .success(
                FileNamingExtraction(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    kind: .pdf,
                    text: text,
                    images: [],
                    sources: [.pdfText, .fileMetadata],
                    quality: document.pageCount > textPageCount ? .medium : .high,
                    warnings: document.pageCount > textPageCount ? [.partialDocument] : []
                )
            )
        }

        let pageCount = min(document.pageCount, policy.maxScannedPDFPages)
        var images: [FileNamingExtractedImage] = []
        var ocrParts: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index), let rendered = render(page) else { continue }
            images.append(rendered.image)
            let recognized = VisionTextRecognizer.recognizeText(in: rendered.cgImage).collapsedFileNamingWhitespace()
            if !recognized.isEmpty {
                ocrParts.append(recognized)
            }
        }
        let ocrText = ocrParts.joined(separator: "\n").collapsedFileNamingWhitespace()
        guard !images.isEmpty || !ocrText.isEmpty else {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .pdfUnreadable,
                    detail: "The PDF has no text and no renderable pages."
                )
            )
        }

        var warnings = Set<FileNamingExtractionWarning>()
        if document.pageCount > pageCount { warnings.insert(.partialDocument) }
        if ocrText.count < policy.minimumOCRCharacters { warnings.insert(.lowOCR) }
        return .success(
            FileNamingExtraction(
                candidateId: candidateId,
                fileURL: fileURL,
                kind: .pdf,
                text: ocrText,
                images: images,
                sources: ocrText.isEmpty ? [.imagePixels, .fileMetadata] : [.pdfOCR, .imagePixels, .fileMetadata],
                quality: ocrText.count >= policy.minimumOCRCharacters ? .medium : .low,
                warnings: warnings
            )
        )
    }

    private func render(_ page: PDFPage) -> (image: FileNamingExtractedImage, cgImage: CGImage)? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(
            CGFloat(policy.maxImageDimension) / max(bounds.width, bounds.height),
            2.0
        )
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let cgImage = context.makeImage(), let data = pngData(for: cgImage) else {
            return nil
        }
        return (
            FileNamingExtractedImage(
                data: data,
                mimeType: "image/png",
                pixelWidth: width,
                pixelHeight: height
            ),
            cgImage
        )
    }

    private func pngData(for image: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = NSSize(width: image.width, height: image.height)
        return representation.representation(using: .png, properties: [:])
    }
}
