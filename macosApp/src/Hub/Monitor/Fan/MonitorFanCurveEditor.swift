import Charts
import SwiftUI

/// 每风扇多点温控曲线编辑器。
///
/// 曲线本身使用 Apple Swift Charts。拖动只改本地草稿，
/// 手势结束或滑杆结束编辑后才向 helper 提交，避免拖动期间连续写配置。
struct MonitorFanCurveEditor: View {
    let reading: MonitorFanReading
    let configuration: MonitorFanConfiguration
    let language: AppLanguage
    let powerSource: MonitorFanPowerSource
    let interactive: Bool
    let busy: Bool
    let onCommit: (Int?, MonitorFanCurveSource, [MonitorFanCurvePoint]) -> Void
    let onClear: (Int?, MonitorFanCurveSource) -> Void
    let onCopyAdapterCurves: () -> Void

    @State private var selectedFanIndex: Int?
    @State private var selectedCurveSource: MonitorFanCurveSource?
    @State private var selectedPointIndex = 0
    @State private var draftPoints: [MonitorFanCurvePoint] = []
    @State private var draggingPointIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(ContractCopy.copyMonitorFanCurve.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                Text(ContractCopy.copyMonitorFanCurveHint.text(for: language))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            powerStatus
            curveSourcePicker
            if editingCurveSource == .battery, hasBatteryCurveFallback {
                batteryFallback
            }
            fanPicker
            chartWithInteraction
            pointSelector

            if draftPoints.indices.contains(selectedPointIndex) {
                pointEditor(index: selectedPointIndex)
            }

            if !interactive {
                Text(curveAccessibilityValue)
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textSecondary)
            }
        }
        .onAppear(perform: syncDraft)
        .onChange(of: selectedFanIndex) { _, _ in
            selectedPointIndex = 0
            syncDraft()
        }
        .onChange(of: selectedCurveSource) { _, _ in
            selectedPointIndex = 0
            syncDraft()
        }
        .onChange(of: powerSource) { _, source in
            if selectedCurveSource == nil {
                selectedCurveSource = source.curveSource
            }
        }
        .onChange(of: configuration) { _, _ in
            syncDraft()
        }
    }

    private var powerStatus: some View {
        HStack(spacing: 6) {
            Label {
                Text(powerSourceTitle)
                    .lineLimit(1)
            } icon: {
                Image(systemName: powerSourceIcon)
            }
            .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 0)
            Text(activeCurveText)
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 8, weight: .medium))
    }

    private var curveSourcePicker: some View {
        Picker(ContractCopy.copyMonitorFanCurveSource.text(for: language), selection: Binding(
            get: { editingCurveSource },
            set: { selectedCurveSource = $0 }
        )) {
            Text(ContractCopy.copyMonitorFanCurveSourceAdapter.text(for: language))
                .tag(MonitorFanCurveSource.adapter)
            Text(ContractCopy.copyMonitorFanCurveSourceBattery.text(for: language))
                .tag(MonitorFanCurveSource.battery)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(busy)
    }

    private var batteryFallback: some View {
        HStack(spacing: 8) {
            Text(ContractCopy.copyMonitorFanBatteryCurveFallback.text(for: language))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.warningText)
            Spacer(minLength: 0)
            Button(ContractCopy.copyMonitorFanCopyAdapterCurve.text(for: language)) {
                onCopyAdapterCurves()
                syncDraft()
            }
            .buttonStyle(.link)
            .font(.system(size: 8, weight: .semibold))
            .disabled(busy)
        }
        .padding(7)
        .background(
            MacTheme.warningBackground.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var fanPicker: some View {
        Picker(ContractCopy.copyMonitorFanDetails.text(for: language), selection: $selectedFanIndex) {
            Text(ContractCopy.copyMonitorFanAllFans.text(for: language))
                .tag(nil as Int?)
            ForEach(reading.units) { fan in
                Text(String(format: ContractCopy.copyMonitorFanUnit.text(for: language), fan.index + 1))
                    .tag(Optional(fan.index))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(busy)
    }

    private var editingCurveSource: MonitorFanCurveSource {
        selectedCurveSource ?? powerSource.curveSource
    }

    private var editingFanIndices: [Int] {
        selectedFanIndex.map { [$0] } ?? reading.units.map(\.index)
    }

    private var hasBatteryCurveFallback: Bool {
        editingFanIndices.contains { fanIndex in
            !configuration.hasCustomCurve(for: fanIndex, source: .battery)
        }
    }

    private var clearCurveTitle: String {
        editingCurveSource == .battery
            ? ContractCopy.copyMonitorFanClearBatteryCurve.text(for: language)
            : ContractCopy.copyMonitorFanResetCurve.text(for: language)
    }

    private var canClearCurve: Bool {
        editingCurveSource == .adapter || editingFanIndices.contains { fanIndex in
            configuration.hasCustomCurve(for: fanIndex, source: .battery)
        }
    }

    private var activeCurveText: String {
        guard powerSource == .battery else {
            return ContractCopy.copyMonitorFanActiveCurveAdapter.text(for: language)
        }
        let indices = reading.units.map(\.index)
        let batteryCount = indices.filter {
            configuration.hasCustomCurve(for: $0, source: .battery)
        }.count
        if batteryCount == 0 {
            return ContractCopy.copyMonitorFanActiveCurveAdapter.text(for: language)
        }
        if batteryCount == indices.count {
            return ContractCopy.copyMonitorFanActiveCurveBattery.text(for: language)
        }
        return ContractCopy.copyMonitorFanActiveCurveMixed.text(for: language)
    }

    private var powerSourceTitle: String {
        switch powerSource {
        case .adapter:
            ContractCopy.copyMonitorFanPowerSourceAdapter.text(for: language)
        case .battery:
            ContractCopy.copyMonitorFanPowerSourceBattery.text(for: language)
        case .unknown:
            ContractCopy.copyMonitorFanPowerSourceUnknown.text(for: language)
        }
    }

    private var powerSourceIcon: String {
        switch powerSource {
        case .adapter:
            "powerplug"
        case .battery:
            "battery.75percent"
        case .unknown:
            "questionmark.circle"
        }
    }

    private var chart: some View {
        Chart(draftPoints) { point in
            LineMark(
                x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), point.temperature),
                y: .value(ContractCopy.copyMonitorFanRpm.text(for: language), point.rpm)
            )
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .foregroundStyle(MacTheme.accent)

            PointMark(
                x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), point.temperature),
                y: .value(ContractCopy.copyMonitorFanRpm.text(for: language), point.rpm)
            )
            .symbolSize(58)
            .foregroundStyle(MacTheme.accent)
        }
        .chartXScale(domain: MonitorFanPolicy.minimumCurveCelsius...MonitorFanPolicy.maximumFullCelsius)
        .chartYScale(domain: displayRange)
        .chartXAxis {
            AxisMarks(values: [40, 60, 80, 100])
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(MacTheme.material.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .frame(height: 148)
        .animation(nil, value: draftPoints)
    }

    @ViewBuilder
    private var chartWithInteraction: some View {
        if interactive {
            chart.chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(proxy: proxy, geometry: geometry))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ContractCopy.copyMonitorFanA11yCurve.text(for: language))
            .accessibilityValue(curveAccessibilityValue)
        } else {
            chart
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ContractCopy.copyMonitorFanA11yCurve.text(for: language))
                .accessibilityValue(curveAccessibilityValue)
        }
    }

    private var pointSelector: some View {
        HStack(spacing: 5) {
            ForEach(draftPoints.indices, id: \.self) { index in
                Button("\(index + 1)") {
                    selectedPointIndex = index
                }
                .buttonStyle(.plain)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(index == selectedPointIndex ? Color.white : MacTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    index == selectedPointIndex ? MacTheme.accent : MacTheme.elevated,
                    in: Capsule()
                )
                .disabled(busy)
            }
            Spacer(minLength: 0)
            Button(ContractCopy.copyMonitorFanAddPoint.text(for: language)) {
                addPoint()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(busy || draftPoints.count >= MonitorFanPolicy.maximumCurvePointCount)
            Button(ContractCopy.copyMonitorFanDeletePoint.text(for: language)) {
                deletePoint()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(busy || draftPoints.count <= 2)
        }
    }

    private func pointEditor(index: Int) -> some View {
        let point = draftPoints[index]
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(String(
                    format: ContractCopy.copyMonitorFanControlPoint.text(for: language),
                    index + 1
                ))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: 0)
                Text("\(Int(point.temperature.rounded())) °C · \(Int(point.rpm.rounded())) RPM")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Text(ContractCopy.copyMonitorFanTemperature.text(for: language))
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 30, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { draftPoints[index].temperature },
                        set: { updatePoint(index, temperature: $0, rpm: draftPoints[index].rpm) }
                    ),
                    in: MonitorFanPolicy.minimumCurveCelsius...MonitorFanPolicy.maximumFullCelsius
                ) { editing in
                    if !editing { commitDraft() }
                }
                .disabled(busy)
            }

            HStack(spacing: 8) {
                Text(ContractCopy.copyMonitorFanRpm.text(for: language))
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 30, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { draftPoints[index].rpm },
                        set: {
                            updatePoint(
                                index,
                                temperature: draftPoints[index].temperature,
                                rpm: ($0 / 50).rounded() * 50
                            )
                        }
                    ),
                    in: displayRange
                ) { editing in
                    if !editing { commitDraft() }
                }
                .disabled(busy)
            }

            Button(clearCurveTitle) {
                onClear(selectedFanIndex, editingCurveSource)
                syncDraft()
            }
            .buttonStyle(.link)
            .font(.system(size: 9))
            .disabled(busy || !canClearCurve)
        }
    }

    private var displayRange: ClosedRange<Double> {
        guard let first = reading.units.first else {
            return 0...MonitorFanPolicy.maximumRPM
        }
        if let selectedFanIndex,
           let fan = reading.units.first(where: { $0.index == selectedFanIndex }) {
            return fan.minimumRPM...max(fan.minimumRPM + 1, fan.maximumRPM)
        }
        let minimum = reading.units.map(\.minimumRPM).min() ?? first.minimumRPM
        let maximum = reading.units.map(\.maximumRPM).max() ?? first.maximumRPM
        return minimum...max(minimum + 1, maximum)
    }

    private var curveAccessibilityValue: String {
        draftPoints
            .map {
                "\(Int($0.temperature.rounded())) °C \(Int($0.rpm.rounded())) RPM"
            }
            .joined(separator: "，")
    }

    private func syncDraft() {
        let sourceCurves = configuration.customCurves(for: editingCurveSource)
        let fanIndex = selectedFanIndex
            ?? reading.units.first(where: { sourceCurves[String($0.index)] != nil })?.index
            ?? reading.units.first?.index
            ?? 0
        let fan = reading.units.first(where: { $0.index == fanIndex })
        let minimum = fan?.minimumRPM ?? 0
        let maximum = fan?.maximumRPM ?? MonitorFanPolicy.maximumRPM
        draftPoints = configuration.curvePoints(
            for: fanIndex,
            minimumRPM: minimum,
            maximumRPM: maximum,
            source: editingCurveSource
        )
        selectedPointIndex = min(selectedPointIndex, max(0, draftPoints.count - 1))
    }

    private func addPoint() {
        guard draftPoints.count < MonitorFanPolicy.maximumCurvePointCount else { return }
        var sorted = draftPoints.sorted { $0.temperature < $1.temperature }
        guard sorted.count >= 2 else { return }
        var insertAt = 1
        var largestGap = -Double.infinity
        for index in 1..<sorted.count {
            let gap = sorted[index].temperature - sorted[index - 1].temperature
            if gap > largestGap {
                largestGap = gap
                insertAt = index
            }
        }
        let before = sorted[insertAt - 1]
        let after = sorted[insertAt]
        sorted.insert(
            MonitorFanCurvePoint(
                temperature: ((before.temperature + after.temperature) / 2).rounded(),
                rpm: ((before.rpm + after.rpm) / 2 / 50).rounded() * 50
            ),
            at: insertAt
        )
        draftPoints = sorted
        selectedPointIndex = insertAt
        commitDraft()
    }

    private func deletePoint() {
        guard draftPoints.count > 2, draftPoints.indices.contains(selectedPointIndex) else { return }
        draftPoints.remove(at: selectedPointIndex)
        selectedPointIndex = min(selectedPointIndex, draftPoints.count - 1)
        commitDraft()
    }

    private func updatePoint(_ index: Int, temperature: Double, rpm: Double) {
        guard draftPoints.indices.contains(index) else { return }
        draftPoints[index] = MonitorFanCurvePoint(
            temperature: min(
                MonitorFanPolicy.maximumFullCelsius,
                max(MonitorFanPolicy.minimumCurveCelsius, temperature.rounded())
            ),
            rpm: min(displayRange.upperBound, max(displayRange.lowerBound, rpm))
        )
    }

    private func commitDraft() {
        let sorted = draftPoints.sorted { $0.temperature < $1.temperature }
        draftPoints = sorted
        onCommit(selectedFanIndex, editingCurveSource, sorted)
    }

    private func dragGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let plotFrame = proxy.plotFrame else { return }
                let frame = geometry[plotFrame]
                if draggingPointIndex == nil {
                    draggingPointIndex = nearestPointIndex(
                        location: value.location,
                        frame: frame,
                        proxy: proxy
                    )
                    if let draggingPointIndex {
                        selectedPointIndex = draggingPointIndex
                    }
                }
                guard let index = draggingPointIndex, draftPoints.indices.contains(index) else { return }
                let x = value.location.x - frame.origin.x
                let y = value.location.y - frame.origin.y
                guard let temperature = proxy.value(atX: x, as: Double.self),
                      let rpm = proxy.value(atY: y, as: Double.self)
                else { return }
                updatePoint(index, temperature: temperature, rpm: (rpm / 50).rounded() * 50)
            }
            .onEnded { _ in
                draggingPointIndex = nil
                commitDraft()
            }
    }

    private func nearestPointIndex(location: CGPoint, frame: CGRect, proxy: ChartProxy) -> Int? {
        let candidates = draftPoints.indices.compactMap { index -> (Int, CGPoint)? in
            guard let x = proxy.position(forX: draftPoints[index].temperature),
                  let y = proxy.position(forY: draftPoints[index].rpm)
            else { return nil }
            return (index, CGPoint(x: frame.origin.x + x, y: frame.origin.y + y))
        }
        guard let nearest = candidates.min(by: {
            hypot($0.1.x - location.x, $0.1.y - location.y) <
                hypot($1.1.x - location.x, $1.1.y - location.y)
        }), hypot(nearest.1.x - location.x, nearest.1.y - location.y) <= 26 else {
            return nil
        }
        return nearest.0
    }
}
