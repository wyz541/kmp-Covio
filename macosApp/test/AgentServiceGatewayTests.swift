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

    func testInspectFileRequiresStableWorkspaceOrAttachmentId() async {
        let counter = Counter()
        let validId = "workspace:\(String(repeating: "a", count: 64))"
        let gateway = AgentServiceGateway(
            handlers: handlers(counter: counter) { fileId, _ in
                await counter.increment(text: fileId)
                return AgentServiceResult(ok: true, summary: "inspected", data: nil)
            }
        )

        _ = await gateway.handle(
            call(name: "inspect_file", arguments: ["fileId": .string(validId)])
        )
        let rejected = await gateway.handle(
            call(name: "inspect_file", arguments: ["fileId": .string("/etc/passwd")])
        )

        XCTAssertTrue(rejected.contains("invalidArguments"))
        let count = await counter.value
        let lastText = await counter.lastText
        XCTAssertEqual(count, 1)
        XCTAssertEqual(lastText, validId)
    }

    func testDescribeImageQueuesUntilTheModelLeaseIsReleased() async throws {
        let counter = Counter()
        let fileId = "workspace:\(String(repeating: "e", count: 64))"
        let gateway = AgentServiceGateway(
            handlers: handlers(counter: counter, describeImage: { id, question in
                await counter.increment(text: "\(id):\(question)")
                return AgentServiceResult(
                    ok: true,
                    summary: "Visual answer",
                    data: .object([
                        "fileId": .string(id),
                        "name": .string("diagram.png"),
                        "answer": .string("A red square."),
                        "citation": .string("\(id)#image-1"),
                    ])
                )
            })
        )

        _ = await gateway.handle(
            call(name: "describe_image", arguments: [
                "fileId": .string(fileId),
                "question": .string("What color is the square?"),
            ])
        )
        let before = await counter.value
        XCTAssertEqual(before, 0)
        let deferred = await gateway.takeDeferredAction()
        let action = try XCTUnwrap(deferred)
        let result = await gateway.executeDeferred(action)

        XCTAssertTrue(result.ok)
        let after = await counter.value
        XCTAssertEqual(after, 1)
    }

    func testDeferredPreviewQueuesAndExecutesExplicitly() async throws {
        let counter = Counter()
        let fileId = "workspace:\(String(repeating: "b", count: 64))"
        let gateway = AgentServiceGateway(
            handlers: handlers(counter: counter, previewFileNames: { ids, maxResults in
                await counter.increment(text: ids.joined(separator: ","))
                return AgentServiceResult(
                    ok: true,
                    summary: "Generated \(ids.count) previews.",
                    data: .object(["maxResults": .int(maxResults)])
                )
            })
        )

        let queued = await gateway.handle(
            call(
                name: "preview_file_names",
                arguments: [
                    "fileIds": .array([.string(fileId)]),
                    "maxResults": .int(3),
                ]
            )
        )
        let countBeforeExecution = await counter.value
        XCTAssertTrue(queued.contains("queued"), queued)
        XCTAssertEqual(countBeforeExecution, 0)

        let deferredAction = await gateway.takeDeferredAction()
        let action = try XCTUnwrap(deferredAction)
        let result = await gateway.executeDeferred(action)
        let countAfterExecution = await counter.value
        XCTAssertTrue(result.ok)
        XCTAssertEqual(countAfterExecution, 1)
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.map(\.status), [.queued, .completed])
    }

    func testRenameRequiresConfirmationBeforeCallingService() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(
            handlers: handlers(counter: counter, applyFileRenames: { ids in
                await counter.increment(text: ids.joined(separator: ","))
                return AgentServiceResult(ok: true, summary: "renamed", data: nil)
            })
        )

        _ = await gateway.handle(
            call(name: "apply_file_renames", arguments: [
                "previewIds": .array([.string("preview-1")]),
            ])
        )
        let beforeConfirm = await counter.value
        XCTAssertEqual(beforeConfirm, 0)
        let pending = await gateway.pendingAction()
        XCTAssertEqual(pending?.toolName, "apply_file_renames")

        _ = await gateway.confirmPending()
        let afterConfirm = await counter.value
        XCTAssertEqual(afterConfirm, 1)
    }

    func testOpenPaneRejectsUnknownPagesBeforeTheHandlerRuns() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(
            handlers: handlers(counter: counter, openPane: { pane in
                await counter.increment(text: pane)
                return AgentServiceResult(ok: true, summary: "opened", data: nil)
            })
        )

        _ = await gateway.handle(call(name: "open_pane", arguments: ["pane": .string("files")]))
        let rejected = await gateway.handle(call(name: "open_pane", arguments: ["pane": .string("mars")]))

        XCTAssertTrue(rejected.contains("invalidArguments"))
        let count = await counter.value
        let pane = await counter.lastText
        XCTAssertEqual(count, 1)
        XCTAssertEqual(pane, "files")
    }

    func testReadSettingRejectsUnknownKeys() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(
            handlers: handlers(counter: counter, readSetting: { key in
                await counter.increment(text: key)
                return AgentServiceResult(ok: true, summary: "read", data: nil)
            })
        )

        _ = await gateway.handle(
            call(name: "read_setting", arguments: ["key": .string("notifications.enabled")])
        )
        let rejected = await gateway.handle(
            call(name: "read_setting", arguments: ["key": .string("system.anything")])
        )

        XCTAssertTrue(rejected.contains("invalidArguments"))
        let count = await counter.value
        let key = await counter.lastText
        XCTAssertEqual(count, 1)
        XCTAssertEqual(key, "notifications.enabled")
    }

    func testSettingChangeWaitsForConfirmationAndRunsOnce() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(
            handlers: handlers(counter: counter, requestSettingChange: { key, value in
                await counter.increment(text: "\(key)=\(value)")
                return AgentServiceResult(ok: true, summary: "changed", data: nil)
            })
        )

        _ = await gateway.handle(
            call(name: "request_setting_change", arguments: [
                "key": .string("power.batteryFloorPercent"),
                "value": .string("65"),
            ])
        )
        let before = await counter.value
        XCTAssertEqual(before, 0)
        let pending = await gateway.pendingAction()
        XCTAssertEqual(pending?.toolName, "request_setting_change")
        XCTAssertEqual(pending?.summary, "Change power.batteryFloorPercent to 65.")

        let result = await gateway.confirmPending()

        XCTAssertTrue(result.ok)
        let after = await counter.value
        let value = await counter.lastText
        XCTAssertEqual(after, 1)
        XCTAssertEqual(value, "power.batteryFloorPercent=65")
    }

    func testSettingChangeRejectsTypeMismatch() async {
        let counter = Counter()
        let gateway = AgentServiceGateway(handlers: handlers(counter: counter))

        let rejected = await gateway.handle(
            call(name: "request_setting_change", arguments: [
                "key": .string("power.batteryFloorPercent"),
                "value": .string("high"),
            ])
        )

        XCTAssertTrue(rejected.contains("invalidArguments"))
        let count = await counter.value
        XCTAssertEqual(count, 0)
    }

    private func call(name: String, arguments: [String: JSONValue]) -> ToolCall {
        ToolCall(function: .init(name: name, arguments: arguments))
    }

    private func handlers(
        counter: Counter,
        inspectFile: @escaping @Sendable (String, Int) async -> AgentServiceResult = { _, _ in
            .failure("unused", code: .fileUnavailable)
        },
        describeImage: @escaping @Sendable (String, String) async -> AgentServiceResult = { _, _ in
            .failure("unused", code: .executionFailed)
        },
        previewFileNames: @escaping @Sendable ([String], Int) async -> AgentServiceResult = { _, _ in
            .failure("unused", code: .executionFailed)
        },
        applyFileRenames: @escaping @Sendable ([String]) async -> AgentServiceResult = { _ in
            .failure("unused", code: .executionFailed)
        },
        undoRenameRun: @escaping @Sendable (String) async -> AgentServiceResult = { _ in
            .failure("unused", code: .executionFailed)
        },
        openPane: @escaping @Sendable (String) async -> AgentServiceResult = { _ in
            .failure("unused", code: .executionFailed)
        },
        readSetting: @escaping @Sendable (String) async -> AgentServiceResult = { _ in
            .failure("unused", code: .executionFailed)
        },
        requestSettingChange: @escaping @Sendable (String, String) async -> AgentServiceResult = { _, _ in
            .failure("unused", code: .executionFailed)
        }
    ) -> AgentServiceHandlers {
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
            },
            inspectFile: inspectFile,
            describeImage: describeImage,
            previewFileNames: previewFileNames,
            applyFileRenames: applyFileRenames,
            undoRenameRun: undoRenameRun,
            openPane: openPane,
            readSetting: readSetting,
            requestSettingChange: requestSettingChange
        )
    }
}
