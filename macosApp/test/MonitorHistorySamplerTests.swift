import XCTest
@testable import Covio

@MainActor
final class MonitorHistorySamplerTests: XCTestCase {
    func testCadenceUsesThirtySecondsOnPowerAndSixtyOnBattery() {
        XCTAssertEqual(
            MonitorHistorySamplingPolicy.interval(for: sample(power: .ac)),
            30
        )
        XCTAssertEqual(
            MonitorHistorySamplingPolicy.interval(for: sample(power: .battery)),
            60
        )
        XCTAssertEqual(MonitorHistorySamplingPolicy.gapThreshold(for: 30), 75)
    }

    func testPowerAndThermalTransitionsAreReported() {
        XCTAssertEqual(
            MonitorHistorySamplingPolicy.eventKinds(
                previousPower: .battery,
                currentPower: .ac,
                previousThermal: .fair,
                currentThermal: .serious
            ),
            [.adapterConnected, .thermalSerious]
        )
        XCTAssertEqual(
            MonitorHistorySamplingPolicy.eventKinds(
                previousPower: .ac,
                currentPower: .battery,
                previousThermal: .critical,
                currentThermal: .nominal
            ),
            [.adapterDisconnected, .thermalNominal]
        )
    }

    func testClockChangeDetectsWallClockJump() {
        let previous = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(
            MonitorHistorySamplingPolicy.clockChanged(
                previousWallTime: previous,
                previousMonotonicNanoseconds: 1_000,
                currentWallTime: previous.addingTimeInterval(3_600),
                currentMonotonicNanoseconds: 31_000_000_000
            )
        )
        XCTAssertFalse(
            MonitorHistorySamplingPolicy.clockChanged(
                previousWallTime: previous,
                previousMonotonicNanoseconds: 1_000,
                currentWallTime: previous.addingTimeInterval(30),
                currentMonotonicNanoseconds: 30_000_001_000
            )
        )
    }

    func testStartWritesBootEpochAndFirstSample() async throws {
        let fixture = makeFixture()
        fixture.sampler.start()
        defer { fixture.sampler.stop() }

        try await waitForSamples(store: fixture.store, count: 1)

        let epochs = try await fixture.store.systemEpochs()
        let events = try await fixture.store.events(
            from: fixture.context.bootStartedAt,
            to: fixture.context.bootStartedAt
        )
        XCTAssertEqual(epochs.count, 1)
        XCTAssertEqual(epochs.first?.bootID, "boot-1")
        XCTAssertEqual(events.map(\.kind), [.boot])
    }

    func testPowerAndThermalChangesMarkTheNewSampleAsEvent() async throws {
        let fixture = makeFixture()
        fixture.sampler.start()
        defer { fixture.sampler.stop() }
        try await waitForSamples(store: fixture.store, count: 1)

        await fixture.reader.set(power: .battery, thermal: .serious)
        fixture.clock.advance(seconds: 30)
        _ = await fixture.sampler.captureOnce(kind: .periodic)

        let samples = try await fixture.store.samples(
            from: fixture.context.bootStartedAt,
            to: fixture.clock.now.addingTimeInterval(1)
        )
        let events = try await fixture.store.events(
            from: fixture.context.bootStartedAt,
            to: fixture.clock.now.addingTimeInterval(1)
        )
        XCTAssertEqual(samples.last?.kind, .event)
        XCTAssertEqual(samples.last?.powerSource, .battery)
        XCTAssertEqual(
            events.map(\.kind),
            [.boot, .adapterDisconnected, .thermalSerious]
        )
    }

    func testClockJumpWritesClockChangeGap() async throws {
        let fixture = makeFixture()
        fixture.sampler.start()
        defer { fixture.sampler.stop() }
        try await waitForSamples(store: fixture.store, count: 1)

        fixture.clock.advance(wallSeconds: 3_600, monotonicSeconds: 30)
        _ = await fixture.sampler.captureOnce(kind: .periodic)

        let gaps = try await fixture.store.gaps(
            overlapping: fixture.context.bootStartedAt,
            through: fixture.clock.now.addingTimeInterval(1)
        )
        XCTAssertTrue(gaps.contains { $0.reason == .clockChange })
    }

    func testBootChangeWritesRebootGapAndBootEvent() async throws {
        let fixture = makeFixture()
        fixture.sampler.start()
        defer { fixture.sampler.stop() }
        try await waitForSamples(store: fixture.store, count: 1)

        fixture.clock.advance(seconds: 90)
        let secondContext = MonitorHistorySystemContext(
            bootID: "boot-2",
            bootStartedAt: fixture.clock.now.addingTimeInterval(-10),
            osVersion: fixture.context.osVersion,
            osBuild: fixture.context.osBuild,
            model: fixture.context.model,
            chip: fixture.context.chip,
            memoryBytes: fixture.context.memoryBytes,
            diskTotalBytes: fixture.context.diskTotalBytes
        )
        fixture.system.set(secondContext)
        _ = await fixture.sampler.captureOnce(kind: .periodic)

        let gaps = try await fixture.store.gaps(
            overlapping: fixture.context.bootStartedAt,
            through: fixture.clock.now
        )
        let events = try await fixture.store.events(
            from: fixture.context.bootStartedAt,
            to: fixture.clock.now
        )
        XCTAssertTrue(gaps.contains { $0.reason == .reboot })
        XCTAssertEqual(events.filter { $0.kind == .boot }.map(\.bootID), ["boot-1", "boot-2"])
    }

    func testSleepDarkWakeAndFullWakeAreRecorded() async throws {
        let fixture = makeFixture()
        fixture.sampler.start()
        defer { fixture.sampler.stop() }
        try await waitForSamples(store: fixture.store, count: 1)

        fixture.sleepObserver.send(.willSleep)
        try await waitForGapCount(store: fixture.store, count: 1)

        fixture.clock.advance(seconds: 600)
        fixture.sleepObserver.send(.willPowerOn)
        try await waitForEvent(store: fixture.store, kind: .darkWake)

        fixture.sleepObserver.send(.didPowerOn)
        try await waitForEvent(store: fixture.store, kind: .fullWake)
        try await waitForClosedSleepGap(store: fixture.store)

        let events = try await fixture.store.events(
            from: fixture.context.bootStartedAt,
            to: fixture.clock.now.addingTimeInterval(2)
        )
        XCTAssertTrue(events.contains { $0.kind == .sleep })
        XCTAssertTrue(events.contains { $0.kind == .darkWake })
        XCTAssertTrue(events.contains { $0.kind == .fullWake })
    }

    private func makeFixture() -> SamplerFixture {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let context = MonitorHistorySystemContext(
            bootID: "boot-1",
            bootStartedAt: base.addingTimeInterval(-3_600),
            osVersion: "27.0.1",
            osBuild: "26A434",
            model: "MacBookPro18,2",
            chip: "Apple M1 Max",
            memoryBytes: 68_719_476_736,
            diskTotalBytes: 994_662_584_320
        )
        let store = RecordingMonitorHistoryStore()
        let reader = ScriptedMonitorHistoryReader()
        let clock = TestSamplerClock(now: base, monotonicNanoseconds: 5_000_000_000)
        let system = TestSystemContext(context)
        let powerObserver = TestHistoryPowerObserver()
        let sleepObserver = TestHistorySleepObserver()
        let sampler = MonitorHistorySampler(
            store: store,
            reader: reader,
            systemProvider: { system.get() },
            clock: { clock.now },
            monotonicClock: { clock.monotonicNanoseconds },
            powerObserver: powerObserver,
            sleepObserver: sleepObserver,
            notificationCenter: NotificationCenter()
        )
        return SamplerFixture(
            sampler: sampler,
            store: store,
            reader: reader,
            clock: clock,
            context: context,
            system: system,
            sleepObserver: sleepObserver
        )
    }

    private func waitForSamples(
        store: RecordingMonitorHistoryStore,
        count: Int
    ) async throws {
        for _ in 0..<100 {
            if await store.sampleCount() >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(count) samples")
    }

    private func waitForGapCount(
        store: RecordingMonitorHistoryStore,
        count: Int
    ) async throws {
        for _ in 0..<100 {
            if await store.gapCount() >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(count) gaps")
    }

    private func waitForEvent(
        store: RecordingMonitorHistoryStore,
        kind: MonitorHistoryEvent.Kind
    ) async throws {
        for _ in 0..<100 {
            if await store.eventKinds().contains(kind) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for event \(kind.rawValue)")
    }

    private func waitForClosedSleepGap(
        store: RecordingMonitorHistoryStore
    ) async throws {
        for _ in 0..<150 {
            if await store.hasClosedGap(reason: .sleep) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for a closed sleep gap")
    }

    private func sample(
        power: MonitorHistorySample.PowerSource
    ) -> MonitorHistorySample {
        MonitorHistorySample(
            sampledAt: Date(timeIntervalSince1970: 1_800_000_000),
            monotonicNanoseconds: 1,
            bootID: "boot-1",
            powerSource: power
        )
    }
}

@MainActor
private struct SamplerFixture {
    let sampler: MonitorHistorySampler
    let store: RecordingMonitorHistoryStore
    let reader: ScriptedMonitorHistoryReader
    let clock: TestSamplerClock
    let context: MonitorHistorySystemContext
    let system: TestSystemContext
    let sleepObserver: TestHistorySleepObserver
}

private final class TestSamplerClock: @unchecked Sendable {
    private let lock = NSLock()
    private var wallTime: Date
    private var monotonic: UInt64

    init(now: Date, monotonicNanoseconds: UInt64) {
        wallTime = now
        monotonic = monotonicNanoseconds
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return wallTime
    }

    var monotonicNanoseconds: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return monotonic
    }

    func advance(seconds: TimeInterval) {
        advance(wallSeconds: seconds, monotonicSeconds: seconds)
    }

    func advance(wallSeconds: TimeInterval, monotonicSeconds: TimeInterval) {
        lock.lock()
        wallTime = wallTime.addingTimeInterval(wallSeconds)
        monotonic += UInt64(max(0, monotonicSeconds) * 1_000_000_000)
        lock.unlock()
    }
}

private final class TestSystemContext: @unchecked Sendable {
    private let lock = NSLock()
    private var context: MonitorHistorySystemContext

    init(_ context: MonitorHistorySystemContext) {
        self.context = context
    }

    func get() -> MonitorHistorySystemContext {
        lock.lock()
        defer { lock.unlock() }
        return context
    }

    func set(_ context: MonitorHistorySystemContext) {
        lock.lock()
        self.context = context
        lock.unlock()
    }
}

private actor ScriptedMonitorHistoryReader: MonitorHistoryReading {
    private var power: MonitorHistorySample.PowerSource = .ac
    private var thermal: MonitorHistorySample.ThermalState = .nominal

    func set(
        power: MonitorHistorySample.PowerSource,
        thermal: MonitorHistorySample.ThermalState
    ) {
        self.power = power
        self.thermal = thermal
    }

    func read(
        at date: Date,
        monotonicNanoseconds: UInt64,
        bootID: String,
        kind: MonitorHistorySample.Kind
    ) -> MonitorHistorySample {
        MonitorHistorySample(
            sampledAt: date,
            monotonicNanoseconds: monotonicNanoseconds,
            bootID: bootID,
            powerSource: power,
            thermalState: thermal,
            cpuUsage: 0.5,
            cpuLoad1: 2,
            cpuCoreCount: 10,
            memoryUsedBytes: 20,
            memoryTotalBytes: 40,
            memoryPressure: .normal,
            diskReadBytesPerSecond: 1,
            diskWriteBytesPerSecond: 2,
            diskUsedBytes: 10,
            diskFreeBytes: 20,
            networkReceiveBytesPerSecond: 3,
            networkTransmitBytesPerSecond: 4,
            batteryPercent: power == .battery ? 70 : 80,
            displayState: .on,
            lidState: .open,
            kind: kind,
            quality: .complete
        )
    }
}

private final class TestHistoryPowerObserver: MonitorHistoryPowerObserving, @unchecked Sendable {
    func start(_ callback: @escaping @Sendable () -> Void) {}
    func stop() {}
}

private final class TestHistorySleepObserver: MonitorHistorySleepObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (
        MonitorHistorySleepSignal,
        @escaping @Sendable () -> Void
    ) -> Void)?

    func start(
        _ callback: @escaping @Sendable (
            MonitorHistorySleepSignal,
            @escaping @Sendable () -> Void
        ) -> Void
    ) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func stop() {
        lock.lock()
        callback = nil
        lock.unlock()
    }

    func send(_ signal: MonitorHistorySleepSignal) {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        callback?(signal) {}
    }
}

private actor RecordingMonitorHistoryStore: MonitorHistoryStoring {
    private var recordedSamples: [MonitorHistorySample] = []
    private var recordedEvents: [MonitorHistoryEvent] = []
    private var recordedGaps: [MonitorHistoryGap] = []
    private var recordedEpochs: [MonitorSystemEpoch] = []

    func insert(samples: [MonitorHistorySample]) {
        recordedSamples.append(contentsOf: samples)
        recordedSamples.sort { $0.sampledAt < $1.sampledAt }
    }

    func insert(event: MonitorHistoryEvent) {
        recordedEvents.append(event)
    }

    func insert(gap: MonitorHistoryGap) {
        recordedGaps.append(gap)
    }

    func upsert(systemEpoch: MonitorSystemEpoch) {
        recordedEpochs.removeAll { $0.bootID == systemEpoch.bootID }
        recordedEpochs.append(systemEpoch)
    }

    func closeOpenGap(bootID: String, endedAt: Date) {
        recordedGaps = recordedGaps.map { gap in
            guard gap.bootID == bootID, gap.endedAt == nil else { return gap }
            return MonitorHistoryGap(
                startedAt: gap.startedAt,
                endedAt: endedAt,
                bootID: gap.bootID,
                reason: gap.reason
            )
        }
    }

    func samples(from start: Date, to end: Date) -> [MonitorHistorySample] {
        recordedSamples.filter { $0.sampledAt >= start && $0.sampledAt <= end }
    }

    func events(from start: Date, to end: Date) -> [MonitorHistoryEvent] {
        recordedEvents.filter { $0.occurredAt >= start && $0.occurredAt <= end }
    }

    func gaps(overlapping start: Date, through end: Date) -> [MonitorHistoryGap] {
        recordedGaps.filter {
            $0.startedAt <= end && ($0.endedAt == nil || $0.endedAt! >= start)
        }
    }

    func systemEpochs() -> [MonitorSystemEpoch] {
        recordedEpochs
    }

    func latestSampleDate() -> Date? {
        recordedSamples.last?.sampledAt
    }

    func sampleCount() -> Int {
        recordedSamples.count
    }

    func prune(now: Date) {}

    func deleteAll() {
        recordedSamples.removeAll()
        recordedEvents.removeAll()
        recordedGaps.removeAll()
        recordedEpochs.removeAll()
    }

    func gapCount() -> Int {
        recordedGaps.count
    }

    func eventKinds() -> [MonitorHistoryEvent.Kind] {
        recordedEvents.map(\.kind)
    }

    func hasClosedGap(reason: MonitorHistoryGap.Reason) -> Bool {
        recordedGaps.contains { $0.reason == reason && $0.endedAt != nil }
    }
}
