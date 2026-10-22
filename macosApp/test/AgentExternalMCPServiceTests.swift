import MLXLMCommon
import XCTest
@testable import Covio

@MainActor
final class AgentExternalMCPServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-external-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoopbackServiceInitializesListsToolsAndPersistsAudit() async throws {
        let gateway = AgentServiceGateway(
            handlers: AgentServiceHandlers(
                monitorSnapshot: {
                    AgentServiceResult(ok: true, summary: "read", data: nil)
                },
                powerStatus: { .failure("unused") },
                workspaceFiles: { _, _ in .failure("unused") },
                screenshots: { _ in .failure("unused") },
                clipboardMetadata: { _ in .failure("unused") },
                copyText: { _ in .failure("unused") },
                openPane: { _ in
                    AgentServiceResult(ok: true, summary: "opened", data: nil)
                }
            )
        )
        let auditStore = AgentHistoryStore(path: directory.appendingPathComponent("history.sqlite3"))
        let service = AgentExternalMCPService(
            gateway: gateway,
            auditStore: auditStore,
            token: "secret"
        )
        await gateway.setAuditObserver { [weak service] audit in
            await service?.recordExternalAudit(audit)
        }
        service.start()
        await waitUntil { service.port != nil }
        let endpoint = try XCTUnwrap(service.endpointURL)
        defer { service.stop() }

        let initialized = try await send(
            endpoint: endpoint,
            body: #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#
        )
        XCTAssertEqual(initialized.status, 200)
        let sessionID = try XCTUnwrap(initialized.sessionID)

        let listed = try await send(
            endpoint: endpoint,
            sessionID: sessionID,
            body: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
        )
        XCTAssertTrue(listed.body.contains("get_monitor_snapshot"))

        _ = try await send(
            endpoint: endpoint,
            sessionID: sessionID,
            body: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"open_pane","arguments":{"pane":"files"}}}"#
        )
        await waitUntilAsync {
            let records = try await auditStore.recentExternalAudits()
            return records.contains {
                $0.toolName == "open_pane" && $0.status == .pendingConfirmation
            }
        }
        let pending = await gateway.pendingAction()
        XCTAssertEqual(pending?.source, .external(sessionID))
        let confirmed = await gateway.confirmPending()
        XCTAssertTrue(confirmed.ok)
        await waitUntilAsync {
            let records = try await auditStore.recentExternalAudits()
            return records.contains {
                $0.toolName == "open_pane" && $0.status == .completed
            }
        }

        _ = try await send(
            endpoint: endpoint,
            sessionID: sessionID,
            body: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_monitor_snapshot","arguments":{}}}"#
        )
        await waitUntilAsync {
            let records = try await auditStore.recentExternalAudits()
            return records.first?.toolName == "get_monitor_snapshot"
        }
        let records = try await auditStore.recentExternalAudits()
        XCTAssertEqual(records.first?.sessionID, sessionID)
        XCTAssertEqual(records.first?.status, .completed)
        service.stop()
        await auditStore.close()
    }

    private struct Response {
        let status: Int
        let sessionID: String?
        let body: String
    }

    private func send(
        endpoint: URL,
        sessionID: String? = nil,
        body: String
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "accept")
        request.setValue("Bearer secret", forHTTPHeaderField: "authorization")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "mcp-session-id")
            request.setValue("2025-06-18", forHTTPHeaderField: "mcp-protocol-version")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return Response(
            status: http.statusCode,
            sessionID: http.value(forHTTPHeaderField: "mcp-session-id"),
            body: String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition did not become true")
    }

    private func waitUntilAsync(_ condition: @escaping () async throws -> Bool) async {
        for _ in 0..<100 {
            if (try? await condition()) == true { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Async condition did not become true")
    }
}
