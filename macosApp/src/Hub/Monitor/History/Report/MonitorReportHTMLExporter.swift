import Foundation

struct MonitorReportHTMLExporter: Sendable {
    func suggestedFileName(for report: MonitorReport) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Covio-Report-\(formatter.string(from: report.range.start))-\(formatter.string(from: report.range.end)).html"
    }

    func write(
        report: MonitorReport,
        to destination: URL,
        language: AppLanguage
    ) throws {
        let data = Data(html(report: report, language: language).utf8)
        try data.write(to: destination, options: .atomic)
    }

    func html(report: MonitorReport, language: AppLanguage) -> String {
        let dateFormatter = makeDateFormatter(language: language)
        let rangeText = "\(dateFormatter.string(from: report.range.start)) – \(dateFormatter.string(from: report.range.end))"
        let generatedText = dateFormatter.string(from: report.generatedAt)
        let coverage = report.coverage
        let coveragePercent = percent(coverage.coverageFraction, fraction: true)
        let partialBanner: String
        if coverage.isPartial {
            partialBanner = "<p class=\"notice\">"
                + escape(text(.copyMonitorReportPartial, language))
                + "</p>"
        } else {
            partialBanner = ""
        }

        let systemRows = report.systemEpochs.map { epoch in
            """
            <tr>
              <td>\(escape(dateFormatter.string(from: epoch.startedAt)))</td>
              <td>\(escape(epoch.osVersion)) (\(escape(epoch.osBuild)))</td>
              <td>\(escape(epoch.model))</td>
              <td>\(escape(epoch.chip))</td>
              <td>\(formatBytes(Double(epoch.memoryBytes), language: language))</td>
              <td>\(formatBytes(Double(epoch.diskTotalBytes), language: language))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let peakRows = report.peaks.map { peak in
            """
            <tr>
              <td>\(escape(peak.metric.rawValue))</td>
              <td>\(escape(metricValue(peak.value, metric: peak.metric, language: language)))</td>
              <td>\(escape(dateFormatter.string(from: peak.at)))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let thresholdRows = report.thresholdIntervals.map { interval in
            """
            <tr>
              <td>\(escape(interval.kind.rawValue))</td>
              <td>\(escape(dateFormatter.string(from: interval.start)))</td>
              <td>\(escape(dateFormatter.string(from: interval.end)))</td>
              <td>\(escape(formatDuration(interval.duration, language: language)))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let eventRows = report.events.map { event in
            """
            <tr>
              <td>\(escape(dateFormatter.string(from: event.occurredAt)))</td>
              <td>\(escape(event.kind.rawValue))</td>
              <td>\(escape(event.source.rawValue))</td>
              <td>\(escape(event.confidence.rawValue))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let gapRows = report.gapSummaries.map { gap in
            """
            <tr>
              <td>\(escape(gap.reason.rawValue))</td>
              <td>\(gap.count)</td>
              <td>\(escape(formatDuration(gap.duration, language: language)))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let unavailableRows = report.unavailableMetrics.map { metric in
            "<li>\(escape(metric.rawValue))</li>"
        }.joined(separator: "\n")

        let tableRows = report.buckets
            .filter { $0.sampleCount > 0 }
            .map { bucket in
                """
                <tr>
                  <td>\(escape(dateFormatter.string(from: bucket.start)))</td>
                  <td>\(escape(optionalPercent(bucket.cpuUsage, language: language)))</td>
                  <td>\(escape(optionalPercent(bucket.gpuUsage, language: language)))</td>
                  <td>\(escape(optionalPercent(bucket.memoryFraction, language: language)))</td>
                  <td>\(escape(optionalRate(bucket.networkReceiveBytesPerSecond, language: language)))</td>
                  <td>\(escape(optionalRate(bucket.networkTransmitBytesPerSecond, language: language)))</td>
                </tr>
                """
            }
            .joined(separator: "\n")

        let cpuGpuChart = lineChart(
            title: text(.copyMonitorReportChartCpuGpu, language),
            description: "\(text(.copyMonitorReportChartCpuGpu, language)): \(text(.copyMonitorReportMethod, language))",
            buckets: report.buckets,
            series: [
                .init(name: "CPU", values: report.buckets.map(\.cpuUsage), maximum: 1, color: "#0A84FF"),
                .init(name: "GPU", values: report.buckets.map(\.gpuUsage), maximum: 1, color: "#FF9F0A"),
            ]
        )
        let memoryChart = lineChart(
            title: text(.copyMonitorReportChartMemory, language),
            description: text(.copyMonitorReportChartMemory, language),
            buckets: report.buckets,
            series: [
                .init(name: "Memory", values: report.buckets.map(\.memoryFraction), maximum: 1, color: "#30D158"),
            ]
        )
        let networkMaximum = max(
            report.buckets.compactMap(\.networkReceiveBytesPerSecond).max() ?? 0,
            report.buckets.compactMap(\.networkTransmitBytesPerSecond).max() ?? 0,
            1
        )
        let networkChart = lineChart(
            title: text(.copyMonitorReportChartNetwork, language),
            description: text(.copyMonitorReportChartNetwork, language),
            buckets: report.buckets,
            series: [
                .init(
                    name: text(.copyMonitorReportTableNetworkDown, language),
                    values: report.buckets.map(\.networkReceiveBytesPerSecond),
                    maximum: networkMaximum,
                    color: "#64D2FF"
                ),
                .init(
                    name: text(.copyMonitorReportTableNetworkUp, language),
                    values: report.buckets.map(\.networkTransmitBytesPerSecond),
                    maximum: networkMaximum,
                    color: "#BF5AF2"
                ),
            ]
        )

        return """
        <!doctype html>
        <html lang="\(language == .simplifiedChinese ? "zh-Hans" : "en")">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(text(.copyMonitorReportTitle, language))) · \(escape(rangeText))</title>
          <style>
            :root { color-scheme: light dark; --paper:#f7f6f2; --ink:#1f2328; --muted:#666b73; --line:#d7d9dd; --accent:#0a84ff; --card:#ffffff; }
            @media (prefers-color-scheme: dark) { :root { --paper:#15171a; --ink:#f2f3f5; --muted:#a7abb2; --line:#34383f; --card:#1e2126; } }
            * { box-sizing: border-box; }
            body { margin:0; background:var(--paper); color:var(--ink); font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC",sans-serif; line-height:1.48; }
            main { width:min(1100px, calc(100% - 40px)); margin:32px auto 64px; }
            h1 { margin:0 0 6px; font-size:34px; letter-spacing:-.02em; }
            h2 { margin:36px 0 12px; font-size:22px; }
            h3 { margin:24px 0 10px; font-size:17px; }
            p { margin:8px 0; }
            .muted { color:var(--muted); }
            .notice { padding:12px 14px; border:1px solid #f0b35a; background:#fff5df; color:#5f3a00; border-radius:10px; }
            .summary { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:12px; margin:20px 0; }
            .metric { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px; }
            .metric strong { display:block; font-size:22px; }
            .metric span { color:var(--muted); font-size:13px; }
            table { width:100%; border-collapse:collapse; margin:10px 0 20px; font-size:13px; }
            th,td { text-align:left; vertical-align:top; padding:8px 9px; border-bottom:1px solid var(--line); }
            th { color:var(--muted); font-weight:600; }
            .scroll { overflow-x:auto; }
            .chart { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px; margin:12px 0; }
            .chart svg { width:100%; height:auto; display:block; }
            details { margin:12px 0 24px; }
            summary { cursor:pointer; color:var(--accent); }
            ul { padding-left:20px; }
            footer { margin-top:40px; padding-top:16px; border-top:1px solid var(--line); color:var(--muted); font-size:12px; }
            @media print {
              body { background:white; color:black; }
              main { width:100%; margin:0; }
              .metric,.chart { break-inside:avoid; }
              details { display:block; }
              details > summary { display:none; }
            }
          </style>
        </head>
        <body>
        <main>
          <header>
            <h1>\(escape(text(.copyMonitorReportTitle, language)))</h1>
            <p class="muted">\(escape(rangeText))</p>
            <p class="muted">\(escape(text(.copyMonitorReportGenerated, language))): \(escape(generatedText))</p>
          </header>
          \(partialBanner)

          <section class="summary" aria-label="\(escape(text(.copyMonitorReportCoverageTitle, language)))">
            <div class="metric"><strong>\(escape(coveragePercent))</strong><span>\(escape(text(.copyMonitorReportCoverageObserved, language)))</span></div>
            <div class="metric"><strong>\(coverage.sampleCount)</strong><span>\(escape(text(.copyMonitorReportCoverageSamples, language)))</span></div>
            <div class="metric"><strong>\(escape(formatDuration(coverage.sleepSeconds, language: language)))</strong><span>\(escape(text(.copyMonitorReportCoverageSleep, language)))</span></div>
            <div class="metric"><strong>\(escape(formatDuration(coverage.unknownSeconds, language: language)))</strong><span>\(escape(text(.copyMonitorReportCoverageUnknown, language)))</span></div>
          </section>

          <h2>\(escape(text(.copyMonitorReportSystemTitle, language)))</h2>
          <div class="scroll"><table>
            <thead><tr><th>Start</th><th>macOS</th><th>Model</th><th>Chip</th><th>Memory</th><th>Disk</th></tr></thead>
            <tbody>\(systemRows)</tbody>
          </table></div>

          <h2>\(escape(text(.copyMonitorReportPeaksTitle, language)))</h2>
          <div class="scroll"><table>
            <thead><tr><th>Metric</th><th>Peak</th><th>\(escape(text(.copyMonitorReportTableTime, language)))</th></tr></thead>
            <tbody>\(peakRows)</tbody>
          </table></div>

          <h2>\(escape(text(.copyMonitorReportThresholdsTitle, language)))</h2>
          <div class="scroll"><table>
            <thead><tr><th>Kind</th><th>Start</th><th>End</th><th>Duration</th></tr></thead>
            <tbody>\(thresholdRows)</tbody>
          </table></div>

          <h2>\(escape(text(.copyMonitorReportTitle, language)))</h2>
          \(cpuGpuChart)
          \(memoryChart)
          \(networkChart)

          <details>
            <summary>\(escape(text(.copyMonitorReportCoverageTitle, language)))</summary>
            <div class="scroll"><table>
              <thead><tr><th>\(escape(text(.copyMonitorReportTableTime, language)))</th><th>\(escape(text(.copyMonitorReportTableCpu, language)))</th><th>\(escape(text(.copyMonitorReportTableGpu, language)))</th><th>\(escape(text(.copyMonitorReportTableMemory, language)))</th><th>\(escape(text(.copyMonitorReportTableNetworkDown, language)))</th><th>\(escape(text(.copyMonitorReportTableNetworkUp, language)))</th></tr></thead>
              <tbody>\(tableRows)</tbody>
            </table></div>
          </details>

          <h2>\(escape(text(.copyMonitorReportEventsTitle, language)))</h2>
          <div class="scroll"><table>
            <thead><tr><th>Time</th><th>Event</th><th>Source</th><th>Confidence</th></tr></thead>
            <tbody>\(eventRows)</tbody>
          </table></div>

          <h2>\(escape(text(.copyMonitorReportGapsTitle, language)))</h2>
          <div class="scroll"><table>
            <thead><tr><th>Reason</th><th>Count</th><th>Duration</th></tr></thead>
            <tbody>\(gapRows)</tbody>
          </table></div>

          <h2>\(escape(text(.copyMonitorReportUnavailableTitle, language)))</h2>
          <ul>\(unavailableRows)</ul>

          <footer>
            \(escape(text(.copyMonitorReportMethod, language))).<br>
            \(language == .simplifiedChinese
                ? "CPU/GPU：接电源每 30 秒采样，使用电池每 60 秒采样。图表使用 5 分钟时间桶。"
                : "CPU/GPU: 30-second AC samples and 60-second battery samples. Charts use 5-minute buckets.")
          </footer>
        </main>
        </body>
        </html>
        """
    }

    private struct Series {
        let name: String
        let values: [Double?]
        let maximum: Double
        let color: String
    }

    private func lineChart(
        title: String,
        description: String,
        buckets: [MonitorReportBucket],
        series: [Series]
    ) -> String {
        let width = 1_000.0
        let height = 220.0
        let innerWidth = 940.0
        let innerHeight = 170.0
        let pointCount = max(1, buckets.count)
        let paths = series.map { series -> String in
            let points = series.values.enumerated().compactMap { index, value -> String? in
                guard let value, value.isFinite else { return nil }
                let x = 30 + innerWidth * Double(index) / Double(max(1, pointCount - 1))
                let normalized = min(1, max(0, value / max(series.maximum, 0.000_001)))
                let y = 20 + innerHeight * (1 - normalized)
                return String(format: "%.2f,%.2f", x, y)
            }.joined(separator: " ")
            let safeName = escape(series.name)
            return "<polyline points=\"\(points)\" fill=\"none\" stroke=\"\(series.color)\" stroke-width=\"2.5\" stroke-linejoin=\"round\" stroke-linecap=\"round\" aria-label=\"\(safeName)\"/>"
        }.joined(separator: "\n")
        let legend = series.map {
            "<span style=\"display:inline-flex;gap:6px;align-items:center;margin-right:14px\"><span style=\"width:10px;height:10px;border-radius:50%;background:\($0.color)\"></span>\(escape($0.name))</span>"
        }.joined()

        return """
        <figure class="chart">
          <svg viewBox="0 0 \(Int(width)) \(Int(height))" role="img" aria-labelledby="chart-title-\(stableID(title)) chart-desc-\(stableID(title))">
            <title id="chart-title-\(stableID(title))">\(escape(title))</title>
            <desc id="chart-desc-\(stableID(title))">\(escape(description))</desc>
            <line x1="30" y1="190" x2="970" y2="190" stroke="currentColor" opacity="0.25"/>
            <line x1="30" y1="20" x2="30" y2="190" stroke="currentColor" opacity="0.25"/>
            \(paths)
          </svg>
          <figcaption>\(legend)</figcaption>
        </figure>
        """
    }

    private enum TextKey {
        case copyMonitorReportTitle
        case copyMonitorReportSummary
        case copyMonitorReportRangeStart
        case copyMonitorReportRangeEnd
        case copyMonitorReportCoverageTitle
        case copyMonitorReportCoverageSamples
        case copyMonitorReportCoverageObserved
        case copyMonitorReportCoverageSleep
        case copyMonitorReportCoverageUnknown
        case copyMonitorReportPeaksTitle
        case copyMonitorReportThresholdsTitle
        case copyMonitorReportEventsTitle
        case copyMonitorReportGapsTitle
        case copyMonitorReportUnavailableTitle
        case copyMonitorReportSystemTitle
        case copyMonitorReportChartCpuGpu
        case copyMonitorReportChartMemory
        case copyMonitorReportChartNetwork
        case copyMonitorReportTableTime
        case copyMonitorReportTableCpu
        case copyMonitorReportTableGpu
        case copyMonitorReportTableMemory
        case copyMonitorReportTableNetworkDown
        case copyMonitorReportTableNetworkUp
        case copyMonitorReportMethod
        case copyMonitorReportGenerated
        case copyMonitorReportPartial
    }

    private func text(_ key: TextKey, _ language: AppLanguage) -> String {
        switch key {
        case .copyMonitorReportTitle: ContractCopy.copyMonitorReportTitle.text(for: language)
        case .copyMonitorReportSummary: ContractCopy.copyMonitorReportSummary.text(for: language)
        case .copyMonitorReportRangeStart: ContractCopy.copyMonitorReportRangeStart.text(for: language)
        case .copyMonitorReportRangeEnd: ContractCopy.copyMonitorReportRangeEnd.text(for: language)
        case .copyMonitorReportCoverageTitle: ContractCopy.copyMonitorReportCoverageTitle.text(for: language)
        case .copyMonitorReportCoverageSamples: ContractCopy.copyMonitorReportCoverageSamples.text(for: language)
        case .copyMonitorReportCoverageObserved: ContractCopy.copyMonitorReportCoverageObserved.text(for: language)
        case .copyMonitorReportCoverageSleep: ContractCopy.copyMonitorReportCoverageSleep.text(for: language)
        case .copyMonitorReportCoverageUnknown: ContractCopy.copyMonitorReportCoverageUnknown.text(for: language)
        case .copyMonitorReportPeaksTitle: ContractCopy.copyMonitorReportPeaksTitle.text(for: language)
        case .copyMonitorReportThresholdsTitle: ContractCopy.copyMonitorReportThresholdsTitle.text(for: language)
        case .copyMonitorReportEventsTitle: ContractCopy.copyMonitorReportEventsTitle.text(for: language)
        case .copyMonitorReportGapsTitle: ContractCopy.copyMonitorReportGapsTitle.text(for: language)
        case .copyMonitorReportUnavailableTitle: ContractCopy.copyMonitorReportUnavailableTitle.text(for: language)
        case .copyMonitorReportSystemTitle: ContractCopy.copyMonitorReportSystemTitle.text(for: language)
        case .copyMonitorReportChartCpuGpu: ContractCopy.copyMonitorReportChartCpuGpu.text(for: language)
        case .copyMonitorReportChartMemory: ContractCopy.copyMonitorReportChartMemory.text(for: language)
        case .copyMonitorReportChartNetwork: ContractCopy.copyMonitorReportChartNetwork.text(for: language)
        case .copyMonitorReportTableTime: ContractCopy.copyMonitorReportTableTime.text(for: language)
        case .copyMonitorReportTableCpu: ContractCopy.copyMonitorReportTableCpu.text(for: language)
        case .copyMonitorReportTableGpu: ContractCopy.copyMonitorReportTableGpu.text(for: language)
        case .copyMonitorReportTableMemory: ContractCopy.copyMonitorReportTableMemory.text(for: language)
        case .copyMonitorReportTableNetworkDown: ContractCopy.copyMonitorReportTableNetworkDown.text(for: language)
        case .copyMonitorReportTableNetworkUp: ContractCopy.copyMonitorReportTableNetworkUp.text(for: language)
        case .copyMonitorReportMethod: ContractCopy.copyMonitorReportMethod.text(for: language)
        case .copyMonitorReportGenerated: ContractCopy.copyMonitorReportGenerated.text(for: language)
        case .copyMonitorReportPartial: ContractCopy.copyMonitorReportPartial.text(for: language)
        }
    }

    private func makeDateFormatter(language: AppLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func metricValue(
        _ value: Double,
        metric: MonitorReportMetric,
        language: AppLanguage
    ) -> String {
        switch metric {
        case .cpuUsage, .gpuUsage, .memoryFraction, .batteryPercent:
            return percent(value, fraction: metric != .batteryPercent)
        case .diskReadRate, .diskWriteRate, .networkReceiveRate, .networkTransmitRate:
            return formatRate(value, language: language)
        case .swapUsed, .batteryTemperature, .systemPower, .batteryPower,
             .cpuTemperature, .gpuTemperature, .fanRPM, .cpuFrequency:
            return String(format: "%.2f", value)
        }
    }

    private func optionalPercent(_ value: Double?, language: AppLanguage) -> String {
        guard let value else { return "—" }
        return percent(value, fraction: true)
    }

    private func optionalRate(_ value: Double?, language: AppLanguage) -> String {
        guard let value else { return "—" }
        return formatRate(value, language: language)
    }

    private func percent(_ value: Double, fraction: Bool) -> String {
        let normalized = fraction ? value * 100 : value
        return String(format: "%.1f%%", normalized)
    }

    private func formatRate(_ value: Double, language: AppLanguage) -> String {
        "\(formatBytes(value, language: language))/s"
    }

    private func formatBytes(_ value: Double, language: AppLanguage) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = max(0, value)
        var unit = 0
        while scaled >= 1_000, unit < units.count - 1 {
            scaled /= 1_000
            unit += 1
        }
        return String(format: "%.2f %@", scaled, units[unit])
    }

    private func formatDuration(_ seconds: TimeInterval, language: AppLanguage) -> String {
        let totalMinutes = Int(max(0, seconds) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0 { return language == .simplifiedChinese ? "\(days)天 \(hours)小时" : "\(days)d \(hours)h" }
        if hours > 0 { return language == .simplifiedChinese ? "\(hours)小时 \(minutes)分钟" : "\(hours)h \(minutes)m" }
        return language == .simplifiedChinese ? "\(minutes)分钟" : "\(minutes)m"
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func stableID(_ value: String) -> String {
        value.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }
}
