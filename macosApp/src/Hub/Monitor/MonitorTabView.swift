import SwiftUI

/// Stats 风格的实时监控页。
///
/// 页面只在自己出现时运行采样任务。`HubView` 切到别的页后，SwiftUI 会取消
/// `.task`，采样器随之停止。
struct MonitorTabView: View {
    let language: AppLanguage
    private let runsSampling: Bool

    @State private var snapshot: MonitorSnapshot
    @State private var history: MonitorHistory
    @State private var sampler = MonitorSampler()

    init(
        language: AppLanguage,
        initialSnapshot: MonitorSnapshot = .empty,
        initialHistory: MonitorHistory = MonitorHistory(),
        runsSampling: Bool = true
    ) {
        self.language = language
        self.runsSampling = runsSampling
        _snapshot = State(initialValue: initialSnapshot)
        _history = State(initialValue: initialHistory)
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
                if snapshot.battery != nil {
                    batteryCard
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard runsSampling else { return }
            await runSamples()
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
    private var batteryCard: some View {
        if let battery = snapshot.battery {
            MonitorGaugeCard(
                kind: .battery,
                fraction: battery.percent / 100,
                value: MonitorFormat.percent(battery.percent / 100),
                history: history.battery,
                accent: MonitorCardKind.battery.accent,
                language: language,
                perCore: nil,
                details: [
                    .init(ContractCopy.copyMonitorBatteryState.text(for: language), batteryStateText(battery.state)),
                    .init(ContractCopy.copyMonitorBatteryRemaining.text(for: language), MonitorFormat.duration(battery.remaining)),
                ]
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

    private func batteryStateText(_ state: MonitorSnapshot.BatteryState) -> String {
        switch state {
        case .charging: ContractCopy.copyMonitorStateCharging.text(for: language)
        case .discharging: ContractCopy.copyMonitorStateOnBattery.text(for: language)
        case .charged: ContractCopy.copyMonitorStateCharged.text(for: language)
        case .acPower: ContractCopy.copyMonitorStateAcPower.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }
}

// MARK: - 卡片种类

private enum MonitorCardKind {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case battery

    var title: LocalizedCopy {
        switch self {
        case .cpu: ContractCopy.copyMonitorTitleCpu
        case .gpu: ContractCopy.copyMonitorTitleGpu
        case .memory: ContractCopy.copyMonitorTitleMemory
        case .disk: ContractCopy.copyMonitorTitleDisk
        case .network: ContractCopy.copyMonitorTitleNetwork
        case .battery: ContractCopy.copyMonitorTitleBattery
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up.fill"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .battery: "battery.75percent"
        }
    }

    var accent: Color {
        switch self {
        case .cpu: MacTheme.color(ContractColors.tokenColorBrand)
        case .gpu: MacTheme.accent
        case .memory: MacTheme.color(ContractColors.tokenColorSuccessFill)
        case .disk: MacTheme.color(ContractColors.tokenColorWarningFill)
        case .network: MacTheme.color(ContractColors.tokenColorErrorText)
        case .battery: MacTheme.color(ContractColors.tokenColorSuccessFill)
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
        .accessibilityElement(children: .combine)
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
