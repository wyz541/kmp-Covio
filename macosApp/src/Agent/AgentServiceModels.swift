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

    init(
        id: String,
        toolName: String,
        summary: String,
        characterCount: Int?,
        textPreview: String? = nil,
        risk: AgentToolRisk = .sideEffect,
        toolCallID: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.summary = summary
        self.characterCount = characterCount
        self.textPreview = textPreview
        self.risk = risk
        self.toolCallID = toolCallID
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

    init(
        id: String,
        toolName: String,
        risk: AgentToolRisk,
        status: AgentToolAuditStatus,
        detail: String,
        errorCode: AgentServiceErrorCode? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.risk = risk
        self.status = status
        self.detail = detail
        self.errorCode = errorCode
    }
}

struct AgentServiceHandlers: Sendable {
    let monitorSnapshot: @Sendable () async -> AgentServiceResult
    let powerStatus: @Sendable () async -> AgentServiceResult
    let workspaceFiles: @Sendable (String?, Int) async -> AgentServiceResult
    let inspectFile: @Sendable (String, Int) async -> AgentServiceResult
    let previewFileNames: @Sendable ([String], Int) async -> AgentServiceResult
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
        previewFileNames: @escaping @Sendable ([String], Int) async -> AgentServiceResult = { _, _ in
            .failure("File naming preview is unavailable.", code: .executionFailed)
        }
    ) {
        self.monitorSnapshot = monitorSnapshot
        self.powerStatus = powerStatus
        self.workspaceFiles = workspaceFiles
        self.inspectFile = inspectFile
        self.previewFileNames = previewFileNames
        self.screenshots = screenshots
        self.clipboardMetadata = clipboardMetadata
        self.copyText = copyText
    }
}

private struct EmptyAgentInput: Codable {}
private struct AgentToolAck: Codable { let ok = true }
private struct WorkspaceToolInput: Codable { let query: String?; let limit: Int? }
private struct InspectFileToolInput: Codable { let fileId: String; let maxCharacters: Int? }
private struct PreviewFileNamesToolInput: Codable { let fileIds: [String]; let maxResults: Int? }
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
