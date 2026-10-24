import SwiftUI
import kmpDomain

/// `Monitor` 页签中的电源管理面。
///
/// 所有值都来自 `AppRuntime.powerRuntime`。这里不保存状态值，
/// 只保存当前选择、按钮结果和最近一次动作提示。
struct PowerManagementView: View {
    let model: any PowerManagementModel

    @State private var sessionMode: PowerRuntime.SessionMode = .system
    @State private var sessionDuration: PowerRuntime.SessionDuration = .oneHour
    @State private var outcome: PowerOutcome?

    private var language: AppLanguage { model.language }

    init(model: any PowerManagementModel) {
        self.model = model
        _sessionMode = State(initialValue: model.sessionMode ?? .system)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacTheme.space3) {
                statusCard
                HStack(alignment: .top, spacing: MacTheme.space3) {
                    sessionCard
                    rulesCard
                }
                historyCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    // MARK: - 当前供电

    private var statusCard: some View {
        MacCard {
            sectionHeader(
                title: ContractCopy.copyPowerSectionStatus.text(for: language),
                symbol: "bolt.batteryblock.fill"
            )

            MacSettingRow(title: ContractCopy.copyHubPowerTitle.text(for: language)) {
                MacSwitch(
                    label: ContractCopy.copyHubPowerTitle.text(for: language),
                    isOn: Binding(
                        get: { model.powerConfig.enabled },
                        set: { model.setPowerEnabled($0) }
                    )
                )
            }

            LazyVGrid(columns: statusColumns, alignment: .leading, spacing: MacTheme.space2) {
                statusTile(
                    title: ContractCopy.copyMonitorTitleBattery.text(for: language),
                    value: batteryValue,
                    symbol: "battery.50percent"
                )
                statusTile(
                    title: ContractCopy.copyPowerStatusAdapter.text(for: language),
                    value: adapterValue,
                    symbol: "powerplug.fill"
                )
                statusTile(
                    title: ContractCopy.copyPowerStatusExternalDisplay.text(for: language),
                    value: externalDisplayValue,
                    symbol: "display"
                )
                statusTile(
                    title: ContractCopy.copyMonitorThermal.text(for: language),
                    value: thermalValue,
                    symbol: "thermometer.medium"
                )
                statusTile(
                    title: ContractCopy.copyPowerStatusLowPowerMode.text(for: language),
                    value: boolValue(model.observation.lowPowerModeEnabled?.boolValue),
                    symbol: "leaf.fill"
                )
                statusTile(
                    title: helperTitle,
                    value: helperValue,
                    symbol: "wrench.and.screwdriver.fill"
                )
            }

            if let reason = HelperStatusPresentation.readOnlyReason(
                model.helperStatus,
                language: language
            ) {
                statusAlert(
                    message: reason,
                    kind: .warning
                ) {
                    MacButton(
                        title: HelperStatusPresentation.repairTitle.text(for: language),
                        kind: .primary,
                        isEnabled: !model.busy
                    ) {
                        model.installHelper()
                    }
                }
            }
            if hasExternalSleepConflict {
                MacAlert(
                    message: ContractCopy.copyPowerAlertExternalConflict.text(for: language),
                    kind: .error
                )
            }
            if thermalNeedsAttention {
                MacAlert(
                    message: ContractCopy.copyPowerAlertThermal.text(for: language),
                    kind: .warning
                )
            }
        }
    }

    private var statusColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 110), spacing: MacTheme.space2), count: 3)
    }

    private func statusTile(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(MacTheme.space2)
        .background(MacTheme.elevated, in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 保持唤醒

    private var sessionCard: some View {
        MacCard {
            sectionHeader(
                title: ContractCopy.copyPowerSectionSession.text(for: language),
                symbol: "cup.and.saucer.fill"
            )

            Picker(
                ContractCopy.copyPowerSectionSession.text(for: language),
                selection: $sessionMode
            ) {
                ForEach(PowerRuntime.SessionMode.allCases) { mode in
                    Text(sessionModeTitle(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(ContractCopy.copyPowerSectionSession.text(for: language))

            if sessionMode == .lid {
                MacStatusLine(text: lidSessionHint)
            }

            HStack(spacing: MacTheme.space2) {
                Text(ContractCopy.copyPowerSessionExpires.text(for: language))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                Picker(
                    ContractCopy.copyPowerSessionExpires.text(for: language),
                    selection: $sessionDuration
                ) {
                    ForEach(PowerRuntime.SessionDuration.allCases) { duration in
                        Text(durationTitle(duration)).tag(duration)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: MacTheme.space1) {
                ForEach(reasons) { reason in
                    HStack(alignment: .firstTextBaseline, spacing: MacTheme.space2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.successText)
                        Text(reason.title)
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: MacTheme.space2)
                        if let detail = reason.detail {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if reasons.isEmpty {
                    MacStatusLine(text: ContractCopy.copyPowerSessionNone.text(for: language))
                }
            }

            ForEach(Array(model.decision.safetyVetoes.enumerated()), id: \.offset) { _, veto in
                MacAlert(message: vetoText(veto), kind: .warning)
            }

            HStack(spacing: MacTheme.space2) {
                MacButton(
                    title: ContractCopy.copyPowerSessionStart.text(for: language),
                    kind: .primary,
                    isEnabled: canStartSession
                ) {
                    let started = model.startSession(mode: sessionMode, duration: sessionDuration)
                    outcome = PowerOutcome(
                        message: (started ? ContractCopy.copyStateSuccess : ContractCopy.copyStateError)
                            .text(for: language),
                        kind: started ? .success : .error
                    )
                }
                if model.hasManualSession {
                    MacButton(title: ContractCopy.copyPowerSessionEnd.text(for: language)) {
                        model.endSession()
                        outcome = PowerOutcome(
                            message: ContractCopy.copyStateSuccess.text(for: language),
                            kind: .success
                        )
                    }
                }
                Spacer(minLength: 0)
            }

            if let outcome {
                MacAlert(message: outcome.message, kind: outcome.kind)
            }
            if let error = model.executionError {
                MacAlert(message: error, kind: .error)
            }
            if let message = model.statusMessage, !message.isEmpty {
                MacAlert(message: message, kind: .info)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var canStartSession: Bool {
        model.powerConfig.enabled &&
            (!model.hasManualSession || model.sessionMode != sessionMode) &&
            (sessionMode != .lid || model.helperStatus == .match)
    }

    private var reasons: [PowerReason] {
        var result: [PowerReason] = []
        if model.decision.automaticRuleApplied {
            result.append(
                PowerReason(
                    id: "automatic",
                    title: ContractCopy.copyPowerSessionReasonAdapter.text(for: language),
                    detail: ContractCopy.copyPowerSessionActive.text(for: language)
                )
            )
        }
        if model.hasManualSession, let mode = model.sessionMode {
            result.append(
                PowerReason(
                    id: "session",
                    title: sessionModeTitle(mode),
                    detail: model.remainingSeconds.map {
                        "\(ContractCopy.copyPowerSessionExpires.text(for: language)) \(SettingsFormat.duration(seconds: $0, language: language))"
                    } ?? ContractCopy.copyPowerSessionDurationOpen.text(for: language)
                )
            )
        }
        if let remaining = model.appState.idleCancelRemainingSeconds?.int64Value {
            result.append(
                PowerReason(
                    id: "legacy-idle-timer",
                    title: ContractCopy.copyPowerSessionSystem.text(for: language),
                    detail: SettingsFormat.duration(seconds: remaining, language: language)
                )
            )
        }
        if !model.appState.idleSleepAvailable,
           !model.decision.preventUserIdleSystemSleep,
           model.appState.idleCancelRemainingSeconds == nil {
            result.append(
                PowerReason(
                    id: "engine-idle",
                    title: ContractCopy.copyPowerSessionSystem.text(for: language),
                    detail: ContractCopy.copyPowerSessionActive.text(for: language)
                )
            )
        }
        if !model.appState.lidSleepAvailable,
           model.sessionMode != .lid {
            result.append(
                PowerReason(
                    id: "engine-lid",
                    title: ContractCopy.copyPowerSessionLid.text(for: language),
                    detail: model.appState.lidCancelRemainingSeconds.map {
                        SettingsFormat.duration(seconds: $0.int64Value, language: language)
                    }
                )
            )
        }
        return result
    }

    // MARK: - 安全与自动规则

    private var rulesCard: some View {
        MacCard {
            sectionHeader(
                title: ContractCopy.copyPowerSectionRules.text(for: language),
                symbol: "shield.lefthalf.filled"
            )

            ruleRow(
                title: ContractCopy.copyPowerRulesAdapter.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.keepAwakeOnAdapter },
                    set: { model.setPowerKeepAwakeOnAdapter($0) }
                )
            )
            ruleRow(
                title: ContractCopy.copyPowerRulesBattery.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.keepAwakeOnBattery },
                    set: { model.setPowerKeepAwakeOnBattery($0) }
                )
            )
            ruleRow(
                title: ContractCopy.copyPowerRulesLid.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.allowClosedLid },
                    set: { model.setPowerAllowClosedLid($0) }
                ),
                isEnabled: model.helperStatus == .match || !model.powerConfig.allowClosedLid
            )
            ruleRow(
                title: ContractCopy.copyPowerRulesClosedLidZeroBrightness.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.closedLidZeroBrightness },
                    set: { model.setPowerClosedLidZeroBrightness($0) }
                ),
                isEnabled: model.powerConfig.closedLidZeroBrightness ||
                    (model.helperStatus == .match &&
                        model.closedLidZeroBrightnessAvailability.isAvailable)
            )
            Text(
                model.closedLidZeroBrightnessAvailability.isAvailable
                    ? ContractCopy.copyPowerRulesClosedLidZeroBrightnessHint.text(for: language)
                    : ContractCopy.copyPowerRulesClosedLidZeroBrightnessUnavailable.text(for: language)
            )
            .font(.system(size: 10))
            .foregroundStyle(MacTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, MacTheme.space2)
            if model.powerConfig.closedLidZeroBrightness,
               model.closedLidZeroBrightnessPhase == .failed,
               let error = model.closedLidZeroBrightnessError {
                MacAlert(
                    message: "\(ContractCopy.copyPowerRulesClosedLidZeroBrightnessFailed.text(for: language)) \(error)",
                    kind: .warning
                )
            }
            ruleRow(
                title: ContractCopy.copyPowerRulesExternalDisplay.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.pauseClosedLidWithExternalDisplay },
                    set: { model.setPowerPauseClosedLidWithExternalDisplay($0) }
                )
            )
            ruleRow(
                title: ContractCopy.copyPowerStatusLowPowerMode.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.yieldOnLowPowerMode },
                    set: { model.setPowerYieldOnLowPowerMode($0) }
                )
            )
            ruleRow(
                title: ContractCopy.copyPowerRulesHeatGuard.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.heatGuardEnabled },
                    set: { model.setPowerHeatGuard($0) }
                )
            )

            Divider().overlay(MacTheme.divider)

            MacSettingRow(title: ContractCopy.copyPowerRulesBatteryFloor.text(for: language)) {
                Stepper(
                    value: Binding(
                        get: { Int(model.powerConfig.batteryFloorPercent) },
                        set: { model.setPowerBatteryFloor($0) }
                    ),
                    in: 5...50,
                    step: 5
                ) {
                    Text("\(model.powerConfig.batteryFloorPercent)%")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .frame(minWidth: 42, alignment: .trailing)
                }
                .accessibilityLabel(ContractCopy.copyPowerRulesBatteryFloor.text(for: language))
            }

            MacSettingRow(title: ContractCopy.copyPowerRulesTimeCap.text(for: language)) {
                Picker(
                    ContractCopy.copyPowerRulesTimeCap.text(for: language),
                    selection: Binding(
                        get: { Int(model.powerConfig.closedLidTimeCapMinutes) },
                        set: { model.setPowerClosedLidTimeCapMinutes($0) }
                    )
                ) {
                    ForEach(Self.timeCapOptions, id: \.self) { minutes in
                        Text(SettingsFormat.duration(seconds: Int64(minutes) * 60, language: language))
                            .tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func ruleRow(title: String, isOn: Binding<Bool>, isEnabled: Bool = true) -> some View {
        MacSettingRow(title: title) {
            MacSwitch(label: title, isOn: isOn, isEnabled: isEnabled)
        }
    }

    // MARK: - 最近活动

    private var historyCard: some View {
        MacCard {
            HStack {
                sectionHeader(
                    title: ContractCopy.copyPowerSectionHistory.text(for: language),
                    symbol: "clock.arrow.circlepath"
                )
                Spacer(minLength: MacTheme.space2)
                Text(ContractCopy.copyPowerHistoryWindow.text(for: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            if model.recentHistory.isEmpty {
                HStack(spacing: MacTheme.space2) {
                    Image(systemName: "tray")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                    Text(ContractCopy.copyPowerHistoryNoEvents.text(for: language))
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .background(
                    MacTheme.elevated,
                    in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                )
                .accessibilityElement(children: .combine)
            } else {
                LazyVStack(spacing: MacTheme.space1) {
                    ForEach(model.recentHistory, id: \.id) { event in
                        historyRow(event)
                    }
                }
            }
        }
    }

    private func historyRow(_ event: PowerHistoryEvent) -> some View {
        HStack(alignment: .center, spacing: MacTheme.space2) {
            Text(Self.historyTime.string(
                from: Date(timeIntervalSince1970: TimeInterval(event.atEpochSeconds))
            ))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(MacTheme.textSecondary)
            .frame(width: 42, alignment: .leading)
            Image(systemName: historySymbol(event.kind))
                .font(.system(size: 11))
                .foregroundStyle(historyColor(event.kind))
                .frame(width: 16)
            Text(historyTitle(event.kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer(minLength: MacTheme.space2)
            if let detail = historyDetail(event) {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, MacTheme.space2)
        .frame(minHeight: 30)
        .background(
            MacTheme.elevated,
            in: RoundedRectangle(cornerRadius: MacTheme.smallRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func historyTitle(_ kind: PowerHistoryKind) -> String {
        switch kind {
        case .adapterConnected:
            ContractCopy.copyPowerHistoryAdapterConnected.text(for: language)
        case .adapterDisconnected:
            ContractCopy.copyPowerHistoryAdapterDisconnected.text(for: language)
        case .slept:
            ContractCopy.copyPowerHistorySlept.text(for: language)
        case .darkWake, .fullWake:
            ContractCopy.copyPowerHistoryWoke.text(for: language)
        case .holdStarted:
            ContractCopy.copyPowerHistoryHoldStarted.text(for: language)
        case .guardReleased:
            ContractCopy.copyPowerHistoryGuardReleased.text(for: language)
        case .externalConflict:
            ContractCopy.copyPowerAlertExternalConflict.text(for: language)
        case .externalConflictCleared:
            ContractCopy.copyPowerHistoryExternalConflictCleared.text(for: language)
        default:
            ContractCopy.copyStateWarning.text(for: language)
        }
    }

    private func historyDetail(_ event: PowerHistoryEvent) -> String? {
        let type: String? = switch event.kind {
        case .darkWake: "DarkWake"
        case .fullWake: "Full wake"
        default: nil
        }
        let detail = event.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (type, detail.isEmpty) {
        case let (type?, false): "\(type) · \(detail)"
        case let (type?, true): type
        case (nil, false): detail
        case (nil, true): nil
        }
    }

    private func historySymbol(_ kind: PowerHistoryKind) -> String {
        switch kind {
        case .adapterConnected, .adapterDisconnected: "powerplug.fill"
        case .slept: "moon.fill"
        case .darkWake: "moon.haze.fill"
        case .fullWake: "sun.max.fill"
        case .holdStarted: "cup.and.saucer.fill"
        case .guardReleased: "shield.slash.fill"
        case .externalConflict: "exclamationmark.triangle.fill"
        case .externalConflictCleared: "checkmark.shield.fill"
        default: "circle.fill"
        }
    }

    private func historyColor(_ kind: PowerHistoryKind) -> Color {
        switch kind {
        case .guardReleased, .externalConflict: MacTheme.warningText
        case .fullWake, .externalConflictCleared: MacTheme.successText
        default: MacTheme.textSecondary
        }
    }

    // MARK: - 文案与格式

    private func sectionHeader(title: String, symbol: String) -> some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.accent)
            MacSectionTitle(text: title)
        }
    }

    private func statusAlert<Actions: View>(
        message: String,
        kind: MacAlertKind,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: MacTheme.space2) {
            MacAlert(message: message, kind: kind)
            actions()
        }
    }

    private var batteryValue: String {
        guard model.observation.hasBattery?.boolValue != false else {
            return ContractCopy.copyStateEmpty.text(for: language)
        }
        guard let percent = model.observation.batteryPercent?.intValue else {
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
        return "\(percent)%"
    }

    private var adapterValue: String {
        switch model.observation.powerState {
        case .charging, .charged, .acPower:
            return ContractCopy.copyPowerStatusConnected.text(for: language)
        case .discharging:
            return ContractCopy.copyPowerStatusNotConnected.text(for: language)
        case .unknown:
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        default:
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var externalDisplayValue: String {
        guard let count = model.observation.externalDisplayCount?.intValue else {
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
        guard count > 0 else {
            return ContractCopy.copyPowerStatusNoExternalDisplay.text(for: language)
        }
        return "\(count)"
    }

    private var thermalValue: String {
        switch model.observation.thermalState {
        case .nominal: ContractCopy.copyMonitorThermalNominal.text(for: language)
        case .fair: ContractCopy.copyMonitorThermalFair.text(for: language)
        case .serious: ContractCopy.copyMonitorThermalSerious.text(for: language)
        case .critical: ContractCopy.copyMonitorThermalCritical.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        default: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var helperTitle: String {
        ContractCopy.copyOverviewHelperVersion.text(for: language)
    }

    private var helperValue: String {
        HelperStatusPresentation.value(model.helperStatus, language: language)
    }

    private var thermalNeedsAttention: Bool {
        model.observation.thermalState == .serious || model.observation.thermalState == .critical
    }

    private var hasExternalSleepConflict: Bool {
        model.snapshot.sleepDisabled?.boolValue == true &&
            model.snapshot.covioOwnsSleepDisabled?.boolValue != true
    }

    private func boolValue(_ value: Bool?) -> String {
        guard let value else {
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
        return (value ? ContractCopy.copyPowerRulesOn : ContractCopy.copyPowerRulesOff).text(for: language)
    }

    private func sessionModeTitle(_ mode: PowerRuntime.SessionMode) -> String {
        switch mode {
        case .system: ContractCopy.copyPowerSessionSystem.text(for: language)
        case .display: ContractCopy.copyPowerSessionDisplay.text(for: language)
        case .lid:
            model.powerConfig.closedLidZeroBrightness &&
                model.closedLidZeroBrightnessAvailability.isAvailable
                ? ContractCopy.copyPowerSessionLidZeroBrightness.text(for: language)
                : ContractCopy.copyPowerSessionLidDisplayOff.text(for: language)
        }
    }

    private var lidSessionHint: String {
        if model.powerConfig.closedLidZeroBrightness,
           model.closedLidZeroBrightnessAvailability.isAvailable {
            return ContractCopy.copyPowerRulesClosedLidZeroBrightnessHint.text(for: language)
        }
        return ContractCopy.copyPowerSessionLidDisplayOffHint.text(for: language)
    }

    private func durationTitle(_ duration: PowerRuntime.SessionDuration) -> String {
        switch duration {
        case .fifteenMinutes: ContractCopy.copyPowerSessionDuration15m.text(for: language)
        case .oneHour: ContractCopy.copyPowerSessionDuration1h.text(for: language)
        case .twoHours: ContractCopy.copyPowerSessionDuration2h.text(for: language)
        case .fourHours: ContractCopy.copyPowerSessionDuration4h.text(for: language)
        case .untilOff: ContractCopy.copyPowerSessionDurationOpen.text(for: language)
        }
    }

    private func vetoText(_ veto: SafetyVeto) -> String {
        switch veto {
        case .powerDisabled:
            ContractCopy.copyPowerRulesOff.text(for: language)
        case .batteryFloor:
            ContractCopy.copyPowerRulesBatteryFloor.text(for: language)
        case .thermalSerious, .thermalCritical:
            ContractCopy.copyPowerAlertThermal.text(for: language)
        case .lowPowerMode:
            ContractCopy.copyPowerStatusLowPowerMode.text(for: language)
        case .closedLidTimeCap:
            ContractCopy.copyPowerRulesTimeCap.text(for: language)
        case .closedLidDisabled:
            ContractCopy.copyPowerRulesLid.text(for: language)
        case .helperUnavailable:
            ContractCopy.copyPowerStatusGuardMissing.text(for: language)
        case .batteryStateUnknown:
            ContractCopy.copyMonitorStateUnknown.text(for: language)
        case .externalDisplayConnected, .externalDisplayUnknown:
            ContractCopy.copyPowerStatusExternalDisplay.text(for: language)
        case .sleepDisabledStateUnknown, .externalSleepDisabledConflict:
            ContractCopy.copyPowerAlertExternalConflict.text(for: language)
        case .explicitlyPaused:
            ContractCopy.copyPowerSessionInactive.text(for: language)
        default:
            ContractCopy.copyStateWarning.text(for: language)
        }
    }

    private static let timeCapOptions = [30, 60, 120, 240, 480, 1_440]

    private static let historyTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct PowerReason: Identifiable {
    let id: String
    let title: String
    let detail: String?
}

private struct PowerOutcome {
    let message: String
    let kind: MacAlertKind
}


/// 电源管理面需要的最小运行时合同。
///
/// `AppRuntime` 提供真实系统状态与持久化动作。
/// 调试预览提供稳定的样本状态，便于检查布局与状态文案。
@MainActor
protocol PowerManagementModel: AnyObject {
    var language: AppLanguage { get }
    var powerConfig: PowerConfig { get }
    var observation: PowerObservation { get }
    var snapshot: PowerSnapshot { get }
    var decision: PowerDecision { get }
    var helperStatus: HelperStatus { get }
    var executionError: String? { get }
    var hasManualSession: Bool { get }
    var sessionMode: PowerRuntime.SessionMode? { get }
    var remainingSeconds: Int64? { get }
    var recentHistory: [PowerHistoryEvent] { get }
    var closedLidZeroBrightnessPhase: ClosedLidZeroBrightnessPhase { get }
    var closedLidZeroBrightnessAvailability: ClosedLidBrightnessAvailability { get }
    var closedLidZeroBrightnessError: String? { get }
    var appState: AppState { get }
    var statusMessage: String? { get }
    var busy: Bool { get }

    func setPowerEnabled(_ enabled: Bool)
    func setPowerKeepAwakeOnAdapter(_ enabled: Bool)
    func setPowerKeepAwakeOnBattery(_ enabled: Bool)
    func setPowerAllowClosedLid(_ enabled: Bool)
    func setPowerClosedLidZeroBrightness(_ enabled: Bool)
    func setPowerPauseClosedLidWithExternalDisplay(_ enabled: Bool)
    func setPowerYieldOnLowPowerMode(_ enabled: Bool)
    func setPowerHeatGuard(_ enabled: Bool)
    func setPowerBatteryFloor(_ percent: Int)
    func setPowerClosedLidTimeCapMinutes(_ minutes: Int)
    func startSession(mode: PowerRuntime.SessionMode, duration: PowerRuntime.SessionDuration) -> Bool
    func endSession()
    func installHelper()
}

extension AppRuntime: PowerManagementModel {
    var powerConfig: PowerConfig { config.power }
    var observation: PowerObservation { powerRuntime.observation }
    var snapshot: PowerSnapshot { powerRuntime.snapshot }
    var decision: PowerDecision { powerRuntime.decision }
    var executionError: String? { powerRuntime.executionError }
    var hasManualSession: Bool { powerRuntime.hasManualSession }
    var sessionMode: PowerRuntime.SessionMode? { powerRuntime.sessionMode }
    var remainingSeconds: Int64? { powerRuntime.remainingSeconds }
    var recentHistory: [PowerHistoryEvent] { powerRuntime.recentHistory }
    var closedLidZeroBrightnessPhase: ClosedLidZeroBrightnessPhase {
        powerRuntime.closedLidZeroBrightnessPhase
    }
    var closedLidZeroBrightnessAvailability: ClosedLidBrightnessAvailability {
        powerRuntime.closedLidZeroBrightnessAvailability
    }
    var closedLidZeroBrightnessError: String? { powerRuntime.closedLidZeroBrightnessError }

    func startSession(mode: PowerRuntime.SessionMode, duration: PowerRuntime.SessionDuration) -> Bool {
        powerRuntime.startSession(mode: mode, duration: duration)
    }

    func endSession() {
        powerRuntime.endSession()
    }
}
