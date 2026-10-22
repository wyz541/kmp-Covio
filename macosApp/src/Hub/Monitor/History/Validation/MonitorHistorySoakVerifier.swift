#if DEBUG
import Darwin
import Foundation

@MainActor
enum MonitorHistorySoakVerifier {
    static func run(
        outputDirectory: URL,
        duration: TimeInterval,
        language: AppLanguage
    ) async -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let databaseURL = outputDirectory.appendingPathComponent("Monitor/history.sqlite")
            let store = MonitorHistoryStore(path: databaseURL)
            let sampler = MonitorHistorySampler(store: store)
            let startedAt = Date()
            sampler.start()
            defer { sampler.stop() }

            let warmup = max(0, min(10, duration * 0.1))
            if warmup > 0 {
                try await Task.sleep(for: .seconds(warmup))
            }
            let measurementStartedAt = Date()
            let cpuBefore = processCPU()
            let remaining = max(0, duration - warmup)
            if remaining > 0 {
                try await Task.sleep(for: .seconds(remaining))
            }
            let endedAt = Date()
            let cpuAfter = processCPU()
            let measuredSeconds = max(0.001, endedAt.timeIntervalSince(measurementStartedAt))
            let processCPUPercent = (cpuAfter - cpuBefore) / measuredSeconds * 100

            let range = try MonitorReportRange(start: startedAt, end: endedAt)
            let report = try await MonitorReportBuilder(store: store).build(
                range: range,
                generatedAt: endedAt
            )
            let exporter = MonitorReportHTMLExporter()
            let htmlURL = outputDirectory.appendingPathComponent("monitor-report.html")
            try exporter.write(report: report, to: htmlURL, language: language)
            let htmlBytes = (try? FileManager.default.attributesOfItem(
                atPath: htmlURL.path
            )[.size] as? NSNumber)?.int64Value ?? 0

            let summary: [String: Any] = [
                "startedAt": ISO8601DateFormatter().string(from: startedAt),
                "endedAt": ISO8601DateFormatter().string(from: endedAt),
                "durationSeconds": duration,
                "sampleCount": report.coverage.sampleCount,
                "coverageFraction": report.coverage.coverageFraction,
                "observedSeconds": report.coverage.observedSeconds,
                "sleepSeconds": report.coverage.sleepSeconds,
                "unknownSeconds": report.coverage.unknownSeconds,
                "processCPUPercent": processCPUPercent,
                "databaseBytes": await store.databaseSizeBytes(),
                "htmlBytes": htmlBytes,
                "htmlPath": htmlURL.path,
            ]
            let summaryData = try JSONSerialization.data(
                withJSONObject: summary,
                options: [.prettyPrinted, .sortedKeys]
            )
            try summaryData.write(
                to: outputDirectory.appendingPathComponent("summary.json"),
                options: .atomic
            )
            return true
        } catch {
            let failure: [String: Any] = [
                "error": error.localizedDescription,
                "endedAt": ISO8601DateFormatter().string(from: Date()),
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: failure,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? data.write(
                    to: outputDirectory.appendingPathComponent("summary.json"),
                    options: .atomic
                )
            }
            return false
        }
    }

    private static func processCPU() -> TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
#endif
