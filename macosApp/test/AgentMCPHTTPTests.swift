import MLXLMCommon
import Network
import XCTest
@testable import Covio

final class AgentMCPHTTPTests: XCTestCase {
    func testRequestParserWaitsForTheCompleteBody() throws {
        let data = Data(
            "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:1234\r\nContent-Length: 2\r\n\r\n{}".utf8
        )
        let split = data.count - 1

        XCTAssertEqual(AgentHTTPRequestParser.parse(data.prefix(split)), .incomplete)
        guard case .request(let parsed) = AgentHTTPRequestParser.parse(data) else {
            return XCTFail("Expected a complete request")
        }
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/mcp")
        XCTAssertEqual(parsed.body, Data("{}".utf8))
    }

    func testListenerIsConfiguredForIPv4LoopbackOnly() {
        let parameters = AgentExternalMCPService.listenerParameters()
        guard case .hostPort(let host, let port) = parameters.requiredLocalEndpoint else {
            return XCTFail("Listener must have a loopback endpoint")
        }
        XCTAssertEqual(host, .ipv4(.loopback))
        XCTAssertEqual(port, .any)
    }

    func testUnauthorizedAndInvalidOriginRequestsAreRejected() async {
        let handler = await makeHandler()

        let unauthorized = await handler.handle(
            request(method: "initialize", authorization: nil),
            localPort: 1234
        )
        let badOrigin = await handler.handle(
            request(method: "initialize", origin: "http://example.com"),
            localPort: 1234
        )

        XCTAssertEqual(unauthorized.status, 401)
        XCTAssertEqual(badOrigin.status, 403)
    }

    func testInitializeReturnsSessionAndToolsListSucceeds() async throws {
        let handler = await makeHandler()
        let initialized = await handler.handle(
            request(method: "initialize"),
            localPort: 1234
        )
        XCTAssertEqual(initialized.status, 200)
        let sessionID = try XCTUnwrap(initialized.headers["mcp-session-id"])
        XCTAssertEqual(
            try json(initialized.body).objectValue?["result"]?.objectValue?["protocolVersion"],
            .string("2025-06-18")
        )

        let listed = await handler.handle(
            request(method: "tools/list", sessionID: sessionID),
            localPort: 1234
        )
        XCTAssertEqual(listed.status, 200)
        let result = try XCTUnwrap(try json(listed.body).objectValue?["result"])
        let tools = try XCTUnwrap(result.objectValue?["tools"]?.arrayValue)
        XCTAssertTrue(tools.contains {
            $0.objectValue?["name"] == .string("get_monitor_snapshot")
        })
    }

    func testDeleteClearsPendingExternalAction() async throws {
        let handler = await makeHandler()
        let initialized = await handler.handle(
            request(method: "initialize"),
            localPort: 1234
        )
        let sessionID = try XCTUnwrap(initialized.headers["mcp-session-id"])
        let call = """
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"open_pane","arguments":{"pane":"files"}}}
        """
        let called = await handler.handle(
            request(method: "tools/call", sessionID: sessionID, body: call),
            localPort: 1234
        )
        XCTAssertEqual(called.status, 200)

        let deleted = await handler.handle(
            AgentHTTPRequest(
                method: "DELETE",
                path: "/mcp",
                headers: try headers(sessionID: sessionID),
                body: Data()
            ),
            localPort: 1234
        )

        XCTAssertEqual(deleted.status, 204)
        let pending = await gateway.pendingAction()
        XCTAssertNil(pending)
    }

    func testSessionRateLimitRejectsTheNextRequest() async {
        let sessions = AgentMCPSessionStore(
            now: { 100 },
            idleTimeout: 300,
            rateLimit: 1,
            rateWindow: 60
        )
        let id = await sessions.create()

        let first = await sessions.validate(id, applyingRateLimit: true)
        let second = await sessions.validate(id, applyingRateLimit: true)

        XCTAssertEqual(first, .valid)
        XCTAssertEqual(second, .rateLimited)
    }

    private let gateway = AgentServiceGateway(
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

    private func makeHandler() async -> AgentMCPHTTPHandler {
        let sessions = AgentMCPSessionStore(now: { 1_000 }, idleTimeout: 300)
        return AgentMCPHTTPHandler(
            router: AgentMCPRouter(gateway: gateway),
            gateway: gateway,
            sessions: sessions,
            bearerToken: "secret"
        )
    }

    private func request(
        method: String,
        sessionID: String? = nil,
        origin: String = "http://127.0.0.1:1234",
        authorization: String? = "Bearer secret",
        body: String? = nil
    ) -> AgentHTTPRequest {
        let requestBody = body ?? (method == "tools/list"
            ? #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#
            : #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
        let bodyData = Data(requestBody.utf8)
        var values = [
            "host": "127.0.0.1:1234",
            "origin": origin,
            "content-type": "application/json",
            "accept": "application/json, text/event-stream",
            "content-length": "\(bodyData.count)",
        ]
        if let authorization { values["authorization"] = authorization }
        if let sessionID {
            values["mcp-session-id"] = sessionID
            values["mcp-protocol-version"] = "2025-06-18"
        }
        return AgentHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: values,
            body: bodyData
        )
    }

    private func headers(sessionID: String) throws -> [String: String] {
        [
            "host": "127.0.0.1:1234",
            "origin": "http://127.0.0.1:1234",
            "authorization": "Bearer secret",
            "mcp-session-id": sessionID,
            "mcp-protocol-version": "2025-06-18",
        ]
    }

    private func json(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
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
}
