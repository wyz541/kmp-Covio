import AppKit
import Darwin
import Dispatch
import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.ps

@MainActor
protocol MonitorHistorySampling: AnyObject {
    func start()
    func stop()
}

struct MonitorHistorySystemContext: Equatable, Sendable {
    let bootID: String
    let bootStartedAt: Date
    let osVersion: String
    let osBuild: String
    let model: String
    let chip: String
    let memoryBytes: UInt64
    let diskTotalBytes: UInt64
}

enum MonitorHistorySystemInfo {
    static func current() -> MonitorHistorySystemContext {
        let boot = readBootTime()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = [
            version.majorVersion,
            version.minorVersion,
            version.patchVersion,
        ].map(String.init).joined(separator: ".")
        let diskBytes = (try? FileManager.default.attributesOfFileSystem(forPath: "/"))?[.systemSize]
            as? NSNumber
        return MonitorHistorySystemContext(
            bootID: "boot-\(boot.seconds)-\(boot.microseconds)",
            bootStartedAt: Date(
                timeIntervalSince1970: Double(boot.seconds) + Double(boot.microseconds) / 1_000_000
            ),
            osVersion: osVersion,
            osBuild: readStringSysctl("kern.osversion") ?? "",
            model: readStringSysctl("hw.model") ?? "",
            chip: readStringSysctl("machdep.cpu.brand_string") ?? "",
            memoryBytes: readUInt64Sysctl("hw.memsize") ?? 0,
            diskTotalBytes: diskBytes?.uint64Value ?? 0
        )
    }

    static func epoch(from context: MonitorHistorySystemContext) -> MonitorSystemEpoch {
        MonitorSystemEpoch(
            bootID: context.bootID,
            startedAt: context.bootStartedAt,
            osVersion: context.osVersion,
            osBuild: context.osBuild,
            model: context.model,
            chip: context.chip,
            memoryBytes: context.memoryBytes,
            diskTotalBytes: context.diskTotalBytes
        )
    }

    private static func readBootTime() -> (seconds: Int64, microseconds: Int64) {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (Int64(value.tv_sec), Int64(value.tv_usec))
    }

    private static func readStringSysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func readUInt64Sysctl(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

protocol MonitorHistoryReading: Sendable {
    func read(
        at date: Date,
        monotonicNanoseconds: UInt64,
        bootID: String,
        kind: MonitorHistorySample.Kind
    ) async -> MonitorHistorySample
}

actor MonitorHistoryCaptureReader: MonitorHistoryReading {
    private let reader = MacMonitorReader()

    func read(
        at date: Date,
        monotonicNanoseconds: UInt64,
        bootID: String,
        kind: MonitorHistorySample.Kind
    ) -> MonitorHistorySample {
        reader.readHistory(
            at: date,
            monotonicNanoseconds: monotonicNanoseconds,
            bootID: bootID,
            kind: kind
        )
    }
}

enum MonitorHistorySamplingPolicy {
    static let pluggedInInterval: TimeInterval = 30
    static let batteryInterval: TimeInterval = 60

    static func interval(for sample: MonitorHistorySample) -> TimeInterval {
        sample.powerSource == .battery ? batteryInterval : pluggedInInterval
    }

    static func gapThreshold(for interval: TimeInterval) -> TimeInterval {
        max(interval * 2.5, 5)
    }

    static func clockChanged(
        previousWallTime: Date,
        previousMonotonicNanoseconds: UInt64,
        currentWallTime: Date,
        currentMonotonicNanoseconds: UInt64,
        tolerance: TimeInterval = 5
    ) -> Bool {
        let wallDelta = currentWallTime.timeIntervalSince(previousWallTime)
        guard currentMonotonicNanoseconds >= previousMonotonicNanoseconds else {
            return true
        }
        let monotonicDelta = Double(
            currentMonotonicNanoseconds - previousMonotonicNanoseconds
        ) / 1_000_000_000
        return wallDelta < 0 || abs(wallDelta - monotonicDelta) > tolerance
    }

    static func eventKinds(
        previousPower: MonitorHistorySample.PowerSource?,
        currentPower: MonitorHistorySample.PowerSource,
        previousThermal: MonitorHistorySample.ThermalState?,
        currentThermal: MonitorHistorySample.ThermalState
    ) -> [MonitorHistoryEvent.Kind] {
        var values: [MonitorHistoryEvent.Kind] = []
        if previousPower == .battery, currentPower == .ac {
            values.append(.adapterConnected)
        } else if previousPower == .ac, currentPower == .battery {
            values.append(.adapterDisconnected)
        }

        if let previousThermal, previousThermal != currentThermal {
            switch currentThermal {
            case .nominal: values.append(.thermalNominal)
            case .fair: values.append(.thermalFair)
            case .serious: values.append(.thermalSerious)
            case .critical: values.append(.thermalCritical)
            }
        }
        return values
    }
}

enum MonitorHistorySleepSignal: Equatable, Sendable {
    case willSleep
    case willPowerOn
    case didPowerOn
}

protocol MonitorHistoryPowerObserving: AnyObject {
    func start(_ callback: @escaping @Sendable () -> Void)
    func stop()
}

protocol MonitorHistorySleepObserving: AnyObject {
    func start(
        _ callback: @escaping @Sendable (
            MonitorHistorySleepSignal,
            @escaping @Sendable () -> Void
        ) -> Void
    )
    func stop()
}

/// 独立的电源事件监听器。它不改系统状态。
final class MonitorHistoryPowerObserver: MonitorHistoryPowerObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var stopped = false

    func start(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        self.callback = callback
        stopped = false
        lock.unlock()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let observer = Unmanaged<MonitorHistoryPowerObserver>
                .fromOpaque(context)
                .takeUnretainedValue()
            observer.publish()
        }, context)?.takeRetainedValue() else {
            return
        }

        lock.lock()
        self.source = source
        lock.unlock()

        let thread = Thread { [weak self] in
            guard let self, let source = self.sourceIfRunning else { return }
            let loop = CFRunLoopGetCurrent()
            self.lock.lock()
            self.runLoop = loop
            self.lock.unlock()
            CFRunLoopAddSource(loop, source, .defaultMode)
            CFRunLoopRun()
        }
        thread.name = "Covio-monitor-power-events"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    func stop() {
        lock.lock()
        stopped = true
        callback = nil
        let runLoop = self.runLoop
        let source = self.source
        self.runLoop = nil
        self.source = nil
        lock.unlock()

        if let runLoop { CFRunLoopStop(runLoop) }
        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        }
    }

    private var sourceIfRunning: CFRunLoopSource? {
        lock.lock()
        defer { lock.unlock() }
        return stopped ? nil : source
    }

    private func publish() {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        callback?()
    }
}

/// 监听睡眠和唤醒的 IOKit 事件。
///
/// 收到 `willSleep` 后必须立即放行，否则系统会等到超时。
final class MonitorHistorySleepObserver: MonitorHistorySleepObserving, @unchecked Sendable {
    private static let willSleep = UInt32(0xe000_0280)
    private static let willPowerOn = UInt32(0xe000_0320)
    private static let didPowerOn = UInt32(0xe000_0300)

    private let lock = NSLock()
    private var callback: (@Sendable (
        MonitorHistorySleepSignal,
        @escaping @Sendable () -> Void
    ) -> Void)?
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notificationPort: IONotificationPortRef?
    private var runLoop: CFRunLoop?
    private var stopped = false

    func start(
        _ callback: @escaping @Sendable (
            MonitorHistorySleepSignal,
            @escaping @Sendable () -> Void
        ) -> Void
    ) {
        lock.lock()
        self.callback = callback
        stopped = false
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.runEventLoop()
        }
        thread.name = "Covio-monitor-sleep-events"
        thread.qualityOfService = .utility
        thread.start()
    }

    func stop() {
        lock.lock()
        stopped = true
        callback = nil
        let runLoop = self.runLoop
        let port = rootPort
        let notifier = self.notifier
        let notificationPort = self.notificationPort
        rootPort = 0
        self.notifier = 0
        self.notificationPort = nil
        self.runLoop = nil
        lock.unlock()

        if let runLoop { CFRunLoopStop(runLoop) }
        if port != 0 {
            var handle = notifier
            IODeregisterForSystemPower(&handle)
            if let notificationPort { IONotificationPortDestroy(notificationPort) }
            IOServiceClose(port)
        }
    }

    private func runEventLoop() {
        var port: IONotificationPortRef?
        var notifier: io_object_t = 0
        let context = Unmanaged.passUnretained(self).toOpaque()
        let connection = IORegisterForSystemPower(
            context,
            &port,
            { context, _, messageType, argument in
                guard let context else { return }
                let observer = Unmanaged<MonitorHistorySleepObserver>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                observer.handle(messageType: messageType, argument: argument)
            },
            &notifier
        )
        guard connection != 0,
              let port,
              let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
        else { return }

        lock.lock()
        rootPort = connection
        self.notifier = notifier
        notificationPort = port
        let stopped = self.stopped
        lock.unlock()
        guard !stopped else {
            var handle = notifier
            IODeregisterForSystemPower(&handle)
            IONotificationPortDestroy(port)
            IOServiceClose(connection)
            return
        }

        let loop = CFRunLoopGetCurrent()
        lock.lock()
        runLoop = loop
        lock.unlock()
        CFRunLoopAddSource(loop, source, .defaultMode)
        CFRunLoopRun()
    }

    private func handle(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case Self.willSleep:
            let gate = DispatchSemaphore(value: 0)
            publish(.willSleep) { gate.signal() }
            _ = gate.wait(timeout: .now() + 1)
            let port = rootPort
            if port != 0, let argument {
                IOAllowPowerChange(port, Int(bitPattern: argument))
            }
        case Self.willPowerOn:
            publish(.willPowerOn) {}
        case Self.didPowerOn:
            publish(.didPowerOn) {}
        default:
            break
        }
    }

    private func publish(
        _ signal: MonitorHistorySleepSignal,
        completion: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        if let callback {
            callback(signal, completion)
        } else {
            completion()
        }
    }
}

@MainActor
final class MonitorHistorySampler: MonitorHistorySampling {
    private let store: any MonitorHistoryStoring
    private let reader: any MonitorHistoryReading
    private let systemProvider: @Sendable () -> MonitorHistorySystemContext
    private let clock: @Sendable () -> Date
    private let monotonicClock: @Sendable () -> UInt64
    private let powerObserver: (any MonitorHistoryPowerObserving)?
    private let sleepObserver: (any MonitorHistorySleepObserving)?
    private let notificationCenter: NotificationCenter

    private var loopTask: Task<Void, Never>?
    private var immediateTask: Task<Void, Never>?
    private var thermalObserver: NSObjectProtocol?
    private var systemContext: MonitorHistorySystemContext?
    private var previousSample: MonitorHistorySample?
    private var previousPower: MonitorHistorySample.PowerSource?
    private var previousThermal: MonitorHistorySample.ThermalState?
    private var started = false
    private var sleeping = false
    private var suppressNextUnknownGap = false

    init(
        store: any MonitorHistoryStoring,
        reader: any MonitorHistoryReading = MonitorHistoryCaptureReader(),
        systemProvider: @escaping @Sendable () -> MonitorHistorySystemContext = {
            MonitorHistorySystemInfo.current()
        },
        clock: @escaping @Sendable () -> Date = { Date() },
        monotonicClock: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        powerObserver: (any MonitorHistoryPowerObserving)? = MonitorHistoryPowerObserver(),
        sleepObserver: (any MonitorHistorySleepObserving)? = MonitorHistorySleepObserver(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.reader = reader
        self.systemProvider = systemProvider
        self.clock = clock
        self.monotonicClock = monotonicClock
        self.powerObserver = powerObserver
        self.sleepObserver = sleepObserver
        self.notificationCenter = notificationCenter
    }

    func start() {
        guard !started else { return }
        started = true
        sleeping = false
        powerObserver?.start { [weak self] in
            Task { @MainActor in self?.requestImmediateSample(kind: .event) }
        }
        sleepObserver?.start { [weak self] signal, completion in
            Task { @MainActor in
                await self?.handleSleepSignal(signal)
                completion()
            }
        }
        thermalObserver = notificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.requestImmediateSample(kind: .event) }
        }
        Task { await bootstrap() }
    }

    func stop() {
        guard started else { return }
        started = false
        sleeping = false
        loopTask?.cancel()
        loopTask = nil
        immediateTask?.cancel()
        immediateTask = nil
        powerObserver?.stop()
        sleepObserver?.stop()
        if let thermalObserver {
            notificationCenter.removeObserver(thermalObserver)
        }
        thermalObserver = nil
    }

    /// 测试和事件路径共用的一次采样。
    @discardableResult
    func captureOnce(kind: MonitorHistorySample.Kind) async -> TimeInterval {
        guard started, !sleeping else {
            return MonitorHistorySamplingPolicy.pluggedInInterval
        }
        let now = clock()
        let monotonic = monotonicClock()
        let context = systemProvider()

        if systemContext?.bootID != context.bootID {
            if let previousSample, previousSample.bootID != context.bootID {
                try? await store.insert(
                    gap: MonitorHistoryGap(
                        startedAt: previousSample.sampledAt,
                        endedAt: context.bootStartedAt,
                        bootID: previousSample.bootID,
                        reason: .reboot
                    )
                )
            }
            systemContext = context
            try? await store.upsert(systemEpoch: MonitorHistorySystemInfo.epoch(from: context))
            try? await store.insert(
                event: MonitorHistoryEvent(
                    occurredAt: context.bootStartedAt,
                    bootID: context.bootID,
                    kind: .boot
                )
            )
        }

        var sample = await reader.read(
            at: now,
            monotonicNanoseconds: monotonic,
            bootID: context.bootID,
            kind: kind
        )

        if let previous = previousSample {
            if MonitorHistorySamplingPolicy.clockChanged(
                previousWallTime: previous.sampledAt,
                previousMonotonicNanoseconds: previous.monotonicNanoseconds,
                currentWallTime: now,
                currentMonotonicNanoseconds: monotonic
            ) {
                try? await store.insert(
                    gap: MonitorHistoryGap(
                        startedAt: previous.sampledAt,
                        endedAt: now,
                        bootID: context.bootID,
                        reason: .clockChange
                    )
                )
                suppressNextUnknownGap = true
            } else if !suppressNextUnknownGap {
                let expected = MonitorHistorySamplingPolicy.interval(for: previous)
                let elapsed = now.timeIntervalSince(previous.sampledAt)
                if elapsed > MonitorHistorySamplingPolicy.gapThreshold(for: expected) {
                    try? await store.insert(
                        gap: MonitorHistoryGap(
                            startedAt: previous.sampledAt.addingTimeInterval(expected),
                            endedAt: now,
                            bootID: context.bootID,
                            reason: .unknown
                        )
                    )
                }
            }
        }
        suppressNextUnknownGap = false

        let events = MonitorHistorySamplingPolicy.eventKinds(
            previousPower: previousPower,
            currentPower: sample.powerSource,
            previousThermal: previousThermal,
            currentThermal: sample.thermalState
        )
        if !events.isEmpty {
            sample = sample.replacingKind(.event)
        }

        try? await store.insert(samples: [sample])
        for eventKind in events {
            try? await store.insert(
                event: MonitorHistoryEvent(
                    occurredAt: now,
                    bootID: context.bootID,
                    kind: eventKind
                )
            )
        }

        previousSample = sample
        previousPower = sample.powerSource
        previousThermal = sample.thermalState
        return MonitorHistorySamplingPolicy.interval(for: sample)
    }

    private func bootstrap() async {
        guard started else { return }
        let context = systemProvider()
        systemContext = context
        try? await store.upsert(systemEpoch: MonitorHistorySystemInfo.epoch(from: context))
        try? await store.insert(
            event: MonitorHistoryEvent(
                occurredAt: context.bootStartedAt,
                bootID: context.bootID,
                kind: .boot
            )
        )

        let latest = try? await store.latestSampleDate()
        if let latest, latest < context.bootStartedAt {
            try? await store.insert(
                gap: MonitorHistoryGap(
                    startedAt: latest,
                    endedAt: context.bootStartedAt,
                    bootID: context.bootID,
                    reason: .reboot
                )
            )
        } else if let latest {
            let now = clock()
            let expected = MonitorHistorySamplingPolicy.pluggedInInterval
            if now.timeIntervalSince(latest) > MonitorHistorySamplingPolicy.gapThreshold(for: expected) {
                try? await store.insert(
                    gap: MonitorHistoryGap(
                        startedAt: latest.addingTimeInterval(expected),
                        endedAt: now,
                        bootID: context.bootID,
                        reason: .appStopped
                    )
                )
            }
        }

        let interval = await captureOnce(kind: .periodic)
        guard started, !sleeping else { return }
        startLoop(after: interval)
    }

    private func startLoop(after initialInterval: TimeInterval) {
        loopTask?.cancel()
        let initial = max(1, initialInterval)
        loopTask = Task { [weak self] in
            var delay = initial
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard let self, self.started, !self.sleeping else { return }
                delay = await self.captureOnce(kind: .periodic)
            }
        }
    }

    private func requestImmediateSample(kind: MonitorHistorySample.Kind) {
        guard started, !sleeping else { return }
        immediateTask?.cancel()
        loopTask?.cancel()
        immediateTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard let self, self.started, !self.sleeping else { return }
            let interval = await self.captureOnce(kind: kind)
            guard self.started, !self.sleeping else { return }
            self.startLoop(after: interval)
        }
    }

    private func handleSleepSignal(_ signal: MonitorHistorySleepSignal) async {
        guard started else { return }
        switch signal {
        case .willSleep:
            sleeping = true
            loopTask?.cancel()
            loopTask = nil
            immediateTask?.cancel()
            immediateTask = nil
            let now = clock()
            let context = systemProvider()
            try? await store.closeOpenGap(bootID: context.bootID, endedAt: now)
            try? await store.insert(
                event: MonitorHistoryEvent(
                    occurredAt: now,
                    bootID: context.bootID,
                    kind: .sleep
                )
            )
            try? await store.insert(
                gap: MonitorHistoryGap(
                    startedAt: now,
                    endedAt: nil,
                    bootID: context.bootID,
                    reason: .sleep
                )
            )
            suppressNextUnknownGap = true
        case .willPowerOn:
            let now = clock()
            let context = systemProvider()
            try? await store.insert(
                event: MonitorHistoryEvent(
                    occurredAt: now,
                    bootID: context.bootID,
                    kind: .darkWake
                )
            )
        case .didPowerOn:
            sleeping = false
            suppressNextUnknownGap = true
            let now = clock()
            let context = systemProvider()
            try? await store.closeOpenGap(bootID: context.bootID, endedAt: now)
            try? await store.insert(
                event: MonitorHistoryEvent(
                    occurredAt: now,
                    bootID: context.bootID,
                    kind: .fullWake
                )
            )
            requestImmediateSample(kind: .wake)
        }
    }
}
