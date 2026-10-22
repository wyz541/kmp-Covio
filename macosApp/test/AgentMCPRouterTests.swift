import MLXLMCommon
import XCTest
@testable import Covio

final class AgentMCPRouterTests: XCTestCase {
    private actor Counter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    func testInitializeAdvertisesToolsCapability() async throws {
        let router = AgentMCPRouter(gateway: gateway())
        let response = try await router.handle(
            request(method: "initialize"),
            sessionID: "session"
        )

        let result = try object(try XCTUnwrap(response))["result"]
        let object = try self.object(try XCTUnwrap(result))
        XCTAssertEqual(object["protocolVersion"]?.stringValue, "2025-06-18")
        XCTAssertNotNil(try self.object(try XCTUnwrap(object["capabilities"]))["tools"])
    }

    func testToolsListReturnsOnlyExternallyExposedTools() async throws {
        let router = AgentMCPRouter(gateway: gateway())
        let response = try await router.handle(
            request(method: "tools/list"),
            sessionID: "session"
        )
        let result = try object(try XCTUnwrap(response))["result"]
        let tools = try XCTUnwrap(try object(try XCTUnwrap(result))["tools"]?.arrayValue)
        let names = Set(tools.compactMap { $0.objectValue?["name"]?.stringValue })

        XCTAssertTrue(names.contains("get_monitor_snapshot"))
        XCTAssertTrue(names.contains("open_pane"))
        XCTAssertFalse(names.contains("run_shell"))
        XCTAssertFalse(names.contains("preview_file_names"))
        XCTAssertFalse(names.contains("search_file_content"))
    }

    func testUnknownToolIsRejectedByRouter() async throws {
        let gateway = gateway()
        let router = AgentMCPRouter(gateway: gateway)
        let response = try await router.handle(
            request(
                method: "tools/call",
                params: .object([
                    "name": .string("run_shell"),
                    "arguments": .object([:]),
                ])
            ),
            sessionID: "session"
        )
        let error = try object(try XCTUnwrap(response))["error"]
        XCTAssertNotNil(error)
    }

    func testReadOnlyCallExecutesAndAuditsTheExternalSession() async throws {
        let counter = Counter()
        let gateway = gateway(monitor: { await counter.increment() })
        let router = AgentMCPRouter(gateway: gateway)

        let response = try await router.handle(
            request(
                method: "tools/call",
                params: .object([
                    "name": .string("get_monitor_snapshot"),
                    "arguments": .object([:]),
                ])
            ),
            sessionID: "external-session"
        )

        XCTAssertNotNil(response)
        let count = await counter.value
        XCTAssertEqual(count, 1)
        let audits = await gateway.recentAudits()
        XCTAssertEqual(audits.last?.source, .external("external-session"))
        XCTAssertEqual(audits.last?.status, .completed)
    }

    func testOpenPaneIsElevatedToPendingForExternalAgents() async throws {
        let counter = Counter()
        let gateway = gateway(openPane: { _ in await counter.increment() })
        let router = AgentMCPRouter(gateway: gateway)

        let response = try await router.handle(
            request(
                method: "tools/call",
                params: .object([
                    "name": .string("open_pane"),
                    "arguments": .object(["pane": .string("files")]),
                ])
            ),
            sessionID: "external-session"
        )

        let result = try object(try XCTUnwrap(try object(try XCTUnwrap(response))["result"]))
        let structured = try object(try XCTUnwrap(result["structuredContent"]))
        XCTAssertEqual(structured["status"]?.stringValue, "pendingConfirmation")
        let before = await counter.value
        XCTAssertEqual(before, 0)
        let pending = await gateway.pendingAction()
        XCTAssertEqual(pending?.source, .external("external-session"))

        _ = await gateway.confirmPending()
        let after = await counter.value
        XCTAssertEqual(after, 1)
    }

    private func gateway(
        monitor: @escaping @Sendable () async -> Void = {},
        openPane: @escaping @Sendable (String) async -> Void = { _ in }
    ) -> AgentServiceGateway {
        AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: {
                    await monitor()
                    return AgentServiceResult(ok: true, summary: "read", data: nil)
                },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in .failure("unused") },
                openPane: { pane in
                    await openPane(pane)
                    return AgentServiceResult(ok: true, summary: "opened", data: nil)
                }
            )
        )
    }

    private func request(method: String, params: JSONValue? = nil) -> AgentMCPRequest {
        AgentMCPRequest(
            jsonrpc: "2.0",
            id: .int(1),
            method: method,
            params: params
        )
    }

    private func object(_ value: JSONValue) throws -> [String: JSONValue] {
        try XCTUnwrap(value.objectValue)
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}
