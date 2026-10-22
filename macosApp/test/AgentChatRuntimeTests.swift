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

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition did not become true")
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
