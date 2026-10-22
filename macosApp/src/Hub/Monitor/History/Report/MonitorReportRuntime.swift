import Foundation
import Observation

@MainActor
@Observable
final class MonitorReportModel {
    let store: any MonitorHistoryStoring
    let exporter: MonitorReportHTMLExporter
    let now: @Sendable () -> Date

    var startDate: Date
    var endDate: Date
    private(set) var report: MonitorReport?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(
        store: any MonitorHistoryStoring,
        exporter: MonitorReportHTMLExporter = MonitorReportHTMLExporter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.exporter = exporter
        self.now = now
        let end = now()
        self.endDate = end
        self.startDate = end.addingTimeInterval(-10 * 24 * 60 * 60)
    }

    var suggestedFileName: String {
        guard let report else { return "Covio-Report.html" }
        return exporter.suggestedFileName(for: report)
    }

    func selectLastTenDays() {
        endDate = now()
        startDate = endDate.addingTimeInterval(-10 * 24 * 60 * 60)
    }

    func setStartDate(_ value: Date) {
        startDate = min(value, endDate.addingTimeInterval(-60))
        keepRangeWithinLimit()
    }

    func setEndDate(_ value: Date) {
        endDate = max(value, startDate.addingTimeInterval(60))
        keepRangeWithinLimit()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let range = try MonitorReportRange(start: startDate, end: endDate)
            report = try await MonitorReportBuilder(store: store).build(
                range: range,
                generatedAt: now()
            )
        } catch {
            report = nil
            errorMessage = error.localizedDescription
        }
    }

    func writeReport(to destination: URL, language: AppLanguage) throws {
        guard let report else {
            throw MonitorReportError.invalidRange
        }
        try exporter.write(report: report, to: destination, language: language)
    }

    func clearHistory() async {
        do {
            try await store.deleteAll()
            report = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func keepRangeWithinLimit() {
        let maximum = Double(MonitorReportRange.maximumDays * 24 * 60 * 60)
        if endDate.timeIntervalSince(startDate) > maximum {
            startDate = endDate.addingTimeInterval(-maximum)
        }
    }
}
