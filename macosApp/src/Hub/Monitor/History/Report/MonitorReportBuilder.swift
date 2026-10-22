import Foundation

/// 把历史样本转换为可生成 HTML 的报告事实。
struct MonitorReportBuilder: Sendable {
    let store: any MonitorHistoryStoring

    func build(
        range: MonitorReportRange,
        generatedAt: Date = Date()
    ) async throws -> MonitorReport {
        let samples = try await store.samples(from: range.start, to: range.end)
        let events = try await store.events(from: range.start, to: range.end)
        let gaps = try await store.gaps(overlapping: range.start, through: range.end)
        let epochs = try await store.systemEpochs()
        let sortedSamples = samples.sorted { $0.sampledAt < $1.sampledAt }
        let sortedEvents = events.sorted { $0.occurredAt < $1.occurredAt }
        let sortedGaps = gaps.sorted { $0.startedAt < $1.startedAt }
        let buckets = makeBuckets(samples: sortedSamples, range: range)
        let coverage = makeCoverage(samples: sortedSamples, gaps: sortedGaps, range: range)
        let peaks = makePeaks(samples: sortedSamples)
        let thresholdIntervals = makeThresholdIntervals(
            samples: sortedSamples,
            buckets: buckets,
            range: range
        )
        let gapSummaries = makeGapSummaries(gaps: sortedGaps, range: range)
        let unavailableMetrics = makeUnavailableMetrics(samples: sortedSamples)

        return MonitorReport(
            range: range,
            generatedAt: generatedAt,
            coverage: coverage,
            buckets: buckets,
            peaks: peaks,
            thresholdIntervals: thresholdIntervals,
            events: sortedEvents,
            gaps: sortedGaps,
            gapSummaries: gapSummaries,
            systemEpochs: epochs,
            unavailableMetrics: unavailableMetrics,
            highestMemoryPressure: highestMemoryPressure(in: sortedSamples),
            highestThermalState: highestThermalState(in: sortedSamples)
        )
    }

    // MARK: - Buckets

    private struct AverageAccumulator {
        private(set) var sum = 0.0
        private(set) var count = 0

        mutating func add(_ value: Double?) {
            guard let value, value.isFinite else { return }
            sum += value
            count += 1
        }

        var average: Double? {
            count > 0 ? sum / Double(count) : nil
        }
    }

    private struct BucketAccumulator {
        var sampleCount = 0
        var cpu = AverageAccumulator()
        var gpu = AverageAccumulator()
        var memory = AverageAccumulator()
        var swap = AverageAccumulator()
        var diskRead = AverageAccumulator()
        var diskWrite = AverageAccumulator()
        var networkReceive = AverageAccumulator()
        var networkTransmit = AverageAccumulator()
        var battery = AverageAccumulator()
        var batteryTemperature = AverageAccumulator()
        var systemPower = AverageAccumulator()
        var batteryPower = AverageAccumulator()
        var highestMemoryPressure: MonitorHistorySample.MemoryPressure?
        var highestThermalState: MonitorHistorySample.ThermalState?
        var acSampleCount = 0
        var batterySampleCount = 0

        mutating func add(_ sample: MonitorHistorySample) {
            sampleCount += 1
            cpu.add(sample.cpuUsage)
            gpu.add(sample.gpuUsage)
            if let used = sample.memoryUsedBytes,
               let total = sample.memoryTotalBytes,
               total > 0 {
                memory.add(used / total)
            }
            swap.add(sample.swapUsedBytes)
            diskRead.add(sample.diskReadBytesPerSecond)
            diskWrite.add(sample.diskWriteBytesPerSecond)
            networkReceive.add(sample.networkReceiveBytesPerSecond)
            networkTransmit.add(sample.networkTransmitBytesPerSecond)
            battery.add(sample.batteryPercent)
            batteryTemperature.add(sample.batteryTemperatureCelsius)
            systemPower.add(sample.systemPowerWatts)
            batteryPower.add(sample.batteryPowerWatts)
            if let pressure = sample.memoryPressure,
               pressure.rank >= (highestMemoryPressure?.rank ?? 0) {
                highestMemoryPressure = pressure
            }
            if sample.thermalState.rank >= (highestThermalState?.rank ?? 0) {
                highestThermalState = sample.thermalState
            }
            if sample.powerSource == .ac {
                acSampleCount += 1
            } else if sample.powerSource == .battery {
                batterySampleCount += 1
            }
        }

        func bucket(start: Date, end: Date) -> MonitorReportBucket {
            MonitorReportBucket(
                start: start,
                end: end,
                sampleCount: sampleCount,
                cpuUsage: cpu.average,
                gpuUsage: gpu.average,
                memoryFraction: memory.average,
                swapUsedBytes: swap.average,
                diskReadBytesPerSecond: diskRead.average,
                diskWriteBytesPerSecond: diskWrite.average,
                networkReceiveBytesPerSecond: networkReceive.average,
                networkTransmitBytesPerSecond: networkTransmit.average,
                batteryPercent: battery.average,
                batteryTemperatureCelsius: batteryTemperature.average,
                systemPowerWatts: systemPower.average,
                batteryPowerWatts: batteryPower.average,
                highestMemoryPressure: highestMemoryPressure,
                highestThermalState: highestThermalState,
                acSampleCount: acSampleCount,
                batterySampleCount: batterySampleCount
            )
        }
    }

    private func makeBuckets(
        samples: [MonitorHistorySample],
        range: MonitorReportRange
    ) -> [MonitorReportBucket] {
        let bucketSeconds = Double(range.bucketSeconds)
        var buckets: [Int: BucketAccumulator] = [:]
        for sample in samples {
            let index = Int(floor(sample.sampledAt.timeIntervalSince1970 / bucketSeconds))
            buckets[index, default: BucketAccumulator()].add(sample)
        }

        let firstIndex = Int(floor(range.start.timeIntervalSince1970 / bucketSeconds))
        let effectiveEnd = max(range.start, range.end.addingTimeInterval(-0.001))
        let lastIndex = Int(floor(effectiveEnd.timeIntervalSince1970 / bucketSeconds))
        guard lastIndex >= firstIndex else { return [] }

        return (firstIndex...lastIndex).map { index in
            let start = Date(timeIntervalSince1970: Double(index) * bucketSeconds)
            let end = start.addingTimeInterval(bucketSeconds)
            return buckets[index, default: BucketAccumulator()].bucket(start: start, end: end)
        }
    }

    // MARK: - Coverage

    private func makeCoverage(
        samples: [MonitorHistorySample],
        gaps: [MonitorHistoryGap],
        range: MonitorReportRange
    ) -> MonitorReportCoverage {
        let requested = range.duration
        guard !samples.isEmpty else {
            return MonitorReportCoverage(
                requestedSeconds: requested,
                observedSeconds: 0,
                sleepSeconds: 0,
                unknownSeconds: requested,
                coverageFraction: 0,
                sampleCount: 0,
                firstSampleAt: nil,
                lastSampleAt: nil
            )
        }

        var observed: TimeInterval = 0
        for (index, sample) in samples.enumerated() {
            let interval = MonitorHistorySamplingPolicy.interval(for: sample)
            let naturalEnd = sample.sampledAt.addingTimeInterval(interval)
            let segmentEnd: Date
            if index + 1 < samples.count {
                let next = samples[index + 1].sampledAt
                if next.timeIntervalSince(sample.sampledAt)
                    <= MonitorHistorySamplingPolicy.gapThreshold(for: interval) {
                    segmentEnd = next
                } else {
                    segmentEnd = naturalEnd
                }
            } else {
                segmentEnd = min(naturalEnd, range.end)
            }
            observed += overlap(
                start: max(sample.sampledAt, range.start),
                end: min(segmentEnd, range.end)
            )
        }
        observed = min(requested, max(0, observed))

        let sleepRanges = mergedRanges(
            gaps
                .filter { $0.reason == .sleep }
                .compactMap { clippedRange(for: $0, in: range) }
        )
        let sleepGap = duration(of: sleepRanges)
        let unobserved = max(0, requested - observed)
        let sleep = min(unobserved, sleepGap)
        let unknown = max(0, unobserved - sleep)
        let fraction = requested > 0 ? observed / requested : 0

        return MonitorReportCoverage(
            requestedSeconds: requested,
            observedSeconds: observed,
            sleepSeconds: sleep,
            unknownSeconds: unknown,
            coverageFraction: min(1, max(0, fraction)),
            sampleCount: samples.count,
            firstSampleAt: samples.first?.sampledAt,
            lastSampleAt: samples.last?.sampledAt
        )
    }

    // MARK: - Peaks

    private func makePeaks(samples: [MonitorHistorySample]) -> [MonitorReportPeak] {
        var peaks: [MonitorReportMetric: MonitorReportPeak] = [:]

        func update(_ metric: MonitorReportMetric, value: Double?, at date: Date) {
            guard let value, value.isFinite else { return }
            if let previous = peaks[metric], previous.value >= value { return }
            peaks[metric] = MonitorReportPeak(metric: metric, value: value, at: date)
        }

        for sample in samples {
            update(.cpuUsage, value: sample.cpuUsage, at: sample.sampledAt)
            update(.gpuUsage, value: sample.gpuUsage, at: sample.sampledAt)
            if let used = sample.memoryUsedBytes,
               let total = sample.memoryTotalBytes,
               total > 0 {
                update(.memoryFraction, value: used / total, at: sample.sampledAt)
            }
            update(.swapUsed, value: sample.swapUsedBytes, at: sample.sampledAt)
            update(.diskReadRate, value: sample.diskReadBytesPerSecond, at: sample.sampledAt)
            update(.diskWriteRate, value: sample.diskWriteBytesPerSecond, at: sample.sampledAt)
            update(.networkReceiveRate, value: sample.networkReceiveBytesPerSecond, at: sample.sampledAt)
            update(.networkTransmitRate, value: sample.networkTransmitBytesPerSecond, at: sample.sampledAt)
            update(.batteryPercent, value: sample.batteryPercent, at: sample.sampledAt)
            update(.batteryTemperature, value: sample.batteryTemperatureCelsius, at: sample.sampledAt)
            update(.systemPower, value: sample.systemPowerWatts, at: sample.sampledAt)
            update(.batteryPower, value: sample.batteryPowerWatts, at: sample.sampledAt)
        }

        return peaks.values.sorted { $0.metric.rawValue < $1.metric.rawValue }
    }

    // MARK: - Thresholds

    private struct OpenThreshold {
        var kind: MonitorReportThresholdInterval.Kind
        var start: Date
        var end: Date
        var peakValue: Double?
    }

    private func makeThresholdIntervals(
        samples: [MonitorHistorySample],
        buckets: [MonitorReportBucket],
        range: MonitorReportRange
    ) -> [MonitorReportThresholdInterval] {
        var values: [MonitorReportThresholdInterval] = []
        values.append(
            contentsOf: makeBucketThresholdIntervals(
                buckets: buckets,
                kind: .cpuHigh,
                value: { $0.cpuUsage },
                isHigh: { ($0 ?? 0) >= 0.8 }
            )
        )
        values.append(
            contentsOf: makeBucketThresholdIntervals(
                buckets: buckets,
                kind: .gpuHigh,
                value: { $0.gpuUsage },
                isHigh: { ($0 ?? 0) >= 0.8 }
            )
        )
        values.append(
            contentsOf: makeSampleThresholdIntervals(
                samples: samples,
                kind: .lowDiskSpace,
                range: range,
                value: { sample in
                    guard let used = sample.diskUsedBytes,
                          let free = sample.diskFreeBytes,
                          used + free > 0 else { return nil }
                    return used / (used + free)
                },
                isHigh: { ($0 ?? 0) >= 0.9 }
            )
        )
        values.append(
            contentsOf: makeSampleThresholdIntervals(
                samples: samples,
                kind: .batteryHighTemperature,
                range: range,
                value: \.batteryTemperatureCelsius,
                isHigh: { ($0 ?? 0) >= 45 }
            )
        )
        values.append(
            contentsOf: makeThermalIntervals(samples: samples, range: range)
        )
        return values.sorted {
            if $0.start == $1.start { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.start < $1.start
        }
    }

    private func makeBucketThresholdIntervals(
        buckets: [MonitorReportBucket],
        kind: MonitorReportThresholdInterval.Kind,
        value: (MonitorReportBucket) -> Double?,
        isHigh: (Double?) -> Bool
    ) -> [MonitorReportThresholdInterval] {
        var intervals: [MonitorReportThresholdInterval] = []
        var open: OpenThreshold?
        for bucket in buckets {
            let current = value(bucket)
            if isHigh(current), bucket.sampleCount > 0 {
                if var currentOpen = open {
                    currentOpen.end = bucket.end
                    if let current, current > (currentOpen.peakValue ?? -.infinity) {
                        currentOpen.peakValue = current
                    }
                    open = currentOpen
                } else {
                    open = OpenThreshold(
                        kind: kind,
                        start: bucket.start,
                        end: bucket.end,
                        peakValue: current
                    )
                }
            } else if let currentOpen = open {
                intervals.append(
                    MonitorReportThresholdInterval(
                        kind: currentOpen.kind,
                        start: currentOpen.start,
                        end: currentOpen.end,
                        peakValue: currentOpen.peakValue
                    )
                )
                open = nil
            }
        }
        if let open {
            intervals.append(
                MonitorReportThresholdInterval(
                    kind: open.kind,
                    start: open.start,
                    end: open.end,
                    peakValue: open.peakValue
                )
            )
        }
        return intervals
    }

    private func makeSampleThresholdIntervals(
        samples: [MonitorHistorySample],
        kind: MonitorReportThresholdInterval.Kind,
        range: MonitorReportRange,
        value: (MonitorHistorySample) -> Double?,
        isHigh: (Double?) -> Bool
    ) -> [MonitorReportThresholdInterval] {
        var intervals: [MonitorReportThresholdInterval] = []
        var open: OpenThreshold?
        for sample in samples {
            let current = value(sample)
            guard isHigh(current) else {
                if let open {
                    intervals.append(
                        MonitorReportThresholdInterval(
                            kind: open.kind,
                            start: open.start,
                            end: min(open.end, range.end),
                            peakValue: open.peakValue
                        )
                    )
                }
                open = nil
                continue
            }
            let end = min(
                sample.sampledAt.addingTimeInterval(
                    MonitorHistorySamplingPolicy.interval(for: sample)
                ),
                range.end
            )
            if var currentOpen = open,
               sample.sampledAt <= currentOpen.end.addingTimeInterval(90) {
                currentOpen.end = end
                if let current, current > (currentOpen.peakValue ?? -.infinity) {
                    currentOpen.peakValue = current
                }
                open = currentOpen
            } else {
                if let open {
                    intervals.append(
                        MonitorReportThresholdInterval(
                            kind: open.kind,
                            start: open.start,
                            end: min(open.end, range.end),
                            peakValue: open.peakValue
                        )
                    )
                }
                open = OpenThreshold(
                    kind: kind,
                    start: max(sample.sampledAt, range.start),
                    end: end,
                    peakValue: current
                )
            }
        }
        if let open {
            intervals.append(
                MonitorReportThresholdInterval(
                    kind: open.kind,
                    start: open.start,
                    end: min(open.end, range.end),
                    peakValue: open.peakValue
                )
            )
        }
        return intervals
    }

    private func makeThermalIntervals(
        samples: [MonitorHistorySample],
        range: MonitorReportRange
    ) -> [MonitorReportThresholdInterval] {
        var intervals: [MonitorReportThresholdInterval] = []
        var open: OpenThreshold?
        for sample in samples {
            let kind: MonitorReportThresholdInterval.Kind?
            let value: Double?
            switch sample.thermalState {
            case .nominal:
                kind = nil
                value = 0
            case .fair:
                kind = .thermalFair
                value = 1
            case .serious:
                kind = .thermalSerious
                value = 2
            case .critical:
                kind = .thermalCritical
                value = 3
            }
            guard let kind else {
                closeThreshold(&open, into: &intervals, range: range)
                continue
            }
            let end = min(
                sample.sampledAt.addingTimeInterval(
                    MonitorHistorySamplingPolicy.interval(for: sample)
                ),
                range.end
            )
            if var current = open, current.kind == kind {
                current.end = end
                current.peakValue = max(current.peakValue ?? 0, value ?? 0)
                open = current
            } else {
                closeThreshold(&open, into: &intervals, range: range)
                open = OpenThreshold(
                    kind: kind,
                    start: max(sample.sampledAt, range.start),
                    end: end,
                    peakValue: value
                )
            }
        }
        closeThreshold(&open, into: &intervals, range: range)
        return intervals
    }

    private func closeThreshold(
        _ open: inout OpenThreshold?,
        into values: inout [MonitorReportThresholdInterval],
        range: MonitorReportRange
    ) {
        guard let current = open else { return }
        values.append(
            MonitorReportThresholdInterval(
                kind: current.kind,
                start: current.start,
                end: min(current.end, range.end),
                peakValue: current.peakValue
            )
        )
        open = nil
    }

    // MARK: - Gaps and unavailable metrics

    private func makeGapSummaries(
        gaps: [MonitorHistoryGap],
        range: MonitorReportRange
    ) -> [MonitorReportGapSummary] {
        var totals: [MonitorHistoryGap.Reason: (duration: TimeInterval, count: Int)] = [:]
        for gap in gaps {
            guard let clipped = clippedRange(for: gap, in: range) else { continue }
            let duration = max(0, clipped.upperBound - clipped.lowerBound)
            let previous = totals[gap.reason] ?? (0, 0)
            totals[gap.reason] = (previous.duration + duration, previous.count + 1)
        }
        return totals
            .map { MonitorReportGapSummary(reason: $0.key, duration: $0.value.duration, count: $0.value.count) }
            .sorted { $0.reason.rawValue < $1.reason.rawValue }
    }

    private func makeUnavailableMetrics(
        samples: [MonitorHistorySample]
    ) -> [MonitorReportMetric] {
        var unavailable: Set<MonitorReportMetric> = [
            .cpuTemperature,
            .gpuTemperature,
            .fanRPM,
            .cpuFrequency,
        ]
        if !samples.contains(where: { $0.gpuUsage != nil }) {
            unavailable.insert(.gpuUsage)
        }
        if !samples.contains(where: { $0.batteryPercent != nil }) {
            unavailable.insert(.batteryPercent)
        }
        if !samples.contains(where: { $0.batteryTemperatureCelsius != nil }) {
            unavailable.insert(.batteryTemperature)
        }
        if !samples.contains(where: { $0.systemPowerWatts != nil }) {
            unavailable.insert(.systemPower)
        }
        if !samples.contains(where: { $0.batteryPowerWatts != nil }) {
            unavailable.insert(.batteryPower)
        }
        return unavailable.sorted { $0.rawValue < $1.rawValue }
    }

    private func highestMemoryPressure(
        in samples: [MonitorHistorySample]
    ) -> MonitorHistorySample.MemoryPressure? {
        samples.compactMap(\.memoryPressure).max { $0.rank < $1.rank }
    }

    private func highestThermalState(
        in samples: [MonitorHistorySample]
    ) -> MonitorHistorySample.ThermalState? {
        samples.map(\.thermalState).max { $0.rank < $1.rank }
    }

    // MARK: - Range helpers

    private func clippedRange(
        for gap: MonitorHistoryGap,
        in range: MonitorReportRange
    ) -> ClosedRange<TimeInterval>? {
        let start = max(gap.startedAt, range.start)
        let end = min(gap.endedAt ?? range.end, range.end)
        guard end > start else { return nil }
        return start.timeIntervalSince1970...end.timeIntervalSince1970
    }

    private func mergedRanges(
        _ ranges: [ClosedRange<TimeInterval>]
    ) -> [ClosedRange<TimeInterval>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var result: [ClosedRange<TimeInterval>] = []
        for range in sorted {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private func duration(of ranges: [ClosedRange<TimeInterval>]) -> TimeInterval {
        ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    private func overlap(start: Date, end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

private extension MonitorHistorySample.MemoryPressure {
    var rank: Int {
        switch self {
        case .normal: 0
        case .warning: 1
        case .critical: 2
        }
    }
}

private extension MonitorHistorySample.ThermalState {
    var rank: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }
}
