import AppKit
import SwiftUI

struct LocalModelPackagesCard: View {
    let runtime: AppRuntime

    @State private var busyTier: LocalModelTier?
    @State private var failure: String?

    var body: some View {
        MacCard {
            MacSectionTitle(text: ContractCopy.copyGeneralLocalModelTitle.text(for: runtime.language))
            Text(ContractCopy.copyGeneralLocalModelSummary.text(for: runtime.language))
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(LocalModelTier.allCases, id: \.rawValue) { tier in
                modelRow(tier)
            }

            if runtime.activeModelTier == .heavy30BA3B {
                MacAlert(
                    message: ContractCopy.copyGeneralLocalModelAgentDisabled.text(for: runtime.language),
                    kind: .warning
                )
            }
            if let failure {
                MacAlert(message: failure, kind: .error)
            }
        }
    }

    private func modelRow(_ tier: LocalModelTier) -> some View {
        HStack(spacing: MacTheme.space2) {
            VStack(alignment: .leading, spacing: MacTheme.space1) {
                Text(title(for: tier))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(
                    String(
                        format: ContractCopy.copyGeneralLocalModelMinimum.text(for: runtime.language),
                        Int(tier.minimumPhysicalMemoryBytes / (1_024 * 1_024 * 1_024))
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer(minLength: MacTheme.space2)
            control(for: tier)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func control(for tier: LocalModelTier) -> some View {
        if busyTier == tier {
            Text(ContractCopy.copyGeneralLocalModelVerifying.text(for: runtime.language))
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
        } else if runtime.activeModelTier == tier {
            Text(ContractCopy.copyGeneralLocalModelActive.text(for: runtime.language))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.successText)
        } else if !runtime.supportsLocalModelTier(tier) {
            Text(ContractCopy.copyGeneralLocalModelUnsupported.text(for: runtime.language))
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
        } else if runtime.hasRegisteredLocalModelPackage(tier: tier) {
            MacButton(title: ContractCopy.copyGeneralLocalModelUse.text(for: runtime.language)) {
                activate(tier)
            }
            .disabled(busyTier != nil)
        } else {
            MacButton(title: ContractCopy.copyGeneralLocalModelImport.text(for: runtime.language)) {
                choosePackage(for: tier)
            }
            .disabled(busyTier != nil)
        }
    }

    private func choosePackage(for tier: LocalModelTier) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = ContractCopy.copyGeneralLocalModelImport.text(for: runtime.language)
        panel.message = title(for: tier)
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        busyTier = tier
        failure = nil
        Task { @MainActor in
            defer { busyTier = nil }
            do {
                _ = try await runtime.importLocalModelPackage(
                    directory: directory,
                    tier: tier
                )
            } catch {
                failure = "\(ContractCopy.copyGeneralLocalModelFailed.text(for: runtime.language)) \(error.localizedDescription)"
            }
        }
    }

    private func activate(_ tier: LocalModelTier) {
        busyTier = tier
        failure = nil
        Task { @MainActor in
            defer { busyTier = nil }
            do {
                _ = try await runtime.activateRegisteredLocalModelPackage(tier: tier)
            } catch {
                failure = "\(ContractCopy.copyGeneralLocalModelFailed.text(for: runtime.language)) \(error.localizedDescription)"
            }
        }
    }

    private func title(for tier: LocalModelTier) -> String {
        switch tier {
        case .compact2B: "Qwen3-VL-2B-Instruct-4bit"
        case .balanced4B: "Qwen3-VL-4B-Instruct-4bit"
        case .highQuality8B: "Qwen3-VL-8B-Instruct-4bit"
        case .heavy30BA3B: "Qwen3-VL-30B-A3B-Instruct-4bit"
        }
    }
}
