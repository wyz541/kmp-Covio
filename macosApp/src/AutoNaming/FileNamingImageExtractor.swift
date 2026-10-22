import AppKit
import CoreGraphics
import Foundation
import ImageIO

struct FileNamingImageExtractor: Sendable {
    let policy: FileNamingExtractionPolicy

    func extract(candidateId: String, fileURL: URL) -> FileNamingExtractionResult {
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize > policy.maxImageBytes {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .fileTooLarge,
                    detail: "Image exceeds \(policy.maxImageBytes) bytes."
                )
            )
        }
        guard let image = decodedImage(fileURL), let data = pngData(for: image) else {
            return .failure(
                FileNamingExtractionFailure(
                    candidateId: candidateId,
                    fileURL: fileURL,
                    error: .imageUnreadable,
                    detail: "ImageIO cannot decode the image."
                )
            )
        }

        let text = VisionTextRecognizer.recognizeText(in: image).collapsedFileNamingWhitespace()
        var warnings = Set<FileNamingExtractionWarning>()
        var sources: Set<FileNamingExtractionSource> = [.imagePixels, .fileMetadata]
        if text.count >= policy.minimumOCRCharacters {
            sources.insert(.imageOCR)
        } else {
            warnings.insert(.lowOCR)
        }
        return .success(
            FileNamingExtraction(
                candidateId: candidateId,
                fileURL: fileURL,
                kind: .image,
                text: text,
                images: [
                    FileNamingExtractedImage(
                        data: data,
                        mimeType: "image/png",
                        pixelWidth: image.width,
                        pixelHeight: image.height
                    )
                ],
                sources: sources,
                quality: text.count >= policy.minimumOCRCharacters ? .high : .low,
                warnings: warnings
            )
        )
    }

    private func decodedImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: policy.maxImageDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func pngData(for image: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = NSSize(width: image.width, height: image.height)
        return representation.representation(using: .png, properties: [:])
    }
}
