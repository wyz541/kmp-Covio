import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MonitorReportView: View {
    @Bindable var model: MonitorReportModel
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            header
            rangeControls
            if model.isLoading {
                ProgressView(ContractCopy.copyMonitorReportLoading.text(for: language))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else if let report = model.report {
                reportContent(report)
            } else {
                emptyState
            }
            footer
        }
        .padding(MacTheme.space4)
        .frame(minWidth: 760, minHeight: 640)
        .background(MacTheme.canvas)
        .task {
            if model.report == nil {
                await model.reload()
            }
        }
        .confirmationDialog(
            ContractCopy.copyMonitorReportDeleteTitle.text(for: language),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(ContractCopy.copyMonitorReportDeleteConfirm.text(for: language), role: .destructive) {
                Task { await model.clearHistory() }
            }
            Button(ContractCopy.copyMonitorReportCancel.text(for: language), role: .cancel) {}
        } message: {
            Text(ContractCopy.copyMonitorReportDeleteMessage.text(for: language))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: MacTheme.space3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ContractCopy.copyMonitorReportTitle.text(for: language))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(ContractCopy.copyMonitorReportSummary.text(for: language))
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ContractCopy.copyMonitorReportClose.text(for: language))
        }
    }

    private var rangeControls: some View {
        HStack(spacing: MacTheme.space2) {
            DatePicker(
                ContractCopy.copyMonitorReportRangeStart.text(for: language),
                selection: Binding(
                    get: { model.startDate },
                    set: { model.setStartDate($0) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            DatePicker(
                ContractCopy.copyMonitorReportRangeEnd.text(for: language),
                selection: Binding(
                    get: { model.endDate },
                    set: { model.setEndDate($0) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            Button(ContractCopy.copyMonitorReportRangeLast10Days.text(for: language)) {
                model.selectLastTenDays()
                Task { await model.reload() }
            }
            .buttonStyle(.bordered)
            Button {
                Task { await model.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(ContractCopy.copyMonitorReportTitle.text(for: language))
        }
        .controlSize(.small)
        .help(ContractCopy.copyMonitorReportRangeLimit.text(for: language))
    }

    private func reportContent(_ report: MonitorReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacTheme.space3) {
                if !report.hasData {
                    emptyState
                } else {
                    coverageSummary(report.coverage)
                    if report.coverage.isPartial {
                        Text(ContractCopy.copyMonitorReportPartial.text(for: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.warningText)
                    }
                    reportSection(
                        title: ContractCopy.copyMonitorReportPeaksTitle.text(for: language),
                        rows: report.peaks.prefix(10).map {
                            "\($0.metric.rawValue) · \(formatPeak($0)) · \(shortTime($0.at))"
                        }
                    )
                    reportSection(
                        title: ContractCopy.copyMonitorReportThresholdsTitle.text(for: language),
                        rows: report.thresholdIntervals.prefix(10).map {
                            "\($0.kind.rawValue) · \(shortTime($0.start)) – \(shortTime($0.end)) · \(formatDuration($0.duration))"
                        }
                    )
                    reportSection(
                        title: ContractCopy.copyMonitorReportEventsTitle.text(for: language),
                        rows: report.events.suffix(12).map {
                            "\(shortTime($0.occurredAt)) · \($0.kind.rawValue)"
                        }
                    )
                    reportSection(
                        title: ContractCopy.copyMonitorReportGapsTitle.text(for: language),
                        rows: report.gapSummaries.map {
                            "\($0.reason.rawValue) · \($0.count) · \(formatDuration($0.duration))"
                        }
                    )
                    reportSection(
                        title: ContractCopy.copyMonitorReportUnavailableTitle.text(for: language),
                        rows: report.unavailableMetrics.map(\.rawValue)
                    )
                }
            }
            .padding(.trailing, MacTheme.space1)
        }
        .frame(maxHeight: .infinity)
    }

    private func coverageSummary(_ coverage: MonitorReportCoverage) -> some View {
        HStack(spacing: MacTheme.space2) {
            reportMetric(
                title: ContractCopy.copyMonitorReportCoverageObserved.text(for: language),
                value: "\(Int((coverage.coverageFraction * 100).rounded()))%"
            )
            reportMetric(
                title: ContractCopy.copyMonitorReportCoverageSamples.text(for: language),
                value: "\(coverage.sampleCount)"
            )
            reportMetric(
                title: ContractCopy.copyMonitorReportCoverageSleep.text(for: language),
                value: formatDuration(coverage.sleepSeconds)
            )
            reportMetric(
                title: ContractCopy.copyMonitorReportCoverageUnknown.text(for: language),
                value: formatDuration(coverage.unknownSeconds)
            )
        }
    }

    private func reportMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
        }
        .padding(MacTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
    }

    private func reportSection(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            if rows.isEmpty {
                Text(ContractCopy.copyMonitorReportEmpty.text(for: language))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MacTheme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(MacTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: MacTheme.space2) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacTheme.textSecondary)
            Text(ContractCopy.copyMonitorReportEmpty.text(for: language))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
            Text(ContractCopy.copyMonitorReportNoDataHint.text(for: language))
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
            if model.errorMessage != nil {
                Text(ContractCopy.copyMonitorReportError.text(for: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.errorText)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var footer: some View {
        HStack(spacing: MacTheme.space2) {
            Button(ContractCopy.copyMonitorReportClear.text(for: language), role: .destructive) {
                showingDeleteConfirmation = true
            }
            .buttonStyle(.bordered)
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer()
            Button(ContractCopy.copyMonitorReportExport.text(for: language)) {
                export()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.report?.hasData != true || model.isLoading)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = model.suggestedFileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try model.writeReport(to: destination, language: language)
            statusMessage = ContractCopy.copyMonitorReportExportSuccess.text(for: language)
        } catch {
            statusMessage = ContractCopy.copyMonitorReportExportError.text(for: language)
        }
    }

    private func formatPeak(_ peak: MonitorReportPeak) -> String {
        switch peak.metric {
        case .cpuUsage, .gpuUsage, .memoryFraction:
            "\(String(format: "%.1f", peak.value * 100))%"
        case .batteryPercent:
            "\(String(format: "%.1f", peak.value))%"
        case .diskReadRate, .diskWriteRate, .networkReceiveRate, .networkTransmitRate:
            "\(formatBytes(peak.value))/s"
        case .swapUsed:
            formatBytes(peak.value)
        case .batteryTemperature, .cpuTemperature, .gpuTemperature:
            "\(String(format: "%.1f", peak.value)) ℃"
        case .systemPower, .batteryPower:
            "\(String(format: "%.1f", peak.value)) W"
        case .fanRPM:
            "\(Int(peak.value)) rpm"
        case .cpuFrequency:
            "\(String(format: "%.1f", peak.value)) Hz"
        }
    }

    private func formatBytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = max(0, value)
        var index = 0
        while scaled >= 1_000, index < units.count - 1 {
            scaled /= 1_000
            index += 1
        }
        return "\(String(format: "%.2f", scaled)) \(units[index])"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(max(0, duration) / 60)
        if minutes >= 24 * 60 {
            return language == .simplifiedChinese
                ? "\(minutes / (24 * 60))天 \(minutes / 60 % 24)小时"
                : "\(minutes / (24 * 60))d \(minutes / 60 % 24)h"
        }
        if minutes >= 60 {
            return language == .simplifiedChinese
                ? "\(minutes / 60)小时 \(minutes % 60)分钟"
                : "\(minutes / 60)h \(minutes % 60)m"
        }
        return language == .simplifiedChinese ? "\(minutes)分钟" : "\(minutes)m"
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#if DEBUG
@MainActor
enum MonitorReportPreviewRenderer {
    static func render(to path: String) async -> Bool {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CovioReportPreview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let store = MonitorHistoryStore(
                path: directory.appendingPathComponent("history.sqlite")
            )
            let now = Date()
            let samples = (0..<2_880).map { index in
                let high = (1_200..<1_260).contains(index)
                let date = now.addingTimeInterval(Double(index - 2_880) * 30)
                return MonitorHistorySample(
                    sampledAt: date,
                    monotonicNanoseconds: UInt64(index) * 30_000_000_000,
                    bootID: "preview-boot",
                    powerSource: .ac,
                    thermalState: high ? .serious : .nominal,
                    cpuUsage: high ? 0.91 : 0.34,
                    cpuLoad1: high ? 7.2 : 1.4,
                    cpuCoreCount: 10,
                    gpuUsage: high ? 0.86 : 0.20,
                    gpuMemoryBytes: 690_000_000,
                    memoryUsedBytes: high ? 58_000_000_000 : 42_000_000_000,
                    memoryTotalBytes: 68_719_476_736,
                    memoryPressure: high ? .warning : .normal,
                    swapUsedBytes: high ? 2_000_000_000 : 0,
                    diskReadBytesPerSecond: 8_000_000,
                    diskWriteBytesPerSecond: 12_000_000,
                    diskUsedBytes: 930_000_000_000,
                    diskFreeBytes: 64_000_000_000,
                    networkReceiveBytesPerSecond: 4_000_000,
                    networkTransmitBytesPerSecond: 2_000_000,
                    batteryPercent: 80,
                    batteryTemperatureCelsius: high ? 47 : 33,
                    batteryHealthPercent: 94,
                    systemPowerWatts: high ? 72 : 22,
                    batteryPowerWatts: nil,
                    displayState: .on,
                    lidState: .open,
                    kind: .periodic,
                    quality: .complete
                )
            }
            try await store.insert(samples: samples)
            let model = MonitorReportModel(store: store, now: { now })
            await model.reload()
            let colorScheme: ColorScheme = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
                .lowercased() == "dark" ? .dark : .light
            let renderer = ImageRenderer(
                content: MonitorReportView(model: model, language: .simplifiedChinese)
                    .environment(\.colorScheme, colorScheme)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                return false
            }
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif

#if DEBUG
@MainActor
final class MonitorReportPreviewWindowController: NSWindowController {
    private let previewDirectory: URL

    private init(previewDirectory: URL, model: MonitorReportModel) {
        self.previewDirectory = previewDirectory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Covio Report Preview"
        window.appearance = HubAppearance.panel
        window.contentView = NSHostingView(
            rootView: MonitorReportView(model: model, language: .simplifiedChinese)
        )
        window.center()
        super.init(window: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        try? FileManager.default.removeItem(at: previewDirectory)
    }

    static func make() async -> MonitorReportPreviewWindowController? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CovioReportPreview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let store = MonitorHistoryStore(
                path: directory.appendingPathComponent("history.sqlite")
            )
            let now = Date()
            let samples = (0..<2_880).map { index in
                let high = (1_200..<1_260).contains(index)
                let date = now.addingTimeInterval(Double(index - 2_880) * 30)
                return MonitorHistorySample(
                    sampledAt: date,
                    monotonicNanoseconds: UInt64(index) * 30_000_000_000,
                    bootID: "preview-boot",
                    powerSource: .ac,
                    thermalState: high ? .serious : .nominal,
                    cpuUsage: high ? 0.91 : 0.34,
                    cpuLoad1: high ? 7.2 : 1.4,
                    cpuCoreCount: 10,
                    gpuUsage: high ? 0.86 : 0.20,
                    gpuMemoryBytes: 690_000_000,
                    memoryUsedBytes: high ? 58_000_000_000 : 42_000_000_000,
                    memoryTotalBytes: 68_719_476_736,
                    memoryPressure: high ? .warning : .normal,
                    swapUsedBytes: high ? 2_000_000_000 : 0,
                    diskReadBytesPerSecond: 8_000_000,
                    diskWriteBytesPerSecond: 12_000_000,
                    diskUsedBytes: 930_000_000_000,
                    diskFreeBytes: 64_000_000_000,
                    networkReceiveBytesPerSecond: 4_000_000,
                    networkTransmitBytesPerSecond: 2_000_000,
                    batteryPercent: 80,
                    batteryTemperatureCelsius: high ? 47 : 33,
                    batteryHealthPercent: 94,
                    systemPowerWatts: high ? 72 : 22,
                    batteryPowerWatts: nil,
                    displayState: .on,
                    lidState: .open,
                    kind: .periodic,
                    quality: .complete
                )
            }
            try await store.insert(samples: samples)
            let model = MonitorReportModel(store: store, now: { now })
            await model.reload()
            return MonitorReportPreviewWindowController(
                previewDirectory: directory,
                model: model
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }
}
#endif
