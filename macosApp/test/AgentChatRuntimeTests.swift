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
