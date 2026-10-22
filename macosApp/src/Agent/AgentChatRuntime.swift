import Foundation
import kmpDomain

enum AgentChatRole: Sendable, Equatable {
    case user
    case assistant
    case service
}

struct AgentChatMessage: Sendable, Equatable, Identifiable {
    let id: UUID
    let role: AgentChatRole
    var text: String

    init(id: UUID = UUID(), role: AgentChatRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum AgentChatStage: Sendable, Equatable {
    case idle
    case thinking
    case awaitingConfirmation
    case executing
    case error
}

@MainActor
@Observable
final class AgentChatRuntime {
    private(set) var messages: [AgentChatMessage] = []
    private(set) var stage: AgentChatStage = .idle
    private(set) var pendingAction: AgentPendingAction?
    private(set) var toolAudits: [AgentToolAudit] = []
    private(set) var errorText: String?
    var language: AppLanguage = CopyLocale.language

    private let model: any AgentModelServing
    private let gateway: AgentServiceGateway
    private var generationTask: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?
    private var generationID = UUID()

    init(
        model: any AgentModelServing,
        gateway: AgentServiceGateway
    ) {
        self.model = model
        self.gateway = gateway
    }

    var isBusy: Bool {
        stage == .thinking || stage == .executing
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy, pendingAction == nil else { return }
        errorText = nil
        messages.append(AgentChatMessage(role: .user, text: prompt))
        let assistantID = UUID()
        messages.append(AgentChatMessage(id: assistantID, role: .assistant, text: ""))
        stage = .thinking
        let generationID = UUID()
        self.generationID = generationID

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await model.respond(to: prompt) { [weak self] chunk in
                    await MainActor.run {
                        self?.append(chunk, to: assistantID, generationID: generationID)
                    }
                }
                guard self.generationID == generationID, !Task.isCancelled else { return }
                await self.runDeferredActions()
                guard self.generationID == generationID, !Task.isCancelled else { return }
                await self.refreshToolState()
                if self.pendingAction != nil {
                    self.stage = .awaitingConfirmation
                } else {
                    self.stage = .idle
                }
                if let index = self.messages.firstIndex(where: { $0.id == assistantID }),
                   self.messages[index].text.isEmpty
                {
                    self.messages[index].text = ContractCopy.copyAgentEmptyResponse.text(for: self.language)
                }
            } catch is CancellationError {
                self.finishStopped(assistantID: assistantID, generationID: generationID)
            } catch {
                guard self.generationID == generationID else { return }
                self.stage = .error
                self.errorText = ContractCopy.copyAgentError.text(for: self.language)
                if let index = self.messages.firstIndex(where: { $0.id == assistantID }),
                   self.messages[index].text.isEmpty
                {
                    self.messages[index].text = self.errorText ?? ""
                }
            }
            self.generationTask = nil
        }
    }

    func stop() {
        guard stage != .executing else { return }
        generationTask?.cancel()
        generationTask = nil
        generationID = UUID()
        stage = .idle
        if let last = messages.indices.last, messages[last].role == .assistant,
           messages[last].text.isEmpty
        {
            messages[last].text = ContractCopy.copyAgentStopped.text(for: language)
        }
    }

    func confirmPendingAction() {
        guard let pendingAction, stage == .awaitingConfirmation else { return }
        errorText = nil
        stage = .executing
        let actionID = pendingAction.id
        let toolName = pendingAction.toolName
        executionTask = Task {
            let result = await gateway.confirmPending()
            guard self.pendingAction?.id == actionID else {
                self.executionTask = nil
                return
            }
            self.pendingAction = nil
            let message = result.ok
                ? ContractCopy.copyAgentActionCompleted.text(for: self.language)
                : ContractCopy.copyAgentActionFailed.text(for: self.language)
            self.messages.append(AgentChatMessage(role: .service, text: message))
            await self.refreshToolState()

            let assistantID = UUID()
            self.messages.append(AgentChatMessage(id: assistantID, role: .assistant, text: ""))
            do {
                _ = try await model.respondAfterServiceResult(
                    toolName: toolName,
                    result: result
                ) { [weak self] chunk in
                    await MainActor.run {
                        guard let self,
                              let index = self.messages.firstIndex(where: { $0.id == assistantID })
                        else { return }
                        self.messages[index].text += chunk
                    }
                }
            } catch is CancellationError {
                // The action already completed. A cancelled explanation must not change its result.
            } catch {
                self.errorText = ContractCopy.copyAgentError.text(for: self.language)
            }
            if let index = self.messages.firstIndex(where: { $0.id == assistantID }),
               self.messages[index].text.isEmpty
            {
                self.messages.remove(at: index)
            }
            self.executionTask = nil
            self.stage = .idle
        }
    }

    func cancelPendingAction() {
        guard pendingAction != nil, stage == .awaitingConfirmation else { return }
        Task {
            await gateway.cancelPending()
            self.pendingAction = nil
            self.messages.append(
                AgentChatMessage(
                    role: .service,
                    text: ContractCopy.copyAgentActionCancelled.text(for: self.language)
                )
            )
            await self.refreshToolState()
            self.stage = .idle
        }
    }

    func clear() {
        guard !isBusy else { return }
        stop()
        messages = []
        pendingAction = nil
        executionTask = nil
        toolAudits = []
        errorText = nil
        stage = .idle
        Task {
            await gateway.reset()
            await model.reset()
        }
    }

    private func append(_ chunk: String, to messageID: UUID, generationID: UUID) {
        guard self.generationID == generationID,
              let index = messages.firstIndex(where: { $0.id == messageID })
        else { return }
        messages[index].text += chunk
    }

    private func finishStopped(assistantID: UUID, generationID: UUID) {
        guard self.generationID == generationID else { return }
        stage = .idle
        if let index = messages.firstIndex(where: { $0.id == assistantID }),
           messages[index].text.isEmpty
        {
            messages[index].text = ContractCopy.copyAgentStopped.text(for: language)
        }
    }

    private func refreshToolState() async {
        pendingAction = await gateway.pendingAction()
        toolAudits = await gateway.recentAudits()
    }

    private func runDeferredActions() async {
        while let action = await gateway.takeDeferredAction() {
            guard !Task.isCancelled else { return }
            stage = .executing
            let result = await gateway.executeDeferred(action)
            messages.append(
                AgentChatMessage(role: .service, text: result.summary)
            )
            await refreshToolState()

            let assistantID = UUID()
            messages.append(AgentChatMessage(id: assistantID, role: .assistant, text: ""))
            do {
                _ = try await model.respondAfterServiceResult(
                    toolName: action.toolName,
                    result: result
                ) { [weak self] chunk in
                    await MainActor.run {
                        guard let self,
                              let index = self.messages.firstIndex(where: { $0.id == assistantID })
                        else { return }
                        self.messages[index].text += chunk
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                errorText = ContractCopy.copyAgentError.text(for: language)
            }
            if let index = messages.firstIndex(where: { $0.id == assistantID }),
               messages[index].text.isEmpty
            {
                messages.remove(at: index)
            }
        }
    }

    #if DEBUG
    static func preview() -> AgentChatRuntime {
        let handlers = AgentServiceHandlers(
            monitorSnapshot: {
                AgentServiceResult(ok: true, summary: "Snapshot ready.", data: nil)
            },
            powerStatus: {
                AgentServiceResult(ok: true, summary: "Power ready.", data: nil)
            },
            workspaceFiles: { _, _ in
                AgentServiceResult(ok: true, summary: "Workspace ready.", data: nil)
            },
            screenshots: { _ in
                AgentServiceResult(ok: true, summary: "Screenshots ready.", data: nil)
            },
            clipboardMetadata: { _ in
                AgentServiceResult(ok: true, summary: "Clipboard ready.", data: nil)
            },
            copyText: { _ in
                AgentServiceResult(ok: true, summary: "Copied.", data: nil)
            }
        )
        let gateway = AgentServiceGateway(handlers: handlers)
        let runtime = AgentChatRuntime(model: PreviewAgentModel(), gateway: gateway)
        runtime.messages = [
            AgentChatMessage(
                role: .user,
                text: "查看当前 CPU、内存和电池状态。"
            ),
            AgentChatMessage(
                role: .assistant,
                text: "当前 CPU 使用率 23%，内存占用 11.8 GB / 64 GB，电池 82%，正在充电。"
            ),
            AgentChatMessage(
                role: .user,
                text: "把“项目周报”复制到剪贴板。"
            ),
            AgentChatMessage(
                role: .assistant,
                text: "这个操作会修改剪贴板，需要你的确认。"
            ),
        ]
        runtime.pendingAction = AgentPendingAction(
            id: "preview-copy",
            toolName: "copy_text",
            summary: "Copy 4 characters to the clipboard.",
            characterCount: 4,
            textPreview: "项目周报"
        )
        runtime.toolAudits = [
            AgentToolAudit(
                id: "preview-monitor",
                toolName: "get_monitor_snapshot",
                risk: .readOnly,
                status: .completed,
                detail: "Completed"
            ),
            AgentToolAudit(
                id: "preview-copy",
                toolName: "copy_text",
                risk: .sideEffect,
                status: .pendingConfirmation,
                detail: "Waiting for user confirmation"
            ),
        ]
        runtime.stage = .awaitingConfirmation
        return runtime
    }
    #endif
}

#if DEBUG
private struct PreviewAgentModel: AgentModelServing {
    func respond(
        to prompt: String,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> String {
        await onChunk("Preview response")
        return "Preview response"
    }

    func reset() async {}
    func release() async {}
}
#endif
