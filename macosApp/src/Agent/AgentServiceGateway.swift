import Foundation
import MLXLMCommon

actor AgentServiceGateway {
    private let handlers: AgentServiceHandlers
    private let timeout: Duration
    private var pending: PendingCall?
    private var deferred: [DeferredCall] = []
    private var activeDeferred: DeferredCall?
    private var audits: [AgentToolAudit] = []
    private let maxAuditEntries = 40

    private struct PendingCall: Sendable {
        let action: AgentPendingAction
        let arguments: [String: JSONValue]
    }

    private struct DeferredCall: Sendable {
        let action: AgentDeferredAction
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
            let previewText = stringArrayValue(call.function.arguments["previewIds"])?
                .joined(separator: "\n")
            let action = AgentPendingAction(
                id: UUID().uuidString,
                toolName: name,
                summary: summary,
                characterCount: name == "copy_text"
                    ? text?.count
                    : nil,
                textPreview: text.map { String($0.prefix(500)) } ?? previewText,
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

        if descriptor.executionMode == .afterModelResponse {
            let action = AgentDeferredAction(
                id: UUID().uuidString,
                toolName: name,
                summary: deferredSummary(name: name, arguments: call.function.arguments)
            )
            deferred.append(DeferredCall(action: action, arguments: call.function.arguments))
            record(
                name: name,
                risk: descriptor.risk,
                status: .queued,
                detail: "Queued until the current model response finishes"
            )
            return AgentServiceResult(
                ok: true,
                summary: "File naming preview queued.",
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

    func takeDeferredAction() -> AgentDeferredAction? {
        guard activeDeferred == nil, !deferred.isEmpty else { return nil }
        let call = deferred.removeFirst()
        activeDeferred = call
        return call.action
    }

    func executeDeferred(_ action: AgentDeferredAction) async -> AgentServiceResult {
        guard let call = activeDeferred, call.action.id == action.id else {
            return .failure("Deferred action was not found.", code: .executionFailed)
        }
        activeDeferred = nil
        let result = await executeWithTimeout(
            name: call.action.toolName,
            arguments: call.arguments
        )
        record(
            name: call.action.toolName,
            risk: .readOnly,
            status: result.ok ? .completed : .failed,
            detail: result.ok ? "Deferred action completed" : result.summary,
            errorCode: result.errorCode
        )
        return result
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
        deferred = []
        activeDeferred = nil
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
        case "preview_file_names":
            guard let fileIds = stringArrayValue(arguments["fileIds"]), !fileIds.isEmpty else {
                return .failure("File IDs are required.", code: .invalidArguments)
            }
            return await handlers.previewFileNames(
                fileIds,
                boundedLimit(arguments["maxResults"], defaultValue: 8)
            )
        case "apply_file_renames":
            guard let previewIds = stringArrayValue(arguments["previewIds"]), !previewIds.isEmpty else {
                return .failure("Preview IDs are required.", code: .invalidArguments)
            }
            return await handlers.applyFileRenames(previewIds)
        case "undo_rename_run":
            guard let runId = stringValue(arguments["runId"]) else {
                return .failure("Run ID is required.", code: .invalidArguments)
            }
            return await handlers.undoRenameRun(runId)
        case "search_file_content":
            guard let fileIds = stringArrayValue(arguments["fileIds"]),
                  let query = stringValue(arguments["query"]),
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return .failure("File IDs and query are required.", code: .invalidArguments)
            }
            return await handlers.searchFileContent(
                fileIds,
                query,
                min(12, boundedLimit(arguments["limit"], defaultValue: 6))
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
        case "preview_file_names":
            allowed = ["fileIds", "maxResults"]
        case "apply_file_renames":
            allowed = ["previewIds"]
        case "undo_rename_run":
            allowed = ["runId"]
        case "search_file_content":
            allowed = ["fileIds", "query", "limit"]
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
        if descriptor.name == "preview_file_names" {
            guard let fileIds = stringArrayValue(arguments["fileIds"]),
                  !fileIds.isEmpty,
                  fileIds.count <= 20,
                  fileIds.allSatisfy({ AgentFileReference(fileId: $0) != nil })
            else { return false }
            if let maxResults = arguments["maxResults"], maxResults != .null {
                guard let value = intValue(maxResults), (1...20).contains(value) else {
                    return false
                }
            }
        }
        if descriptor.name == "apply_file_renames" {
            guard let previewIds = stringArrayValue(arguments["previewIds"]),
                  !previewIds.isEmpty,
                  previewIds.count <= 20,
                  previewIds.allSatisfy({ !$0.isEmpty && $0.count <= 128 })
            else { return false }
        }
        if descriptor.name == "undo_rename_run" {
            guard let runId = stringValue(arguments["runId"]),
                  !runId.isEmpty,
                  runId.count <= 128,
                  runId.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            else { return false }
        }
        if descriptor.name == "search_file_content" {
            guard let fileIds = stringArrayValue(arguments["fileIds"]),
                  !fileIds.isEmpty,
                  fileIds.count <= 20,
                  fileIds.allSatisfy({ AgentFileReference(fileId: $0) != nil }),
                  let query = stringValue(arguments["query"]),
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  query.count <= 512
            else { return false }
            if let limit = arguments["limit"], limit != .null {
                guard let value = intValue(limit), (1...12).contains(value) else { return false }
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
        if name == "apply_file_renames" {
            return "Rename \(stringArrayValue(arguments["previewIds"])?.count ?? 0) files from previews."
        }
        if name == "undo_rename_run" {
            return "Undo the selected Agent rename run."
        }
        return "Run \(name)."
    }

    private func deferredSummary(name: String, arguments: [String: JSONValue]) -> String {
        if name == "preview_file_names" {
            return "Preview names for \(stringArrayValue(arguments["fileIds"])?.count ?? 0) files."
        }
        if name == "search_file_content" {
            return "Search \(stringArrayValue(arguments["fileIds"])?.count ?? 0) files."
        }
        return "Run \(name) after the model response."
    }

    private func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let value)? = value else { return nil }
        return value
    }

    private func stringArrayValue(_ value: JSONValue?) -> [String]? {
        guard case .array(let values)? = value else { return nil }
        return values.compactMap(stringValue)
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
