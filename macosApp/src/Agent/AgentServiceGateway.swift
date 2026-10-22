import Foundation
import MLXLMCommon

actor AgentServiceGateway {
    private let handlers: AgentServiceHandlers
    private let timeout: Duration
    private var pending: PendingCall?
    private var audits: [AgentToolAudit] = []
    private let maxAuditEntries = 40

    private struct PendingCall: Sendable {
        let action: AgentPendingAction
        let arguments: [String: JSONValue]
    }

    init(handlers: AgentServiceHandlers, timeout: Duration = .seconds(15)) {
        self.handlers = handlers
        self.timeout = timeout
    }

    func handle(_ call: ToolCall) async -> String {
        let name = call.function.name
        guard let descriptor = AgentToolCatalog.descriptor(named: name) else {
            record(name: name, risk: .readOnly, status: .rejected, detail: "Unknown tool")
            return AgentServiceResult.failure(
                "Unknown local service.",
                code: .unknownTool
            ).jsonString()
        }

        guard validateArguments(call.function.arguments, for: descriptor) else {
            record(name: name, risk: descriptor.risk, status: .rejected, detail: "Invalid arguments")
            return AgentServiceResult.failure(
                "Invalid local service arguments.",
                code: .invalidArguments
            ).jsonString()
        }

        if descriptor.risk == .sideEffect {
            guard pending == nil else {
                record(
                    name: name,
                    risk: descriptor.risk,
                    status: .rejected,
                    detail: "Another action is waiting for confirmation"
                )
                return AgentServiceResult.failure(
                    "Another local action is already waiting for confirmation.",
                    code: .pendingActionExists
                ).jsonString()
            }
            let summary = pendingSummary(name: name, arguments: call.function.arguments)
            let text = stringValue(call.function.arguments["text"])
            let action = AgentPendingAction(
                id: UUID().uuidString,
                toolName: name,
                summary: summary,
                characterCount: name == "copy_text"
                    ? text?.count
                    : nil,
                textPreview: text.map { String($0.prefix(500)) },
                risk: descriptor.risk,
                toolCallID: call.id
            )
            pending = PendingCall(action: action, arguments: call.function.arguments)
            record(
                name: name,
                risk: descriptor.risk,
                status: .pendingConfirmation,
                detail: "Waiting for user confirmation"
            )
            return AgentServiceResult(
                ok: true,
                summary: "Waiting for user confirmation.",
                data: nil
            ).jsonString()
        }

        let result = await executeWithTimeout(name: name, arguments: call.function.arguments)
        record(
            name: name,
            risk: descriptor.risk,
            status: result.ok ? .completed : .failed,
            detail: result.ok ? "Completed" : result.summary,
            errorCode: result.errorCode
        )
        return result.jsonString()
    }

    func pendingAction() -> AgentPendingAction? {
        pending?.action
    }

    func confirmPending() async -> AgentServiceResult {
        guard let pending else {
            return .failure("There is no pending local action.", code: .executionFailed)
        }
        self.pending = nil
        let result = await executeWithTimeout(
            name: pending.action.toolName,
            arguments: pending.arguments
        )
        record(
            name: pending.action.toolName,
            risk: .sideEffect,
            status: result.ok ? .completed : .failed,
            detail: result.ok ? "Confirmed and completed" : result.summary,
            errorCode: result.errorCode
        )
        return result
    }

    func cancelPending() {
        guard let pending else { return }
        self.pending = nil
        record(
            name: pending.action.toolName,
            risk: .sideEffect,
            status: .cancelled,
            detail: "Cancelled by user"
        )
    }

    func recentAudits(limit: Int = 8) -> [AgentToolAudit] {
        Array(audits.suffix(max(0, limit)))
    }

    func reset() {
        pending = nil
        audits = []
    }

    private func executeWithTimeout(
        name: String,
        arguments: [String: JSONValue]
    ) async -> AgentServiceResult {
        let timeout = self.timeout
        do {
            return try await withThrowingTaskGroup(of: AgentServiceResult.self) { group in
                group.addTask {
                    await self.execute(name: name, arguments: arguments)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw GatewayTimeout()
                }
                guard let result = try await group.next() else {
                    throw GatewayTimeout()
                }
                group.cancelAll()
                return result
            }
        } catch is CancellationError {
            return .failure("Local service was cancelled.", code: .cancelled)
        } catch is GatewayTimeout {
            return .failure("Local service timed out.", code: .timeout)
        } catch {
            return .failure("Local service failed.", code: .executionFailed)
        }
    }

    private func execute(name: String, arguments: [String: JSONValue]) async -> AgentServiceResult {
        switch name {
        case "get_monitor_snapshot":
            return await handlers.monitorSnapshot()
        case "get_power_status":
            return await handlers.powerStatus()
        case "list_workspace_files":
            return await handlers.workspaceFiles(
                stringValue(arguments["query"]),
                boundedLimit(arguments["limit"], defaultValue: 8)
            )
        case "inspect_file":
            guard let fileId = stringValue(arguments["fileId"]),
                  AgentFileReference(fileId: fileId) != nil
            else {
                return .failure("File ID is required.", code: .invalidArguments)
            }
            return await handlers.inspectFile(
                fileId,
                boundedCharacterLimit(arguments["maxCharacters"], defaultValue: 6_000)
            )
        case "list_screenshots":
            return await handlers.screenshots(boundedLimit(arguments["limit"], defaultValue: 8))
        case "list_clipboard_metadata":
            return await handlers.clipboardMetadata(boundedLimit(arguments["limit"], defaultValue: 8))
        case "copy_text":
            guard let text = stringValue(arguments["text"]), !text.isEmpty else {
                return .failure("Text is required.", code: .invalidArguments)
            }
            return await handlers.copyText(text)
        default:
            return .failure("Unknown local service.", code: .unknownTool)
        }
    }

    private func validateArguments(
        _ arguments: [String: JSONValue],
        for descriptor: AgentToolDescriptor
    ) -> Bool {
        let allowed: Set<String>
        switch descriptor.name {
        case "get_monitor_snapshot", "get_power_status":
            allowed = []
        case "list_workspace_files":
            allowed = ["query", "limit"]
        case "inspect_file":
            allowed = ["fileId", "maxCharacters"]
        case "list_screenshots", "list_clipboard_metadata":
            allowed = ["limit"]
        case "copy_text":
            allowed = ["text"]
        default:
            return false
        }
        guard Set(arguments.keys).isSubset(of: allowed) else { return false }

        if let query = arguments["query"], query != .null, stringValue(query) == nil {
            return false
        }
        if let limit = arguments["limit"], limit != .null {
            guard let value = intValue(limit), (1...20).contains(value) else { return false }
        }
        if descriptor.name == "inspect_file" {
            guard let fileId = stringValue(arguments["fileId"]),
                  !fileId.isEmpty,
                  fileId.count <= 256,
                  AgentFileReference(fileId: fileId) != nil
            else { return false }
            if let maxCharacters = arguments["maxCharacters"], maxCharacters != .null {
                guard let value = intValue(maxCharacters), (500...20_000).contains(value) else {
                    return false
                }
            }
        }
        if descriptor.name == "copy_text" {
            guard let text = stringValue(arguments["text"]),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= 10_000
            else { return false }
        }
        return true
    }

    private func pendingSummary(name: String, arguments: [String: JSONValue]) -> String {
        if name == "copy_text", let text = stringValue(arguments["text"]) {
            return "Copy \(text.count) characters to the clipboard."
        }
        return "Run \(name)."
    }

    private func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let value)? = value else { return nil }
        return value
    }

    private func intValue(_ value: JSONValue?) -> Int? {
        switch value {
        case .int(let value):
            return value
        case .double(let value) where value.rounded() == value:
            return Int(value)
        default:
            return nil
        }
    }

    private func boundedLimit(_ value: JSONValue?, defaultValue: Int) -> Int {
        min(20, max(1, intValue(value) ?? defaultValue))
    }

    private func boundedCharacterLimit(_ value: JSONValue?, defaultValue: Int) -> Int {
        min(20_000, max(500, intValue(value) ?? defaultValue))
    }

    private func record(
        name: String,
        risk: AgentToolRisk,
        status: AgentToolAuditStatus,
        detail: String,
        errorCode: AgentServiceErrorCode? = nil
    ) {
        audits.append(
            AgentToolAudit(
                id: UUID().uuidString,
                toolName: name,
                risk: risk,
                status: status,
                detail: detail,
                errorCode: errorCode
            )
        )
        if audits.count > maxAuditEntries {
            audits.removeFirst(audits.count - maxAuditEntries)
        }
    }
}

private struct GatewayTimeout: Error {}
