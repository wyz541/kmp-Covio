import Foundation
import MLXLMCommon

enum AgentToolRisk: String, Sendable, Equatable {
    case readOnly
    case sideEffect
}

struct AgentServiceResult: Codable, Sendable, Equatable {
    let ok: Bool
    let summary: String
    let data: JSONValue?

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

    static func failure(_ summary: String) -> AgentServiceResult {
        AgentServiceResult(ok: false, summary: summary, data: nil)
    }
}

struct AgentToolDescriptor: Sendable {
    let name: String
    let summary: String
    let risk: AgentToolRisk
    let schema: ToolSpec
}

struct AgentPendingAction: Sendable, Equatable, Identifiable {
    let id: String
    let toolName: String
    let summary: String
    let characterCount: Int?
}

enum AgentToolAuditStatus: String, Sendable, Equatable {
    case completed
    case pendingConfirmation
    case rejected
    case failed
    case cancelled
}

struct AgentToolAudit: Sendable, Equatable, Identifiable {
    let id: String
    let toolName: String
    let risk: AgentToolRisk
    let status: AgentToolAuditStatus
    let detail: String
}

struct AgentServiceHandlers: Sendable {
    let monitorSnapshot: @Sendable () async -> AgentServiceResult
    let powerStatus: @Sendable () async -> AgentServiceResult
    let workspaceFiles: @Sendable (String?, Int) async -> AgentServiceResult
    let screenshots: @Sendable (Int) async -> AgentServiceResult
    let clipboardMetadata: @Sendable (Int) async -> AgentServiceResult
    let copyText: @Sendable (String) async -> AgentServiceResult
}

private struct EmptyAgentInput: Codable {}
private struct AgentToolAck: Codable { let ok = true }
private struct WorkspaceToolInput: Codable { let query: String?; let limit: Int? }
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
        tool: T
    ) -> AgentToolDescriptor {
        AgentToolDescriptor(name: name, summary: summary, risk: risk, schema: tool.schema)
    }
}
