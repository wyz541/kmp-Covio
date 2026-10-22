import AppKit
import XCTest
@testable import Covio

final class AgentFileSearchServiceTests: XCTestCase {
    func testTextSearchReturnsCitationAndExcerpt() async throws {
        let url = try temporaryFile(
            name: "notes.txt",
            data: Data("Quarterly budget review and headcount planning.".utf8)
        )
        let index = AgentFileSearchIndex()

        let id = attachmentId
        let result = await index.search(
            files: [file(url, id: id)],
            query: "budget",
            limit: 4
        )
        let chunks = try chunks(result)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?["name"] as? String, "notes.txt")
        XCTAssertEqual(chunks.first?["citation"] as? String, "\(id)#chunk-1")
        XCTAssertTrue((chunks.first?["text"] as? String)?.contains("budget") == true)
    }

    func testCodeSearchUsesCodeText() async throws {
        let url = try temporaryFile(
            name: "Policy.swift",
            data: Data("struct Policy { let requestLimit = 12 }".utf8)
        )
        let result = await AgentFileSearchIndex().search(
            files: [file(url, id: "attachment:\(UUID().uuidString.lowercased())")],
            query: "requestLimit",
            limit: 4
        )
        let chunks = try chunks(result)

        XCTAssertTrue(result.ok)
        XCTAssertTrue((chunks.first?["text"] as? String)?.contains("requestLimit") == true)
    }

    func testPDFSearchIncludesPageCitation() async throws {
        let url = try temporaryFile(name: "report.pdf", data: makePDF())
        let result = await AgentFileSearchIndex().search(
            files: [file(url, id: workspaceId)],
            query: "Offline report",
            limit: 4
        )
        let chunks = try chunks(result)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(chunks.first?["page"] as? Int, 1)
        XCTAssertTrue((chunks.first?["text"] as? String)?.contains("Offline report") == true)
    }

    func testSearchCacheInvalidatesAfterFileChange() async throws {
        let url = try temporaryFile(name: "changing.txt", data: Data("alpha".utf8))
        let index = AgentFileSearchIndex()
        let item = file(url, id: "attachment:\(UUID().uuidString.lowercased())")
        _ = await index.search(files: [item], query: "alpha", limit: 2)
        try Data("beta content".utf8).write(to: url, options: .atomic)

        let result = await index.search(files: [item], query: "beta", limit: 2)
        let chunks = try chunks(result)

        XCTAssertTrue(result.ok)
        XCTAssertTrue((chunks.first?["text"] as? String)?.contains("beta") == true)
    }

    private var attachmentId: String { "attachment:\(UUID().uuidString.lowercased())" }
    private var workspaceId: String { "workspace:\(String(repeating: "d", count: 64))" }

    private func file(_ url: URL, id: String) -> ResolvedAgentFile {
        ResolvedAgentFile(fileId: id, displayName: url.lastPathComponent, url: url)
    }

    private func chunks(_ result: AgentServiceResult) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(result)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(root["data"] as? [String: Any])
        return try XCTUnwrap(payload["chunks"] as? [[String: Any]])
    }

    private func temporaryFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-file-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func makePDF() -> Data {
        let text = NSAttributedString(string: "Offline report\nQ4 budget review")
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        context.beginPDFPage(nil)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        text.draw(at: NSPoint(x: 48, y: 680))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
