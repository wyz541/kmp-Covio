import Foundation
import MLXLMCommon

struct AgentHTTPRequest: Sendable, Equatable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct AgentHTTPResponse: Sendable, Equatable {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(
        status: Int,
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

enum AgentHTTPParseResult: Sendable, Equatable {
    case incomplete
    case request(AgentHTTPRequest)
    case failure(Int, String)
}

enum AgentHTTPRequestParser {
    static let maximumBodyBytes = 1_048_576
    static let maximumHeaderBytes = 32_768

    static func parse(_ data: Data) -> AgentHTTPParseResult {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maximumHeaderBytes
                ? .failure(431, "Request headers are too large.")
                : .incomplete
        }
        guard headerRange.lowerBound <= maximumHeaderBytes else {
            return .failure(431, "Request headers are too large.")
        }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .isoLatin1) else {
            return .failure(400, "Request headers are not valid text.")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .failure(400, "Request line is missing.")
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else {
            return .failure(400, "Request line is invalid.")
        }
        let method = parts[0].uppercased()
        let target = parts[1]
        let path = String(target.split(separator: "?", maxSplits: 1).first ?? "")
        guard path.hasPrefix("/") else {
            return .failure(400, "Request path is invalid.")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(400, "Request header is invalid.")
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                return .failure(400, "Request header name is empty.")
            }
            if let existing = headers[name] {
                headers[name] = "\(existing), \(value)"
            } else {
                headers[name] = value
            }
        }

        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0 else {
                return .failure(400, "Content-Length is invalid.")
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= maximumBodyBytes else {
            return .failure(413, "Request body is too large.")
        }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else {
            return .incomplete
        }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return .request(
            AgentHTTPRequest(method: method, path: path, headers: headers, body: body)
        )
    }
}

enum AgentMCPSessionValidation: Sendable, Equatable {
    case valid
    case missing
    case expired
    case rateLimited
}

actor AgentMCPSessionStore {
    private struct Session {
        let id: String
        var lastAccess: TimeInterval
        var requests: [TimeInterval]
    }

    private var sessions: [String: Session] = [:]
    private let now: @Sendable () -> TimeInterval
    private let idleTimeout: TimeInterval
    private let rateLimit: Int
    private let rateWindow: TimeInterval

    init(
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        idleTimeout: TimeInterval = 300,
        rateLimit: Int = 60,
        rateWindow: TimeInterval = 60
    ) {
        self.now = now
        self.idleTimeout = idleTimeout
        self.rateLimit = rateLimit
        self.rateWindow = rateWindow
    }

    func create() -> String {
        let id = UUID().uuidString.lowercased()
        let timestamp = now()
        sessions[id] = Session(id: id, lastAccess: timestamp, requests: [])
        return id
    }

    func validate(_ id: String, applyingRateLimit: Bool) -> AgentMCPSessionValidation {
        guard var session = sessions[id] else { return .missing }
        let timestamp = now()
        guard timestamp - session.lastAccess <= idleTimeout else {
            sessions.removeValue(forKey: id)
            return .expired
        }
        session.requests.removeAll { timestamp - $0 >= rateWindow }
        if applyingRateLimit, session.requests.count >= rateLimit {
            sessions[id] = session
            return .rateLimited
        }
        if applyingRateLimit {
            session.requests.append(timestamp)
        }
        session.lastAccess = timestamp
        sessions[id] = session
        return .valid
    }

    func delete(_ id: String) {
        sessions.removeValue(forKey: id)
    }

    func removeAll() -> [String] {
        let ids = Array(sessions.keys)
        sessions.removeAll()
        return ids
    }

    func expireIdle() -> [String] {
        let timestamp = now()
        let expired = sessions.values
            .filter { timestamp - $0.lastAccess > idleTimeout }
            .map(\.id)
        for id in expired {
            sessions.removeValue(forKey: id)
        }
        return expired
    }
}

actor AgentMCPHTTPHandler {
    private let router: AgentMCPRouter
    private let gateway: AgentServiceGateway
    private let sessions: AgentMCPSessionStore
    private let bearerToken: String
    private let onPendingActionChanged: @Sendable () async -> Void

    init(
        router: AgentMCPRouter,
        gateway: AgentServiceGateway,
        sessions: AgentMCPSessionStore,
        bearerToken: String,
        onPendingActionChanged: @escaping @Sendable () async -> Void = {}
    ) {
        self.router = router
        self.gateway = gateway
        self.sessions = sessions
        self.bearerToken = bearerToken
        self.onPendingActionChanged = onPendingActionChanged
    }

    func handle(_ request: AgentHTTPRequest, localPort: UInt16) async -> AgentHTTPResponse {
        guard request.path == "/mcp" else {
            return jsonResponse(status: 404, value: .object([
                "error": .string("Not found."),
            ]))
        }
        guard validateHost(request.headers["host"], port: localPort) else {
            return jsonResponse(status: 400, value: .object([
                "error": .string("Invalid Host header."),
            ]))
        }
        guard validateOrigin(request.headers["origin"], port: localPort) else {
            return jsonResponse(status: 403, value: .object([
                "error": .string("Invalid Origin header."),
            ]))
        }
        guard authorize(request.headers["authorization"]) else {
            return AgentHTTPResponse(
                status: 401,
                headers: [
                    "content-type": "application/json; charset=utf-8",
                    "www-authenticate": #"Bearer realm="Covio""#,
                ],
                body: encode(.object(["error": .string("Unauthorized.")]))
            )
        }

        switch request.method {
        case "POST":
            return await handlePost(request, localPort: localPort)
        case "DELETE":
            return await handleDelete(request)
        case "GET":
            return jsonResponse(status: 405, value: .object([
                "error": .string("Server-initiated streams are not available."),
            ]))
        default:
            return jsonResponse(status: 405, value: .object([
                "error": .string("Method not allowed."),
            ]))
        }
    }

    private func handlePost(
        _ request: AgentHTTPRequest,
        localPort: UInt16
    ) async -> AgentHTTPResponse {
        guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            return jsonResponse(status: 415, value: .object([
                "error": .string("Content-Type must be application/json."),
            ]))
        }
        guard acceptsJSONAndEventStream(request.headers["accept"]) else {
            return jsonResponse(status: 406, value: .object([
                "error": .string("Accept must include application/json and text/event-stream."),
            ]))
        }

        let mcpRequest: AgentMCPRequest
        do {
            mcpRequest = try JSONDecoder().decode(AgentMCPRequest.self, from: request.body)
        } catch {
            return jsonResponse(
                status: 400,
                value: rpcError(
                    id: .null,
                    code: .parseError,
                    message: "JSON-RPC payload is invalid."
                )
            )
        }

        let isInitialize = mcpRequest.method == "initialize"
        if isInitialize, mcpRequest.id == nil {
            return jsonResponse(
                status: 400,
                value: rpcError(
                    id: .null,
                    code: .invalidRequest,
                    message: "Initialize must be a request."
                )
            )
        }
        let sessionID: String
        if isInitialize {
            guard request.headers["mcp-session-id"] == nil else {
                return jsonResponse(
                    status: 400,
                    value: rpcError(
                        id: mcpRequest.id,
                        code: .invalidRequest,
                        message: "Initialize must not include Mcp-Session-Id."
                    )
                )
            }
            sessionID = await sessions.create()
        } else {
            guard let supplied = request.headers["mcp-session-id"], !supplied.isEmpty else {
                return jsonResponse(
                    status: 400,
                    value: rpcError(
                        id: mcpRequest.id,
                        code: .invalidRequest,
                        message: "Mcp-Session-Id is required."
                    )
                )
            }
            switch await sessions.validate(supplied, applyingRateLimit: true) {
            case .valid:
                sessionID = supplied
            case .missing:
                return jsonResponse(status: 404, value: .object(["error": .string("Session not found.")]))
            case .expired:
                await gateway.cancelPending(source: .external(supplied))
                return jsonResponse(status: 404, value: .object(["error": .string("Session expired.")]))
            case .rateLimited:
                return jsonResponse(status: 429, value: .object(["error": .string("Rate limit exceeded.")]))
            }
            guard request.headers["mcp-protocol-version"] == AgentMCPRouter.protocolVersion else {
                return jsonResponse(
                    status: 400,
                    value: rpcError(
                        id: mcpRequest.id,
                        code: .invalidRequest,
                        message: "MCP-Protocol-Version is unsupported."
                    )
                )
            }
        }

        guard let response = await router.handle(mcpRequest, sessionID: sessionID) else {
            return AgentHTTPResponse(status: 202)
        }
        if isInitialize, containsJSONRPCError(response) {
            await sessions.delete(sessionID)
            return AgentHTTPResponse(
                status: 400,
                headers: ["content-type": "application/json; charset=utf-8"],
                body: encode(response)
            )
        }
        if let pending = await gateway.pendingAction(),
           pending.source == .external(sessionID)
        {
            await onPendingActionChanged()
        }
        var headers = [
            "content-type": "application/json; charset=utf-8",
            "mcp-protocol-version": AgentMCPRouter.protocolVersion,
        ]
        if isInitialize {
            headers["mcp-session-id"] = sessionID
        }
        return AgentHTTPResponse(status: 200, headers: headers, body: encode(response))
    }

    private func handleDelete(_ request: AgentHTTPRequest) async -> AgentHTTPResponse {
        guard let sessionID = request.headers["mcp-session-id"], !sessionID.isEmpty else {
            return jsonResponse(status: 400, value: .object([
                "error": .string("Mcp-Session-Id is required."),
            ]))
        }
        switch await sessions.validate(sessionID, applyingRateLimit: false) {
        case .valid:
            await sessions.delete(sessionID)
            await gateway.cancelPending(source: .external(sessionID))
            return AgentHTTPResponse(status: 204)
        case .missing, .expired:
            return AgentHTTPResponse(status: 404)
        case .rateLimited:
            return AgentHTTPResponse(status: 429)
        }
    }

    private func authorize(_ authorization: String?) -> Bool {
        guard let authorization else { return false }
        let prefix = "Bearer "
        guard authorization.hasPrefix(prefix) else { return false }
        return constantTimeEqual(String(authorization.dropFirst(prefix.count)), bearerToken)
    }

    private func validateHost(_ host: String?, port: UInt16) -> Bool {
        host?.lowercased() == "127.0.0.1:\(port)"
    }

    private func validateOrigin(_ origin: String?, port: UInt16) -> Bool {
        guard let origin, !origin.isEmpty else { return true }
        return origin.lowercased() == "http://127.0.0.1:\(port)"
    }

    private func acceptsJSONAndEventStream(_ accept: String?) -> Bool {
        guard let accept = accept?.lowercased() else { return false }
        return accept.contains("application/json") && accept.contains("text/event-stream")
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func containsJSONRPCError(_ value: JSONValue) -> Bool {
        guard case .object(let object) = value else { return false }
        return object["error"] != nil
    }

    private func jsonResponse(status: Int, value: JSONValue) -> AgentHTTPResponse {
        AgentHTTPResponse(
            status: status,
            headers: ["content-type": "application/json; charset=utf-8"],
            body: encode(value)
        )
    }

    private func rpcError(
        id: JSONValue?,
        code: AgentMCPErrorCode,
        message: String
    ) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id ?? .null,
            "error": .object([
                "code": .int(code.rawValue),
                "message": .string(message),
            ]),
        ])
    }

    private func encode(_ value: JSONValue) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data(#"{"error":"Encoding failed."}"#.utf8)
    }
}
