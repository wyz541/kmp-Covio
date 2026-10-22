import MLXLMCommon
import XCTest
@testable import Covio

@MainActor
final class AgentChatRuntimeTests: XCTestCase {
    func testSendStreamsAssistantTextAndReturnsToIdle() async {
        let model = FakeAgentModel(chunks: ["你好", "，Covio"])
        let runtime = AgentChatRuntime(model: model, gateway: gateway())

        runtime.send("你好")
        await waitUntil { runtime.stage == .idle }

        XCTAssertEqual(runtime.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(runtime.messages.last?.text, "你好，Covio")
        XCTAssertNil(runtime.errorText)
    }

    func testStopCancelsTheActiveResponse() async {
        let model = SlowAgentModel()
        let runtime = AgentChatRuntime(model: model, gateway: gateway())

        runtime.send("慢一点")
        await waitUntil { runtime.messages.count == 2 }
        runtime.stop()

        XCTAssertEqual(runtime.stage, .idle)
        XCTAssertEqual(runtime.messages.first?.role, .user)
        XCTAssertEqual(runtime.messages.last?.role, .assistant)
    }

    func testClearResetsTheConversation() async {
        let runtime = AgentChatRuntime(
            model: FakeAgentModel(chunks: ["ok"]),
            gateway: gateway()
        )
        runtime.send("hello")
        await waitUntil { runtime.stage == .idle }

        runtime.clear()
        await waitUntil { runtime.messages.isEmpty }

        XCTAssertEqual(runtime.stage, .idle)
        XCTAssertNil(runtime.pendingAction)
        XCTAssertNil(runtime.errorText)
        XCTAssertTrue(runtime.toolAudits.isEmpty)
    }

    func testCancelAndStopCannotInterruptAnExecutingSideEffect() async {
        let counter = CopyCounter()
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: { .failure("unused") },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in
                    try? await Task.sleep(for: .milliseconds(150))
                    await counter.increment()
                    return AgentServiceResult(ok: true, summary: "copied", data: nil)
                }
            )
        )
        let model = PendingCopyAgentModel(gateway: gateway)
        let runtime = AgentChatRuntime(model: model, gateway: gateway)

        runtime.send("copy")
        await waitUntil { runtime.stage == .awaitingConfirmation }
        runtime.confirmPendingAction()

        XCTAssertEqual(runtime.stage, .executing)
        runtime.cancelPendingAction()
        runtime.stop()
        XCTAssertEqual(runtime.stage, .executing)

        await waitUntil { runtime.stage == .idle }
        let copyCount = await counter.value
        XCTAssertEqual(copyCount, 1)
        XCTAssertNil(runtime.pendingAction)
        let recordedTool = await model.recordedToolName
        XCTAssertEqual(recordedTool, "copy_text")
    }

    func testDeferredPreviewRunsAfterModelResponse() async {
        let counter = PreviewCounter()
        let fileId = "workspace:\(String(repeating: "c", count: 64))"
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: { .failure("unused") },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in .failure("unused") },
                previewFileNames: { ids, _ in
                    await counter.increment()
                    return AgentServiceResult(
                        ok: true,
                        summary: "Generated \(ids.count) previews. No files were changed.",
                        data: nil
                    )
                }
            )
        )
        let model = DeferredPreviewAgentModel(gateway: gateway, fileId: fileId)
        let runtime = AgentChatRuntime(model: model, gateway: gateway)

        runtime.send("preview")
        await waitUntil { runtime.stage == .idle }

        let count = await counter.value
        XCTAssertEqual(count, 1)
        XCTAssertTrue(runtime.messages.contains {
            $0.role == .service && $0.text.contains("Generated 1 previews")
        })
        XCTAssertEqual(runtime.messages.last?.text, "Preview ready.")
        let recordedTool = await model.recordedToolName
        XCTAssertEqual(recordedTool, "preview_file_names")
    }

    func testRestoreHistoryLoadsTheMostRecentConversation() async throws {
        let store = makeHistoryStore()
        let first = AgentChatRuntime(
            model: FakeAgentModel(chunks: ["saved answer"]),
            gateway: gateway(),
            historyStore: store
        )
        first.send("saved question")
        await waitUntil { first.stage == .idle }
        await first.flushHistory()

        let restored = AgentChatRuntime(
            model: FakeAgentModel(chunks: ["unused"]),
            gateway: gateway(),
            historyStore: store
        )
        await restored.restoreHistory()

        XCTAssertEqual(restored.messages.map(\.text), ["saved question", "saved answer"])
        let latest = try await store.loadLatestSession()
        XCTAssertEqual(latest?.messages.map(\.text), ["saved question", "saved answer"])
    }

    func testToolAuditPersistsWithRiskStatusAndDuration() async throws {
        let store = makeHistoryStore()
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: { .failure("unused") },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in
                    AgentServiceResult(ok: true, summary: "copied", data: nil)
                }
            )
        )
        let runtime = AgentChatRuntime(
            model: PendingCopyAgentModel(gateway: gateway),
            gateway: gateway,
            historyStore: store
        )

        runtime.send("copy")
        await waitUntil { runtime.stage == .awaitingConfirmation }
        runtime.confirmPendingAction()
        await waitUntil { runtime.stage == .idle }
        await runtime.flushHistory()

        let latest = try await store.loadLatestSession()
        let completed = latest?.audits.first {
            $0.toolName == "copy_text" && $0.status == .completed
        }
        XCTAssertEqual(completed?.risk, .sideEffect)
        XCTAssertNotNil(completed?.durationMilliseconds)
    }

    func testFileDerivedAnswerIsRedactedFromPersistentHistory() async throws {
        let store = makeHistoryStore()
        let fileId = "workspace:\(String(repeating: "d", count: 64))"
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: { .failure("unused") },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in .failure("unused") },
                inspectFile: { id, _ in
                    AgentServiceResult(
                        ok: true,
                        summary: "Inspected",
                        data: .object([
                            "fileId": .string(id),
                            "text": .string("secret-file-body-42"),
                        ])
                    )
                }
            )
        )
        let runtime = AgentChatRuntime(
            model: FileInspectAgentModel(gateway: gateway, fileId: fileId),
            gateway: gateway,
            historyStore: store
        )

        runtime.send("what is in the file?")
        await waitUntil { runtime.stage == .idle }
        await runtime.flushHistory()

        let latest = try await store.loadLatestSession()
        XCTAssertEqual(
            latest?.messages.first(where: { $0.role == .assistant })?.text,
            "[File-derived response omitted from local history.]"
        )
        XCTAssertFalse(latest?.messages.contains(where: {
            $0.text.contains("secret-file-body-42")
        }) ?? true)
    }

    func testClearDeletesCurrentSessionAndClearAllDeletesRemainingHistory() async throws {
        let store = makeHistoryStore()
        let runtime = AgentChatRuntime(
            model: FakeAgentModel(chunks: ["answer"]),
            gateway: gateway(),
            historyStore: store
        )
        runtime.send("first")
        await waitUntil { runtime.stage == .idle }
        await runtime.flushHistory()

        runtime.clear()
        await runtime.flushHistory()
        let afterClear = try await store.loadLatestSession()
        XCTAssertNil(afterClear)

        runtime.send("second")
        await waitUntil { runtime.stage == .idle }
        await runtime.flushHistory()
        let afterSecond = try await store.loadLatestSession()
        XCTAssertNotNil(afterSecond)

        runtime.clearAllHistory()
        await runtime.flushHistory()
        let afterClearAll = try await store.loadLatestSession()
        XCTAssertNil(afterClearAll)
    }

    func testExternalPendingActionAppearsInTheLocalConfirmationState() async {
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: { .failure("unused") },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in
                    AgentServiceResult(ok: true, summary: "copied", data: nil)
                }
            )
        )
        let runtime = AgentChatRuntime(
            model: FakeAgentModel(chunks: ["unused"]),
            gateway: gateway
        )

        _ = await gateway.handleExternal(
            ToolCall(function: .init(
                name: "copy_text",
                arguments: ["text": .string("external")]
            )),
            sessionID: "mcp-session"
        )
        await runtime.refreshExternalToolState()

        XCTAssertEqual(runtime.stage, .awaitingConfirmation)
        XCTAssertEqual(runtime.pendingAction?.source, .external("mcp-session"))
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition did not become true")
    }

    private func makeHistoryStore() -> AgentHistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-agent-runtime-history-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return AgentHistoryStore(
            path: directory.appendingPathComponent("history.sqlite3")
        )
    }

    private func gateway() -> AgentServiceGateway {
        AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: { .failure("unused") },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in .failure("unused") }
            )
        )
    }
}

private actor CopyCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor PreviewCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor PendingCopyAgentModel: AgentModelServing {
    private let gateway: AgentServiceGateway
    private(set) var recordedToolName: String?

    init(gateway: AgentServiceGateway) {
        self.gateway = gateway
    }

    func respond(
        to prompt: String,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        _ = await gateway.handle(
            ToolCall(function: .init(
                name: "copy_text",
                arguments: ["text": .string("confirm me")]
            ))
        )
        return ""
    }

    func reset() async {}
    func release() async {}

    func respondAfterServiceResult(
        toolName: String,
        result: AgentServiceResult,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        recordedToolName = toolName
        return ""
    }
}

private actor DeferredPreviewAgentModel: AgentModelServing {
    private let gateway: AgentServiceGateway
    private let fileId: String
    private(set) var recordedToolName: String?

    init(gateway: AgentServiceGateway, fileId: String) {
        self.gateway = gateway
        self.fileId = fileId
    }

    func respond(
        to prompt: String,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        _ = await gateway.handle(
            ToolCall(function: .init(
                name: "preview_file_names",
                arguments: ["fileIds": .array([.string(fileId)])]
            ))
        )
        return "queued"
    }

    func respondAfterServiceResult(
        toolName: String,
        result: AgentServiceResult,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        recordedToolName = toolName
        await onChunk("Preview ready.")
        return "Preview ready."
    }

    func reset() async {}
    func release() async {}
}

private actor FileInspectAgentModel: AgentModelServing {
    private let gateway: AgentServiceGateway
    private let fileId: String

    init(gateway: AgentServiceGateway, fileId: String) {
        self.gateway = gateway
        self.fileId = fileId
    }

    func respond(
        to prompt: String,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        _ = await gateway.handle(
            ToolCall(function: .init(
                name: "inspect_file",
                arguments: ["fileId": .string(fileId), "maxCharacters": .int(2_000)]
            ))
        )
        let answer = "The file says secret-file-body-42."
        await onChunk(answer)
        return answer
    }

    func reset() async {}
    func release() async {}
}

private actor FakeAgentModel: AgentModelServing {
    let chunks: [String]

    init(chunks: [String]) {
        self.chunks = chunks
    }

    func respond(
        to prompt: String,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        for chunk in chunks {
            await onChunk(chunk)
        }
        return chunks.joined()
    }

    func reset() async {}
    func release() async {}
}

private actor SlowAgentModel: AgentModelServing {
    func respond(
        to prompt: String,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        try await Task.sleep(for: .seconds(5))
        return "late"
    }

    func reset() async {}
    func release() async {}
}
