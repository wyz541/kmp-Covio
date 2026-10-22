import MLXLMCommon
import XCTest
@testable import Covio

final class AgentServiceGatewayTests: XCTestCase {
    private actor Counter {
        private(set) var value = 0
        private(set) var lastText: String?

        func increment(text: String? = nil) {
            value += 1
            lastText = text
        }
    }

    func testReadOnlyToolExecutesWithoutConfirmation() async throws {
        let counter = Counter()
        let gateway = AgentServiceGateway(handlers: handlers(counter: counter))

        _ = await gateway.handle(call(name: "get_monitor_snapshot", arguments: [:]))

        let count = await counter.value
        XCTAssertEqual(count, 1)
        let pending = await gateway.pendingAction()
        XCTAssertNil(pending)
    }

    func testUnknownToolIsRejected() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(handlers: handlers(counter: counter))

        let result = await gateway.handle(call(name: "run_shell", arguments: ["command": .string("rm -rf /")]))

        XCTAssertTrue(result.contains("Unknown local service"))
        let count = await counter.value
        XCTAssertEqual(count, 0)
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.last?.status, .rejected)
    }

    func testUnexpectedAndOutOfRangeArgumentsAreRejected() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(handlers: handlers(counter: counter))

        _ = await gateway.handle(
            call(name: "list_screenshots", arguments: ["limit": .int(50)])
        )
        _ = await gateway.handle(
            call(name: "get_power_status", arguments: ["unexpected": .bool(true)])
        )

        let count = await counter.value
        XCTAssertEqual(count, 0)
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.filter { $0.status == .rejected }.count, 2)
    }

    func testSideEffectWaitsForConfirmationAndRunsOnce() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(handlers: handlers(counter: counter))

        _ = await gateway.handle(call(name: "copy_text", arguments: ["text": .string("你好，Covio")]))

        let pending = await gateway.pendingAction()
        XCTAssertEqual(pending?.toolName, "copy_text")
        XCTAssertEqual(pending?.summary, "Copy 8 characters to the clipboard.")
        XCTAssertEqual(pending?.textPreview, "你好，Covio")
        XCTAssertEqual(pending?.risk, .sideEffect)
        let beforeConfirm = await counter.value
        XCTAssertEqual(beforeConfirm, 0)

        let confirmed = await gateway.confirmPending()

        XCTAssertTrue(confirmed.ok)
        let afterConfirm = await counter.value
        let copiedText = await counter.lastText
        XCTAssertEqual(afterConfirm, 1)
        XCTAssertEqual(copiedText, "你好，Covio")
        let afterPending = await gateway.pendingAction()
        XCTAssertNil(afterPending)
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.map(\.status), [.pendingConfirmation, .completed])
    }

    func testCancelDoesNotRunSideEffect() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(handlers: handlers(counter: counter))

        _ = await gateway.handle(call(name: "copy_text", arguments: ["text": .string("cancel me")]))
        await gateway.cancelPending()

        let count = await counter.value
        XCTAssertEqual(count, 0)
        let pending = await gateway.pendingAction()
        XCTAssertNil(pending)
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.last?.status, .cancelled)
    }

    func testSecondSideEffectIsRejectedWithoutReplacingPendingAction() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(handlers: handlers(counter: counter))

        _ = await gateway.handle(
            call(name: "copy_text", arguments: ["text": .string("first")])
        )
        let second = await gateway.handle(
            call(name: "copy_text", arguments: ["text": .string("second")])
        )

        XCTAssertTrue(second.contains("pendingActionExists"))
        let pending = await gateway.pendingAction()
        XCTAssertEqual(pending?.textPreview, "first")
        let count = await counter.value
        XCTAssertEqual(count, 0)
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.map(\.status), [.pendingConfirmation, .rejected])
    }

    func testTimedOutToolReturnsAFixedErrorCode() async {
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: {
                    try? await Task.sleep(for: .seconds(5))
                    return AgentServiceResult(ok: true, summary: "late", data: nil)
                },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in .failure("unused") }
            ),
            timeout: .milliseconds(20)
        )

        let result = await gateway.handle(call(name: "get_monitor_snapshot", arguments: [:]))

        XCTAssertTrue(result.contains("timeout"))
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.last?.status, .failed)
        XCTAssertEqual(audits.last?.errorCode, .timeout)
    }

    private func call(name: String, arguments: [String: JSONValue]) -> ToolCall {
        ToolCall(function: .init(name: name, arguments: arguments))
    }

    private func handlers(counter: Counter) -> AgentServiceHandlers {
        let readOnly = AgentServiceResult(
            ok: true,
            summary: "read",
            data: .object(["value": .string("ok")])
        )
        return AgentServiceHandlers(
            monitorSnapshot: {
                await counter.increment()
                return readOnly
            },
            powerStatus: {
                await counter.increment()
                return readOnly
            },
            workspaceFiles: { _, _ in
                await counter.increment()
                return readOnly
            },
            screenshots: { _ in
                await counter.increment()
                return readOnly
            },
            clipboardMetadata: { _ in
                await counter.increment()
                return readOnly
            },
            copyText: { text in
                await counter.increment(text: text)
                return AgentServiceResult(ok: true, summary: "copied", data: nil)
            }
        )
    }
}
