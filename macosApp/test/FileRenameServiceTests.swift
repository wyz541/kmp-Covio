import Foundation
import XCTest
@testable import Covio

final class FileRenameServiceTests: XCTestCase {
    func testApplyRenamesFileAndUndoRestoresIt() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "hello")
        let expected = try FileIdentity.read(source)
        let candidate = try FileRenameService.capture(
            candidateId: "one",
            sourceURL: source,
            targetName: "new.txt"
        )
        let service = FileRenameService(journal: fixture.journal)
        let result = try service.apply(fixture.plan([candidate]))

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failureCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("new.txt"), encoding: .utf8), "hello")
        XCTAssertEqual(try FileIdentity.read(fixture.directory.appendingPathComponent("new.txt")), expected)

        let undo = try service.undo(runId: result.runId)
        XCTAssertEqual(undo.successCount, 1)
        XCTAssertEqual(undo.items.first?.status, .undone)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("new.txt").path))
    }

    func testTargetExistsIsNotOverwritten() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "source")
        _ = try fixture.file("new.txt", contents: "target")
        let candidate = try FileRenameService.capture(
            candidateId: "one",
            sourceURL: source,
            targetName: "new.txt"
        )
        let result = try FileRenameService(journal: fixture.journal).apply(fixture.plan([candidate]))

        XCTAssertEqual(result.failureCount, 1)
        XCTAssertEqual(result.items.first?.error?.code, .targetExists)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("new.txt"), encoding: .utf8), "target")
    }

    func testFileChangedAfterPreviewIsRejected() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "before")
        let candidate = try FileRenameService.capture(
            candidateId: "one",
            sourceURL: source,
            targetName: "new.txt"
        )
        try "after preview".write(to: source, atomically: true, encoding: .utf8)
        let result = try FileRenameService(journal: fixture.journal).apply(fixture.plan([candidate]))

        XCTAssertEqual(result.failureCount, 1)
        XCTAssertEqual(result.items.first?.error?.code, .fileChanged)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "after preview")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("new.txt").path))
    }

    func testJournalFailurePreventsRename() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "hello")
        let candidate = try FileRenameService.capture(
            candidateId: "one",
            sourceURL: source,
            targetName: "new.txt"
        )

        XCTAssertThrowsError(
            try FileRenameService(journal: FailingJournal()).apply(fixture.plan([candidate]))
        ) { error in
            XCTAssertEqual((error as? FileRenameError)?.code, .journalWriteFailed)
        }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("new.txt").path))
    }

    func testUndoRefusesToOverwriteNewOriginal() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "hello")
        let candidate = try FileRenameService.capture(
            candidateId: "one",
            sourceURL: source,
            targetName: "new.txt"
        )
        let service = FileRenameService(journal: fixture.journal)
        let applied = try service.apply(fixture.plan([candidate]))
        try "new file".write(to: source, atomically: true, encoding: .utf8)

        let undo = try service.undo(runId: applied.runId)
        XCTAssertEqual(undo.failureCount, 1)
        XCTAssertEqual(undo.items.first?.error?.code, .undoConflict)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new file")
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("new.txt"), encoding: .utf8), "hello")
    }

    func testSymbolicLinkIsRejectedAtCapture() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let target = try fixture.file("target.txt", contents: "hello")
        let link = fixture.directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try FileIdentity.read(link)) { error in
            XCTAssertEqual((error as? FileRenameError)?.code, .symbolicLinkUnsupported)
        }
    }

    func testCrossDirectoryAndExtensionChangesAreRejected() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.file("old.txt", contents: "hello")
        let identity = try FileIdentity.read(source)
        let otherDirectory = fixture.directory.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let service = FileRenameService(journal: fixture.journal)

        let crossDirectory = FileRenameCandidate(
            candidateId: "cross",
            sourceURL: source,
            targetURL: otherDirectory.appendingPathComponent("new.txt"),
            identity: identity
        )
        let crossResult = try service.apply(fixture.plan([crossDirectory]))
        XCTAssertEqual(crossResult.items.first?.error?.code, .crossDirectory)

        let extensionChanged = FileRenameCandidate(
            candidateId: "extension",
            sourceURL: source,
            targetURL: fixture.directory.appendingPathComponent("new.pdf"),
            identity: identity
        )
        let extensionResult = try service.apply(fixture.plan([extensionChanged], runId: "extension-run"))
        XCTAssertEqual(extensionResult.items.first?.error?.code, .extensionChanged)
    }

    func testPartialSuccessCanBeUndone() throws {
        let fixture = try RenameFixture()
        defer { fixture.cleanUp() }
        let first = try fixture.file("first.txt", contents: "first")
        let second = try fixture.file("second.txt", contents: "second")
        _ = try fixture.file("conflict.txt", contents: "kept")
        let firstCandidate = try FileRenameService.capture(
            candidateId: "first",
            sourceURL: first,
            targetName: "renamed.txt"
        )
        let secondCandidate = try FileRenameService.capture(
            candidateId: "second",
            sourceURL: second,
            targetName: "conflict.txt"
        )
        let service = FileRenameService(journal: fixture.journal)
        let applied = try service.apply(fixture.plan([firstCandidate, secondCandidate]))

        XCTAssertEqual(applied.successCount, 1)
        XCTAssertEqual(applied.failureCount, 1)
        let undo = try service.undo(runId: applied.runId)
        XCTAssertEqual(undo.successCount, 1)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("conflict.txt"), encoding: .utf8), "kept")
    }
}

private struct FailingJournal: FileRenameJournaling {
    func save(_ plan: FileRenamePlan) throws {
        throw FileRenameError(.journalWriteFailed)
    }

    func load(runId: String) throws -> FileRenamePlan {
        throw FileRenameError(.journalReadFailed)
    }
}

private final class RenameFixture {
    let directory: URL
    let journal: FileRenameJournalStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        journal = FileRenameJournalStore(
            directory: directory.appendingPathComponent("journal", isDirectory: true)
        )
    }

    func file(_ name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func plan(_ items: [FileRenameCandidate], runId: String = "run-1") -> FileRenamePlan {
        FileRenamePlan(runId: runId, createdAtEpochSeconds: 1_000, items: items)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
