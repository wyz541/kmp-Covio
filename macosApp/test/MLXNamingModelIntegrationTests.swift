import AppKit
import XCTest
@testable import Covio

final class MLXNamingModelIntegrationTests: XCTestCase {
    @MainActor
    func testLocalModelReturnsValidFieldsForTextAndImage() async throws {
        guard let modelPath = Self.testValue(
            environmentKey: "COVIO_FILE_NAMING_MODEL_DIR",
            fileName: "file-naming-model-test-path.txt"
        ) else {
            throw XCTSkip("Run scripts/test-file-naming-model.sh with a local model directory")
        }

        var configuration = NamingModelConfiguration(
            modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true)
        )
        configuration.requestTimeout = .seconds(120)
        let model = MLXNamingModel(configuration: configuration)

        do {
            let preheat = try await model.preheat()
            let text = try await model.generate(
                NamingModelRequest(
                    candidateId: "integration-text",
                    kind: .text,
                    text: "2026 年第四季度产品预算评审。项目：离线文件自动命名。本周完成模型选型、内容提取和安全校验。",
                    quality: .high
                )
            )
            let image = try await model.generate(
                NamingModelRequest(
                    candidateId: "integration-image",
                    kind: .image,
                    text: "",
                    images: [
                        FileNamingExtractedImage(
                            data: try Self.makeReceiptImage(),
                            mimeType: "image/png",
                            pixelWidth: 900,
                            pixelHeight: 600
                        ),
                    ],
                    quality: .medium
                )
            )

            XCTAssertEqual(text.origin, .mlx)
            XCTAssertFalse(text.title.isEmpty)
            XCTAssertEqual(image.origin, .mlx)
            XCTAssertFalse(image.title.isEmpty)
            XCTAssertGreaterThan(preheat.peakResidentBytes, 0)
            XCTAssertGreaterThan(text.metrics.outputTokenCount, 0)
            XCTAssertGreaterThan(image.metrics.outputTokenCount, 0)

            let result: [String: Any] = [
                "load_ms": preheat.modelLoadMilliseconds ?? -1,
                "preheat_ms": preheat.preheatMilliseconds ?? -1,
                "text_generation_ms": text.metrics.generationMilliseconds,
                "image_generation_ms": image.metrics.generationMilliseconds,
                "text_input_tokens": text.metrics.inputTokenCount ?? -1,
                "image_input_tokens": image.metrics.inputTokenCount ?? -1,
                "text_output_tokens": text.metrics.outputTokenCount,
                "image_output_tokens": image.metrics.outputTokenCount,
                "peak_resident_bytes": Int64(clamping: image.metrics.peakResidentBytes),
                "text_title": text.title,
                "text_category": text.category,
                "image_title": image.title,
                "image_category": image.category,
            ]
            let data = try JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
            )
            if let outputPath = Self.testValue(
                environmentKey: "COVIO_FILE_NAMING_RESULTS_PATH",
                fileName: "file-naming-model-results-path.txt"
            ) {
                try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            }
            print("COVIO_FILE_NAMING_RESULT\n\(String(decoding: data, as: UTF8.self))")

            await model.release()
        } catch {
            await model.release()
            throw error
        }
    }

    private static func testValue(environmentKey: String, fileName: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty {
            return value
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pointer = repositoryRoot.appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent(fileName)
        guard let value = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    private static func makeReceiptImage() throws -> Data {
        let size = NSSize(width: 900, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: NSRect(x: 24, y: 24, width: 852, height: 552)).stroke()

        let title: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.darkGray,
        ]
        ("差旅报销单" as NSString).draw(at: NSPoint(x: 70, y: 500), withAttributes: title)
        ("金额：128.00 元" as NSString).draw(at: NSPoint(x: 70, y: 390), withAttributes: body)
        ("日期：2026-10-18" as NSString).draw(at: NSPoint(x: 70, y: 320), withAttributes: body)
        ("用途：离线文件命名调研" as NSString).draw(at: NSPoint(x: 70, y: 250), withAttributes: body)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(using: .png, properties: [:])
        else {
            throw NamingModelError(.generationFailed, detail: "Could not create integration image")
        }
        return data
    }
}
