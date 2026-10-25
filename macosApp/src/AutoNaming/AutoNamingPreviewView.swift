import SwiftUI

struct AutoNamingPreviewView: View {
    let runtime: AutoNamingRuntime
    let language: AppLanguage
    let modelSetup: ModelSetupRuntime?

    init(
        runtime: AutoNamingRuntime,
        language: AppLanguage,
        modelSetup: ModelSetupRuntime? = nil
    ) {
        self.runtime = runtime
        self.language = language
        self.modelSetup = modelSetup
    }

    var body: some View {
        Group {
            if let modelSetup, !modelSetup.isAIReady {
                ModelSetupPanel(
                    model: modelSetup,
                    language: language,
                    purpose: .naming
                )
            } else {
                VStack(alignment: .leading, spacing: MacTheme.space2) {
                    header
                    Divider().overlay(MacTheme.divider)
                    content
                    footer
                }
            }
        }
        .padding(MacTheme.space2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .fill(MacTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
        .task { await modelSetup?.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTheme.space2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ContractCopy.copyAutoNamingTitle.text(for: language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(ContractCopy.copyAutoNamingSubtitle.text(for: language))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if modelSetup?.isAIReady == true {
                Label(
                    ContractCopy.copyModelSetupStateReady.text(for: language),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MacTheme.successText)
                .accessibilityElement(children: .combine)
            }
            Text(summaryText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch runtime.stage {
        case .analyzing:
            analyzing
        case .applying:
            progress(ContractCopy.copyAutoNamingStatusReady)
        case .undoing:
            progress(ContractCopy.copyAutoNamingActionUndo)
        case .preview, .results:
            previewList
        case .idle:
            Spacer(minLength: 0)
        }
    }

    private var analyzing: some View {
        VStack(spacing: MacTheme.space2) {
            ProgressView()
                .controlSize(.small)
            Text(ContractCopy.copyAutoNamingTitle.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func progress(_ copy: LocalizedCopy) -> some View {
        VStack(spacing: MacTheme.space2) {
            ProgressView()
                .controlSize(.small)
            Text(copy.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var previewList: some View {
        ScrollView {
            LazyVStack(spacing: MacTheme.space1) {
                ForEach(runtime.items, id: \.candidateId) { item in
                    AutoNamingPreviewRow(
                        item: item,
                        isSelected: runtime.selectedIDs.contains(item.candidateId),
                        canSelect: runtime.stage == .preview && item.canSelect,
                        language: language,
                        onToggle: { runtime.toggleSelection(item.candidateId) }
                    )
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: MacTheme.space1) {
            if let message {
                MacAlert(message: message.text, kind: message.kind)
            }
            HStack(spacing: MacTheme.space2) {
                if runtime.stage == .analyzing {
                    MacButton(
                        title: ContractCopy.copyAutoNamingActionCancel.text(for: language),
                        kind: .plain,
                        action: runtime.cancelAnalysis
                    )
                } else {
                    if runtime.stage == .preview {
                        MacButton(
                            title: ContractCopy.copyAutoNamingActionApply.text(for: language),
                            kind: .primary,
                            isEnabled: runtime.canApply
                        ) {
                            Task { await runtime.applySelected() }
                        }
                    }
                    if runtime.canUndo {
                        MacButton(
                            title: ContractCopy.copyAutoNamingActionUndo.text(for: language),
                            kind: .plain
                        ) {
                            Task { await runtime.undoLastRun() }
                        }
                    }
                    MacButton(
                        title: ContractCopy.copyAutoNamingActionClose.text(for: language),
                        kind: .plain,
                        isEnabled: !runtime.busy,
                        action: runtime.reset
                    )
                }
                Spacer(minLength: 0)
                if let run = runtime.lastRunResult {
                    Text("\(run.successCount) / \(run.items.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("\(run.successCount) / \(run.items.count)")
                }
            }
        }
    }

    private var summaryText: String {
        let ready = runtime.items.count(where: \.canSelect)
        let selected = runtime.selectedIDs.count
        return "\(selected) / \(ready)"
    }

    private var message: (text: String, kind: MacAlertKind)? {
        if let error = runtime.errorMessage {
            return (error.text(for: language), .error)
        }
        if let info = runtime.infoMessage {
            return (info.text(for: language), .info)
        }
        return nil
    }
}

private struct AutoNamingPreviewRow: View {
    let item: AutoNamingPreviewItem
    let isSelected: Bool
    let canSelect: Bool
    let language: AppLanguage
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MacTheme.space2) {
            Toggle(
                ContractCopy.copyAutoNamingActionSelect.text(for: language),
                isOn: Binding(
                    get: { isSelected },
                    set: { enabled in
                        if enabled != isSelected { onToggle() }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!canSelect)
            .accessibilityLabel(ContractCopy.copyAutoNamingActionSelect.text(for: language))
            .accessibilityValue(item.originalName)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MacTheme.space1) {
                    Text(item.originalName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(MacTheme.textPrimary)
                        .accessibilityLabel(
                            "\(ContractCopy.copyAutoNamingLabelOriginal.text(for: language)): \(item.originalName)"
                        )
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text(item.targetName ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(item.canSelect ? MacTheme.brand : .secondary)
                        .accessibilityLabel(
                            "\(ContractCopy.copyAutoNamingLabelTarget.text(for: language)): \(item.targetName ?? "—")"
                        )
                    Spacer(minLength: 0)
                    Text(statusText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                Text(detailText)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                if !item.risks.isEmpty || item.errorCode != nil {
                    HStack(spacing: MacTheme.space1) {
                        ForEach(riskTexts, id: \.self) { risk in
                            Text(risk)
                                .font(.system(size: 8, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(MacTheme.elevated)
                                )
                                .foregroundStyle(risk == errorText ? .red : MacTheme.textSecondary)
                        }
                        if let errorCode = item.errorCode {
                            Text(errorCode)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        switch item.status {
        case .ready: ContractCopy.copyAutoNamingStatusReady.text(for: language)
        case .blocked: ContractCopy.copyAutoNamingStatusBlocked.text(for: language)
        case .renamed: ContractCopy.copyAutoNamingStatusRenamed.text(for: language)
        case .failed: ContractCopy.copyAutoNamingStatusFailed.text(for: language)
        case .undone: ContractCopy.copyAutoNamingStatusUndone.text(for: language)
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .ready, .renamed: MacTheme.brand
        case .blocked, .failed: .red
        case .undone: .secondary
        }
    }

    private var detailText: String {
        var parts: [String] = []
        if !item.evidence.isEmpty {
            parts.append("\(ContractCopy.copyAutoNamingLabelEvidence.text(for: language)): \(item.evidence.joined(separator: ", "))")
        }
        if !item.warnings.isEmpty {
            parts.append("\(ContractCopy.copyAutoNamingLabelWarnings.text(for: language)): \(item.warnings.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    private var riskTexts: [String] {
        item.risks.sorted { $0.rawValue < $1.rawValue }.map { risk in
            switch risk {
            case .scannedDocument: ContractCopy.copyAutoNamingRiskScanned.text(for: language)
            case .mixedContent: ContractCopy.copyAutoNamingRiskMixed.text(for: language)
            case .lowConfidence: ContractCopy.copyAutoNamingRiskLowConfidence.text(for: language)
            case .conflict: ContractCopy.copyAutoNamingRiskConflict.text(for: language)
            case .fallbackModel: ContractCopy.copyAutoNamingRiskFallback.text(for: language)
            case .truncatedInput: ContractCopy.copyAutoNamingRiskTruncated.text(for: language)
            case .promptInjection: ContractCopy.copyAutoNamingRiskPromptInjection.text(for: language)
            case .fileChanged: ContractCopy.copyAutoNamingStatusFailed.text(for: language)
            }
        }
    }

    private var errorText: String? {
        item.errorCode == nil ? nil : ContractCopy.copyAutoNamingStatusFailed.text(for: language)
    }
}
