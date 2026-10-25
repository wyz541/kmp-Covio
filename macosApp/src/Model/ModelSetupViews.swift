import AppKit
import SwiftUI

enum ModelSetupPurpose {
    case naming
    case agent
}

/// Content-only model setup panel.
/// The caller owns the surrounding card or surface.
struct ModelSetupPanel: View {
    let model: ModelSetupRuntime
    let language: AppLanguage
    let purpose: ModelSetupPurpose

    var body: some View {
        let state = model.preferredState
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            HStack(alignment: .firstTextBaseline, spacing: MacTheme.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ContractCopy.copyModelSetupTitle.text(for: language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(state.info.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer(minLength: 0)
                if model.selectedTier == state.tier {
                    Text(ContractCopy.copyModelSetupRecommended.text(for: language))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MacTheme.brand)
                }
            }

            Text(ContractCopy.copyModelSetupSummary.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ModelSetupFacts(state: state, language: language)
                .accessibilityElement(children: .combine)

            Text(ContractCopy.copyModelSetupNetwork.text(for: language))
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ModelSetupStatusView(state: state, language: language)

            if purpose == .agent,
               state.isReady,
               model.activeTier == state.tier,
               !model.activeModelSupportsAgent
            {
                MacAlert(
                    message: ContractCopy.copyGeneralLocalModelAgentDisabled.text(for: language),
                    kind: .warning
                )
                Text(ContractCopy.copyModelSetupSelectModel.text(for: language))
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.textSecondary)
            } else if state.phase == .unsupported {
                MacAlert(
                    message: ContractCopy.copyGeneralLocalModelUnsupported.text(for: language),
                    kind: .warning
                )
            } else if let failure = state.failure {
                MacAlert(message: ModelSetupPresentation.errorText(failure, language: language), kind: .error)
            }

            controls(for: state)
        }
        .task { await model.refresh() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controls(for state: ModelSetupState) -> some View {
        if state.isReady, model.activeTier != state.tier {
            HStack(spacing: MacTheme.space2) {
                MacButton(
                    title: ContractCopy.copyGeneralLocalModelUse.text(for: language),
                    kind: .primary,
                    isEnabled: !model.isBusy
                ) {
                    Task { await model.activate(state.tier) }
                }
                .accessibilityHint(state.info.displayName)
            }
        } else {
            switch state.phase {
            case .notInstalled:
                HStack(spacing: MacTheme.space2) {
                    downloadButton(state)
                    importButton(state)
                }
            case .downloading:
                MacButton(
                    title: ContractCopy.copyModelSetupActionPause.text(for: language),
                    isEnabled: !model.isBusy || model.operationTier == state.tier
                ) {
                    Task { await model.pause() }
                }
                .accessibilityHint(ContractCopy.copyModelSetupStatePaused.text(for: language))
            case .paused:
                HStack(spacing: MacTheme.space2) {
                    resumeButton(state)
                    importButton(state)
                }
            case .verifying:
                EmptyView()
            case .ready:
                EmptyView()
            case .failed:
                HStack(spacing: MacTheme.space2) {
                    resumeButton(state)
                    importButton(state)
                }
            case .unsupported:
                EmptyView()
            }
        }
    }

    private func downloadButton(_ state: ModelSetupState) -> some View {
        MacButton(
            title: ContractCopy.copyModelSetupActionDownload.text(for: language),
            kind: .primary,
            isEnabled: !model.isBusy
        ) {
            Task { await model.download(state.tier) }
        }
        .accessibilityHint(ContractCopy.copyModelSetupNetwork.text(for: language))
    }

    private func resumeButton(_ state: ModelSetupState) -> some View {
        MacButton(
            title: state.phase == .failed
                ? ContractCopy.copyModelSetupActionRetry.text(for: language)
                : ContractCopy.copyModelSetupActionResume.text(for: language),
            kind: .primary,
            isEnabled: !model.isBusy
        ) {
            Task { await model.download(state.tier) }
        }
    }

    private func importButton(_ state: ModelSetupState) -> some View {
        MacButton(
            title: ContractCopy.copyGeneralLocalModelImport.text(for: language),
            isEnabled: !model.isBusy
        ) {
            choosePackage(for: state.tier)
        }
    }

    private func choosePackage(for tier: LocalModelTier) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = ContractCopy.copyGeneralLocalModelImport.text(for: language)
        panel.message = model.state(for: tier).info.displayName
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await model.importPackage(tier: tier, directory: directory) }
    }
}

struct ModelSetupInlineCard: View {
    let model: ModelSetupRuntime
    let language: AppLanguage
    var purpose: ModelSetupPurpose = .naming

    var body: some View {
        MacCard {
            ModelSetupPanel(model: model, language: language, purpose: purpose)
        }
    }
}

struct ModelSetupSettingsCard: View {
    let model: ModelSetupRuntime
    let language: AppLanguage

    @State private var removal: LocalModelTier?

    var body: some View {
        MacCard {
            MacSectionTitle(text: ContractCopy.copyGeneralLocalModelTitle.text(for: language))
            Text(ContractCopy.copyGeneralLocalModelSummary.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.orderedStates) { state in
                modelRow(state)
                if state.id != model.orderedStates.last?.id {
                    Divider().overlay(MacTheme.divider)
                }
            }

            if model.activeTier == .heavy30BA3B {
                MacAlert(
                    message: ContractCopy.copyGeneralLocalModelAgentDisabled.text(for: language),
                    kind: .warning
                )
            }
        }
        .task { await model.refresh() }
        .alert(
            ContractCopy.copyModelSetupRemoveTitle.text(for: language),
            isPresented: Binding(
                get: { removal != nil },
                set: { if !$0 { removal = nil } }
            ),
            presenting: removal
        ) { tier in
            Button(ContractCopy.copyModelSetupActionRemove.text(for: language), role: .destructive) {
                removal = nil
                Task { await model.remove(tier) }
            }
            Button(ContractCopy.copyStateCancel.text(for: language), role: .cancel) {
                removal = nil
            }
        } message: { _ in
            Text(ContractCopy.copyModelSetupRemoveBody.text(for: language))
        }
        .accessibilityElement(children: .contain)
    }

    private func modelRow(_ state: ModelSetupState) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            HStack(alignment: .firstTextBaseline, spacing: MacTheme.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.info.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(
                        String(
                            format: ContractCopy.copyGeneralLocalModelMinimum.text(for: language),
                            Int(state.info.minimumPhysicalMemoryBytes / (1_024 * 1_024 * 1_024))
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer(minLength: MacTheme.space2)
                Text(ModelSetupPresentation.statusText(state, language: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ModelSetupPresentation.statusColor(state.phase))
            }

            ModelSetupFacts(state: state, language: language)
                .accessibilityElement(children: .combine)

            if state.phase == .unsupported {
                MacAlert(
                    message: ContractCopy.copyGeneralLocalModelUnsupported.text(for: language),
                    kind: .warning
                )
            } else if let failure = state.failure {
                MacAlert(message: ModelSetupPresentation.errorText(failure, language: language), kind: .error)
            }

            rowControls(state)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func rowControls(_ state: ModelSetupState) -> some View {
        switch state.phase {
        case .notInstalled:
            HStack(spacing: MacTheme.space2) {
                downloadButton(state)
                importButton(state)
            }
        case .downloading:
            MacButton(
                title: ContractCopy.copyModelSetupActionPause.text(for: language),
                isEnabled: !model.isBusy || model.operationTier == state.tier
            ) {
                Task { await model.pause() }
            }
        case .paused:
            HStack(spacing: MacTheme.space2) {
                resumeButton(state)
                importButton(state)
                removeButton(state)
            }
        case .verifying:
            EmptyView()
        case .ready:
            HStack(spacing: MacTheme.space2) {
                if model.activeTier != state.tier {
                    MacButton(
                        title: ContractCopy.copyGeneralLocalModelUse.text(for: language),
                        kind: .primary,
                        isEnabled: !model.isBusy
                    ) {
                        Task { await model.activate(state.tier) }
                    }
                }
                if model.activeTier == state.tier {
                    Text(ContractCopy.copyGeneralLocalModelActive.text(for: language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacTheme.successText)
                }
                if !model.isBundled(state.tier) {
                    removeButton(state)
                }
            }
        case .failed:
            HStack(spacing: MacTheme.space2) {
                resumeButton(state)
                importButton(state)
                removeButton(state)
            }
        case .unsupported:
            EmptyView()
        }
    }

    private func downloadButton(_ state: ModelSetupState) -> some View {
        MacButton(
            title: ContractCopy.copyModelSetupActionDownload.text(for: language),
            kind: .primary,
            isEnabled: !model.isBusy
        ) {
            Task { await model.download(state.tier) }
        }
        .accessibilityHint(ContractCopy.copyModelSetupNetwork.text(for: language))
    }

    private func resumeButton(_ state: ModelSetupState) -> some View {
        MacButton(
            title: state.phase == .failed
                ? ContractCopy.copyModelSetupActionRetry.text(for: language)
                : ContractCopy.copyModelSetupActionResume.text(for: language),
            kind: .primary,
            isEnabled: !model.isBusy
        ) {
            Task { await model.download(state.tier) }
        }
    }

    private func importButton(_ state: ModelSetupState) -> some View {
        MacButton(
            title: ContractCopy.copyGeneralLocalModelImport.text(for: language),
            isEnabled: !model.isBusy
        ) {
            choosePackage(for: state.tier)
        }
    }

    private func removeButton(_ state: ModelSetupState) -> some View {
        MacButton(
            title: ContractCopy.copyModelSetupActionRemove.text(for: language),
            kind: .plain,
            isEnabled: !model.isBusy
        ) {
            removal = state.tier
        }
    }

    private func choosePackage(for tier: LocalModelTier) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = ContractCopy.copyGeneralLocalModelImport.text(for: language)
        panel.message = model.state(for: tier).info.displayName
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await model.importPackage(tier: tier, directory: directory) }
    }
}

private struct ModelSetupFacts: View {
    let state: ModelSetupState
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                String(
                    format: ContractCopy.copyModelSetupSize.text(for: language),
                    ModelSetupPresentation.byteCount(state.info.totalBytes)
                )
            )
            Text(
                String(
                    format: ContractCopy.copyModelSetupLicense.text(for: language),
                    state.info.license
                )
            )
        }
        .font(.system(size: 10))
        .foregroundStyle(MacTheme.textSecondary)
    }
}

private struct ModelSetupStatusView: View {
    let state: ModelSetupState
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space1) {
            switch state.phase {
            case .downloading:
                ProgressView(value: state.fractionCompleted)
                    .progressViewStyle(.linear)
                    .accessibilityLabel(ContractCopy.copyModelSetupStateDownloading.text(for: language))
                    .accessibilityValue(ModelSetupPresentation.progressAccessibilityValue(state))
                Text(ModelSetupPresentation.statusText(state, language: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.brand)
            case .verifying:
                HStack(spacing: MacTheme.space1) {
                    ProgressView().controlSize(.small)
                    Text(ContractCopy.copyModelSetupStateVerifying.text(for: language))
                        .font(.system(size: 10))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            case .ready:
                Label(
                    ContractCopy.copyModelSetupStateReady.text(for: language),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.successText)
            case .paused, .failed, .unsupported, .notInstalled:
                Text(ModelSetupPresentation.statusText(state, language: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ModelSetupPresentation.statusColor(state.phase))
            }
        }
    }
}

enum ModelSetupPresentation {
    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func statusText(_ state: ModelSetupState, language: AppLanguage) -> String {
        switch state.phase {
        case .notInstalled:
            ContractCopy.copyModelSetupStateNotInstalled.text(for: language)
        case .unsupported:
            ContractCopy.copyGeneralLocalModelUnsupported.text(for: language)
        case .downloading:
            String(
                format: ContractCopy.copyModelSetupStateDownloading.text(for: language),
                Int((state.fractionCompleted * 100).rounded())
            )
        case .paused:
            ContractCopy.copyModelSetupStatePaused.text(for: language)
        case .verifying:
            ContractCopy.copyModelSetupStateVerifying.text(for: language)
        case .ready:
            ContractCopy.copyModelSetupStateReady.text(for: language)
        case .failed:
            ContractCopy.copyModelSetupStateFailed.text(for: language)
        }
    }

    static func progressAccessibilityValue(_ state: ModelSetupState) -> String {
        "\(Int((state.fractionCompleted * 100).rounded()))%"
    }

    static func statusColor(_ phase: ModelSetupPhase) -> Color {
        switch phase {
        case .ready: MacTheme.successText
        case .failed, .unsupported: MacTheme.errorText
        case .downloading, .verifying: MacTheme.brand
        case .notInstalled, .paused: MacTheme.textSecondary
        }
    }

    static func errorText(_ failure: ModelSetupFailure, language: AppLanguage) -> String {
        switch failure {
        case .insufficientDisk:
            ContractCopy.copyModelSetupErrorDisk.text(for: language)
        case .insufficientMemory:
            ContractCopy.copyModelSetupErrorMemory.text(for: language)
        case .network:
            ContractCopy.copyModelSetupErrorNetwork.text(for: language)
        case .revisionMismatch:
            ContractCopy.copyModelSetupErrorRevision.text(for: language)
        case .verification:
            ContractCopy.copyModelSetupErrorVerification.text(for: language)
        case .activation:
            ContractCopy.copyModelSetupErrorActivation.text(for: language)
        case .generic:
            ContractCopy.copyModelSetupErrorGeneric.text(for: language)
        }
    }
}
