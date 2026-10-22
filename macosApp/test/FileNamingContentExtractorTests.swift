import AppKit
import CoreGraphics
import PDFKit
import XCTest
@testable import Covio

final class FileNamingContentExtractorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-file-extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPlainTextIsExtracted() throws {
        let url = try write("Quarterly budget review\nOwner: Product", name: "notes.txt")

        let result = FileNamingContentExtractor().extract(candidateId: "text", fileURL: url)

        XCTAssertEqual(result.extraction?.kind, .text)
        XCTAssertEqual(result.extraction?.text, "Quarterly budget review\nOwner: Product")
        XCTAssertTrue(result.extraction?.sources.contains(.fileText) == true)
        XCTAssertEqual(result.extraction?.quality, .high)
    }

    func testCodeFileIsExtracted() throws {
        let url = try write(
            """
            import Foundation

            struct RetryPolicy {
                let maxAttempts: Int
            }
            """,
            name: "RetryPolicy.swift"
        )

        let result = FileNamingContentExtractor().extract(candidateId: "code", fileURL: url)

        XCTAssertEqual(result.extraction?.kind, .code)
        XCTAssertTrue(result.extraction?.text.contains("struct RetryPolicy") == true)
        XCTAssertEqual(result.extraction?.quality, .high)
    }

    func testUnknownExtensionWithMultipleSignalsIsMixed() throws {
        let url = try write(
            """
            subject: File naming review
            from: qa@example.invalid
            {"status":"ready","model":"local"}
            2026-10-20T13:20:00Z INFO complete
            """,
            name: "mixed-no-extension"
        )

        let result = FileNamingContentExtractor().extract(candidateId: "mixed", fileURL: url)

        XCTAssertEqual(result.extraction?.kind, .mixed)
        XCTAssertTrue(result.extraction?.warnings.contains(.mixedContent) == true)
    }

    func testLargeTextIsTruncated() throws {
        let url = try write(String(repeating: "a", count: 64), name: "large.txt")
        let extractor = FileNamingContentExtractor(
            policy: FileNamingExtractionPolicy(maxTextBytes: 16)
        )

        let result = extractor.extract(candidateId: "large", fileURL: url)

        XCTAssertEqual(result.extraction?.text.count, 16)
        XCTAssertTrue(result.extraction?.warnings.contains(.truncatedInput) == true)
        XCTAssertEqual(result.extraction?.quality, .medium)
    }

    func testEmptyTextIsRejected() throws {
        let url = try write("", name: "empty.txt")

        let result = FileNamingContentExtractor().extract(candidateId: "empty", fileURL: url)

        XCTAssertEqual(result.failure?.error, .emptyContent)
    }

    func testTextPDFUsesPDFKit() throws {
        let url = directory.appendingPathComponent("report.pdf")
        try makeTextPDF("Project Alpha budget review", at: url)

        let result = FileNamingContentExtractor().extract(candidateId: "pdf", fileURL: url)

        XCTAssertEqual(result.extraction?.kind, .pdf)
        XCTAssertTrue(result.extraction?.text.contains("Project Alpha") == true)
        XCTAssertTrue(result.extraction?.sources.contains(.pdfText) == true)
        XCTAssertTrue(result.extraction?.images.isEmpty == true)
    }

    func testScannedPDFUsesOCRAndReturnsPageImages() throws {
        let url = directory.appendingPathComponent("scan.pdf")
        try makeImagePDF("Project Beta weekly report", at: url)

        let result = FileNamingContentExtractor().extract(candidateId: "scan", fileURL: url)

        XCTAssertEqual(result.extraction?.kind, .pdf)
        XCTAssertTrue(result.extraction?.sources.contains(.pdfOCR) == true)
        XCTAssertFalse(result.extraction?.images.isEmpty ?? true)
        XCTAssertTrue(result.extraction?.text.lowercased().contains("project beta") == true)
    }

    func testImageUsesOCRAndReturnsWorkspaceImage() throws {
        let url = directory.appendingPathComponent("receipt.png")
        try makeTextPNG("Travel receipt for Shanghai", at: url)

        let result = FileNamingContentExtractor().extract(candidateId: "image", fileURL: url)

        XCTAssertEqual(result.extraction?.kind, .image)
        XCTAssertTrue(result.extraction?.text.lowercased().contains("travel receipt") == true)
        XCTAssertTrue(result.extraction?.sources.contains(.imageOCR) == true)
        XCTAssertEqual(result.extraction?.images.count, 1)
    }

    func testImageWithoutTextKeepsPixelsForVisionModel() throws {
        let url = directory.appendingPathComponent("plain.png")
        try makeSolidPNG(at: url)

        let result = FileNamingContentExtractor().extract(candidateId: "plain", fileURL: url)

        XCTAssertEqual(result.extraction?.kind, .image)
        XCTAssertEqual(result.extraction?.text, "")
        XCTAssertEqual(result.extraction?.images.count, 1)
        XCTAssertTrue(result.extraction?.warnings.contains(.lowOCR) == true)
    }

    func testOversizedImageAndPDFAreRejected() throws {
        let png = directory.appendingPathComponent("large.png")
        try makeTextPNG("Large image", at: png)
        let pdf = directory.appendingPathComponent("large.pdf")
        try makeTextPDF("Large PDF", at: pdf)
        let extractor = FileNamingContentExtractor(
            policy: FileNamingExtractionPolicy(maxPDFBytes: 1, maxImageBytes: 1)
        )

        XCTAssertEqual(
            extractor.extract(candidateId: "image", fileURL: png).failure?.error,
            .fileTooLarge
        )
        XCTAssertEqual(
            extractor.extract(candidateId: "pdf", fileURL: pdf).failure?.error,
            .fileTooLarge
        )
    }

    func testCorruptedPDFAndImageHaveStableErrors() throws {
        let pdf = try write("not a pdf", name: "broken.pdf")
        let image = try write("not an image", name: "broken.png")

        let extractor = FileNamingContentExtractor()
        XCTAssertEqual(
            extractor.extract(candidateId: "pdf", fileURL: pdf).failure?.error,
            .pdfUnreadable
        )
        XCTAssertEqual(
            extractor.extract(candidateId: "image", fileURL: image).failure?.error,
            .imageUnreadable
        )
    }

    func testDirectoriesAndSymlinksAreRejected() throws {
        let extractor = FileNamingContentExtractor()
        let directoryResult = extractor.extract(candidateId: "dir", fileURL: directory)
        XCTAssertEqual(directoryResult.failure?.error, .notRegularFile)

        let file = try write("text", name: "target.txt")
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let linkResult = extractor.extract(candidateId: "link", fileURL: link)
        XCTAssertEqual(linkResult.failure?.error, .symbolicLinkUnsupported)
    }

    func testUnknownBinaryIsRejected() throws {
        let url = try write(Data([0x00, 0xFF, 0x10, 0x80, 0x00]), name: "blob.bin")

        let result = FileNamingContentExtractor().extract(candidateId: "binary", fileURL: url)

        XCTAssertEqual(result.failure?.error, .unsupportedType)
    }

    private func write(_ text: String, name: String) throws -> URL {
        try write(Data(text.utf8), name: name)
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func makeTextPDF(_ text: String, at url: URL) throws {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw NSError(domain: "test", code: 1)
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 800, height: 240)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "test", code: 2)
        }
        context.beginPDFPage(nil)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        (text as NSString).draw(at: NSPoint(x: 40, y: 100), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        try data.write(to: url)
    }

    private func makeImagePDF(_ text: String, at url: URL) throws {
        let image = try makeTextImage(text)
        guard let page = PDFPage(image: image) else {
            throw NSError(domain: "test", code: 3)
        }
        let document = PDFDocument()
        document.insert(page, at: 0)
        guard document.write(to: url) else {
            throw NSError(domain: "test", code: 4)
        }
    }

    private func makeSolidPNG(at url: URL) throws {
        let image = NSImage(size: NSSize(width: 120, height: 120))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 120).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    private func makeTextPNG(_ text: String, at url: URL) throws {
        let image = try makeTextImage(text)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    private func makeTextImage(_ text: String) throws -> NSImage {
        let size = NSSize(width: 900, height: 280)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        string.draw(at: NSPoint(x: 32, y: 110))
        image.unlockFocus()
        return image
    }
}
