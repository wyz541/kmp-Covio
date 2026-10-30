import SwiftUI

/// CPU、GPU 和电池来源的温度控制点编辑器。
///
/// 每个来源保存独立的温度到百分比曲线。底部摘要调用与 helper 相同的
/// `mergedTargetPercent`，只显示来源合并后的每台风扇请求。
struct MonitorFanTemperatureRuleEditor: View {
    let reading: MonitorFanReading
    let configuration: MonitorFanConfiguration
    let helperSourceTemperatures: [String: Double]
    let language: AppLanguage
    let busy: Bool
    let onToggleSource: (MonitorFanTemperatureSource, Bool) -> Void
    let onChangePoints: (
        MonitorFanTemperatureSource,
        [MonitorFanTemperatureRulePoint],
        Bool
    ) -> Void

    private var sourceTemperatures: [MonitorFanTemperatureSource: Double] {
        var values = configuration.temperatureSourceReadings(in: reading)
        for source in MonitorFanTemperatureSource.allCases where values[source] == nil {
            values[source] = helperSourceTemperatures[source.rawValue]
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ContractCopy.copyMonitorFanTemperatureSources.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                Text(ContractCopy.copyMonitorFanSourceHint.text(for: language))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            if !configuration.enabledTemperatureSources.isEmpty,
               !omittedThermalSources.isEmpty {
                sourceCoverageWarning
            }

            ForEach(MonitorFanTemperatureSource.allCases, id: \.self) { source in
                sourceEditor(source)
            }

            if !configuration.enabledTemperatureSources.isEmpty {
                mergedTargetSummary
            }
        }
    }

    private var omittedThermalSources: [MonitorFanTemperatureSource] {
        let enabled = Set(configuration.enabledTemperatureSources)
        return [MonitorFanTemperatureSource.cpu, .gpu].filter { !enabled.contains($0) }
    }

    private var sourceCoverageWarning: some View {
        let names = omittedThermalSources.map(sourceTitle)
        let separator = language == .english ? ", " : "、"
        return Label {
            Text(String(
                format: ContractCopy.copyMonitorFanSourceCoverageWarning.text(for: language),
                names.joined(separator: separator)
            ))
            .font(.system(size: 9, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(MacTheme.errorText)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverContentSurface(
            cornerRadius: 7,
            tint: MacTheme.errorText.opacity(0.10)
        )
    }

    private func sourceEditor(_ source: MonitorFanTemperatureSource) -> some View {
        let enabled = configuration.hasTemperatureRules(for: source)
        return VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(
                get: { enabled },
                set: { onToggleSource(source, $0) }
            )) {
                HStack(spacing: 6) {
                    Text(sourceTitle(source))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer(minLength: 0)
                    Text(sourceTemperatureText(source))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            sourceTemperatures[source] == nil
                                ? MacTheme.textSecondary
                                : MacTheme.accent
                        )
                        .monospacedDigit()
                    if !sourceRequestText(source).isEmpty {
                        Text(sourceRequestText(source))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(MacTheme.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(busy)
            .accessibilityLabel(sourceTitle(source))
            .accessibilityValue(sourceAccessibilityValue(source))

            if enabled {
                let points = configuredPoints(for: source)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(points.indices, id: \.self) { index in
                        pointEditor(source: source, index: index, points: points)
                    }
                }

                HStack(spacing: 6) {
                    Button {
                        addPoint(source: source, points: points)
                    } label: {
                        Label(
                            ContractCopy.copyMonitorFanAddTemperaturePoint.text(for: language),
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(
                        busy
                            || points.count >= MonitorFanPolicy.maximumRulePointCount
                            || !canAddPoint(to: points)
                    )

                    Spacer(minLength: 0)
                    Text(String(format: "%d / %d", points.count, MonitorFanPolicy.maximumRulePointCount))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(8)
        .background(
            MacTheme.material.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.45), lineWidth: 0.75)
        )
    }

    private func pointEditor(
        source: MonitorFanTemperatureSource,
        index: Int,
        points: [MonitorFanTemperatureRulePoint]
    ) -> some View {
        let point = points[index]
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("#\(index + 1)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 20, alignment: .leading)

                TextField(
                    "",
                    value: temperatureBinding(source: source, index: index, points: points),
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .accessibilityLabel(ContractCopy.copyMonitorFanTemperature.text(for: language))
                .accessibilityValue("\(Int(point.celsius.rounded())) °C")

                Text("°C")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)

                Text("→")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)

                TextField(
                    "",
                    value: percentBinding(source: source, index: index, points: points),
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .accessibilityLabel(ContractCopy.copyMonitorFanSourceFanPercentLabel.text(for: language))
                .accessibilityValue("\(Int(point.fanPercent.rounded()))%")

                Text("%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)

                Spacer(minLength: 0)

                Button {
                    deletePoint(source: source, index: index, points: points)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    points.count > 2 && !busy ? MacTheme.errorText : MacTheme.disabledText
                )
                .frame(width: 24, height: 24)
                .disabled(busy || points.count <= 2)
                .accessibilityLabel(ContractCopy.copyMonitorFanDeletePoint.text(for: language))
            }

            let temperatureRange = temperatureRange(for: index, points: points)
            if temperatureRange.lowerBound < temperatureRange.upperBound {
                temperatureSliderRow(
                    value: temperatureBinding(source: source, index: index, points: points),
                    range: temperatureRange,
                    accessibilityLabel: "\(sourceTitle(source)) \(controlPointTitle(index)) \(ContractCopy.copyMonitorFanTemperature.text(for: language))",
                    accessibilityValue: "\(Int(point.celsius.rounded())) °C",
                    onEditingChanged: { editing in
                        if !editing {
                            onChangePoints(source, configuredPoints(for: source), true)
                        }
                    }
                )
            } else {
                fixedValueRow(
                    title: ContractCopy.copyMonitorFanTemperature.text(for: language),
                    value: "\(Int(point.celsius.rounded())) °C"
                )
            }

            percentSliderRow(
                value: percentBinding(source: source, index: index, points: points),
                accessibilityLabel: "\(sourceTitle(source)) \(controlPointTitle(index)) \(ContractCopy.copyMonitorFanSourceFanPercentLabel.text(for: language))",
                accessibilityValue: "\(Int(point.fanPercent.rounded()))%",
                onEditingChanged: { editing in
                    if !editing {
                        onChangePoints(source, configuredPoints(for: source), true)
                    }
                }
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            MacTheme.surface.opacity(0.36),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private func temperatureSliderRow(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        accessibilityLabel: String,
        accessibilityValue: String,
        onEditingChanged: @escaping (Bool) -> Void
    ) -> some View {
        let midpoint = ((range.lowerBound + range.upperBound) / 2).rounded()
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ContractCopy.copyMonitorFanTemperature.text(for: language))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Text(ContractCopy.copyMonitorFanTemperatureTick.text(for: language))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Slider(
                    value: value,
                    in: range,
                    onEditingChanged: onEditingChanged
                )
                .disabled(busy)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)

                HStack(spacing: 0) {
                    Text(MonitorFanFormat.celsius(range.lowerBound))
                    Spacer(minLength: 0)
                    Text(MonitorFanFormat.celsius(midpoint))
                    Spacer(minLength: 0)
                    Text(MonitorFanFormat.celsius(range.upperBound))
                }
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(MacTheme.textSecondary)
                .monospacedDigit()
                .accessibilityHidden(true)
            }
        }
    }

    private func percentSliderRow(
        value: Binding<Double>,
        accessibilityLabel: String,
        accessibilityValue: String,
        onEditingChanged: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ContractCopy.copyMonitorFanSourceFanPercentLabel.text(for: language))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Text(ContractCopy.copyMonitorFanPercentTick.text(for: language))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Slider(
                    value: value,
                    in: 0...100,
                    step: MonitorFanPolicy.rulePercentStep,
                    onEditingChanged: onEditingChanged
                )
                .disabled(busy)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)

                HStack(spacing: 0) {
                    Text("0%")
                    Spacer(minLength: 0)
                    Text("25%")
                    Spacer(minLength: 0)
                    Text("50%")
                    Spacer(minLength: 0)
                    Text("75%")
                    Spacer(minLength: 0)
                    Text("100%")
                }
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(MacTheme.textSecondary)
                .monospacedDigit()
                .accessibilityHidden(true)
            }
        }
    }

    private func fixedValueRow(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .frame(width: 58, alignment: .leading)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(MacTheme.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var mergedTargetSummary: some View {
        let temperatures = sourceTemperatures
        let percent = configuration.mergedTargetPercent(sourceTemperatures: temperatures)
        return VStack(alignment: .leading, spacing: 5) {
            Divider()
            Text(ContractCopy.copyMonitorFanTarget.text(for: language))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MacTheme.textSecondary)
            ForEach(reading.units) { fan in
                HStack(spacing: 6) {
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(MonitorCardKind.fan.accent)
                    Text(String(
                        format: ContractCopy.copyMonitorFanUnit.text(for: language),
                        fan.index + 1
                    ))
                    .font(.system(size: 9, weight: .medium))
                    Spacer(minLength: 0)
                    if let percent {
                        Text(String(
                            format: ContractCopy.copyMonitorFanSourceFanPercent.text(for: language),
                            Int(percent.rounded())
                        ))
                        .foregroundStyle(MacTheme.textPrimary)
                        Text(MonitorFanFormat.rpm(MonitorFanPercent.rpm(
                            percent: percent,
                            minimumRPM: fan.minimumRPM,
                            maximumRPM: fan.maximumRPM
                        )))
                        .foregroundStyle(MacTheme.textSecondary)
                    } else {
                        Text(ContractCopy.copyMonitorFanSourceUnavailable.text(for: language))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
            }
        }
    }

    private func sourceTitle(_ source: MonitorFanTemperatureSource) -> String {
        switch source {
        case .cpu:
            ContractCopy.copyMonitorFanSourceCpu.text(for: language)
        case .gpu:
            ContractCopy.copyMonitorFanSourceGpu.text(for: language)
        case .battery:
            ContractCopy.copyMonitorFanSourceBattery.text(for: language)
        }
    }

    private func sourceTemperatureText(_ source: MonitorFanTemperatureSource) -> String {
        guard let temperature = sourceTemperatures[source] else {
            return ContractCopy.copyMonitorFanSourceUnavailable.text(for: language)
        }
        return MonitorFanFormat.temperature(temperature)
    }

    private func sourceRequestText(_ source: MonitorFanTemperatureSource) -> String {
        guard configuration.hasTemperatureRules(for: source) else { return "" }
        guard let temperature = sourceTemperatures[source],
              let percent = configuration.targetPercent(for: source, temperature: temperature)
        else { return "" }
        return String(
            format: ContractCopy.copyMonitorFanSourceRequest.text(for: language),
            Int(percent.rounded())
        )
    }

    private func sourceAccessibilityValue(_ source: MonitorFanTemperatureSource) -> String {
        let temperature = sourceTemperatureText(source)
        let request = sourceRequestText(source)
        return request.isEmpty ? temperature : "\(temperature)，\(request)"
    }

    private func controlPointTitle(_ index: Int) -> String {
        String(
            format: ContractCopy.copyMonitorFanControlPoint.text(for: language),
            index + 1
        )
    }

    private func configuredPoints(
        for source: MonitorFanTemperatureSource
    ) -> [MonitorFanTemperatureRulePoint] {
        configuration.temperatureRules[source.rawValue]
            ?? MonitorFanTemperatureRule.defaultPoints(for: source)
    }

    private func temperatureBinding(
        source: MonitorFanTemperatureSource,
        index: Int,
        points: [MonitorFanTemperatureRulePoint]
    ) -> Binding<Double> {
        Binding(
            get: {
                guard points.indices.contains(index) else { return MonitorFanPolicy.minimumRuleCelsius }
                return points[index].celsius
            },
            set: { value in
                updatePoint(source: source, index: index, celsius: value, percent: nil, points: points)
            }
        )
    }

    private func percentBinding(
        source: MonitorFanTemperatureSource,
        index: Int,
        points: [MonitorFanTemperatureRulePoint]
    ) -> Binding<Double> {
        Binding(
            get: {
                guard points.indices.contains(index) else { return 0 }
                return points[index].fanPercent
            },
            set: { value in
                updatePoint(source: source, index: index, celsius: nil, percent: value, points: points)
            }
        )
    }

    private func temperatureRange(
        for index: Int,
        points: [MonitorFanTemperatureRulePoint]
    ) -> ClosedRange<Double> {
        MonitorFanTemperatureRule.editableTemperatureRange(index: index, points: points)
    }

    private func updatePoint(
        source: MonitorFanTemperatureSource,
        index: Int,
        celsius: Double?,
        percent: Double?,
        points: [MonitorFanTemperatureRulePoint]
    ) {
        guard points.indices.contains(index) else { return }
        var updated = points
        let range = temperatureRange(for: index, points: points)
        updated[index].celsius = min(
            range.upperBound,
            max(range.lowerBound, (celsius ?? points[index].celsius).rounded())
        )
        updated[index].fanPercent = MonitorFanTemperatureRule.snappedPercent(
            percent ?? points[index].fanPercent
        )
        onChangePoints(source, updated, false)
    }

    private func addPoint(
        source: MonitorFanTemperatureSource,
        points: [MonitorFanTemperatureRulePoint]
    ) {
        guard points.count < MonitorFanPolicy.maximumRulePointCount else { return }
        var sorted = points.sorted { $0.celsius < $1.celsius }
        guard sorted.count >= 2 else { return }
        if let last = sorted.last,
           last.celsius + MonitorFanPolicy.minimumRuleTemperatureSpan
            <= MonitorFanPolicy.maximumRuleCelsius {
            sorted.append(MonitorFanTemperatureRulePoint(
                celsius: last.celsius + MonitorFanPolicy.minimumRuleTemperatureSpan,
                fanPercent: last.fanPercent
            ))
            onChangePoints(source, sorted, true)
            return
        }
        if let first = sorted.first,
           first.celsius - MonitorFanPolicy.minimumRuleTemperatureSpan
            >= MonitorFanPolicy.minimumRuleCelsius {
            sorted.insert(MonitorFanTemperatureRulePoint(
                celsius: first.celsius - MonitorFanPolicy.minimumRuleTemperatureSpan,
                fanPercent: first.fanPercent
            ), at: 0)
            onChangePoints(source, sorted, true)
            return
        }
        var insertAt = 1
        var gap = -Double.infinity
        for index in 1..<sorted.count {
            let candidate = sorted[index].celsius - sorted[index - 1].celsius
            if candidate > gap {
                gap = candidate
                insertAt = index
            }
        }
        guard gap >= MonitorFanPolicy.minimumRuleTemperatureSpan * 2 else { return }
        let before = sorted[insertAt - 1]
        let after = sorted[insertAt]
        sorted.insert(
            MonitorFanTemperatureRulePoint(
                celsius: ((before.celsius + after.celsius) / 2).rounded(),
                fanPercent: MonitorFanTemperatureRule.snappedPercent(
                    (before.fanPercent + after.fanPercent) / 2
                )
            ),
            at: insertAt
        )
        onChangePoints(source, sorted, true)
    }

    private func deletePoint(
        source: MonitorFanTemperatureSource,
        index: Int,
        points: [MonitorFanTemperatureRulePoint]
    ) {
        guard points.count > 2, points.indices.contains(index) else { return }
        var updated = points
        updated.remove(at: index)
        onChangePoints(source, updated, true)
    }

    private func largestGap(in points: [MonitorFanTemperatureRulePoint]) -> Double {
        let sorted = points.sorted { $0.celsius < $1.celsius }
        guard sorted.count >= 2 else { return 0 }
        return zip(sorted, sorted.dropFirst()).map { right, next in
            next.celsius - right.celsius
        }.max() ?? 0
    }

    private func canAddPoint(to points: [MonitorFanTemperatureRulePoint]) -> Bool {
        guard points.count < MonitorFanPolicy.maximumRulePointCount,
              let first = points.min(by: { $0.celsius < $1.celsius }),
              let last = points.max(by: { $0.celsius < $1.celsius })
        else { return false }
        return last.celsius + MonitorFanPolicy.minimumRuleTemperatureSpan
                <= MonitorFanPolicy.maximumRuleCelsius
            || first.celsius - MonitorFanPolicy.minimumRuleTemperatureSpan
                >= MonitorFanPolicy.minimumRuleCelsius
            || largestGap(in: points) >= MonitorFanPolicy.minimumRuleTemperatureSpan * 2
    }
}
