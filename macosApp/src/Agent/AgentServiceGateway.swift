import Foundation
import MLXLMCommon

actor AgentServiceGateway {
    private let handlers: AgentServiceHandlers
    private let timeout: Duration
    private var pending: PendingCall?
    private var deferred: [DeferredCall] = []
    private var activeDeferred: DeferredCall?
    private var audits: [AgentToolAudit] = []
    private var auditObserver: (@Sendable (AgentToolAudit) async -> Void)?
    private let maxAuditEntries = 40

    private struct PendingCall: Sendable {
        let action: AgentPendingAction
        let arguments: [String: JSONValue]
    }

    private struct DeferredCall: Sendable {
        let action: AgentDeferredAction
        let arguments: [String: JSONValue]
        let source: AgentActionSource
    }

    init(handlers: AgentServiceHandlers, timeout: Duration = .seconds(15)) {
        self.handlers = handlers
        self.timeout = timeout
    }

    func handle(_ call: ToolCall) async -> String {
        let descriptor = AgentToolCatalog.descriptor(named: call.function.name)
        return await process(call, source: .local, descriptor: descriptor)
    }

    func handleExternal(_ call: ToolCall, sessionID: String) async -> String {
        let descriptor = AgentExternalToolPolicy.descriptor(named: call.function.name)
        return await process(
            call,
            source: .external(sessionID),
            descriptor: descriptor
        )
    }

    func setAuditObserver(_ observer: (@Sendable (AgentToolAudit) async -> Void)?) {
        auditObserver = observer
    }

    private func process(
        _ call: ToolCall,
        source: AgentActionSource,
        descriptor: AgentToolDescriptor?
    ) async -> String {
        let name = call.function.name
        guard let descriptor else {
            record(
                name: name,
                risk: .readOnly,
                status: .rejected,
                detail: "Unknown tool",
                source: source
            )
            return AgentServiceResult.failure(
                "Unknown local service.",
                code: .unknownTool
            ).jsonString()
        }

        let risk = source == .local
            ? descriptor.risk
            : AgentExternalToolPolicy.risk(for: descriptor)

        guard validateArguments(call.function.arguments, for: descriptor) else {
            record(
                name: name,
                risk: risk,
                status: .rejected,
                detail: "Invalid arguments",
                source: source
            )
            return AgentServiceResult.failure(
                "Invalid local service arguments.",
                code: .invalidArguments
            ).jsonString()
        }

        if risk == .sideEffect {
            guard pending == nil else {
                record(
                    name: name,
                    risk: risk,
                    status: .rejected,
                    detail: "Another action is waiting for confirmation",
                    source: source
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
                risk: risk,
                toolCallID: call.id,
                source: source
            )
            pending = PendingCall(action: action, arguments: call.function.arguments)
            record(
                name: name,
                risk: risk,
                status: .pendingConfirmation,
                detail: "Waiting for user confirmation",
                source: source
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
            deferred.append(
                DeferredCall(
                    action: action,
                    arguments: call.function.arguments,
                    source: source
                )
            )
            record(
                name: name,
                risk: risk,
                status: .queued,
                detail: "Queued until the current model response finishes",
                source: source
            )
            return AgentServiceResult(
                ok: true,
                summary: "File naming preview queued.",
                data: nil
            ).jsonString()
        }

        let started = ContinuousClock.now
        let result = await executeWithTimeout(name: name, arguments: call.function.arguments)
        record(
            name: name,
            risk: risk,
            status: result.ok ? .completed : .failed,
            detail: result.ok ? "Completed" : result.summary,
            errorCode: result.errorCode,
            durationMilliseconds: Self.milliseconds(since: started),
            source: source
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
        let started = ContinuousClock.now
        let result = await executeWithTimeout(
            name: call.action.toolName,
            arguments: call.arguments
        )
        record(
            name: call.action.toolName,
            risk: .readOnly,
            status: result.ok ? .completed : .failed,
            detail: result.ok ? "Deferred action completed" : result.summary,
            errorCode: result.errorCode,
            durationMilliseconds: Self.milliseconds(since: started),
            source: call.source
        )
        return result
    }

    func confirmPending() async -> AgentServiceResult {
        guard let pending else {
            return .failure("There is no pending local action.", code: .executionFailed)
        }
        self.pending = nil
        let started = ContinuousClock.now
        let result = await executeWithTimeout(
            name: pending.action.toolName,
            arguments: pending.arguments
        )
        record(
            name: pending.action.toolName,
            risk: .sideEffect,
            status: result.ok ? .completed : .failed,
            detail: result.ok ? "Confirmed and completed" : result.summary,
            errorCode: result.errorCode,
            durationMilliseconds: Self.milliseconds(since: started),
            source: pending.action.source
        )
        return result
    }

    func cancelPending(source: AgentActionSource? = nil) {
        guard let pending else { return }
        if let source, pending.action.source != source { return }
        self.pending = nil
        record(
            name: pending.action.toolName,
            risk: .sideEffect,
            status: .cancelled,
            detail: "Cancelled",
            source: pending.action.source
        )
    }

    func recentAudits(limit: Int = 40) -> [AgentToolAudit] {
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
        case "describe_image":
            guard let fileId = stringValue(arguments["fileId"]),
                  let question = stringValue(arguments["question"]),
                  AgentFileReference(fileId: fileId) != nil,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return .failure("File ID and image question are required.", code: .invalidArguments)
            }
            return await handlers.describeImage(fileId, question)
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
        case "open_pane":
            guard let pane = stringValue(arguments["pane"]) else {
                return .failure("Pane is required.", code: .invalidArguments)
            }
            return await handlers.openPane(pane)
        case "read_setting":
            guard let key = stringValue(arguments["key"]) else {
                return .failure("Setting key is required.", code: .invalidArguments)
            }
            return await handlers.readSetting(key)
        case "request_setting_change":
            guard let key = stringValue(arguments["key"]),
                  let value = stringValue(arguments["value"])
            else {
                return .failure("Setting key and value are required.", code: .invalidArguments)
            }
            return await handlers.requestSettingChange(key, value)
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
        case "describe_image":
            allowed = ["fileId", "question"]
        case "preview_file_names":
            allowed = ["fileIds", "maxResults"]
        case "apply_file_renames":
            allowed = ["previewIds"]
        case "undo_rename_run":
            allowed = ["runId"]
        case "search_file_content":
            allowed = ["fileIds", "query", "limit"]
        case "open_pane":
            allowed = ["pane"]
        case "read_setting":
            allowed = ["key"]
        case "request_setting_change":
            allowed = ["key", "value"]
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
        if descriptor.name == "describe_image" {
            guard let fileId = stringValue(arguments["fileId"]),
                  AgentFileReference(fileId: fileId) != nil,
                  let question = stringValue(arguments["question"]),
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  question.count <= 1_000
            else { return false }
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
        if descriptor.name == "open_pane" {
            guard let pane = stringValue(arguments["pane"]),
                  AgentPane(rawValue: pane) != nil
            else { return false }
        }
        if descriptor.name == "read_setting" {
            guard let key = stringValue(arguments["key"]),
                  AgentSettingKey(rawValue: key) != nil
            else { return false }
        }
        if descriptor.name == "request_setting_change" {
            guard let key = stringValue(arguments["key"]),
                  let settingKey = AgentSettingKey(rawValue: key),
                  let value = stringValue(arguments["value"]),
                  !value.isEmpty,
                  value.count <= 32,
                  settingKey.parse(value) != nil
            else { return false }
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
        if name == "open_pane", let pane = stringValue(arguments["pane"]) {
            return "Open the \(pane) page."
        }
        if name == "request_setting_change" {
            let key = stringValue(arguments["key"]) ?? "setting"
            let value = stringValue(arguments["value"]) ?? ""
            return "Change \(key) to \(value)."
        }
        return "Run \(name)."
    }

    private func deferredSummary(name: String, arguments: [String: JSONValue]) -> String {
        if name == "describe_image" {
            return "Answer an image question locally."
        }
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
        errorCode: AgentServiceErrorCode? = nil,
        durationMilliseconds: Int? = nil,
        source: AgentActionSource = .local
    ) {
        let audit = AgentToolAudit(
            id: UUID().uuidString,
            toolName: name,
            risk: risk,
            status: status,
            detail: detail,
            errorCode: errorCode,
            durationMilliseconds: durationMilliseconds,
            source: source
        )
        audits.append(audit)
        if audits.count > maxAuditEntries {
            audits.removeFirst(audits.count - maxAuditEntries)
        }
        if let auditObserver {
            Task { await auditObserver(audit) }
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let components = start.duration(to: .now).components
        let milliseconds = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
        return Int(max(0, milliseconds))
    }
}

private struct GatewayTimeout: Error {}
