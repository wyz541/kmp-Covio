import SwiftUI

/// Stats 风格的实时监控页。
///
/// 页面只在自己出现时运行采样任务。`HubView` 切到别的页后，SwiftUI 会取消
/// `.task`，采样器随之停止。
struct MonitorTabView: View {
    let language: AppLanguage
    private let runsSampling: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: MonitorSnapshot
    @State private var history: MonitorHistory
    @State private var powerHistory = MonitorPowerHistory()
    @State private var sampler = MonitorSampler()

    init(
        language: AppLanguage,
        initialSnapshot: MonitorSnapshot = .empty,
        initialHistory: MonitorHistory = MonitorHistory(),
        initialPowerHistory: MonitorPowerHistory = MonitorPowerHistory(),
        runsSampling: Bool = true
    ) {
        self.language = language
        self.runsSampling = runsSampling
        _snapshot = State(initialValue: initialSnapshot)
        _history = State(initialValue: initialHistory)
        _powerHistory = State(initialValue: initialPowerHistory)
    }

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 170), spacing: MacTheme.space3),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            statusRow
            LazyVGrid(columns: columns, spacing: MacTheme.space3) {
                cpuCard
                gpuCard
                memoryCard
                diskCard
                networkCard
                powerCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard runsSampling else { return }
            await runSamples()
        }
        .task {
            guard runsSampling else { return }
            await runPowerSamples()
        }
    }

    // MARK: - 采样

    private func runSamples() async {
        while !Task.isCancelled {
            let next = await sampler.sample()
            guard !Task.isCancelled else { break }
            await MainActor.run {
                snapshot = next
                history.append(next)
            }
            do {
                try await Task.sleep(for: .seconds(MonitorCadence.interval(for: next)))
            } catch {
                break
            }
        }
    }

    /// 电源数据独立刷新。耗电窗口内部每 10 秒扫描一次进程。
    private func runPowerSamples() async {
        while !Task.isCancelled {
            let power = await sampler.samplePowerOnly()
            guard !Task.isCancelled else { break }
            await MainActor.run {
                snapshot = snapshot.replacingPower(power)
                powerHistory.append(power)
            }
            do {
                try await Task.sleep(for: .seconds(MonitorPowerFormat.powerRefreshSeconds))
            } catch {
                break
            }
        }
    }

    // MARK: - 状态行

    private var statusRow: some View {
        HStack(spacing: MacTheme.space1) {
            Circle()
                .fill(snapshot.sampledAt == .distantPast ? MacTheme.textSecondary : thermalAccent)
                .frame(width: 6, height: 6)
            Text(ContractCopy.copyMonitorLive.text(for: language))
            Text("·")
            Text(cadenceText)
            Spacer(minLength: MacTheme.space2)
            Text(ContractCopy.copyMonitorThermal.text(for: language))
            Text("·")
            Text(thermalText)
            Text("·")
            Text("\(history.cpu.count)/60")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(MacTheme.textSecondary)
        .frame(height: 18)
        .accessibilityElement(children: .combine)
    }

    private var cadenceText: String {
        let copy = snapshot.isOnBattery
            ? ContractCopy.copyMonitorSamplingSlow
            : ContractCopy.copyMonitorSamplingFast
        return copy.text(for: language)
    }

    private var thermalText: String {
        switch snapshot.thermal {
        case .nominal: ContractCopy.copyMonitorThermalNominal.text(for: language)
        case .fair: ContractCopy.copyMonitorThermalFair.text(for: language)
        case .serious: ContractCopy.copyMonitorThermalSerious.text(for: language)
        case .critical: ContractCopy.copyMonitorThermalCritical.text(for: language)
        }
    }

    private var thermalAccent: Color {
        switch snapshot.thermal {
        case .nominal: MacTheme.successText
        case .fair: MacTheme.warningText
        case .serious, .critical: MacTheme.errorText
        }
    }

    // MARK: - 卡片

    @ViewBuilder
    private var cpuCard: some View {
        if let cpu = snapshot.cpu {
            MonitorGaugeCard(
                kind: .cpu,
                fraction: cpu.usage,
                value: MonitorFormat.percent(cpu.usage),
                history: history.cpu,
                accent: MonitorCardKind.cpu.accent,
                language: language,
                perCore: cpu.perCore,
                details: [
                    .init(ContractCopy.copyMonitorPerCore.text(for: language), MonitorFormat.percent(cpu.perCore.reduce(0, +) / Double(max(1, cpu.perCore.count)))),
                    .init(ContractCopy.copyMonitorLoad1.text(for: language), MonitorFormat.load(cpu.loadAverage)),
                    .init(ContractCopy.copyMonitorCores.text(for: language), "\(cpu.coreCount)"),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .cpu, language: language)
        }
    }

    @ViewBuilder
    private var gpuCard: some View {
        if let gpu = snapshot.gpu {
            MonitorGaugeCard(
                kind: .gpu,
                fraction: gpu.usage,
                value: MonitorFormat.percent(gpu.usage),
                history: history.gpu,
                accent: MonitorCardKind.gpu.accent,
                language: language,
                perCore: nil,
                details: [
                    .init(ContractCopy.copyMonitorGpuMemory.text(for: language), MonitorFormat.bytes(gpu.memoryUsed)),
                    .init(ContractCopy.copyMonitorGpuDevice.text(for: language), gpu.model),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .gpu, language: language)
        }
    }

    @ViewBuilder
    private var memoryCard: some View {
        if let memory = snapshot.memory, memory.total > 0 {
            let fraction = memory.used / memory.total
            MonitorGaugeCard(
                kind: .memory,
                fraction: fraction,
                value: MonitorFormat.percent(fraction),
                history: history.memory,
                accent: MonitorCardKind.memory.accent,
                language: language,
                perCore: nil,
                details: [
                    .init(ContractCopy.copyMonitorMemoryUsed.text(for: language), MonitorFormat.bytes(memory.used)),
                    .init(ContractCopy.copyMonitorMemoryTotal.text(for: language), MonitorFormat.bytes(memory.total)),
                    .init(ContractCopy.copyMonitorMemorySwap.text(for: language), MonitorFormat.bytes(memory.swapUsed)),
                    .init(ContractCopy.copyMonitorMemoryPressure.text(for: language), pressureText(memory.pressure)),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .memory, language: language)
        }
    }

    @ViewBuilder
    private var diskCard: some View {
        if let disk = snapshot.disk, disk.total > 0 {
            let fraction = disk.used / disk.total
            MonitorGaugeCard(
                kind: .disk,
                fraction: fraction,
                value: MonitorFormat.percent(fraction),
                history: history.disk,
                accent: MonitorCardKind.disk.accent,
                language: language,
                perCore: nil,
                details: [
                    .init(ContractCopy.copyMonitorDiskRead.text(for: language), MonitorFormat.rate(disk.readRate)),
                    .init(ContractCopy.copyMonitorDiskWrite.text(for: language), MonitorFormat.rate(disk.writeRate)),
                    .init(ContractCopy.copyMonitorDiskFree.text(for: language), MonitorFormat.bytes(disk.free)),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .disk, language: language)
        }
    }

    @ViewBuilder
    private var powerCard: some View {
        if let power = snapshot.power {
            MonitorPowerCard(
                power: power,
                history: powerHistory,
                language: language,
                reduceMotion: reduceMotion,
                onOpenApp: openApplication
            )
        } else {
            MonitorPowerCard(
                power: MonitorSnapshot.Power.empty,
                history: powerHistory,
                language: language,
                reduceMotion: reduceMotion,
                onOpenApp: openApplication
            )
        }
    }

    @ViewBuilder
    private var networkCard: some View {
        if let network = snapshot.network {
            MonitorNetworkCard(
                network: network,
                downloadHistory: history.download,
                uploadHistory: history.upload,
                language: language
            )
        } else {
            MonitorUnavailableCard(kind: .network, language: language)
        }
    }

    private func pressureText(_ pressure: MonitorSnapshot.MemoryPressure) -> String {
        switch pressure {
        case .normal: ContractCopy.copyMonitorMemoryPressureNormal.text(for: language)
        case .warning: ContractCopy.copyMonitorMemoryPressureWarning.text(for: language)
        case .critical: ContractCopy.copyMonitorMemoryPressureCritical.text(for: language)
        }
    }

    private func openApplication(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
    }
}

// MARK: - 卡片种类

private enum MonitorCardKind {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case power

    var title: LocalizedCopy {
        switch self {
        case .cpu: ContractCopy.copyMonitorTitleCpu
        case .gpu: ContractCopy.copyMonitorTitleGpu
        case .memory: ContractCopy.copyMonitorTitleMemory
        case .disk: ContractCopy.copyMonitorTitleDisk
        case .network: ContractCopy.copyMonitorTitleNetwork
        case .power: ContractCopy.copyMonitorTitleBattery
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up.fill"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .power: "powerplug.fill"
        }
    }

    var accent: Color {
        switch self {
        case .cpu: MacTheme.color(ContractColors.tokenColorBrand)
        case .gpu: MacTheme.accent
        case .memory: MacTheme.color(ContractColors.tokenColorSuccessFill)
        case .disk: MacTheme.color(ContractColors.tokenColorWarningFill)
        case .network: MacTheme.color(ContractColors.tokenColorErrorText)
        case .power: MacTheme.color(ContractColors.tokenColorSuccessFill)
        }
    }
}

// MARK: - 电源卡片

private struct MonitorPowerCard: View {
    let power: MonitorSnapshot.Power
    let history: MonitorPowerHistory
    let language: AppLanguage
    let reduceMotion: Bool
    let onOpenApp: (String) -> Void

    @AppStorage("monitor.power.detailsExpanded") private var detailsExpanded = false
    @State private var detailsPresented = false
    @State private var chargingPulse = false
    @FocusState private var isFocused: Bool

    private var lowBattery: Bool {
        guard let percent = power.batteryPercent else { return false }
        return percent < MonitorPowerFormat.lowBatteryPercent
    }

    private var criticalBattery: Bool {
        guard let percent = power.batteryPercent else { return false }
        return percent < MonitorPowerFormat.criticalBatteryPercent
    }

    private var highTemperature: Bool {
        guard let value = power.temperatureCelsius else { return false }
        return value >= MonitorPowerFormat.highTemperatureCelsius
    }

    private var accent: Color {
        switch power.supply {
        case .charging, .adapter:
            MacTheme.successText
        case .battery:
            lowBattery ? MacTheme.errorText : MacTheme.brand
        case .unknown:
            MacTheme.textSecondary
        }
    }

    private var temperatureAccent: Color {
        highTemperature ? MacTheme.errorText : MacTheme.warningText
    }

    private var batteryColor: Color {
        lowBattery ? MacTheme.errorText : MacTheme.textPrimary
    }

    private var statusText: String {
        switch power.supply {
        case .battery: ContractCopy.copyMonitorPowerStateBattery.text(for: language)
        case .charging: ContractCopy.copyMonitorStateCharging.text(for: language)
        case .adapter: ContractCopy.copyMonitorPowerStateConnected.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var detailActionText: String {
        detailsPresented
            ? ContractCopy.copyMonitorPowerDetailsCollapse.text(for: language)
            : ContractCopy.copyMonitorPowerDetailsExpand.text(for: language)
    }

    var body: some View {
        Button {
            toggleDetails()
        } label: {
            MonitorCardShell(
                kind: .power,
                accent: accent,
                language: language,
                combinesAccessibility: false
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    primaryRow
                    MonitorPowerTrendSection(
                        power: power,
                        history: history,
                        language: language,
                        powerAccent: accent,
                        temperatureAccent: temperatureAccent
                    )
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Text(detailActionText)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accent)
                            .rotationEffect(detailsPresented ? .degrees(90) : .zero)
                            .animation(
                                .easeInOut(duration: MonitorPowerFormat.detailAnimationSeconds),
                                value: detailsPresented
                            )
                    }
                    .frame(height: 12)
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
            detailsPresented = detailsExpanded
        }
        .onChange(of: detailsPresented) { _, presented in
            detailsExpanded = presented
        }
        .popover(isPresented: $detailsPresented, arrowEdge: .trailing) {
            MonitorPowerDetailPanel(
                power: power,
                history: history,
                language: language,
                reduceMotion: reduceMotion,
                onOpenApp: onOpenApp,
                onClose: { detailsPresented = false }
            )
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
        .accessibilityHint(detailActionText)
        .task(id: power.supply) {
            chargingPulse = false
            guard power.supply == .charging, !reduceMotion else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.7)) {
                    chargingPulse.toggle()
                }
                do {
                    try await Task.sleep(for: .milliseconds(700))
                } catch {
                    break
                }
            }
        }
    }

    private var accessibilityLabel: String {
        let percent = MonitorPowerFormat.percent(power.batteryPercent)
        let temperature = MonitorPowerFormat.temperature(power.temperatureCelsius)
        return "\(ContractCopy.copyMonitorTitleBattery.text(for: language)), \(statusText), \(percent), \(temperature)"
    }

    private func toggleDetails() {
        detailsPresented.toggle()
    }

    private var primaryRow: some View {
        HStack(alignment: .center, spacing: MacTheme.space2) {
            MonitorPowerSymbol(
                power: power,
                accent: accent,
                chargingPulse: chargingPulse,
                reduceMotion: reduceMotion
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    if lowBattery {
                        Image(systemName: criticalBattery ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MacTheme.errorText)
                    }
                }

                if power.hasBattery {
                    Text(MonitorPowerFormat.percent(power.batteryPercent))
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .foregroundStyle(batteryColor)
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text(ContractCopy.copyMonitorPowerNoBattery.text(for: language))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .lineLimit(1)
                }

                if let hint = warningHint {
                    Label(hint.text, systemImage: hint.symbol)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(hint.color)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var warningHint: (text: String, symbol: String, color: Color)? {
        if criticalBattery {
            return (
                ContractCopy.copyMonitorPowerCriticalBattery.text(for: language),
                "exclamationmark.octagon.fill",
                MacTheme.errorText
            )
        }
        if lowBattery {
            return (
                ContractCopy.copyMonitorPowerLowBattery.text(for: language),
                "exclamationmark.triangle.fill",
                MacTheme.errorText
            )
        }
        if highTemperature {
            return (
                ContractCopy.copyMonitorPowerHighTemperature.text(for: language),
                "thermometer.high",
                MacTheme.errorText
            )
        }
        if power.hasReadFailure {
            return (
                ContractCopy.copyMonitorPowerReadFailed.text(for: language),
                "exclamationmark.triangle.fill",
                MacTheme.warningText
            )
        }
        return nil
    }
}

private struct MonitorPowerTrendSection: View {
    let power: MonitorSnapshot.Power
    let history: MonitorPowerHistory
    let language: AppLanguage
    let powerAccent: Color
    let temperatureAccent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(ContractCopy.copyMonitorPowerTrendTitle.text(for: language))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: 0)
                Text(ContractCopy.copyMonitorPowerTrendWindow.text(for: language))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            HStack(spacing: 8) {
                trendLegend(
                    symbol: "bolt.fill",
                    value: MonitorPowerFormat.watts(power.watts),
                    color: powerAccent
                )
                trendLegend(
                    symbol: "thermometer.medium",
                    value: MonitorPowerFormat.temperature(power.temperatureCelsius),
                    color: temperatureAccent
                )
                Spacer(minLength: 0)
            }

            MonitorPowerDualLineChart(
                powerValues: history.recentPower.map(Optional.some),
                temperatureValues: power.hasBattery
                    ? history.recentTemperature.map(Optional.some)
                    : [],
                powerAccent: powerAccent,
                temperatureAccent: temperatureAccent,
                emptyText: ContractCopy.copyMonitorPowerHistoryAccumulating.text(for: language)
            )
            .frame(height: 48)
        }
        .padding(7)
        .background(
            MacTheme.surface.opacity(0.28),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func trendLegend(symbol: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .monospacedDigit()
        }
    }
}

private struct MonitorPowerDualLineChart: View {
    let powerValues: [Double?]
    let temperatureValues: [Double?]
    let powerAccent: Color
    let temperatureAccent: Color
    let emptyText: String

    var body: some View {
        GeometryReader { proxy in
            let powerCount = validCount(powerValues)
            let temperatureCount = validCount(temperatureValues)
            let hasAnyData = powerCount + temperatureCount > 0
            let hasEnoughData = max(powerCount, temperatureCount) >= 2
            ZStack {
                linePath(values: powerValues, in: proxy.size, zeroBaseline: true)
                    .stroke(
                        powerAccent,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                linePath(values: temperatureValues, in: proxy.size, zeroBaseline: false)
                    .stroke(
                        temperatureAccent.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
                markerPath(values: powerValues, in: proxy.size, zeroBaseline: true)
                    .fill(powerAccent)
                markerPath(values: temperatureValues, in: proxy.size, zeroBaseline: false)
                    .fill(temperatureAccent)

                if !hasAnyData {
                    Text(emptyText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasEnoughData {
                    Text(emptyText)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MacTheme.surface.opacity(0.72), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func validCount(_ values: [Double?]) -> Int {
        values.filter { $0?.isFinite == true }.count
    }

    private func markerPath(
        values: [Double?],
        in size: CGSize,
        zeroBaseline: Bool
    ) -> Path {
        let finiteValues = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard let lastIndex = values.lastIndex(where: { $0?.isFinite == true }),
              let lastValue = values[lastIndex],
              !finiteValues.isEmpty
        else { return Path() }

        let minimum = zeroBaseline ? 0 : (finiteValues.min() ?? 0) - 1
        let maximum = zeroBaseline
            ? max(finiteValues.max() ?? 1, 0.1)
            : max((finiteValues.max() ?? 1) + 1, minimum + 1)
        let span = max(0.001, maximum - minimum)
        let denominator = max(1, values.count - 1)
        let x = values.count == 1
            ? size.width
            : size.width * CGFloat(lastIndex) / CGFloat(denominator)
        let normalized = min(1, max(0, (lastValue - minimum) / span))
        let y = size.height - CGFloat(normalized) * max(0, size.height - 2) - 1
        var path = Path()
        path.addEllipse(in: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6))
        return path
    }

    private func linePath(
        values: [Double?],
        in size: CGSize,
        zeroBaseline: Bool
    ) -> Path {
        let finiteValues = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard !finiteValues.isEmpty else { return Path() }

        let minimum = zeroBaseline ? 0 : (finiteValues.min() ?? 0) - 1
        let maximum = zeroBaseline
            ? max(finiteValues.max() ?? 1, 0.1)
            : max((finiteValues.max() ?? 1) + 1, minimum + 1)
        let span = max(0.001, maximum - minimum)
        let denominator = max(1, values.count - 1)
        var path = Path()
        var hasCurrentPoint = false

        for (index, raw) in values.enumerated() {
            guard let value = raw, value.isFinite else {
                hasCurrentPoint = false
                continue
            }
            let x = values.count == 1
                ? size.width
                : size.width * CGFloat(index) / CGFloat(denominator)
            let normalized = min(1, max(0, (value - minimum) / span))
            let y = size.height - CGFloat(normalized) * max(0, size.height - 2) - 1
            let point = CGPoint(x: x, y: y)
            if hasCurrentPoint {
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            hasCurrentPoint = true
        }
        return path
    }
}

// MARK: - 可展开详情

struct MonitorPowerDetailPanel: View {
    let power: MonitorSnapshot.Power
    let history: MonitorPowerHistory
    let language: AppLanguage
    let reduceMotion: Bool
    let onOpenApp: (String) -> Void
    let onClose: () -> Void

    private var detailHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 800
        return min(620, max(300, available - 140))
    }

    var body: some View {
        GeometryReader { proxy in
            let visibility = MonitorPowerDetailLayoutPolicy.resolve(height: proxy.size.height)
            VStack(alignment: .leading, spacing: 8) {
                header
                if visibility.showsTopApps {
                    topAppsSection
                }
                if visibility.showsHistory {
                    historySection
                }
                if visibility.showsEstimate, power.hasBattery {
                    estimateSection
                }
                if visibility.showsCharging,
                   power.hasBattery,
                   power.supply == .charging || power.supply == .adapter {
                    chargingSection
                }
                if visibility.showsEvents {
                    eventsSection
                }
                Spacer(minLength: 0)
            }
            .padding(MacTheme.space4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 480, height: detailHeight)
        .background(
            MacTheme.surface.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.8), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text(ContractCopy.copyMonitorPowerDetailsTitle.text(for: language))
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

    private var accent: Color {
        switch power.supply {
        case .charging, .adapter: MacTheme.successText
        case .battery: MacTheme.brand
        case .unknown: MacTheme.textSecondary
        }
    }

    private var topAppsSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerTopApps.text(for: language)
        ) {
            if power.energyDataAvailable, !power.topApps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(power.topApps.prefix(3))) { app in
                        if let bundlePath = app.bundlePath {
                            Button {
                                onOpenApp(bundlePath)
                            } label: {
                                topAppRow(app)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .frame(height: 28)
                            .accessibilityLabel(
                                "\(app.name), \(MonitorPowerFormat.energy(app.energyMilliwattHours)), \(MonitorPowerFormat.share(app.share))"
                            )
                        } else {
                            topAppRow(app)
                                .frame(height: 28)
                        }
                    }
                }
            } else {
                emptyRow(ContractCopy.copyMonitorPowerNoData.text(for: language))
            }
        }
    }

    private func topAppRow(_ app: MonitorSnapshot.Power.TopApp) -> some View {
        HStack(spacing: MacTheme.space2) {
            Text(app.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(MonitorPowerFormat.energy(app.energyMilliwattHours))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(MacTheme.textSecondary)
                .monospacedDigit()
            Text(MonitorPowerFormat.share(app.share))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var historySection: some View {
        let points = history.minutePoints
        return MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerHistoryTitle.text(for: language)
        ) {
            HStack(spacing: 10) {
                detailLegend(
                    symbol: "bolt.fill",
                    value: MonitorPowerFormat.watts(points.last?.watts),
                    color: MacTheme.successText
                )
                if power.hasBattery {
                    detailLegend(
                        symbol: "thermometer.medium",
                        value: MonitorPowerFormat.temperature(points.last?.temperatureCelsius),
                        color: MacTheme.warningText
                    )
                }
                Spacer(minLength: 0)
            }
            MonitorPowerDualLineChart(
                powerValues: points.map(\.watts),
                temperatureValues: power.hasBattery ? points.map(\.temperatureCelsius) : [],
                powerAccent: MacTheme.successText,
                temperatureAccent: MacTheme.warningText,
                emptyText: ContractCopy.copyMonitorPowerHistoryAccumulating.text(for: language)
            )
            .frame(height: 104)
        }
    }

    private var estimateSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerRemaining.text(for: language)
        ) {
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerRemaining.text(for: language),
                value: MonitorPowerFormat.remaining(power.remainingSeconds, language: language),
                symbol: "hourglass"
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerAverageDraw.text(for: language),
                value: MonitorPowerFormat.watts(power.averageWatts),
                symbol: "chart.line.uptrend.xyaxis"
            )
            Text(ContractCopy.copyMonitorPowerEstimateBasis.text(for: language))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    private var chargingSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerChargeTitle.text(for: language)
        ) {
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargePower.text(for: language),
                value: MonitorPowerFormat.watts(power.chargePowerWatts),
                symbol: "bolt.fill",
                color: MacTheme.successText
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargeTimeToFull.text(for: language),
                value: MonitorPowerFormat.remaining(power.timeToFullSeconds, language: language),
                symbol: "timer"
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargeHealth.text(for: language),
                value: MonitorPowerFormat.percent(power.batteryHealthPercent),
                symbol: "heart.text.square"
            )
        }
    }

    private var eventsSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerEventsTitle.text(for: language)
        ) {
            if power.events.isEmpty {
                emptyRow(ContractCopy.copyMonitorPowerNoData.text(for: language))
            } else {
                ForEach(Array(power.events.suffix(3).reversed())) { event in
                    HStack(spacing: MacTheme.space2) {
                        Image(systemName: eventSymbol(event.kind))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(eventColor(event.kind))
                            .frame(width: 12)
                        Text(eventText(event.kind))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                        Spacer(minLength: 4)
                        Text(MonitorPowerFormat.eventTime(event.at, language: language))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(height: 22)
                }
            }
        }
    }

    private func detailLegend(symbol: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .monospacedDigit()
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(MacTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
    }

    private func eventText(_ kind: MonitorPowerEvent.Kind) -> String {
        switch kind {
        case .connected: ContractCopy.copyMonitorPowerEventsConnected.text(for: language)
        case .disconnected: ContractCopy.copyMonitorPowerEventsDisconnected.text(for: language)
        case .fullyCharged: ContractCopy.copyMonitorPowerEventsFullyCharged.text(for: language)
        }
    }

    private func eventSymbol(_ kind: MonitorPowerEvent.Kind) -> String {
        switch kind {
        case .connected: "powerplug.fill"
        case .disconnected: "powerplug"
        case .fullyCharged: "battery.100percent.bolt"
        }
    }

    private func eventColor(_ kind: MonitorPowerEvent.Kind) -> Color {
        switch kind {
        case .connected, .fullyCharged: MacTheme.successText
        case .disconnected: MacTheme.textSecondary
        }
    }
}

private struct MonitorPowerDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MacTheme.elevated.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}

private struct MonitorPowerDetailRow: View {
    let label: String
    let value: String
    let symbol: String
    var color: Color = MacTheme.textPrimary

    var body: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(height: 18)
        .accessibilityElement(children: .combine)
    }
}

private struct MonitorPowerSymbol: View {
    let power: MonitorSnapshot.Power
    let accent: Color
    let chargingPulse: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbolName)
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .frame(width: 42, height: 32)

            if power.supply == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.successText)
                    .padding(3)
                    .background(MacTheme.successText.opacity(0.14), in: Circle())
                    .opacity(reduceMotion || chargingPulse ? 1 : 0.38)
                    .scaleEffect(reduceMotion || chargingPulse ? 1 : 0.86)
            }
        }
        .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch power.supply {
        case .battery:
            batterySymbol
        case .charging, .adapter:
            "powerplug.fill"
        case .unknown:
            "questionmark.circle"
        }
    }

    private var batterySymbol: String {
        let fraction = min(1, max(0, (power.batteryPercent ?? 0) / 100))
        return switch fraction {
        case ..<0.125: "battery.0percent"
        case ..<0.375: "battery.25percent"
        case ..<0.625: "battery.50percent"
        case ..<0.875: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

// MARK: - 仪表卡片

private struct MonitorDetail: Identifiable {
    let label: String
    let value: String
    var id: String { "\(label):\(value)" }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

private struct MonitorGaugeCard: View {
    let kind: MonitorCardKind
    let fraction: Double
    let value: String
    let history: [Double]
    let accent: Color
    let language: AppLanguage
    let perCore: [Double]?
    let details: [MonitorDetail]

    var body: some View {
        MonitorCardShell(kind: kind, accent: accent, language: language) {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                HStack(spacing: MacTheme.space3) {
                    MonitorRing(fraction: fraction, accent: accent, value: value)
                    VStack(alignment: .leading, spacing: MacTheme.space1) {
                        Text(ContractCopy.copyMonitorUsage.text(for: language))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                        MonitorSparkline(values: history, accent: accent)
                            .frame(height: 58)
                    }
                }

                if let perCore {
                    MonitorCoreBars(values: perCore, accent: accent)
                }

                Spacer(minLength: 0)
                detailsView
            }
        }
    }

    private var detailsView: some View {
        VStack(spacing: 4) {
            ForEach(details.prefix(3)) { detail in
                HStack(spacing: MacTheme.space2) {
                    Text(detail.label)
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer(minLength: MacTheme.space1)
                    Text(detail.value)
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 9, weight: .medium))
    }
}

private struct MonitorNetworkCard: View {
    let network: MonitorSnapshot.Network
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let language: AppLanguage

    var body: some View {
        MonitorCardShell(kind: .network, accent: MonitorCardKind.network.accent, language: language) {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                HStack(spacing: MacTheme.space3) {
                    rateBlock(
                        title: ContractCopy.copyMonitorNetworkDownload.text(for: language),
                        value: MonitorFormat.rate(network.downloadRate),
                        symbol: "arrow.down",
                        color: MacTheme.accent
                    )
                    Divider().frame(height: 34)
                    rateBlock(
                        title: ContractCopy.copyMonitorNetworkUpload.text(for: language),
                        value: MonitorFormat.rate(network.uploadRate),
                        symbol: "arrow.up",
                        color: MacTheme.errorText
                    )
                }

                ZStack(alignment: .bottom) {
                    MonitorSparkline(values: uploadHistory, accent: MacTheme.errorText.opacity(0.65))
                    MonitorSparkline(values: downloadHistory, accent: MacTheme.accent)
                }
                .frame(height: 54)
                .padding(.top, MacTheme.space1)

                Spacer(minLength: 0)
                HStack(spacing: MacTheme.space2) {
                    Text(ContractCopy.copyMonitorNetworkInterface.text(for: language))
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer(minLength: MacTheme.space1)
                    Text(network.interfaceName)
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
            }
        }
    }

    private func rateBlock(title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MonitorUnavailableCard: View {
    let kind: MonitorCardKind
    let language: AppLanguage

    var body: some View {
        MonitorCardShell(kind: kind, accent: kind.accent, language: language) {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                Spacer(minLength: 0)
                Image(systemName: "waveform.slash")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(kind.accent.opacity(0.85))
                Text(ContractCopy.copyMonitorUnavailable.text(for: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct MonitorCardShell<Content: View>: View {
    let kind: MonitorCardKind
    let accent: Color
    let language: AppLanguage
    var combinesAccessibility = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            HStack(spacing: MacTheme.space2) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 16, height: 16)
                Text(kind.title.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: MacTheme.space1)
                Text(ContractCopy.copyMonitorLive.text(for: language).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            content
        }
        .padding(MacTheme.space3)
        .frame(maxWidth: .infinity).frame(height: HubMetrics.monitorCardHeight, alignment: .topLeading)
        .background(cardBackground, in: shape)
        .glassSurface(cornerRadius: MacTheme.cardRadius)
        .overlay(shape.strokeBorder(accent.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: combinesAccessibility ? .combine : .contain)
        .accessibilityLabel(kind.title.text(for: language))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(0.22),
                accent.opacity(0.08),
                MacTheme.surface.opacity(0.62),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 图形件

private struct MonitorRing: View {
    let fraction: Double
    let accent: Color
    let value: String

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(MacTheme.divider.opacity(0.8), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.002, clamped))
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.45), accent, accent.opacity(0.72)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.28), value: clamped)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

private struct MonitorSparkline: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let line = linePath(in: proxy.size)
            ZStack {
                areaPath(in: proxy.size)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.28), accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                line
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.7), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let capacity = max(2, values.count)
        let maximum = max(values.max() ?? 0, 0.000_001)
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(1, capacity - 1))
            let y = size.height - (size.height - 3) * CGFloat(min(1, max(0, value / maximum)))
            return CGPoint(x: x, y: max(1.5, y))
        }
    }

    private func linePath(in size: CGSize) -> Path {
        let points = normalizedPoints(in: size)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func areaPath(in size: CGSize) -> Path {
        let points = normalizedPoints(in: size)
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

private struct MonitorCoreBars: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.prefix(16).enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(accent.opacity(0.35 + min(0.65, max(0, value) * 0.65)))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 18 * min(1, max(0, value))))
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
