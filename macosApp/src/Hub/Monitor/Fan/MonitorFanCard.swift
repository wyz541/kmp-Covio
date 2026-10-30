import SwiftUI

struct MonitorFanCard: View {
    let reading: MonitorFanReading
    let cpuHistory: [Double]
    let temperatureHistory: [Double]
    let rpmHistory: [Double]
    let language: AppLanguage
    @ObservedObject var model: MonitorFanControlModel
    var popoverCoordinator: HubPopoverCoordinator? = nil

    @State private var popoverPresented = false
    @State private var popoverID = UUID().uuidString

    private var controlTemperature: Double? {
        model.configuration.controlTemperature(in: reading)
    }

    private var selectedSensorCount: Int {
        let known = Set(reading.temperatures.map(\.key))
        let selected = model.configuration.selectedSensorKeys.filter(known.contains)
        return selected.isEmpty ? reading.temperatures.count : selected.count
    }

    private var statusText: String {
        if model.busy || model.availability == .checking {
            return ContractCopy.copyMonitorFanApplying.text(for: language)
        }
        if model.helperStatus?.active == true || model.configuration.enabled {
            return ContractCopy.copyMonitorFanOwned.text(for: language)
        }
        return ContractCopy.copyMonitorFanSystemControl.text(for: language)
    }

    var body: some View {
        MonitorCardShell(
            kind: .fan,
            accent: MonitorCardKind.fan.accent,
            language: language,
            combinesAccessibility: false,
            statusText: statusText
        ) {
            VStack(alignment: .leading, spacing: 5) {
                primaryRow
                MonitorFanTripleChart(
                    temperatures: temperatureHistory,
                    cpu: cpuHistory,
                    rpm: rpmHistory,
                    emptyText: ContractCopy.copyMonitorPowerHistoryAccumulating.text(for: language)
                )
                .frame(height: 58)
                chartLegend
                fanRows
                Spacer(minLength: 0)
                Button {
                    setPopoverPresented(!popoverPresented)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MonitorCardKind.fan.accent)
                        Text(ContractCopy.copyMonitorFanDetails.text(for: language))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MonitorCardKind.fan.accent)
                            .rotationEffect(popoverPresented ? .degrees(90) : .zero)
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ContractCopy.copyMonitorFanA11yOpen.text(for: language))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .popover(isPresented: $popoverPresented, arrowEdge: .bottom) {
            MonitorFanPopover(
                reading: reading,
                language: language,
                model: model
            )
            .frame(width: 420, height: 760, alignment: .topLeading)
            .onAppear {
                popoverCoordinator?.setPresented(true, id: popoverID)
            }
            .onDisappear {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .onChange(of: popoverPresented) { _, presented in
            if !presented {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .onChange(of: popoverCoordinator?.dismissalRequest) { _, _ in
            setPopoverPresented(false)
        }
        .onAppear {
            model.adoptDefaultSensors(from: reading)
            model.refreshFanControlStatus()
        }
        .onChange(of: reading) { _, value in
            model.adoptDefaultSensors(from: value)
        }
        .onDisappear {
            popoverCoordinator?.setPresented(false, id: popoverID)
        }
    }

    /// 同时更新 Popover 与协调器。先登记再等窗口出现，避免指针事件抢先启动收起。
    private func setPopoverPresented(_ presented: Bool) {
        popoverPresented = presented
        popoverCoordinator?.setPresented(presented, id: popoverID)
    }

    private var primaryRow: some View {
        HStack(alignment: .top, spacing: MacTheme.space2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(MonitorFanFormat.temperature(controlTemperature))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textPrimary)
                    .monospacedDigit()
                Text(String(
                    format: ContractCopy.copyMonitorFanControlSummary.text(for: language),
                    selectedSensorCount
                ))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text("CPU")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(MacTheme.textSecondary)
                Text(MonitorFormat.percent(cpuHistory.last ?? 0))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    private var chartLegend: some View {
        HStack(spacing: MacTheme.space2) {
            legend(color: MacTheme.errorText, text: ContractCopy.copyMonitorFanTemperature.text(for: language))
            legend(color: MacTheme.accent, text: "CPU")
            legend(color: MacTheme.successText, text: "RPM")
            Spacer(minLength: 0)
            Text(ContractCopy.copyMonitorFanLegendWindow.text(for: language))
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Capsule()
                .fill(color)
                .frame(width: 8, height: 2)
            Text(text)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var fanRows: some View {
        VStack(spacing: 2) {
            ForEach(reading.units.prefix(2)) { fan in
                HStack(spacing: MacTheme.space1) {
                    Text(String(
                        format: ContractCopy.copyMonitorFanUnit.text(for: language),
                        fan.index + 1
                    ))
                    .foregroundStyle(MacTheme.textSecondary)
                    Spacer(minLength: 0)
                    Text(MonitorFanFormat.rpm(fan.rpm))
                        .foregroundStyle(MacTheme.textPrimary)
                        .monospacedDigit()
                    if fan.targetRPM > 0 {
                        Text("/ \(MonitorFanFormat.targetRPM(fan.targetRPM))")
                            .foregroundStyle(MacTheme.textSecondary)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 8, weight: .medium))
            }
        }
    }


}

private struct MonitorFanTripleChart: View {
    let temperatures: [Double]
    let cpu: [Double]
    let rpm: [Double]
    let emptyText: String

    var body: some View {
        GeometryReader { proxy in
            let sampleCount = max(temperatures.count, max(cpu.count, rpm.count))
            ZStack {
                linePath(values: temperatures, in: proxy.size, color: MacTheme.errorText)
                linePath(values: cpu.map { $0 * 100 }, in: proxy.size, color: MacTheme.accent)
                linePath(values: rpm, in: proxy.size, color: MacTheme.successText)
                if sampleCount < 2 {
                    Text(emptyText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func linePath(values: [Double], in size: CGSize, color: Color) -> some View {
        Path { path in
            let finite = values.filter(\.isFinite)
            guard finite.count >= 2 else { return }
            let minimum = finite.min() ?? 0
            let maximum = finite.max() ?? minimum + 1
            let span = max(0.001, maximum - minimum)
            let denominator = max(1, values.count - 1)
            var hasCurrentPoint = false
            for (index, value) in values.enumerated() where value.isFinite {
                let x = size.width * CGFloat(index) / CGFloat(denominator)
                let normalized = (value - minimum) / span
                let y = size.height - CGFloat(normalized) * max(0, size.height - 3) - 1.5
                let point = CGPoint(x: x, y: y)
                if hasCurrentPoint {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    hasCurrentPoint = true
                }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
    }
}

struct MonitorFanPopover: View {
    let reading: MonitorFanReading
    let language: AppLanguage
    @ObservedObject var model: MonitorFanControlModel
    var scrollsContent = true
    var rendersForSnapshot = false
    var sensorsInitiallyExpanded = false

    @State private var sensorsExpanded = false
    @State private var sensorQuery = ""

    private var controlTemperature: Double? {
        model.configuration.controlTemperature(in: reading)
    }

    private var helperReady: Bool {
        model.availability == .ready
    }

    private var isControllingFans: Bool {
        model.helperStatus?.active == true || model.configuration.enabled
    }

    private var statusText: String {
        if model.busy {
            return ContractCopy.copyMonitorFanApplying.text(for: language)
        }
        if model.helperStatus?.active == true || model.configuration.enabled {
            return ContractCopy.copyMonitorFanOwned.text(for: language)
        }
        return ContractCopy.copyMonitorFanSystemControl.text(for: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 12)
            if scrollsContent {
                ScrollView(.vertical, showsIndicators: false) {
                    detailContent
                }
                .defaultScrollAnchor(sensorsInitiallyExpanded ? .bottom : .top)
            } else {
                detailContent
            }
        }
        .padding(16)
        .tint(MonitorCardKind.fan.accent)
        .onAppear {
            if sensorsInitiallyExpanded {
                sensorsExpanded = true
            }
            model.refreshFanControlStatus()
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(MonitorFanPolicy.heartbeatSeconds))
                } catch {
                    break
                }
                model.refreshFanControlStatus()
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !helperReady {
                helperCallout
            }
            if isControllingFans {
                takeoverBanner
            } else {
                warning
            }
            controls
            Divider()
            fanSection
            if model.configuration.enabled,
               model.configuration.enabledTemperatureSources.isEmpty {
                sensorSection
            }
        }
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ContractCopy.copyMonitorFanControlTemperature.text(for: language))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MonitorCardKind.fan.accent)
                Text(MonitorFanFormat.temperature(controlTemperature))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textPrimary)
                    .monospacedDigit()
                Text(controlSummaryText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Label {
                Text(statusText)
            } icon: {
                Circle()
                    .fill(
                        isControllingFans
                            ? MacTheme.warningText
                            : MacTheme.textSecondary
                    )
                    .frame(width: 7, height: 7)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MacTheme.textSecondary)
            .accessibilityLabel(ContractCopy.copyMonitorFanA11yStatus.text(for: language))
            .accessibilityValue(statusText)
        }
    }

    private var takeoverBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.warningText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ContractCopy.copyMonitorFanTakeoverTitle.text(for: language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(ContractCopy.copyMonitorFanTakeoverBody.text(for: language))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                model.restore()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                    Text(ContractCopy.copyMonitorFanRestoreSystem.text(for: language))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(MonitorCardKind.fan.accent)
            .frame(maxWidth: .infinity)
            .disabled(model.busy)
            .accessibilityHint(ContractCopy.copyMonitorFanTakeoverBody.text(for: language))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverContentSurface(
            cornerRadius: 9,
            tint: MacTheme.warningText.opacity(0.10)
        )
    }

    private var helperCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(
                    model.availability == .missing || model.availability == .outdated
                        ? ContractCopy.copyMonitorFanHelperRequired.text(for: language)
                        : ContractCopy.copyMonitorFanHelperUnavailable.text(for: language)
                )
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MacTheme.textSecondary)

        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverContentSurface(
            cornerRadius: 9,
            tint: MacTheme.warningText.opacity(0.12)
        )
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            enableControl

            if model.configuration.enabled {
                modeControl

                if model.configuration.mode == .curve {
                    temperatureRuleEditor
                    if model.configuration.enabledTemperatureSources.isEmpty {
                        presetRow
                        curveEditor
                    }
                } else {
                    manualControls
                }
            }
        }
        .padding(10)
        .popoverContentSurface()
    }

    @ViewBuilder
    private var enableControl: some View {
        if rendersForSnapshot {
            HStack(spacing: 10) {
                Text(ContractCopy.copyMonitorFanEnable.text(for: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                ZStack(alignment: model.configuration.enabled ? .trailing : .leading) {
                    Capsule()
                        .fill(
                            model.configuration.enabled
                                ? MacTheme.accent
                                : MacTheme.textSecondary.opacity(0.2)
                        )
                        .frame(width: 70, height: 32)
                    Circle()
                        .fill(.white)
                        .frame(width: 28, height: 28)
                        .padding(2)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ContractCopy.copyMonitorFanEnable.text(for: language))
                .accessibilityValue(model.configuration.enabled ? "on" : "off")
            }
        } else {
            Toggle(isOn: Binding(
                get: { model.configuration.enabled },
                set: { model.setEnabled($0, reading: reading) }
            )) {
                Text(ContractCopy.copyMonitorFanEnable.text(for: language))
                    .font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.switch)
            .disabled(!helperReady || model.busy)
        }
    }

    @ViewBuilder
    private var modeControl: some View {
        if rendersForSnapshot {
            HStack(spacing: 0) {
                ForEach([MonitorFanMode.curve, .manual], id: \.rawValue) { mode in
                    Button {
                        model.setMode(mode, reading: reading)
                    } label: {
                        Text(modeTitle(mode))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                model.configuration.mode == mode ? Color.white : MacTheme.textPrimary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                model.configuration.mode == mode
                                    ? MacTheme.accent
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                MacTheme.textSecondary.opacity(0.13),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        } else {
            Picker(ContractCopy.copyMonitorFanDetails.text(for: language), selection: Binding(
                get: { model.configuration.mode },
                set: { model.setMode($0, reading: reading) }
            )) {
                Text(modeTitle(.curve))
                    .tag(MonitorFanMode.curve)
                Text(modeTitle(.manual))
                    .tag(MonitorFanMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.busy)
        }
    }

    private func modeTitle(_ mode: MonitorFanMode) -> String {
        switch mode {
        case .automatic:
            ContractCopy.copyMonitorFanSystemAuto.text(for: language)
        case .curve:
            ContractCopy.copyMonitorFanAutoCurve.text(for: language)
        case .manual:
            ContractCopy.copyMonitorFanManualRpm.text(for: language)
        }
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            presetButton(ContractCopy.copyMonitorFanQuiet, MonitorFanPolicy.quiet)
            presetButton(ContractCopy.copyMonitorFanBalanced, MonitorFanPolicy.balanced)
            presetButton(ContractCopy.copyMonitorFanTurbo, MonitorFanPolicy.turbo)
            Spacer(minLength: 0)
        }
    }

    private func presetButton(_ title: LocalizedCopy, _ preset: MonitorFanConfiguration) -> some View {
        Group {
            if rendersForSnapshot {
                Button(title.text(for: language)) {
                    model.applyPreset(preset, reading: reading)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MacTheme.textSecondary.opacity(0.12), in: Capsule())
            } else {
                Button(title.text(for: language)) {
                    model.applyPreset(preset, reading: reading)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .disabled(model.busy)
    }

    private var curveEditor: some View {
        MonitorFanCurveEditor(
            reading: reading,
            configuration: model.configuration,
            language: language,
            powerSource: model.configuration.powerSource,
            interactive: !rendersForSnapshot,
            busy: model.busy,
            onCommit: { fanIndex, source, points in
                model.setCurve(
                    fanIndex: fanIndex,
                    points: points,
                    source: source,
                    reading: reading
                )
            },
            onClear: { fanIndex, source in
                model.clearCurve(fanIndex: fanIndex, source: source, reading: reading)
            },
            onCopyAdapterCurves: {
                model.copyAdapterCurvesToBattery(reading: reading)
            }
        )
    }

    private var temperatureRuleEditor: some View {
        MonitorFanTemperatureRuleEditor(
            reading: reading,
            configuration: model.configuration,
            helperSourceTemperatures: model.helperStatus?.sourceTemperatures ?? [:],
            language: language,
            busy: model.busy,
            onToggleSource: { source, enabled in
                model.setTemperatureSource(source, enabled: enabled, reading: reading)
            },
            onChangePoints: { source, points, applyImmediately in
                model.setTemperatureRulePoints(
                    points,
                    source: source,
                    reading: reading,
                    applyImmediately: applyImmediately
                )
            }
        )
    }

    private var controlSummaryText: String {
        let sources = model.configuration.enabledTemperatureSources
        if sources.count == 1, let source = sources.first {
            return String(
                format: ContractCopy.copyMonitorFanControlSource.text(for: language),
                temperatureSourceTitle(source)
            )
        }
        if sources.count > 1 {
            return String(
                format: ContractCopy.copyMonitorFanSourceSummary.text(for: language),
                sources.count
            )
        }
        return String(
            format: ContractCopy.copyMonitorFanControlSummary.text(for: language),
            model.configuration.selectedSensorKeys.isEmpty
                ? reading.temperatures.count
                : model.configuration.selectedSensorKeys.count
        )
    }

    private func temperatureSourceTitle(_ source: MonitorFanTemperatureSource) -> String {
        switch source {
        case .cpu:
            ContractCopy.copyMonitorFanSourceCpu.text(for: language)
        case .gpu:
            ContractCopy.copyMonitorFanSourceGpu.text(for: language)
        case .battery:
            ContractCopy.copyMonitorFanSourceBattery.text(for: language)
        }
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(ContractCopy.copyMonitorFanManualRpm.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                compactActionButton(
                    ContractCopy.copyMonitorFanFullSpeedAll,
                    systemImage: "forward.fill"
                ) {
                    model.boostAllFans(reading: reading)
                }
                compactActionButton(
                    ContractCopy.copyMonitorFanRestoreAutoCurve,
                    systemImage: "arrow.uturn.backward"
                ) {
                    model.restoreAutoCurve(reading: reading)
                }
            }
            if reading.units.count > 1 {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ContractCopy.copyMonitorFanSyncFans.text(for: language))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text(ContractCopy.copyMonitorFanSyncHint.text(for: language))
                            .font(.system(size: 8))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if rendersForSnapshot {
                        MonitorFanSnapshotSwitch(
                            isOn: model.configuration.syncFans,
                            label: ContractCopy.copyMonitorFanSyncFans.text(for: language)
                        )
                    } else {
                        Toggle("", isOn: Binding(
                            get: { model.configuration.syncFans },
                            set: { model.setSyncFans($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(model.busy)
                    }
                }
            }
            ForEach(reading.units) { fan in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(String(
                            format: ContractCopy.copyMonitorFanUnit.text(for: language),
                            fan.index + 1
                        ))
                        .font(.system(size: 10, weight: .medium))
                        Spacer(minLength: 0)
                        Text(MonitorFanFormat.rpm(
                            model.manualMode(for: fan.index) == .manual
                                ? model.configuration.manualRPM[String(fan.index)]
                                : fan.rpm
                        ))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        compactActionButton(
                            ContractCopy.copyMonitorFanFullSpeed,
                            systemImage: "forward.fill"
                        ) {
                            model.boostFan(fan.index, reading: reading)
                        }
                        .accessibilityLabel(String(
                            format: ContractCopy.copyMonitorFanFullSpeedUnit.text(for: language),
                            fan.index + 1
                        ))
                    }
                    Picker("", selection: Binding(
                        get: { model.manualMode(for: fan.index) },
                        set: { model.setManualMode($0, fanIndex: fan.index, reading: reading) }
                    )) {
                        Text(ContractCopy.copyMonitorFanAutomatic.text(for: language))
                            .tag(MonitorFanMode.automatic)
                        Text(ContractCopy.copyMonitorFanManual.text(for: language))
                            .tag(MonitorFanMode.manual)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    .disabled(model.busy)

                    if model.manualMode(for: fan.index) == .manual {
                        if rendersForSnapshot {
                            MonitorFanSnapshotSlider(
                                value: model.configuration.manualRPM[String(fan.index)] ?? fan.minimumRPM,
                                range: fan.minimumRPM...max(fan.minimumRPM + 1, fan.maximumRPM)
                            )
                        } else {
                            Slider(
                                value: Binding(
                                    get: {
                                        model.configuration.manualRPM[String(fan.index)] ?? fan.minimumRPM
                                    },
                                    set: {
                                        model.setManualRPM(
                                            $0,
                                            fanIndex: fan.index,
                                            reading: reading
                                        )
                                    }
                                ),
                                in: fan.minimumRPM...max(fan.minimumRPM + 1, fan.maximumRPM),
                                step: 50
                            )
                            .disabled(model.busy)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compactActionButton(
        _ title: LocalizedCopy,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if rendersForSnapshot {
                Button(action: action) {
                    Label(title.text(for: language), systemImage: systemImage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(MacTheme.textSecondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(title.text(for: language), systemImage: systemImage, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .disabled(model.busy)
    }

    private var fanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reading.units) { fan in
                HStack(spacing: 8) {
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MonitorCardKind.fan.accent)
                        .frame(width: 14)
                    Text(String(
                        format: ContractCopy.copyMonitorFanUnit.text(for: language),
                        fan.index + 1
                    ))
                    .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                    Text(MonitorFanFormat.rpm(fan.rpm))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(ContractCopy.copyMonitorFanTarget.text(for: language)) \(MonitorFanFormat.targetRPM(fan.targetRPM))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .monospacedDigit()
                }
                .frame(minHeight: 22)
            }
        }
        .padding(10)
        .popoverContentSurface()
    }

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: $sensorsExpanded) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField(
                        ContractCopy.copyMonitorFanSensorFilter.text(for: language),
                        text: $sensorQuery
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .accessibilityLabel(ContractCopy.copyMonitorFanSensorFilter.text(for: language))

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredTemperatures) { sensor in
                                Toggle(isOn: Binding(
                                    get: { model.configuration.selectedSensorKeys.contains(sensor.key) },
                                    set: { model.setSensor(sensor.key, enabled: $0, reading: reading) }
                                )) {
                                    HStack(spacing: 6) {
                                        Text(SMCTemperatureName.displayName(
                                            for: sensor.key,
                                            language: language
                                        ))
                                        Text(sensor.key)
                                            .foregroundStyle(MacTheme.textSecondary)
                                        Spacer(minLength: 0)
                                        Text(MonitorFanFormat.temperature(sensor.celsius))
                                            .monospacedDigit()
                                    }
                                    .font(.system(size: 9, weight: .medium))
                                }
                                .toggleStyle(.checkbox)
                                .frame(minHeight: 22)
                            }
                            if filteredTemperatures.isEmpty {
                                Text(ContractCopy.copyMonitorFanSensorFilterEmpty.text(for: language))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(MacTheme.textSecondary)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxHeight: 150)

                    Text(ContractCopy.copyMonitorFanSensorLibraryHint.text(for: language))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            } label: {
                Text(ContractCopy.copyMonitorFanControlSensors.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(10)
        .popoverContentSurface()
    }

    private var filteredTemperatures: [MonitorFanReading.Temperature] {
        reading.temperatures.filter { sensor in
            SMCTemperatureName.matches(sensor.key, query: sensorQuery)
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MacTheme.warningText)
            VStack(alignment: .leading, spacing: 5) {
                Text(ContractCopy.copyMonitorFanWarning.text(for: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                if let message = model.visibleErrorMessage {
                    Text(message)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.errorText)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MonitorFanSnapshotSlider: View {
    let value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(
                1,
                max(0, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound))
            )
            let knobX = max(0, min(proxy.size.width - 16, proxy.size.width * fraction - 8))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MacTheme.textSecondary.opacity(0.18))
                    .frame(height: 5)
                Capsule()
                    .fill(MacTheme.accent)
                    .frame(width: max(5, proxy.size.width * fraction), height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

private struct MonitorFanSnapshotSwitch: View {
    let isOn: Bool
    let label: String

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? MacTheme.accent : MacTheme.textSecondary.opacity(0.18))
                .frame(width: 42, height: 24)
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .padding(2)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}
