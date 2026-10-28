import AppKit
import SwiftUI
import kmpDomain

/// `Monitor` 网格中的屏幕卡片。
///
/// 卡片显示状态、亮度和显示功耗。
/// 第三段打开详情与持久化设置。
struct MonitorDisplayCard: View {
    let display: MonitorSnapshot.Display
    let language: AppLanguage
    let powerModel: (any PowerManagementModel)?
    let popoverCoordinator: HubPopoverCoordinator?
    var popoverInitiallyPresented = false

    @AppStorage("monitor.display.detailsExpanded") private var detailsExpanded = false
    @State private var detailsPresented = false
    @State private var popoverID = UUID().uuidString
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: toggleDetails) {
            MonitorCardShell(
                kind: .display,
                accent: accent,
                language: language,
                combinesAccessibility: false
            ) {
                VStack(alignment: .leading, spacing: MacTheme.space2) {
                    HStack(spacing: MacTheme.space3) {
                        screenPreview
                        VStack(alignment: .leading, spacing: MacTheme.space2) {
                            Text(stateText)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MacTheme.textPrimary)
                            HStack(spacing: MacTheme.space2) {
                                metricPill(
                                    title: ContractCopy.copyMonitorDisplayBrightness.text(for: language),
                                    value: brightnessText
                                )
                                metricPill(
                                    title: ContractCopy.copyMonitorDisplayPower.text(for: language),
                                    value: powerText
                                )
                            }
                            Text(display.powerWatts == nil
                                ? ContractCopy.copyMonitorDisplayPowerUnavailable.text(for: language)
                                : MonitorPowerFormat.watts(display.powerWatts))
                                .font(.system(size: 9))
                                .foregroundStyle(MacTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    detailRows
                    actionRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onKeyPress(.return) {
            toggleDetails()
            return .handled
        }
        .onKeyPress(.space) {
            toggleDetails()
            return .handled
        }
        .onAppear {
            setDetailsPresented(popoverInitiallyPresented || detailsExpanded)
        }
        .onChange(of: detailsPresented) { _, presented in
            detailsExpanded = presented
            if !presented {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .onChange(of: popoverCoordinator?.dismissalRequest) { _, _ in
            setDetailsPresented(false)
        }
        .popover(isPresented: $detailsPresented, arrowEdge: .trailing) {
            MonitorDisplayDetailPanel(
                display: display,
                language: language,
                powerModel: powerModel,
                onClose: { setDetailsPresented(false) }
            )
            .onAppear {
                popoverCoordinator?.setPresented(true, id: popoverID)
            }
            .onDisappear {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.focusRing, lineWidth: 2)
                    .padding(1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(actionText)
        .onDisappear {
            popoverCoordinator?.setPresented(false, id: popoverID)
        }
    }

    private var accent: Color {
        MacTheme.color(ContractColors.tokenColorBrand)
    }

    private var screenPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(accent.opacity(0.38), lineWidth: 1)
                )
            VStack(spacing: 4) {
                Image(systemName: display.state == .asleep ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(brightnessText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(accent)
        }
        .frame(width: 78, height: 56)
        .accessibilityHidden(true)
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(MacTheme.textSecondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, MacTheme.space2)
        .padding(.vertical, 4)
        .background(MacTheme.surface.opacity(0.54), in: Capsule())
    }

    private var detailRows: some View {
        VStack(spacing: 4) {
            detailRow(
                ContractCopy.copyPowerStatusExternalDisplay.text(for: language),
                externalDisplayText
            )
            detailRow(ContractCopy.copyMonitorDisplayResolution.text(for: language), resolutionText)
            detailRow(
                ContractCopy.copyMonitorDisplayRefreshRate.text(for: language),
                refreshRateText
            )
        }
        .font(.system(size: 9, weight: .medium))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: MacTheme.space2) {
            Text(title).foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: MacTheme.space1)
            Text(value)
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 4) {
            Text(actionText)
                .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)
                .rotationEffect(detailsPresented ? .degrees(90) : .zero)
                .animation(.easeInOut(duration: 0.22), value: detailsPresented)
        }
        .font(.system(size: 9, weight: .medium))
        .frame(height: 12)
    }

    private var stateText: String {
        switch display.state {
        case .active: ContractCopy.copyMonitorDisplayStatusActive.text(for: language)
        case .asleep: ContractCopy.copyMonitorDisplayStatusAsleep.text(for: language)
        case .offline: ContractCopy.copyMonitorDisplayStatusOffline.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var brightnessText: String {
        display.brightnessPercent.map { "\(Int(min(100, max(0, $0)).rounded()))%" }
            ?? ContractCopy.copyMonitorUnavailable.text(for: language)
    }

    private var powerText: String {
        MonitorPowerFormat.watts(display.powerWatts)
    }

    private var externalDisplayText: String {
        guard let count = display.externalDisplayCount else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return count == 0
            ? ContractCopy.copyPowerStatusNoExternalDisplay.text(for: language)
            : String(count)
    }

    private var resolutionText: String {
        guard let width = display.pixelWidth, let height = display.pixelHeight else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return "\(width) × \(height)"
    }

    private var refreshRateText: String {
        guard let refreshRate = display.refreshRate, refreshRate.isFinite else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return String(format: "%.0f Hz", refreshRate)
    }

    private var actionText: String {
        (detailsPresented
            ? ContractCopy.copyMonitorDisplayDetailsCollapse
            : ContractCopy.copyMonitorDisplayDetailsExpand)
            .text(for: language)
    }

    private var accessibilityLabel: String {
        [
            ContractCopy.copyMonitorTitleDisplay.text(for: language),
            stateText,
            "\(ContractCopy.copyMonitorDisplayBrightness.text(for: language)) \(brightnessText)",
            "\(ContractCopy.copyMonitorDisplayPower.text(for: language)) \(powerText)",
        ].joined(separator: ", ")
    }

    private func toggleDetails() {
        setDetailsPresented(!detailsPresented)
    }

    private func setDetailsPresented(_ presented: Bool) {
        detailsPresented = presented
        popoverCoordinator?.setPresented(presented, id: popoverID)
    }
}

private struct MonitorDisplayDetailPanel: View {
    let display: MonitorSnapshot.Display
    let language: AppLanguage
    let powerModel: (any PowerManagementModel)?
    let onClose: () -> Void

    private var panelHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 800
        return min(780, max(420, available - 140))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.space3) {
                    statusCard
                    if let powerModel {
                        actionsCard(model: powerModel)
                        closedLidCard(model: powerModel)
                        Text(ContractCopy.copyMonitorDisplaySafetyNote.text(for: language))
                            .font(.caption)
                            .foregroundStyle(MacTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, MacTheme.space4)
            }
            .scrollIndicators(.automatic)
        }
        .padding(MacTheme.space4)
        .frame(width: 560, height: panelHeight)
        .background(
            MacTheme.surface.opacity(0.98),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.8), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: displaySymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(display.state == .asleep ? MacTheme.textSecondary : MacTheme.brand)
            Text(ContractCopy.copyMonitorDisplayDetailsTitle.text(for: language))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacTheme.textSecondary)
            .accessibilityLabel(ContractCopy.copyMonitorPowerDetailsClose.text(for: language))
        }
        .frame(height: 26)
    }

    private var statusCard: some View {
        DisplaySettingsCard {
            DisplaySectionHeader(
                title: ContractCopy.copyMonitorDisplayStatusTitle.text(for: language),
                symbol: "display"
            )
            HStack(spacing: MacTheme.space3) {
                Image(systemName: displaySymbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(display.state == .asleep ? MacTheme.textSecondary : MacTheme.brand)
                    .frame(width: 62, height: 62)
                    .background(MacTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: MacTheme.space1) {
                    Text(stateText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text("\(ContractCopy.copyMonitorDisplayBrightness.text(for: language)) · \(brightnessText)")
                        .font(.callout)
                        .foregroundStyle(MacTheme.textSecondary)
                    Text("\(ContractCopy.copyMonitorDisplayPower.text(for: language)) \(powerText)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(MacTheme.textPrimary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: MacTheme.space4) {
                statusMetric(
                    ContractCopy.copyPowerStatusExternalDisplay.text(for: language),
                    externalDisplayText
                )
                statusMetric(ContractCopy.copyMonitorDisplayResolution.text(for: language), resolutionText)
                statusMetric(ContractCopy.copyMonitorDisplayRefreshRate.text(for: language), refreshRateText)
            }
            if display.powerWatts == nil {
                Text(ContractCopy.copyMonitorDisplayPowerUnavailable.text(for: language))
                    .font(.caption)
                    .foregroundStyle(MacTheme.textSecondary)
            }
        }
    }

    private func actionsCard(model: any PowerManagementModel) -> some View {
        DisplaySettingsCard {
            DisplaySectionHeader(
                title: ContractCopy.copyMonitorDisplayActionsTitle.text(for: language),
                symbol: "switch.2"
            )
            HStack(spacing: MacTheme.space2) {
                MacButton(
                    title: ContractCopy.copyMonitorDisplayActionSleep.text(for: language),
                    kind: .secondary,
                    minimumHitHeight: 44
                ) {
                    model.displaySleepNow()
                }
                MacButton(
                    title: ContractCopy.copyMonitorDisplayActionSettings.text(for: language),
                    kind: .secondary,
                    minimumHitHeight: 44
                ) {
                    model.openDisplaySettings()
                }
            }
        }
    }

    private func closedLidCard(model: any PowerManagementModel) -> some View {
        DisplaySettingsCard {
            DisplaySectionHeader(
                title: ContractCopy.copyPowerSectionClosedLid.text(for: language),
                symbol: "laptopcomputer"
            )

            if model.helperStatus != .match || model.helperServiceState != .enabled {
                MacAlert(
                    message: ContractCopy.copyPowerAlertHelperMissing.text(for: language),
                    kind: .warning,
                    language: language
                )
            }
            if !model.sleepProtectionEnabled || !model.powerConfig.enabled {
                MacAlert(
                    message: ContractCopy.copyPowerErrorMasterOff.text(for: language),
                    kind: .warning,
                    language: language
                )
            }

            MacSettingRow(
                title: ContractCopy.copyMonitorDisplayKeepAwake.text(for: language),
                description: ContractCopy.copyMonitorDisplayKeepAwakeHint.text(for: language)
            ) {
                MacSwitch(
                    label: ContractCopy.copyMonitorDisplayKeepAwake.text(for: language),
                    isOn: Binding(
                        get: { model.displayConfig.keepAwakeWhenLidClosed },
                        set: { model.setDisplayKeepAwakeWhenLidClosed($0) }
                    ),
                    isEnabled: model.helperStatus == .match || !model.displayConfig.keepAwakeWhenLidClosed,
                    size: .regular
                )
            }

            Divider().overlay(MacTheme.divider)

            MacSettingRow(title: ContractCopy.copyMonitorDisplayMode.text(for: language)) {
                Picker(
                    ContractCopy.copyMonitorDisplayMode.text(for: language),
                    selection: Binding(
                        get: { effectiveMode(for: model) },
                        set: { mode in
                            if mode == .system {
                                model.setDisplayKeepAwakeWhenLidClosed(false)
                            } else {
                                model.setDisplayClosedLidMode(mode)
                            }
                        }
                    )
                ) {
                    Text(ContractCopy.copyMonitorDisplayModeSystem.text(for: language))
                        .tag(ClosedLidDisplayMode.system)
                    Text(ContractCopy.copyMonitorDisplayModeOff.text(for: language))
                        .tag(ClosedLidDisplayMode.displayOff)
                    Text(ContractCopy.copyMonitorDisplayModeBlack.text(for: language))
                        .tag(ClosedLidDisplayMode.blackScreenPipeline)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 230, alignment: .trailing)
                .disabled(
                    !model.displayConfig.keepAwakeWhenLidClosed ||
                        model.helperStatus != .match
                )
            }

            if !model.closedLidZeroBrightnessAvailability.isAvailable {
                Text(ContractCopy.copyPowerRulesClosedLidZeroBrightnessUnavailable.text(for: language))
                    .font(.caption)
                    .foregroundStyle(MacTheme.warningText)
            }

            Divider().overlay(MacTheme.divider)

            MacSettingRow(
                title: ContractCopy.copyPowerRulesExternalDisplay.text(for: language),
                description: ContractCopy.copyPowerRulesExternalDisplayHint.text(for: language)
            ) {
                MacSwitch(
                    label: ContractCopy.copyPowerRulesExternalDisplay.text(for: language),
                    isOn: Binding(
                        get: { model.displayConfig.pauseWhenExternalDisplayConnected },
                        set: { model.setDisplayPauseWithExternalDisplay($0) }
                    ),
                    isEnabled: model.displayConfig.keepAwakeWhenLidClosed &&
                        model.helperStatus == .match
                )
            }

            Divider().overlay(MacTheme.divider)

            helperRow(model: model)

            if let error = model.closedLidZeroBrightnessError, !error.isEmpty,
               model.displayConfig.closedLidDisplayMode == .blackScreenPipeline {
                MacAlert(
                    message: "\(ContractCopy.copyPowerRulesClosedLidZeroBrightnessFailed.text(for: language)) \(error)",
                    kind: .warning,
                    language: language
                )
            }

            if model.displayConfig.keepAwakeWhenLidClosed {
                Divider().overlay(MacTheme.divider)
                sessionRow(model: model)
            }
        }
    }

    private func helperRow(model: any PowerManagementModel) -> some View {
        MacSettingRow(
            title: ContractCopy.copyPowerStatusHelper.text(for: language),
            description: ContractCopy.copyPowerStatusHelperHint.text(for: language)
        ) {
            HStack(spacing: MacTheme.space2) {
                Text(helperValue(model))
                    .font(.callout)
                    .foregroundStyle(helperNeedsAction(model) ? MacTheme.warningText : MacTheme.textSecondary)
                    .lineLimit(1)
                if helperNeedsAction(model) {
                    MacButton(
                        title: helperActionTitle(model),
                        kind: .primary,
                        isEnabled: !model.busy,
                        minimumHitHeight: 44
                    ) {
                        if model.helperServiceState == .requiresApproval {
                            model.openHelperApproval()
                        } else {
                            model.installHelper()
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(model: any PowerManagementModel) -> some View {
        HStack(alignment: .center, spacing: MacTheme.space3) {
            VStack(alignment: .leading, spacing: MacTheme.space1) {
                Text(ContractCopy.copyPowerSectionClosedLid.text(for: language))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(sessionStatusText(model))
                    .font(.caption)
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer(minLength: MacTheme.space2)
            if model.hasManualSession, model.sessionMode == .lid {
                MonitorGlassActionButton(
                    title: ContractCopy.copyPowerSessionEnd.text(for: language),
                    symbol: "stop.fill"
                ) {
                    model.endSession()
                }
            } else {
                MonitorGlassActionButton(
                    title: ContractCopy.copyMonitorDisplaySessionStart.text(for: language),
                    symbol: "play.fill",
                    isEnabled: canStartClosedLidSession(model)
                ) {
                    _ = model.startSession(mode: .lid, duration: .untilOff)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private func statusMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(MacTheme.textSecondary)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var displaySymbol: String {
        switch display.state {
        case .active: "display"
        case .asleep: "display"
        case .offline: "display.trianglebadge.exclamationmark"
        case .unknown: "display"
        }
    }

    private var stateText: String {
        switch display.state {
        case .active: ContractCopy.copyMonitorDisplayStatusActive.text(for: language)
        case .asleep: ContractCopy.copyMonitorDisplayStatusAsleep.text(for: language)
        case .offline: ContractCopy.copyMonitorDisplayStatusOffline.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var brightnessText: String {
        display.brightnessPercent.map { "\(Int(min(100, max(0, $0)).rounded()))%" }
            ?? ContractCopy.copyMonitorUnavailable.text(for: language)
    }

    private var powerText: String {
        MonitorPowerFormat.watts(display.powerWatts)
    }

    private var externalDisplayText: String {
        guard let count = display.externalDisplayCount else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return count == 0
            ? ContractCopy.copyPowerStatusNoExternalDisplay.text(for: language)
            : String(count)
    }

    private var resolutionText: String {
        guard let width = display.pixelWidth, let height = display.pixelHeight else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return "\(width) × \(height)"
    }

    private var refreshRateText: String {
        guard let refreshRate = display.refreshRate, refreshRate.isFinite else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return String(format: "%.0f Hz", refreshRate)
    }

    private func effectiveMode(for model: any PowerManagementModel) -> ClosedLidDisplayMode {
        guard model.displayConfig.keepAwakeWhenLidClosed else { return .system }
        return model.displayConfig.closedLidDisplayMode == .system
            ? .blackScreenPipeline
            : model.displayConfig.closedLidDisplayMode
    }

    private func canStartClosedLidSession(_ model: any PowerManagementModel) -> Bool {
        model.sleepProtectionEnabled &&
            model.powerConfig.enabled &&
            model.displayConfig.keepAwakeWhenLidClosed &&
            model.helperStatus == .match
    }

    private func sessionStatusText(_ model: any PowerManagementModel) -> String {
        if model.hasManualSession, model.sessionMode == .lid {
            return model.remainingSeconds.map {
                "\(ContractCopy.copyPowerSessionExpires.text(for: language)) \(SettingsFormat.duration(seconds: $0, language: language))"
            } ?? ContractCopy.copyPowerSessionActive.text(for: language)
        }
        return ContractCopy.copyPowerSessionInactive.text(for: language)
    }

    private func helperNeedsAction(_ model: any PowerManagementModel) -> Bool {
        model.helperStatus != .match || model.helperServiceState != .enabled
    }

    private func helperValue(_ model: any PowerManagementModel) -> String {
        if model.helperStatus == .match, model.helperServiceState == .enabled {
            return ContractCopy.copyOverviewHelperInstalled.text(for: language)
        }
        if model.helperServiceState == .requiresApproval {
            return ContractCopy.copyHelperServiceRequiresApproval.text(for: language)
        }
        return ContractCopy.copyOverviewHelperMissing.text(for: language)
    }

    private func helperActionTitle(_ model: any PowerManagementModel) -> String {
        model.helperServiceState == .requiresApproval
            ? ContractCopy.copyClipboardActionOpenSettings.text(for: language)
            : ContractCopy.copyOverviewHelperInstall.text(for: language)
    }
}

private struct DisplaySectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
                .font(.headline)
                .foregroundStyle(MacTheme.textPrimary)
        } icon: {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(MacTheme.brand)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct DisplaySettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MacTheme.space4)
        .background {
            if usesOpaqueSurface {
                shape.fill(MacTheme.surface)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay(shape.strokeBorder(MacTheme.divider, lineWidth: usesOpaqueSurface ? 1.5 : 1))
        .accessibilityElement(children: .contain)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
    }

    private var usesOpaqueSurface: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }
}
