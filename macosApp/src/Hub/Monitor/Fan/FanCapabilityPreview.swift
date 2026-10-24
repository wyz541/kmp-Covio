#if DEBUG
import AppKit
import Charts
import Observation
import SwiftUI

/// #331 的原生 SwiftUI 能力预览。
///
/// 曲线使用 Apple Swift Charts，不使用自绘 Canvas。
/// 预览只用假数据，不连接风扇运行时或 helper。
@MainActor
struct FanCapabilityPreviewRoot: View {
    @State private var model: FanCapabilityPreviewModel

    init(scenario: FanCapabilityScenario = .auto, dark: Bool = false) {
        _model = State(initialValue: FanCapabilityPreviewModel(scenario: scenario, dark: dark))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            scenarioRail
            FanCapabilityPopover(model: model)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 1_200, height: 960)
        .background(MacTheme.canvas)
        .preferredColorScheme(model.dark ? .dark : .light)
    }

    private func scenarioLabel(_ scenario: FanCapabilityScenario) -> some View {
        let selected = model.scenario == scenario
        let foreground = selected ? Color.white : MacTheme.textPrimary
        let secondary = selected ? Color.white.opacity(0.75) : MacTheme.textSecondary
        let background = selected ? MacTheme.accent : MacTheme.elevated
        return HStack(spacing: 8) {
            Text(scenario.title)
                .font(.system(size: 10, weight: .medium))
            Spacer(minLength: 0)
            Text(scenario.rawValue)
                .font(.system(size: 8))
                .foregroundStyle(secondary)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var scenarioRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("评审状态")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Text("点击切换完整主路径。原生 SwiftUI + Swift Charts。")
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
            Divider()
            ForEach(FanCapabilityScenario.allCases) { scenario in
                Button {
                    model.applyScenario(scenario)
                } label: {
                    scenarioLabel(scenario)
                }
                .buttonStyle(.plain)
            }
            Divider()
            Text("固定宽度 420 点，内容滚动，不推动 Monitor 网格。")
                .font(.system(size: 9))
                .foregroundStyle(MacTheme.textSecondary)
            if model.reducedMotion {
                Label("减少动态：静态模式", systemImage: "figure.stand")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.successText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MacTheme.successBackground, in: Capsule())
            }
        }
        .padding(16)
        .frame(width: 238)
        .background(MacTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MacTheme.divider, lineWidth: 1)
        }
    }
}

@MainActor
private struct FanCapabilityPopover: View {
    let model: FanCapabilityPreviewModel

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 11)
                ScrollView(.vertical, showsIndicators: false) {
                    scrollContent(proxy: proxy)
                        .padding(16)
                }
            }
        }
        .frame(width: 420, height: 760)
        .background(MacTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MacTheme.divider.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: MacTheme.shadow, radius: 18, y: 8)
        .tint(MacTheme.accent)
    }

    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            if model.helperMissing {
                helperCallout
            }
            safetyCallout
            enableRow
            modePicker
            if model.mode == .automatic {
                automaticControls.id("curve")
            } else {
                manualControls.id("manual")
            }
            fanReadings
            Divider()
            nightSection.id("night")
            alertSection.id("alerts")
            sensorSection.id("sensors")
            maintenanceSection.id("maintenance")
            if let message = model.actionMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.accent)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacTheme.infoBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            footer
        }
        .onAppear { scroll(for: model.scenario, proxy: proxy, animated: false) }
        .onChange(of: model.scenario) { _, scenario in
            scroll(for: scenario, proxy: proxy, animated: !model.reducedMotion)
        }
    }


    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("65.9 °C")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MacTheme.textPrimary)
                Text("控制温度 · \(model.selectedSensors.count) 个传感器取最大")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                HStack(spacing: 6) {
                    badge(
                        model.source == .ac ? "适配器曲线" : "电池曲线",
                        color: model.source == .ac ? MacTheme.textSecondary : MacTheme.warningText,
                        background: model.source == .ac ? MacTheme.elevated : MacTheme.warningBackground
                    )
                    if model.nightEnabled {
                        badge("夜间生效", color: MacTheme.accent, background: MacTheme.infoBackground)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.helperMissing ? MacTheme.errorText : (model.enabled ? MacTheme.successText : MacTheme.textSecondary))
                        .frame(width: 7, height: 7)
                    Text(model.helperMissing ? "Helper 不可用" : (model.enabled ? "Covio 已接管" : "系统控制"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Text(model.mode == .automatic ? "自动曲线" : "手动转速")
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.textSecondary)
            }
        }
    }

    private var helperCallout: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Helper 版本过旧")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacTheme.errorText)
                Text("读数保留，风扇写入暂停。重装后恢复控制。")
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button("重装") {
                model.actionMessage = "已请求重装 helper"
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(MacTheme.errorBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var safetyCallout: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("写入风扇转速会改变硬件行为", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MacTheme.warningText)
            Text("目标转速限制在硬件安全区间。连续 3 次写入失败后恢复系统控制。")
                .font(.system(size: 9))
                .foregroundStyle(MacTheme.textSecondary)
            if let message = model.actionMessage {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.successText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.warningBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var enableRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用风扇控制")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text("20 秒租约 · 正常退出会恢复系统控制")
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { model.enabled },
                set: {
                    model.enabled = $0
                    model.actionMessage = $0 ? "已启用风扇控制" : "已恢复系统控制"
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(MacTheme.accent)
            .disabled(model.helperMissing)
        }
    }

    private var modePicker: some View {
        Picker("模式", selection: Binding(
            get: { model.mode },
            set: { model.mode = $0 }
        )) {
            Text("自动曲线").tag(FanPreviewMode.automatic)
            Text("手动转速").tag(FanPreviewMode.manual)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(MacTheme.accent)
        .disabled(!model.enabled || model.helperMissing)
    }

    private var automaticControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                presetButton("安静", start: 80, full: 100)
                presetButton("均衡", start: 70, full: 95)
                presetButton("强力", start: 55, full: 85)
                Spacer(minLength: 0)
            }
            HStack {
                Text("温控曲线")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Text("Swift Charts · 拖动控制点")
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Picker("电源", selection: Binding(
                get: { model.source },
                set: { model.source = $0 }
            )) {
                Text("插电曲线").tag(FanCurveSource.ac)
                Text("电池曲线").tag(FanCurveSource.battery)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(MacTheme.accent)

            Picker("风扇", selection: Binding(
                get: { model.fanFilter },
                set: { model.fanFilter = $0 }
            )) {
                Text("全部风扇").tag(FanFilter.all)
                Text("风扇 1").tag(FanFilter.fan1)
                Text("风扇 2").tag(FanFilter.fan2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.source == .battery && !model.hasBatteryCurve {
                HStack(spacing: 8) {
                    Text("电池曲线未设置，当前沿用插电曲线。")
                        .font(.system(size: 9))
                        .foregroundStyle(MacTheme.warningText)
                    Spacer(minLength: 0)
                    Button("复制插电曲线") { model.copyBatteryFromAC() }
                        .buttonStyle(.link)
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(9)
                .background(MacTheme.warningBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            FanCurveChart(
                points: model.displayCurve,
                minimumRPM: model.selectedMinimumRPM,
                maximumRPM: model.selectedMaximumRPM,
                onMove: { index, temperature, rpm in
                    model.movePoint(index: index, temperature: temperature, rpm: rpm)
                },
                onCommit: { model.sortCurrentCurve() }
            )

            HStack(spacing: 5) {
                ForEach(Array(model.displayCurve.indices), id: \.self) { index in
                    Button("\(index + 1)") {
                        model.selectedPointIndex = index
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(index == model.selectedPointIndex ? Color.white : MacTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(index == model.selectedPointIndex ? MacTheme.accent : MacTheme.elevated, in: Capsule())
                }
                Spacer()
                Button("添加") { model.addPoint() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(model.displayCurve.count >= 6)
                Button("删除") { model.removeSelectedPoint() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(model.displayCurve.count <= 2)
            }

            pointEditor
            if model.source == .battery {
                Button("清空当前电池曲线") { model.clearBatteryCurve() }
                    .buttonStyle(.link)
                    .font(.system(size: 9))
            }
        }
    }

    private var pointEditor: some View {
        let points = model.displayCurve
        let index = min(model.selectedPointIndex, max(0, points.count - 1))
        let point = points.indices.contains(index) ? points[index] : PreviewCurvePoint(temperature: 40, rpm: model.selectedMinimumRPM)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("控制点 \(index + 1)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer()
                Text("\(Int(point.temperature.rounded())) °C · \(Int(point.rpm.rounded())) RPM")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Text("温度")
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 30, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { point.temperature },
                        set: { model.updateSelectedPoint(temperature: $0, rpm: point.rpm) }
                    ),
                    in: 40...105,
                    step: 1
                )
            }
            HStack(spacing: 8) {
                Text("转速")
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 30, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { point.rpm.coerce(to: model.selectedMinimumRPM...model.selectedMaximumRPM) },
                        set: { model.updateSelectedPoint(temperature: point.temperature, rpm: ($0 / 50).rounded() * 50) }
                    ),
                    in: model.selectedMinimumRPM...model.selectedMaximumRPM,
                    step: 50
                )
            }
        }
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("手动转速")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Button("全部全速") {
                    model.manualRPM[0] = 5_800
                    model.manualRPM[1] = 5_800
                    model.actionMessage = "全部风扇已设为全速"
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            ForEach(model.fans, id: \.index) { fan in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("风扇 \(fan.index + 1)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                        Spacer()
                        Text("\(Int((model.manualRPM[fan.index] ?? fan.minimumRPM).rounded())) RPM")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(MacTheme.textSecondary)
                            .monospacedDigit()
                        Button("全速") { model.manualRPM[fan.index] = fan.maximumRPM }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                    Slider(
                        value: Binding(
                            get: { (model.manualRPM[fan.index] ?? fan.minimumRPM).coerce(to: fan.minimumRPM...fan.maximumRPM) },
                            set: { model.manualRPM[fan.index] = ($0 / 50).rounded() * 50 }
                        ),
                        in: fan.minimumRPM...fan.maximumRPM,
                        step: 50
                    )
                }
            }
            Text("手动目标受每个风扇的硬件最小和最大转速限制。")
                .font(.system(size: 9))
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    private var fanReadings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("风扇")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Text("实际 / 目标")
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            ForEach(model.fans, id: \.index) { fan in
                let target = model.target(for: fan)
                let actual = model.fanFault && fan.index == 1 ? 0 : min(fan.maximumRPM, target + 200)
                HStack(spacing: 7) {
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(model.fanFault && fan.index == 1 ? MacTheme.errorText : MacTheme.accent)
                    Text("风扇 \(fan.index + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer()
                    Text("\(Int(actual.rounded())) RPM")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.fanFault && fan.index == 1 ? MacTheme.errorText : MacTheme.textPrimary)
                        .monospacedDigit()
                    Text("目标 \(Int(target.rounded()))")
                        .font(.system(size: 8))
                        .foregroundStyle(MacTheme.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    model.fanFault && fan.index == 1 ? MacTheme.errorBackground : MacTheme.elevated,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
    }

    private var nightSection: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { model.nightExpanded },
            set: { model.nightExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("夜间使用预设", isOn: Binding(
                    get: { model.nightEnabled },
                    set: { model.nightEnabled = $0 }
                ))
                .font(.system(size: 9))
                timeRow(label: "开始", minutes: Binding(
                    get: { model.nightStartMinutes },
                    set: { model.nightStartMinutes = $0 }
                ))
                timeRow(label: "结束", minutes: Binding(
                    get: { model.nightEndMinutes },
                    set: { model.nightEndMinutes = $0 }
                ))
                Picker("夜间预设", selection: Binding(
                    get: { model.nightPreset },
                    set: { model.nightPreset = $0 }
                )) {
                    ForEach(NightPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                Label(
                    model.nightEnabled ? "生效中：夜间预设接管曲线" : "未启用",
                    systemImage: model.nightEnabled ? "moon.fill" : "moon"
                )
                .font(.system(size: 9))
                .foregroundStyle(model.nightEnabled ? MacTheme.accent : MacTheme.textSecondary)
            }
            .padding(.top, 6)
        } label: {
            sectionLabel(
                "定时夜间模式",
                subtitle: model.nightEnabled ? "23:00–07:00 · \(model.nightPreset.title)" : "未启用"
            )
        }
    }

    private var alertSection: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { model.alertsExpanded },
            set: { model.alertsExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("高温通知", isOn: Binding(
                    get: { model.highTemperatureEnabled },
                    set: { model.highTemperatureEnabled = $0 }
                ))
                .font(.system(size: 9))
                if model.highTemperatureEnabled {
                    HStack(spacing: 8) {
                        Text("阈值")
                            .font(.system(size: 9))
                            .foregroundStyle(MacTheme.textSecondary)
                        Slider(value: Binding(
                            get: { model.highTemperatureThreshold },
                            set: { model.highTemperatureThreshold = $0.rounded() }
                        ), in: 60...105, step: 1)
                        Text("\(Int(model.highTemperatureThreshold)) °C")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(MacTheme.textPrimary)
                            .monospacedDigit()
                    }
                    Label(
                        65.9 >= model.highTemperatureThreshold ? "当前温度已触发高温状态" : "当前温度低于阈值",
                        systemImage: "thermometer.high"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(65.9 >= model.highTemperatureThreshold ? MacTheme.warningText : MacTheme.successText)
                }
                Toggle("风扇故障通知", isOn: Binding(
                    get: { model.fanFaultEnabled },
                    set: { model.fanFaultEnabled = $0 }
                ))
                .font(.system(size: 9))
                if model.fanFaultEnabled {
                    Text(model.fanFault ? "风扇 2 实际转速为 0，已进入故障通知状态。" : "两个风扇转速正常。")
                        .font(.system(size: 9))
                        .foregroundStyle(model.fanFault ? MacTheme.errorText : MacTheme.successText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.fanFault ? MacTheme.errorBackground : MacTheme.successBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel(
                "通知",
                subtitle: model.highTemperatureEnabled || model.fanFaultEnabled ? "高温与风扇故障已启用" : "未启用"
            )
        }
    }

    private var sensorSection: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { model.sensorsExpanded },
            set: { model.sensorsExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(MacTheme.textSecondary)
                    TextField("搜索名称或键名", text: Binding(
                        get: { model.sensorQuery },
                        set: { model.sensorQuery = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(MacTheme.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                ForEach(model.filteredSensors) { sensor in
                    Toggle(isOn: Binding(
                        get: { model.selectedSensors.contains(sensor.key) },
                        set: { model.toggleSensor(sensor.key, enabled: $0) }
                    )) {
                        HStack {
                            Text(sensor.name)
                                .font(.system(size: 9))
                                .foregroundStyle(MacTheme.textPrimary)
                            Text(sensor.key)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(MacTheme.textSecondary)
                            Spacer()
                            Text("\(Int(sensor.temperature.rounded())) °C")
                                .font(.system(size: 8, design: .rounded))
                                .foregroundStyle(MacTheme.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9))
                }
                Text("完整名称库包含 64 个显式键名，未知键保留原始键名。")
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("控制传感器", subtitle: "\(model.selectedSensors.count) 个参与控制 · 取最大值")
        }
    }

    private var maintenanceSection: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { model.maintenanceExpanded },
            set: { model.maintenanceExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("登录时启动", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
                .font(.system(size: 9))
                HStack(spacing: 7) {
                    Button("趋势") { model.actionMessage = "已打开近 15 分钟风扇趋势" }
                    Button("诊断") { model.actionMessage = "诊断信息已准备导出" }
                    Button("修复 Helper") { model.actionMessage = "已打开 helper 修复流程" }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                if model.uninstallArmed {
                    HStack {
                        Text("卸载 helper 会先恢复系统控制。")
                            .font(.system(size: 8))
                            .foregroundStyle(MacTheme.errorText)
                        Spacer()
                        Button("确认卸载") {
                            model.uninstallArmed = false
                            model.actionMessage = "已恢复系统控制并请求卸载 helper"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(MacTheme.errorText)
                    }
                } else {
                    Button("卸载 Helper") { model.uninstallArmed = true }
                        .buttonStyle(.link)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.errorText)
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("维护与导航", subtitle: "趋势、诊断、helper")
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(model.enabled ? "Covio 退出或租约过期后恢复系统控制。" : "风扇控制已恢复系统模式。")
                .font(.system(size: 9))
                .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 0)
            Button("恢复系统控制") {
                model.enabled = false
                model.actionMessage = "已恢复系统控制"
            }
            .buttonStyle(.link)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MacTheme.warningText)
        }
    }

    private func presetButton(_ title: String, start: Double, full: Double) -> some View {
        Button(title) { model.applyPreset(start: start, full: full) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
    }

    private func timeRow(label: String, minutes: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(MacTheme.textSecondary)
                .frame(width: 28, alignment: .leading)
            Slider(value: Binding(
                get: { Double(minutes.wrappedValue) },
                set: { minutes.wrappedValue = Int(($0 / 30).rounded() * 30).clamped(to: 0...(24 * 60 - 30)) }
            ), in: 0...Double(24 * 60 - 30), step: 30)
            Text(minuteText(minutes.wrappedValue))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func badge(_ text: String, color: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }

    private func sectionLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    private func minuteText(_ value: Int) -> String {
        let wrapped = value.clamped(to: 0...(24 * 60 - 1))
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    private func scroll(for scenario: FanCapabilityScenario, proxy: ScrollViewProxy, animated: Bool) {
        let id: String? = switch scenario {
        case .auto, .helper, .dark: nil
        case .manual: "manual"
        case .battery: "curve"
        case .night, .reduced: "night"
        case .alerts: "alerts"
        case .sensors: "sensors"
        case .maintenance: "maintenance"
        }
        guard let id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .top) }
        } else {
            proxy.scrollTo(id, anchor: .top)
        }
    }
}

private struct FanCurveChart: View {
    let points: [PreviewCurvePoint]
    let minimumRPM: Double
    let maximumRPM: Double
    let onMove: (Int, Double, Double) -> Void
    let onCommit: () -> Void

    @State private var draggingIndex: Int?

    var body: some View {
        chart
            .frame(height: 156)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(proxy: proxy, geometry: geometry))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("风扇温控曲线")
            .accessibilityValue(
                points.map {
                    "\(Int($0.temperature.rounded()))度\(Int($0.rpm.rounded()))转"
                }.joined(separator: "，")
            )
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(
                x: .value("温度", point.temperature),
                y: .value("转速", point.rpm)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .foregroundStyle(MacTheme.accent)

            PointMark(
                x: .value("温度", point.temperature),
                y: .value("转速", point.rpm)
            )
            .symbolSize(58)
            .foregroundStyle(MacTheme.accent)
        }
        .chartXScale(domain: 40...105)
        .chartYScale(domain: minimumRPM...maximumRPM)
        .chartXAxis {
            AxisMarks(values: [40, 60, 80, 105])
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(MacTheme.elevated.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func dragGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let plotFrame = proxy.plotFrame else { return }
                let frame = geometry[plotFrame]
                if draggingIndex == nil {
                    draggingIndex = nearestPointIndex(
                        location: value.location,
                        frame: frame,
                        proxy: proxy
                    )
                }
                guard let index = draggingIndex, points.indices.contains(index) else { return }
                let x = value.location.x - frame.origin.x
                let y = value.location.y - frame.origin.y
                guard let temperature = proxy.value(atX: x, as: Double.self),
                      let rpm = proxy.value(atY: y, as: Double.self)
                else { return }
                onMove(
                    index,
                    Swift.min(105, Swift.max(40, temperature.rounded())),
                    Swift.min(maximumRPM, Swift.max(minimumRPM, (rpm / 50).rounded() * 50))
                )
            }
            .onEnded { _ in
                draggingIndex = nil
                onCommit()
            }
    }

    private func nearestPointIndex(location: CGPoint, frame: CGRect, proxy: ChartProxy) -> Int? {
        let candidates = points.indices.compactMap { index -> (Int, CGPoint)? in
            guard let x = proxy.position(forX: points[index].temperature),
                  let y = proxy.position(forY: points[index].rpm)
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

enum FanCapabilityScenario: String, CaseIterable, Identifiable {
    case auto
    case manual
    case battery
    case night
    case alerts
    case sensors
    case maintenance
    case helper
    case dark
    case reduced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "自动曲线"
        case .manual: "手动与全速"
        case .battery: "电池曲线"
        case .night: "夜间模式"
        case .alerts: "高温与故障"
        case .sensors: "传感器搜索"
        case .maintenance: "维护入口"
        case .helper: "Helper 缺失"
        case .dark: "深色外观"
        case .reduced: "减少动态"
        }
    }
}

private enum FanPreviewMode: String, CaseIterable, Identifiable {
    case automatic
    case manual
    var id: String { rawValue }
}

private enum FanCurveSource: String, CaseIterable, Identifiable {
    case ac
    case battery
    var id: String { rawValue }
}

private enum FanFilter: String, CaseIterable, Identifiable {
    case all
    case fan1
    case fan2
    var id: String { rawValue }
}

private enum NightPreset: String, CaseIterable, Identifiable {
    case quiet
    case balanced
    case turbo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quiet: "安静"
        case .balanced: "均衡"
        case .turbo: "强力"
        }
    }
}

private struct PreviewCurvePoint: Identifiable, Equatable {
    let id = UUID()
    var temperature: Double
    var rpm: Double
}

private struct FanPreviewFan: Identifiable {
    let index: Int
    let minimumRPM: Double
    let maximumRPM: Double
    var id: Int { index }
}

private struct FanPreviewSensor: Identifiable {
    let key: String
    let name: String
    let temperature: Double
    var id: String { key }
}

@MainActor
@Observable
private final class FanCapabilityPreviewModel {
    var scenario: FanCapabilityScenario
    var dark: Bool
    var mode: FanPreviewMode
    var source: FanCurveSource
    var fanFilter: FanFilter = .all
    var selectedPointIndex = 0
    var enabled: Bool
    var helperMissing: Bool
    var nightEnabled: Bool
    var nightExpanded: Bool
    var nightStartMinutes = 23 * 60
    var nightEndMinutes = 7 * 60
    var nightPreset: NightPreset = .quiet
    var highTemperatureEnabled: Bool
    var fanFaultEnabled: Bool
    var fanFault: Bool
    var highTemperatureThreshold: Double
    var alertsExpanded: Bool
    var sensorsExpanded: Bool
    var sensorQuery = ""
    var maintenanceExpanded: Bool
    var launchAtLogin = true
    var uninstallArmed = false
    var reducedMotion: Bool
    var actionMessage: String?

    let fans = [
        FanPreviewFan(index: 0, minimumRPM: 1_200, maximumRPM: 5_800),
        FanPreviewFan(index: 1, minimumRPM: 1_200, maximumRPM: 6_200),
    ]
    var manualRPM: [Int: Double] = [0: 2_580, 1: 2_710]
    var selectedSensors: Set<String> = ["TCMz", "TC0D", "TC0P", "TG0D", "TG0P"]
    let sensors = [
        FanPreviewSensor(key: "TCMz", name: "CPU 峰值", temperature: 65.9),
        FanPreviewSensor(key: "TCMb", name: "CPU 平均", temperature: 63.2),
        FanPreviewSensor(key: "TC0D", name: "CPU 核心", temperature: 61.8),
        FanPreviewSensor(key: "TC0P", name: "CPU 邻近", temperature: 60.4),
        FanPreviewSensor(key: "TG0D", name: "GPU 核心", temperature: 58.7),
        FanPreviewSensor(key: "TG0P", name: "GPU 邻近", temperature: 57.2),
        FanPreviewSensor(key: "TB0T", name: "电池 1", temperature: 34.1),
        FanPreviewSensor(key: "TM0P", name: "内存", temperature: 49.3),
        FanPreviewSensor(key: "TP0P", name: "供电", temperature: 52.8),
        FanPreviewSensor(key: "TH0P", name: "硬盘", temperature: 43.9),
        FanPreviewSensor(key: "TW0P", name: "无线网卡", temperature: 45.2),
        FanPreviewSensor(key: "Ts0P", name: "掌托", temperature: 31.7),
    ]

    var acCurves: [Int: [PreviewCurvePoint]] = [
        0: [
            PreviewCurvePoint(temperature: 45, rpm: 1_200),
            PreviewCurvePoint(temperature: 62, rpm: 2_200),
            PreviewCurvePoint(temperature: 78, rpm: 3_900),
            PreviewCurvePoint(temperature: 92, rpm: 5_800),
        ],
        1: [
            PreviewCurvePoint(temperature: 45, rpm: 1_200),
            PreviewCurvePoint(temperature: 62, rpm: 2_400),
            PreviewCurvePoint(temperature: 78, rpm: 4_300),
            PreviewCurvePoint(temperature: 92, rpm: 6_200),
        ],
    ]
    var batteryCurves: [Int: [PreviewCurvePoint]] = [
        0: [
            PreviewCurvePoint(temperature: 50, rpm: 1_200),
            PreviewCurvePoint(temperature: 70, rpm: 2_200),
            PreviewCurvePoint(temperature: 86, rpm: 3_900),
            PreviewCurvePoint(temperature: 100, rpm: 5_800),
        ],
        1: [
            PreviewCurvePoint(temperature: 50, rpm: 1_200),
            PreviewCurvePoint(temperature: 70, rpm: 2_500),
            PreviewCurvePoint(temperature: 86, rpm: 4_300),
            PreviewCurvePoint(temperature: 100, rpm: 6_200),
        ],
    ]

    init(scenario: FanCapabilityScenario, dark: Bool) {
        self.scenario = scenario
        self.dark = dark || scenario == .dark
        mode = .automatic
        source = .ac
        enabled = true
        helperMissing = false
        nightEnabled = false
        nightExpanded = false
        highTemperatureEnabled = false
        fanFaultEnabled = false
        fanFault = false
        highTemperatureThreshold = 90
        alertsExpanded = false
        sensorsExpanded = false
        maintenanceExpanded = false
        reducedMotion = false
        applyScenario(scenario, resetDark: false)
    }

    var selectedMinimumRPM: Double {
        switch fanFilter {
        case .all: fans.map(\.minimumRPM).min() ?? 1_200
        case .fan1: fans[0].minimumRPM
        case .fan2: fans[1].minimumRPM
        }
    }

    var selectedMaximumRPM: Double {
        switch fanFilter {
        case .all: fans.map(\.maximumRPM).max() ?? 6_200
        case .fan1: fans[0].maximumRPM
        case .fan2: fans[1].maximumRPM
        }
    }

    var displayCurve: [PreviewCurvePoint] {
        let key = fanFilter == .fan2 ? 1 : 0
        let map = source == .ac ? acCurves : batteryCurves
        return (map[key] ?? acCurves[key] ?? acCurves[0] ?? []).sorted { $0.temperature < $1.temperature }
    }

    var hasBatteryCurve: Bool {
        let keys = fanFilter == .all ? [0, 1] : [fanFilter == .fan2 ? 1 : 0]
        return keys.allSatisfy { (batteryCurves[$0]?.count ?? 0) >= 2 }
    }

    var filteredSensors: [FanPreviewSensor] {
        guard !sensorQuery.isEmpty else { return Array(sensors.prefix(10)) }
        return sensors.filter {
            $0.name.localizedCaseInsensitiveContains(sensorQuery) ||
                $0.key.localizedCaseInsensitiveContains(sensorQuery)
        }
    }

    func target(for fan: FanPreviewFan) -> Double {
        if mode == .manual {
            return (manualRPM[fan.index] ?? fan.minimumRPM).coerce(to: fan.minimumRPM...fan.maximumRPM)
        }
        let map = source == .ac ? acCurves : batteryCurves
        let points = map[fan.index] ?? acCurves[fan.index] ?? acCurves[0] ?? []
        let target = curveTarget(points, temperature: 65.9)
        return target.coerce(to: fan.minimumRPM...fan.maximumRPM)
    }

    func applyScenario(_ scenario: FanCapabilityScenario, resetDark: Bool = true) {
        self.scenario = scenario
        if resetDark {
            dark = scenario == .dark
        }
        mode = scenario == .manual ? .manual : .automatic
        source = scenario == .battery ? .battery : .ac
        fanFilter = .all
        helperMissing = scenario == .helper
        enabled = !helperMissing
        nightEnabled = scenario == .night || scenario == .reduced
        nightExpanded = scenario == .night || scenario == .reduced
        alertsExpanded = scenario == .alerts
        sensorsExpanded = scenario == .sensors
        maintenanceExpanded = scenario == .maintenance
        highTemperatureEnabled = scenario == .alerts
        fanFaultEnabled = scenario == .alerts
        fanFault = scenario == .alerts
        highTemperatureThreshold = scenario == .alerts ? 64 : 90
        reducedMotion = scenario == .reduced
        actionMessage = nil
        uninstallArmed = false
        selectedPointIndex = 0
    }

    func applyPreset(start: Double, full: Double) {
        updateCurve([
            PreviewCurvePoint(temperature: start, rpm: selectedMinimumRPM),
            PreviewCurvePoint(temperature: full, rpm: selectedMaximumRPM),
        ])
        actionMessage = "已应用 \(Int(start))–\(Int(full)) °C 预设"
    }

    func movePoint(index: Int, temperature: Double, rpm: Double) {
        var points = displayCurve
        guard points.indices.contains(index) else { return }
        points[index].temperature = temperature
        points[index].rpm = rpm
        updateCurve(points, announce: false)
    }

    func updateSelectedPoint(temperature: Double, rpm: Double) {
        var points = displayCurve
        let index = min(selectedPointIndex, max(0, points.count - 1))
        guard points.indices.contains(index) else { return }
        points[index].temperature = temperature
        points[index].rpm = rpm
        updateCurve(points, announce: false)
    }

    func sortCurrentCurve() {
        updateCurve(displayCurve.sorted { $0.temperature < $1.temperature })
        actionMessage = "曲线已保存"
    }

    func addPoint() {
        var points = displayCurve.sorted { $0.temperature < $1.temperature }
        guard points.count >= 2, points.count < 6 else { return }
        var bestIndex = 1
        var bestGap = -Double.infinity
        for index in 1..<points.count {
            let gap = points[index].temperature - points[index - 1].temperature
            if gap > bestGap {
                bestGap = gap
                bestIndex = index
            }
        }
        let before = points[bestIndex - 1]
        let after = points[bestIndex]
        points.insert(
            PreviewCurvePoint(
                temperature: ((before.temperature + after.temperature) / 2).rounded(),
                rpm: (((before.rpm + after.rpm) / 2) / 50).rounded() * 50
            ),
            at: bestIndex
        )
        selectedPointIndex = bestIndex
        updateCurve(points)
    }

    func removeSelectedPoint() {
        var points = displayCurve
        guard points.count > 2, points.indices.contains(selectedPointIndex) else { return }
        points.remove(at: selectedPointIndex)
        selectedPointIndex = min(selectedPointIndex, points.count - 1)
        updateCurve(points)
    }

    func copyBatteryFromAC() {
        batteryCurves = acCurves
        actionMessage = "插电曲线已复制到电池曲线"
    }

    func clearBatteryCurve() {
        let keys = fanFilter == .all ? [0, 1] : [fanFilter == .fan2 ? 1 : 0]
        for key in keys {
            batteryCurves.removeValue(forKey: key)
        }
        actionMessage = "电池曲线已清空，当前沿用插电曲线"
    }

    func toggleSensor(_ key: String, enabled: Bool) {
        if enabled {
            selectedSensors.insert(key)
        } else if selectedSensors.count > 1 {
            selectedSensors.remove(key)
        } else {
            actionMessage = "至少保留一个控制传感器"
        }
    }

    private func updateCurve(_ points: [PreviewCurvePoint], announce: Bool = true) {
        let normalized = normalize(points)
        let keys = fanFilter == .all ? [0, 1] : [fanFilter == .fan2 ? 1 : 0]
        if source == .ac {
            for key in keys { acCurves[key] = normalized }
        } else {
            for key in keys { batteryCurves[key] = normalized }
        }
        if announce {
            actionMessage = "曲线已保存"
        }
    }

    private func normalize(_ points: [PreviewCurvePoint]) -> [PreviewCurvePoint] {
        var output: [PreviewCurvePoint] = []
        for var point in points {
            point.temperature = point.temperature.coerce(to: 40...105).rounded()
            point.rpm = ((point.rpm.coerce(to: selectedMinimumRPM...selectedMaximumRPM) / 50).rounded() * 50)
                .coerce(to: selectedMinimumRPM...selectedMaximumRPM)
            if output.last?.temperature != point.temperature {
                output.append(point)
            }
        }
        return output.sorted { $0.temperature < $1.temperature }
    }

    private func curveTarget(_ points: [PreviewCurvePoint], temperature: Double) -> Double {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        if temperature <= first.temperature { return first.rpm }
        if temperature >= last.temperature { return last.rpm }
        for index in 1..<sorted.count where temperature <= sorted[index].temperature {
            let left = sorted[index - 1]
            let right = sorted[index]
            let fraction = (temperature - left.temperature) / max(0.001, right.temperature - left.temperature)
            return left.rpm + (right.rpm - left.rpm) * fraction
        }
        return last.rpm
    }
}

@MainActor
enum FanCapabilityPreviewRenderer {
    static func render(to path: String) async -> Bool {
        let scenario = scenarioFromEnvironment
        let dark = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?.lowercased() == "dark" || scenario == .dark
        return await MonitorFanPreviewSnapshot.write(
            FanCapabilityPreviewRoot(scenario: scenario, dark: dark)
                .environment(\.colorScheme, dark ? .dark : .light),
            size: CGSize(width: 1_200, height: 960),
            path: path,
            dark: dark
        )
    }

    static var scenarioFromEnvironment: FanCapabilityScenario {
        let raw = ProcessInfo.processInfo.environment["COVIO_FAN_CAPABILITY_SCENARIO"] ?? "auto"
        return FanCapabilityScenario(rawValue: raw) ?? .auto
    }
}

private extension Double {
    func coerce(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
#endif
