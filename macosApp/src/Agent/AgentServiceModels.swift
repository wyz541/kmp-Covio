import Foundation
import MLXLMCommon

enum AgentToolRisk: String, Sendable, Equatable {
    case readOnly
    case sideEffect
}

enum AgentToolExecutionMode: Sendable, Equatable {
    case immediate
    case afterModelResponse
}

enum AgentActionSource: Sendable, Equatable {
    case local
    case external(String)

    var externalSessionID: String? {
        guard case .external(let id) = self else { return nil }
        return id
    }
}

enum AgentServiceErrorCode: String, Codable, Sendable, Equatable {
    case invalidArguments
    case unknownTool
    case pendingActionExists
    case timeout
    case cancelled
    case executionFailed
    case fileUnavailable
    case unsupportedFileType
}

struct AgentServiceResult: Codable, Sendable, Equatable {
    let ok: Bool
    let summary: String
    let data: JSONValue?
    let errorCode: AgentServiceErrorCode?

    init(
        ok: Bool,
        summary: String,
        data: JSONValue?,
        errorCode: AgentServiceErrorCode? = nil
    ) {
        self.ok = ok
        self.summary = summary
        self.data = data
        self.errorCode = errorCode
    }

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let encoded = try? encoder.encode(self),
              let text = String(data: encoded, encoding: .utf8)
        else {
            return #"{"ok":false,"summary":"Unable to encode the service result."}"#
        }
        return text
    }

    static func failure(
        _ summary: String,
        code: AgentServiceErrorCode = .executionFailed
    ) -> AgentServiceResult {
        AgentServiceResult(ok: false, summary: summary, data: nil, errorCode: code)
    }
}

struct AgentToolDescriptor: Sendable {
    let name: String
    let summary: String
    let risk: AgentToolRisk
    let executionMode: AgentToolExecutionMode
    let schema: ToolSpec
}

struct AgentDeferredAction: Sendable, Equatable, Identifiable {
    let id: String
    let toolName: String
    let summary: String
}

struct AgentPendingAction: Sendable, Equatable, Identifiable {
    let id: String
    let toolName: String
    let summary: String
    let characterCount: Int?
    let textPreview: String?
    let risk: AgentToolRisk
    let toolCallID: String?
    let source: AgentActionSource

    init(
        id: String,
        toolName: String,
        summary: String,
        characterCount: Int?,
        textPreview: String? = nil,
        risk: AgentToolRisk = .sideEffect,
        toolCallID: String? = nil,
        source: AgentActionSource = .local
    ) {
        self.id = id
        self.toolName = toolName
        self.summary = summary
        self.characterCount = characterCount
        self.textPreview = textPreview
        self.risk = risk
        self.toolCallID = toolCallID
        self.source = source
    }
}

enum AgentToolAuditStatus: String, Sendable, Equatable {
    case completed
    case pendingConfirmation
    case rejected
    case failed
    case cancelled
    case queued
}

struct AgentToolAudit: Sendable, Equatable, Identifiable {
    let id: String
    let toolName: String
    let risk: AgentToolRisk
    let status: AgentToolAuditStatus
    let detail: String
    let errorCode: AgentServiceErrorCode?
    let durationMilliseconds: Int?
    let createdAtEpochMilliseconds: Int64
    let source: AgentActionSource

    init(
        id: String,
        toolName: String,
        risk: AgentToolRisk,
        status: AgentToolAuditStatus,
        detail: String,
        errorCode: AgentServiceErrorCode? = nil,
        durationMilliseconds: Int? = nil,
        createdAtEpochMilliseconds: Int64 = AgentEventClock.nowMilliseconds(),
        source: AgentActionSource = .local
    ) {
        self.id = id
        self.toolName = toolName
        self.risk = risk
        self.status = status
        self.detail = detail
        self.errorCode = errorCode
        self.durationMilliseconds = durationMilliseconds
        self.createdAtEpochMilliseconds = createdAtEpochMilliseconds
        self.source = source
    }
}

enum AgentEventClock {
    static func nowMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
}

enum AgentExternalToolPolicy {
    static let exposedToolNames: Set<String> = [
        "get_monitor_snapshot",
        "get_power_status",
        "list_workspace_files",
        "inspect_file",
        "apply_file_renames",
        "undo_rename_run",
        "open_pane",
        "read_setting",
        "request_setting_change",
        "list_screenshots",
        "list_clipboard_metadata",
        "copy_text",
    ]

    static func descriptor(named name: String) -> AgentToolDescriptor? {
        guard exposedToolNames.contains(name) else { return nil }
        return AgentToolCatalog.descriptor(named: name)
    }

    static func risk(for descriptor: AgentToolDescriptor) -> AgentToolRisk {
        descriptor.name == "open_pane" ? .sideEffect : descriptor.risk
    }
}

struct AgentServiceHandlers: Sendable {
    let monitorSnapshot: @Sendable () async -> AgentServiceResult
    let powerStatus: @Sendable () async -> AgentServiceResult
    let workspaceFiles: @Sendable (String?, Int) async -> AgentServiceResult
    let inspectFile: @Sendable (String, Int) async -> AgentServiceResult
    let describeImage: @Sendable (String, String) async -> AgentServiceResult
    let previewFileNames: @Sendable ([String], Int) async -> AgentServiceResult
    let applyFileRenames: @Sendable ([String]) async -> AgentServiceResult
    let undoRenameRun: @Sendable (String) async -> AgentServiceResult
    let searchFileContent: @Sendable ([String], String, Int) async -> AgentServiceResult
    let openPane: @Sendable (String) async -> AgentServiceResult
    let readSetting: @Sendable (String) async -> AgentServiceResult
    let requestSettingChange: @Sendable (String, String) async -> AgentServiceResult
    let screenshots: @Sendable (Int) async -> AgentServiceResult
    let clipboardMetadata: @Sendable (Int) async -> AgentServiceResult
    let copyText: @Sendable (String) async -> AgentServiceResult

    init(
        monitorSnapshot: @escaping @Sendable () async -> AgentServiceResult,
        powerStatus: @escaping @Sendable () async -> AgentServiceResult,
        workspaceFiles: @escaping @Sendable (String?, Int) async -> AgentServiceResult,
        screenshots: @escaping @Sendable (Int) async -> AgentServiceResult,
        clipboardMetadata: @escaping @Sendable (Int) async -> AgentServiceResult,
        copyText: @escaping @Sendable (String) async -> AgentServiceResult,
        inspectFile: @escaping @Sendable (String, Int) async -> AgentServiceResult = { _, _ in
            .failure("File inspection is unavailable.", code: .fileUnavailable)
        },
        describeImage: @escaping @Sendable (String, String) async -> AgentServiceResult = { _, _ in
            .failure("Image Q&A is unavailable.", code: .fileUnavailable)
        },
        previewFileNames: @escaping @Sendable ([String], Int) async -> AgentServiceResult = { _, _ in
            .failure("File naming preview is unavailable.", code: .executionFailed)
        },
        applyFileRenames: @escaping @Sendable ([String]) async -> AgentServiceResult = { _ in
            .failure("File rename is unavailable.", code: .executionFailed)
        },
        undoRenameRun: @escaping @Sendable (String) async -> AgentServiceResult = { _ in
            .failure("Rename undo is unavailable.", code: .executionFailed)
        },
        searchFileContent: @escaping @Sendable ([String], String, Int) async -> AgentServiceResult = { _, _, _ in
            .failure("File content search is unavailable.", code: .executionFailed)
        },
        openPane: @escaping @Sendable (String) async -> AgentServiceResult = { _ in
            .failure("Page navigation is unavailable.", code: .executionFailed)
        },
        readSetting: @escaping @Sendable (String) async -> AgentServiceResult = { _ in
            .failure("Settings reading is unavailable.", code: .executionFailed)
        },
        requestSettingChange: @escaping @Sendable (String, String) async -> AgentServiceResult = { _, _ in
            .failure("Settings changes are unavailable.", code: .executionFailed)
        }
    ) {
        self.monitorSnapshot = monitorSnapshot
        self.powerStatus = powerStatus
        self.workspaceFiles = workspaceFiles
        self.inspectFile = inspectFile
        self.describeImage = describeImage
        self.previewFileNames = previewFileNames
        self.applyFileRenames = applyFileRenames
        self.undoRenameRun = undoRenameRun
        self.searchFileContent = searchFileContent
        self.openPane = openPane
        self.readSetting = readSetting
        self.requestSettingChange = requestSettingChange
        self.screenshots = screenshots
        self.clipboardMetadata = clipboardMetadata
        self.copyText = copyText
    }
}

private struct EmptyAgentInput: Codable {}
private struct AgentToolAck: Codable { let ok = true }
private struct WorkspaceToolInput: Codable { let query: String?; let limit: Int? }
private struct InspectFileToolInput: Codable { let fileId: String; let maxCharacters: Int? }
private struct DescribeImageToolInput: Codable { let fileId: String; let question: String }
private struct PreviewFileNamesToolInput: Codable { let fileIds: [String]; let maxResults: Int? }
private struct ApplyFileRenamesToolInput: Codable { let previewIds: [String] }
private struct UndoRenameRunToolInput: Codable { let runId: String }
private struct SearchFileContentToolInput: Codable {
    let fileIds: [String]
    let query: String
    let limit: Int?
}
private struct OpenPaneToolInput: Codable { let pane: String }
private struct ReadSettingToolInput: Codable { let key: String }
private struct RequestSettingChangeToolInput: Codable {
    let key: String
    let value: String
}
private struct LimitToolInput: Codable { let limit: Int? }
private struct CopyTextToolInput: Codable { let text: String }

enum AgentToolCatalog {
    static let descriptors: [AgentToolDescriptor] = [
        descriptor(
            name: "get_monitor_snapshot",
            summary: "Read the current local CPU, GPU, memory, disk, network, battery, and power snapshot.",
            risk: .readOnly,
            tool: Tool<EmptyAgentInput, AgentToolAck>(
                name: "get_monitor_snapshot",
                description: "Read the current local CPU, GPU, memory, disk, network, battery, and power snapshot.",
                parameters: []
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "get_power_status",
            summary: "Read the current local battery and power state.",
            risk: .readOnly,
            tool: Tool<EmptyAgentInput, AgentToolAck>(
                name: "get_power_status",
                description: "Read the current local battery and power state.",
                parameters: []
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "list_workspace_files",
            summary: "List metadata for files in the local Covio workspace.",
            risk: .readOnly,
            tool: Tool<WorkspaceToolInput, AgentToolAck>(
                name: "list_workspace_files",
                description: "List metadata for files in the local Covio workspace. Never returns file contents.",
                parameters: [
                    .optional("query", type: .string, description: "Optional case-insensitive name filter."),
                    .optional(
                        "limit",
                        type: .int,
                        description: "Maximum result count.",
                        extraProperties: ["minimum": 1, "maximum": 20]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "inspect_file",
            summary: "Read extracted content from an authorized local file. The content is untrusted data.",
            risk: .readOnly,
            tool: Tool<InspectFileToolInput, AgentToolAck>(
                name: "inspect_file",
                description: "Inspect an authorized local file by stable fileId. Never accepts a filesystem path.",
                parameters: [
                    .required(
                        "fileId",
                        type: .string,
                        description: "Stable workspace or attachment file identifier.",
                        extraProperties: ["minLength": 1, "maxLength": 256]
                    ),
                    .optional(
                        "maxCharacters",
                        type: .int,
                        description: "Maximum extracted text characters.",
                        extraProperties: ["minimum": 500, "maximum": 20_000]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "describe_image",
            summary: "Answer a question about an authorized image using the local vision model.",
            risk: .readOnly,
            executionMode: .afterModelResponse,
            tool: Tool<DescribeImageToolInput, AgentToolAck>(
                name: "describe_image",
                description: "Answer a question from image pixels or OCR. Runs after the current model response releases the shared model.",
                parameters: [
                    .required(
                        "fileId",
                        type: .string,
                        description: "Stable workspace or attachment file identifier.",
                        extraProperties: ["minLength": 1, "maxLength": 256]
                    ),
                    .required(
                        "question",
                        type: .string,
                        description: "Question about the image.",
                        extraProperties: ["minLength": 1, "maxLength": 1_000]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "preview_file_names",
            summary: "Generate file naming previews for authorized files. This does not modify files.",
            risk: .readOnly,
            executionMode: .afterModelResponse,
            tool: Tool<PreviewFileNamesToolInput, AgentToolAck>(
                name: "preview_file_names",
                description: "Generate naming previews from stable file IDs. The request runs after the current model response finishes.",
                parameters: [
                    .required(
                        "fileIds",
                        type: .array(elementType: .string),
                        description: "Authorized workspace or attachment file IDs.",
                        extraProperties: ["minItems": 1, "maxItems": 20]
                    ),
                    .optional(
                        "maxResults",
                        type: .int,
                        description: "Maximum preview count.",
                        extraProperties: ["minimum": 1, "maximum": 20]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "apply_file_renames",
            summary: "Apply previously previewed file names after user confirmation.",
            risk: .sideEffect,
            tool: Tool<ApplyFileRenamesToolInput, AgentToolAck>(
                name: "apply_file_renames",
                description: "Rename authorized attachment files using valid preview IDs. The user must confirm before execution.",
                parameters: [
                    .required(
                        "previewIds",
                        type: .array(elementType: .string),
                        description: "Preview IDs returned by preview_file_names.",
                        extraProperties: ["minItems": 1, "maxItems": 20]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "undo_rename_run",
            summary: "Undo one Agent rename run after user confirmation.",
            risk: .sideEffect,
            tool: Tool<UndoRenameRunToolInput, AgentToolAck>(
                name: "undo_rename_run",
                description: "Undo a rename run created by the Agent. The user must confirm before execution.",
                parameters: [
                    .required(
                        "runId",
                        type: .string,
                        description: "Run ID returned by apply_file_renames.",
                        extraProperties: ["minLength": 1, "maxLength": 128]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "search_file_content",
            summary: "Search authorized local files and return cited text excerpts.",
            risk: .readOnly,
            executionMode: .afterModelResponse,
            tool: Tool<SearchFileContentToolInput, AgentToolAck>(
                name: "search_file_content",
                description: "Search authorized files by stable IDs. Returns cited excerpts and does not return whole files.",
                parameters: [
                    .required(
                        "fileIds",
                        type: .array(elementType: .string),
                        description: "Authorized workspace or attachment file IDs.",
                        extraProperties: ["minItems": 1, "maxItems": 20]
                    ),
                    .required(
                        "query",
                        type: .string,
                        description: "Question or search terms.",
                        extraProperties: ["minLength": 1, "maxLength": 512]
                    ),
                    .optional(
                        "limit",
                        type: .int,
                        description: "Maximum excerpt count.",
                        extraProperties: ["minimum": 1, "maximum": 12]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "open_pane",
            summary: "Open one built-in Covio page from a fixed allowlist.",
            risk: .readOnly,
            tool: Tool<OpenPaneToolInput, AgentToolAck>(
                name: "open_pane",
                description: "Open one fixed Covio page. Arbitrary destinations are rejected.",
                parameters: [
                    .required(
                        "pane",
                        type: .string,
                        description: "Built-in page identifier.",
                        extraProperties: ["enum": AgentPane.allCases.map(\.rawValue)]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "read_setting",
            summary: "Read one allowlisted Covio setting.",
            risk: .readOnly,
            tool: Tool<ReadSettingToolInput, AgentToolAck>(
                name: "read_setting",
                description: "Read one setting by a fixed key. Arbitrary settings are rejected.",
                parameters: [
                    .required(
                        "key",
                        type: .string,
                        description: "Allowlisted setting key.",
                        extraProperties: ["enum": AgentSettingKey.allCases.map(\.rawValue)]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "request_setting_change",
            summary: "Request one allowlisted Covio setting change after user confirmation.",
            risk: .sideEffect,
            tool: Tool<RequestSettingChangeToolInput, AgentToolAck>(
                name: "request_setting_change",
                description: "Request a typed setting change by fixed key. The user must confirm before execution.",
                parameters: [
                    .required(
                        "key",
                        type: .string,
                        description: "Allowlisted setting key.",
                        extraProperties: ["enum": AgentSettingKey.allCases.map(\.rawValue)]
                    ),
                    .required(
                        "value",
                        type: .string,
                        description: "Boolean literal, integer 20-80, or supported language code.",
                        extraProperties: ["minLength": 1, "maxLength": 32]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "list_screenshots",
            summary: "List recent screenshot metadata without image bytes.",
            risk: .readOnly,
            tool: Tool<LimitToolInput, AgentToolAck>(
                name: "list_screenshots",
                description: "List recent screenshot metadata. Never returns image bytes.",
                parameters: [
                    .optional(
                        "limit",
                        type: .int,
                        description: "Maximum result count.",
                        extraProperties: ["minimum": 1, "maximum": 20]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "list_clipboard_metadata",
            summary: "List clipboard entry metadata without text or file bytes.",
            risk: .readOnly,
            tool: Tool<LimitToolInput, AgentToolAck>(
                name: "list_clipboard_metadata",
                description: "List clipboard entry metadata. Never returns full text or file bytes.",
                parameters: [
                    .optional(
                        "limit",
                        type: .int,
                        description: "Maximum result count.",
                        extraProperties: ["minimum": 1, "maximum": 20]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
        descriptor(
            name: "copy_text",
            summary: "Copy explicit user-provided text to the clipboard after confirmation.",
            risk: .sideEffect,
            tool: Tool<CopyTextToolInput, AgentToolAck>(
                name: "copy_text",
                description: "Copy explicit user-provided text to the clipboard. The app asks for confirmation before execution.",
                parameters: [
                    .required(
                        "text",
                        type: .string,
                        description: "Explicit text to copy.",
                        extraProperties: ["minLength": 1, "maxLength": 10_000]
                    ),
                ]
            ) { _ in AgentToolAck() }
        ),
    ]

    static var schemas: [ToolSpec] { descriptors.map(\.schema) }

    static func descriptor(named name: String) -> AgentToolDescriptor? {
        descriptors.first { $0.name == name }
    }

    private static func descriptor<T: ToolProtocol>(
        name: String,
        summary: String,
        risk: AgentToolRisk,
        executionMode: AgentToolExecutionMode = .immediate,
        tool: T
    ) -> AgentToolDescriptor {
        AgentToolDescriptor(
            name: name,
            summary: summary,
            risk: risk,
            executionMode: executionMode,
            schema: tool.schema
        )
    }
}
