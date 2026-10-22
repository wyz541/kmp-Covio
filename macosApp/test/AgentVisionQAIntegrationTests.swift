import AppKit
import MLXLMCommon
import XCTest
@testable import Covio

final class AgentVisionQAIntegrationTests: XCTestCase {
    func testRealLocalVLMAnswersAColorQuestion() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["COVIO_VISION_QA_MODEL_DIR"],
              !modelPath.isEmpty
        else {
            throw XCTSkip("Set COVIO_VISION_QA_MODEL_DIR to run the real local VLM test.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-vision-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("red-square.png")
        try makeRedSquarePNG().write(to: imageURL, options: .atomic)

        let runtime = LocalModelRuntime(
            modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true)
        )
        let service = AgentVisionQAService(containerRuntime: runtime)
        let result = await service.answer(
            file: ResolvedAgentFile(
                fileId: "attachment:\(UUID().uuidString.lowercased())",
                displayName: "red-square.png",
                url: imageURL
            ),
            question: "What color is the large square? Answer in one short sentence."
        )

        let answer = try XCTUnwrap(result.data?.objectValue?["answer"]?.stringValue)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(answer.lowercased().contains("red"), answer)
        await runtime.unloadModelContainer()
    }

    private func makeRedSquarePNG() throws -> Data {
        let size = NSSize(width: 640, height: 640)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.systemRed.setFill()
        NSRect(x: 120, y: 120, width: 400, height: 400).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}
