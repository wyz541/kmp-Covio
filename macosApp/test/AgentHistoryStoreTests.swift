import XCTest
@testable import Covio

final class AgentHistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-agent-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSessionRoundTripPreservesMessagesAndAuditMetadata() async throws {
        let store = AgentHistoryStore(path: databaseURL)
        let session = makeSession()

        try await store.saveSession(session)
        let restored = try await store.loadLatestSession()

        let schemaVersion = try await store.schemaVersion()
        XCTAssertEqual(restored, session)
        XCTAssertEqual(schemaVersion, 1)
    }

    func testDeletingASessionRemovesItsChildren() async throws {
        let store = AgentHistoryStore(path: databaseURL)
        let session = makeSession()
        try await store.saveSession(session)

        try await store.deleteSession(id: session.id)

        let restored = try await store.loadLatestSession()
        XCTAssertNil(restored)
    }

    func testClearAllRemovesEveryStoredSession() async throws {
        let store = AgentHistoryStore(path: databaseURL)
        let first = makeSession()
        let second = AgentHistorySession(
            id: UUID(),
            title: "Second",
            startedAtEpochMilliseconds: 300,
            updatedAtEpochMilliseconds: 400,
            messages: [
                AgentChatMessage(
                    role: .user,
                    text: "Second question",
                    createdAtEpochMilliseconds: 350
                )
            ],
            audits: []
        )
        try await store.saveSession(first)
        try await store.saveSession(second)

        try await store.deleteAllSessions()

        let restored = try await store.loadLatestSession()
        XCTAssertNil(restored)
    }

    func testMigratedDatabaseCanBeReopenedWithoutLosingRows() async throws {
        let firstStore = AgentHistoryStore(path: databaseURL)
        let session = makeSession()
        try await firstStore.saveSession(session)

        let reopenedStore = AgentHistoryStore(path: databaseURL)
        let restored = try await reopenedStore.loadLatestSession()

        let schemaVersion = try await reopenedStore.schemaVersion()
        XCTAssertEqual(restored, session)
        XCTAssertEqual(schemaVersion, 1)
    }

    func testLatestSessionUsesTheMostRecentUpdate() async throws {
        let store = AgentHistoryStore(path: databaseURL)
        var first = makeSession()
        let second = AgentHistorySession(
            id: UUID(),
            title: "Second",
            startedAtEpochMilliseconds: 500,
            updatedAtEpochMilliseconds: 900,
            messages: [
                AgentChatMessage(
                    role: .user,
                    text: "Second question",
                    createdAtEpochMilliseconds: 600
                )
            ],
            audits: []
        )
        try await store.saveSession(first)
        try await store.saveSession(second)

        first = AgentHistorySession(
            id: first.id,
            title: first.title,
            startedAtEpochMilliseconds: first.startedAtEpochMilliseconds,
            updatedAtEpochMilliseconds: 1_000,
            messages: first.messages,
            audits: first.audits
        )
        try await store.saveSession(first)

        let restored = try await store.loadLatestSession()
        XCTAssertEqual(restored?.id, first.id)
    }

    private var databaseURL: URL {
        directory.appendingPathComponent("Agent/history.sqlite3")
    }

    private func makeSession() -> AgentHistorySession {
        let sessionID = UUID()
        return AgentHistorySession(
            id: sessionID,
            title: "Question",
            startedAtEpochMilliseconds: 100,
            updatedAtEpochMilliseconds: 200,
            messages: [
                AgentChatMessage(
                    id: UUID(),
                    role: .user,
                    text: "Question",
                    createdAtEpochMilliseconds: 110
                ),
                AgentChatMessage(
                    id: UUID(),
                    role: .assistant,
                    text: "Answer",
                    createdAtEpochMilliseconds: 120
                ),
            ],
            audits: [
                AgentToolAudit(
                    id: "audit-1",
                    toolName: "get_monitor_snapshot",
                    risk: .readOnly,
                    status: .completed,
                    detail: "Completed",
                    durationMilliseconds: 12,
                    createdAtEpochMilliseconds: 130
                )
            ]
        )
    }
}
