package com.wyz.covio.core

import com.wyz.covio.domain.EngineDefaults
import com.wyz.covio.domain.EngineLock

class Engine(
    initialConfig: AppConfig,
    private val power: PowerSource,
    private val lid: LidSensor,
    private val idle: IdleSensor,
    private val sleepController: SleepController,
    private val sleepWatcher: SleepWatcher,
    private val privileged: PrivilegedOps,
    private val logger: AppLogger,
    private val wakeLogReader: WakeLogReader = WakeLogReader { null },
    private val clock: () -> Long = { EngineDefaults.nowMillis() },
    private val stateListener: StateListener = StateListener {},
    private val wakeScanExecutor: (() -> Unit) -> Unit = { runnable -> EngineDefaults.wakeScanExecutor(runnable) },
    private val wakeDelay: (Long) -> Unit = { millis -> EngineDefaults.blockingDelay(millis) },
    private val wakeRetryDelayMillis: Long = 1_000L,
    private val wakeRetryCount: Int = 3,
    private val wakeCacheNowMillis: () -> Long = { EngineDefaults.nowMillis() },
) {
    /*
     * 所有可变字段都由这把锁保护。JVM 上是 synchronized，macosArm64 上是
     * 递归的 pthread 互斥量：reconcilePolicy 会嵌套调用 setLidSleepAvailable，
     * 所以锁必须可重入。
     */
    private val lock = EngineLock()
    private var restoreInProgress = false
    private var reconcileInProgress = false

    private var config = initialConfig.normalized()
    private var state = AppState(enabled = config.enabled)
    private var started = false
    private var previousPowerState: PowerState? = null
    private var idleCancelAtMillis: Long? = null
    private var lidCancelAtMillis: Long? = null
    private var restoreAfterSleep: RestorePoint? = null
    private var manualLidHold = false
    private var powerLidHold = false
    private var lowBatterySleepLatched = false
    private var lastWakeEvent: WakeEvent? = null
    private var wakeScanScheduled = false
    private var cachedWakeLog: WakeLogCache? = null
    private var lastLidLeaseStatusAtMillis: Long? = null
    private val holdLeases = HoldLeaseManager(sleepController, clock)

    val currentState: AppState get() = lock.withLock { state }
    val currentConfig: AppConfig get() = lock.withLock { config }

    fun start() {
        val alreadyStarted = lock.withLock {
            if (started) {
                true
            } else {
                started = true
                false
            }
        }
        if (alreadyStarted) return
        power.subscribe(::onPowerChanged)
        lid.subscribe(::onLidChanged)
        sleepWatcher.subscribe(::onSleepEvent)

        val initialLid = runCatching { lid.read() }.getOrDefault(LidState.UNKNOWN)
        val initialBattery = runCatching { power.read() }.getOrNull()
        val helperStatus = runCatching { privileged.status() }.getOrDefault(HelperStatus.ERROR)
        lock.withLock {
            state = state.copy(
                lid = initialLid,
                battery = initialBattery,
                helperStatus = helperStatus,
            )
        }
        syncIdleState(holdLeases.refresh())
        startInitialWakeScan()
        reconcilePolicy(clearStaleLidFlag = true)
        publish()
    }

    fun stop() {
        val wasStarted = lock.withLock {
            if (!started) {
                false
            } else {
                started = false
                idleCancelAtMillis = null
                lidCancelAtMillis = null
                restoreAfterSleep = null
                manualLidHold = false
                powerLidHold = false
                lowBatterySleepLatched = false
                wakeScanScheduled = false
                state = state.copy(darkWake = state.darkWake.copy(scanning = false))
                true
            }
        }
        if (!wasStarted) return
        syncIdleState(holdLeases.clear())
        if (!currentState.lidSleepAvailable || runCatching { privileged.isInstalled() }.getOrDefault(false)) {
            runCatching { privileged.setDisableSleep(false) }
                .onFailure { logger.warn("Cannot clear disablesleep on stop", it) }
        }
        runCatching { power.stop() }
        runCatching { lid.stop() }
        runCatching { sleepWatcher.stop() }
        lock.withLock {
            state = state.copy(
                lidSleepAvailable = true,
                idleCancelRemainingSeconds = null,
                lidCancelRemainingSeconds = null,
            )
        }
        publish()
    }

    fun updateConfig(newConfig: AppConfig): Boolean {
        val normalized = newConfig.normalized()
        val applied = lock.withLock {
            val previous = config
            val outcome = ConfigChange(
                previous = previous,
                enabledChanged = config.enabled != normalized.enabled,
                darkWakeChanged = config.darkWakeAwarenessEnabled != normalized.darkWakeAwarenessEnabled,
            )
            config = normalized
            state = state.copy(enabled = normalized.enabled)
            outcome
        }
        val success = if (applied.enabledChanged) {
            setEnabled(normalized.enabled)
        } else {
            if (applied.darkWakeChanged) {
                if (normalized.darkWakeAwarenessEnabled) {
                    startInitialWakeScan()
                } else {
                    lock.withLock { state = state.copy(darkWake = state.darkWake.copy(scanning = false)) }
                    publish()
                }
            }
            reconcilePolicy()
        }
        if (!success) {
            lock.withLock {
                config = applied.previous
                state = state.copy(enabled = applied.previous.enabled)
            }
        }
        publish()
        return success
    }

    fun tick(nowMillis: Long = clock()) {
        val deadlines = lock.withLock { Deadlines(idleCancelAtMillis, lidCancelAtMillis) }
        val idleDeadline = deadlines.idle
        val lidDeadline = deadlines.lid
        val idleSnapshot = if (idleDeadline != null && idleDeadline <= nowMillis) {
            lock.withLock { idleCancelAtMillis = null }
            holdLeases.cancel(IDLE_TIMER_LEASE_ID)
        } else {
            holdLeases.tick(nowMillis)
        }
        syncIdleState(idleSnapshot)
        if (idleDeadline != null && idleDeadline > nowMillis) {
            updateCountdowns(nowMillis)
        }
        if (lidDeadline != null) {
            val remaining = lidDeadline - nowMillis
            if (remaining <= 0L) {
                lock.withLock { lidCancelAtMillis = null }
                reconcilePolicy()
            } else {
                updateCountdowns(nowMillis)
            }
        }

        val leaseStatusChanged = refreshLidLeaseStatusIfDue(nowMillis)
        if (leaseStatusChanged && currentState.enabled) {
            reconcilePolicy()
        }

        val snapshot = currentState
        if (snapshot.enabled && !snapshot.lidSleepAvailable && snapshot.idleSleepAvailable) {
            val timeout = sleepController.systemIdleSleepTimeoutSeconds()
            if (timeout != null && timeout > 0L && idle.idleSeconds() >= timeout) {
                logger.info("Idle timeout reached while lid sleep is prevented; sleeping manually.")
                requestSleep(restoreAfterWake = true)
            }
        }
    }

    fun setEnabled(enabled: Boolean): Boolean {
        val alreadyApplied = lock.withLock {
            if (config.enabled == enabled && state.enabled == enabled) {
                true
            } else {
                config = config.copy(enabled = enabled)
                state = state.copy(enabled = enabled)
                if (!enabled) {
                    idleCancelAtMillis = null
                    lidCancelAtMillis = null
                    manualLidHold = false
                    powerLidHold = false
                    lowBatterySleepLatched = false
                }
                false
            }
        }
        if (alreadyApplied) return true
        val success = if (!enabled) {
            syncIdleState(holdLeases.clear())
            val idleSuccess = currentState.lastError == null
            idleSuccess && applyDesiredLidHold(forceClear = true).success
        } else {
            reconcilePolicy()
        }
        publish()
        return success
    }

    /**
     * 兼容旧设置页。关闭时结束手动和定时空闲租约。
     *
     * 自动规则由配置控制，本方法不改自动规则。
     */
    fun setIdleSleepAvailable(available: Boolean) {
        setIdleSleepPrevention(if (available) IdleSleepPrevention.NONE else IdleSleepPrevention.SYSTEM)
    }

    /**
     * 设置手动空闲保持等级。
     *
     * [IdleSleepPrevention.NONE] 同时结束手动租约和定时租约。
     * 自动规则租约不受影响。
     */
    fun setIdleSleepPrevention(prevention: IdleSleepPrevention): Boolean {
        if (prevention == IdleSleepPrevention.UNKNOWN) return false
        val snapshot = when (prevention) {
            IdleSleepPrevention.NONE -> {
                lock.withLock { idleCancelAtMillis = null }
                holdLeases.cancelSources(listOf(HoldLeaseSource.MANUAL, HoldLeaseSource.TIMER))
            }
            IdleSleepPrevention.SYSTEM, IdleSleepPrevention.SYSTEM_AND_DISPLAY -> {
                holdLeases.upsert(
                    HoldLease(
                        id = IDLE_MANUAL_LEASE_ID,
                        level = if (prevention == IdleSleepPrevention.SYSTEM) {
                            HoldLeaseLevel.SYSTEM
                        } else {
                            HoldLeaseLevel.SYSTEM_AND_DISPLAY
                        },
                        source = HoldLeaseSource.MANUAL,
                        reason = "Manual idle hold",
                        createdAtEpochSeconds = clock() / 1_000L,
                    ),
                )
            }
            IdleSleepPrevention.UNKNOWN -> return false
        }
        syncIdleState(snapshot)
        snapshot.lastError?.let { logger.warn("Cannot update idle sleep assertion: $it") }
        publish()
        return snapshot.lastError == null
    }

    fun setLidSleepAvailable(available: Boolean): Boolean {
        logger.info("Set lid sleep available=$available")
        val helperInstalled = runCatching { privileged.isInstalled() }.getOrDefault(false)
        val success = if (available && !helperInstalled) {
            true
        } else {
            runCatching { privileged.setDisableSleep(!available) }
                .onFailure { logger.warn("Cannot update disablesleep", it) }
                .getOrDefault(false)
        }
        lock.withLock {
            if (success) {
                state = state.copy(
                    lidSleepAvailable = available,
                    lidCancelRemainingSeconds = if (available) null else state.lidCancelRemainingSeconds,
                )
                if (available) lidCancelAtMillis = null
            }
        }
        if (success) refreshLidLeaseStatus()
        publish()
        return success
    }

    /**
     * 替换 Power 策略产生的空闲租约。
     *
     * 该通道与旧设置页的手动、定时和自动规则分开。
     */
    fun replacePowerLeases(leases: List<HoldLease>): Boolean {
        val snapshot = holdLeases.replaceSource(HoldLeaseSource.AGENT, leases)
        syncIdleState(snapshot)
        snapshot.lastError?.let { logger.warn("Cannot apply power policy leases: $it") }
        publish()
        return snapshot.lastError == null
    }

    /**
     * 合并 Power 策略的合盖保持需求。
     *
     * 旧设置页的手动合盖保持仍独立生效。
     */
    fun setPowerLidHold(required: Boolean): Boolean {
        lock.withLock { powerLidHold = required }
        val result = applyDesiredLidHold()
        if (result.released && currentState.lid == LidState.CLOSED && currentConfig.lidSleepImmediateOnClose) {
            requestSleep(restoreAfterWake = true)
        }
        publish()
        return result.success
    }

    fun setManualLidSleepAvailable(available: Boolean) {
        lock.withLock { manualLidHold = !available }
        val released = applyDesiredLidHold().released
        if (released && currentState.lid == LidState.CLOSED && currentConfig.lidSleepImmediateOnClose) {
            requestSleep(restoreAfterWake = true)
        }
        publish()
    }

    fun scheduleCancelIdle(afterSeconds: Long) {
        require(afterSeconds > 0L) { "afterSeconds must be positive" }
        val startedAtMillis = clock()
        val deadlineMillis = startedAtMillis + afterSeconds * 1_000L
        val expiresAtEpochSeconds = (deadlineMillis + 999L) / 1_000L
        val snapshot = holdLeases.upsert(
            HoldLease(
                id = IDLE_TIMER_LEASE_ID,
                level = HoldLeaseLevel.SYSTEM,
                source = HoldLeaseSource.TIMER,
                reason = "Timed idle hold",
                createdAtEpochSeconds = startedAtMillis / 1_000L,
                expiresAtEpochSeconds = expiresAtEpochSeconds,
            ),
        )
        lock.withLock { idleCancelAtMillis = deadlineMillis }
        syncIdleState(snapshot)
        snapshot.lastError?.let { logger.warn("Cannot start idle timer: $it") }
        updateCountdowns(startedAtMillis)
        publish()
    }

    fun scheduleCancelLid(afterSeconds: Long) {
        require(afterSeconds > 0L) { "afterSeconds must be positive" }
        lock.withLock { lidCancelAtMillis = clock() + afterSeconds * 1_000L }
        val released = applyDesiredLidHold().released
        if (released && currentState.lid == LidState.CLOSED && currentConfig.lidSleepImmediateOnClose) {
            requestSleep(restoreAfterWake = true)
        }
        updateCountdowns(clock())
        publish()
    }

    fun sleepNow() {
        requestSleep(restoreAfterWake = true)
    }

    fun displaySleepNow() {
        runCatching { sleepController.displaySleep() }
            .onFailure { logger.error("Display sleep request failed", it) }
    }

    private fun requestSleep(restoreAfterWake: Boolean) {
        val plan = lock.withLock {
            val fixIdle = !state.idleSleepAvailable
            val fixLid = !state.lidSleepAvailable
            val shouldRestore = restoreAfterWake && (fixIdle || fixLid)
            val outcome = SleepPlan(fixIdle = fixIdle, fixLid = fixLid, shouldRestore = shouldRestore)
            restoreAfterSleep = if (shouldRestore) {
                RestorePoint(
                    restoreIdle = fixIdle,
                    restoreLid = fixLid,
                    lidDeadline = lidCancelAtMillis,
                )
            } else {
                null
            }
            outcome
        }
        if (plan.fixIdle) {
            syncIdleState(
                if (restoreAfterWake) holdLeases.suspend() else holdLeases.clear(),
            )
        }
        if (plan.fixLid) setLidSleepAvailable(true)
        runCatching { sleepController.sleep() }
            .onFailure { logger.error("Sleep request failed", it) }
        if (plan.shouldRestore) {
            EngineDefaults.scheduleAfter(2_000L) { restoreAfterSleep() }
        }
    }

    private fun reconcilePolicy(clearStaleLidFlag: Boolean = false): Boolean {
        val alreadyReconciling = lock.withLock {
            if (reconcileInProgress) {
                true
            } else {
                reconcileInProgress = true
                false
            }
        }
        if (alreadyReconciling) {
            logger.info("Policy reconciliation already in progress.")
            return false
        }
        try {
            val snapshot = currentState
            if (!snapshot.enabled) {
                syncIdleState(holdLeases.clear())
                val idleSuccess = currentState.lastError == null
                return idleSuccess && applyDesiredLidHold(forceClear = clearStaleLidFlag).success
            }
            val battery = snapshot.battery ?: readBattery() ?: run {
                return applyDesiredLidHold(forceClear = clearStaleLidFlag).success
            }
            val idleSuccess = applyChargingIdleRule(
                active = config.disableIdleSleepInCharging && battery.state.isCharging,
            )

            val lowBattery = lowBatterySleepRequired(battery)
            if (lowBattery) {
                val result = applyDesiredLidHold(forceClear = clearStaleLidFlag)
                if (!lowBatterySleepLatched) {
                    lowBatterySleepLatched = true
                    logger.info("Low battery detected: ${battery.percent}% remaining=${battery.remainingSeconds}")
                    requestSleep(restoreAfterWake = false)
                }
                return idleSuccess && result.success
            }
            lowBatterySleepLatched = false

            val result = applyDesiredLidHold(forceClear = clearStaleLidFlag)
            if (result.released && currentState.lid == LidState.CLOSED && currentConfig.lidSleepImmediateOnClose) {
                requestSleep(restoreAfterWake = true)
            }
            return idleSuccess && result.success
        } finally {
            lock.withLock { reconcileInProgress = false }
        }
    }

    private fun applyDesiredLidHold(forceClear: Boolean = false): LidHoldResult {
        val snapshot = currentState
        val desired = desiredLidHold(snapshot)
        val wasHeld = !snapshot.lidSleepAvailable
        if (desired) {
            if (wasHeld) return LidHoldResult(released = false, success = true)
            val success = setLidSleepAvailable(false)
            return LidHoldResult(released = false, success = success)
        }

        val helperInstalled = runCatching { privileged.isInstalled() }.getOrDefault(false)
        if (!wasHeld && !(forceClear && helperInstalled)) return LidHoldResult(released = false, success = true)
        if (!helperInstalled) return LidHoldResult(released = false, success = false)
        val success = setLidSleepAvailable(true)
        return LidHoldResult(released = success && wasHeld, success = success)
    }

    private fun desiredLidHold(snapshot: AppState): Boolean {
        if (!snapshot.enabled) return false
        if (restoreAfterSleep != null) return false
        if (!helperReady()) return false
        val battery = snapshot.battery
        if (battery != null && lowBatterySleepRequired(battery)) return false
        val powerPolicy = when {
            battery?.state?.isCharging == true -> config.disableLidSleepInCharging
            battery?.isDischarging == true -> config.disableLidSleepOnBattery
            else -> false
        }
        return manualLidHold || powerLidHold || lidCancelAtMillis != null || powerPolicy
    }

    private fun helperReady(): Boolean = runCatching {
        privileged.isInstalled() && privileged.status() == HelperStatus.INSTALLED
    }.getOrDefault(false)

    private fun readBattery(): BatteryStatus? = runCatching { power.read() }
        .getOrNull()
        ?.also { battery -> lock.withLock { state = state.copy(battery = battery) } }

    private fun lowBatterySleepRequired(battery: BatteryStatus): Boolean {
        val snapshot = currentConfig
        if (!snapshot.lowBatteryCapacitySleep || !battery.isDischarging) return false
        val lowCapacity = battery.percent <= snapshot.lowBatteryCapacity
        val lowRemaining = battery.remainingSeconds?.let {
            it <= snapshot.lowTimeRemainingMinutes.toLong() * 60L
        } ?: false
        return lowCapacity || lowRemaining
    }

    private fun refreshLidLeaseStatusIfDue(nowMillis: Long): Boolean {
        val last = lock.withLock { lastLidLeaseStatusAtMillis }
        if (last != null && nowMillis - last < LID_LEASE_STATUS_REFRESH_MILLIS) return false
        lock.withLock { lastLidLeaseStatusAtMillis = nowMillis }
        return refreshLidLeaseStatus()
    }

    private fun refreshLidLeaseStatus(): Boolean {
        val status = runCatching { privileged.lidLeaseStatus() }
            .getOrElse {
                LidLeaseStatus(
                    available = false,
                    error = it.message ?: "Cannot read lid lease status",
                )
            }
        return lock.withLock {
            val available = status.sleepDisabled != true
            val changed = state.lidLeaseStatus != status || state.lidSleepAvailable != available
            state = state.copy(
                lidLeaseStatus = status,
                lidSleepAvailable = available,
            )
            changed
        }
    }

    private fun applyChargingIdleRule(active: Boolean): Boolean {
        val snapshot = if (active) {
            holdLeases.upsert(
                HoldLease(
                    id = IDLE_CHARGING_RULE_LEASE_ID,
                    level = HoldLeaseLevel.SYSTEM,
                    source = HoldLeaseSource.RULE,
                    reason = "Adapter idle rule",
                    createdAtEpochSeconds = clock() / 1_000L,
                ),
            )
        } else {
            holdLeases.cancelSource(HoldLeaseSource.RULE)
        }
        syncIdleState(snapshot)
        snapshot.lastError?.let { logger.warn("Cannot update charging idle rule: $it") }
        return snapshot.lastError == null
    }

    private fun syncIdleState(snapshot: HoldLeaseSnapshot) {
        val available = snapshot.actualPrevention == IdleSleepPrevention.NONE ||
            snapshot.actualPrevention == IdleSleepPrevention.UNKNOWN
        lock.withLock {
            state = state.copy(
                idleSleepAvailable = available,
                idleSleepPrevention = snapshot.actualPrevention,
                lastError = snapshot.lastError,
            )
        }
    }

    private fun onPowerChanged() {
        val battery = runCatching { power.read() }.getOrNull() ?: return
        val previous = lock.withLock {
            val previous = previousPowerState
            previousPowerState = battery.state
            state = state.copy(battery = battery)
            previous
        }
        publish()
        if (previous == null || previous != battery.state || currentState.enabled) reconcilePolicy()
    }

    private fun onLidChanged(lidState: LidState) {
        val previous = lock.withLock {
            val previous = state.lid
            state = state.copy(lid = lidState)
            previous
        }
        publish()
        if (lidState == LidState.UNKNOWN || previous == lidState || !currentState.enabled) return
        if (lidState == LidState.CLOSED) {
            if (!currentState.lidSleepAvailable) {
                logger.info("Lid closed while lid sleep is prevented; turning display off.")
                displaySleepNow()
            } else if (currentConfig.lidSleepImmediateOnClose) {
                logger.info("Lid closed; starting immediate sleep.")
                requestSleep(restoreAfterWake = true)
            }
        }
    }

    private fun onSleepEvent(event: SleepEvent) {
        when (event) {
            SleepEvent.WillSleep -> logger.info("System will sleep.")
            SleepEvent.WakeSignal -> {
                logger.info("System wake signal received.")
                if (currentConfig.darkWakeAwarenessEnabled) {
                    scheduleWakeScan(initial = false)
                } else {
                    handleFullWake("DarkWake awareness is disabled")
                }
            }
        }
    }

    private fun startInitialWakeScan() {
        if (!currentConfig.darkWakeAwarenessEnabled) return
        scheduleWakeScan(initial = true)
    }

    private fun scheduleWakeScan(initial: Boolean) {
        val shouldSchedule = lock.withLock {
            if (started && config.darkWakeAwarenessEnabled && !wakeScanScheduled) {
                wakeScanScheduled = true
                state = state.copy(darkWake = state.darkWake.copy(scanning = true))
                true
            } else {
                false
            }
        }
        if (!shouldSchedule) return
        publish()
        wakeScanExecutor {
            runWakeScan(initial)
        }
    }

    private fun runWakeScan(initial: Boolean) {
        try {
            val baseline = lock.withLock { lastWakeEvent }
            if (!initial) wakeDelay(wakeRetryDelayMillis)
            var snapshot = if (initial) readWakeLog() else readWakeLogFresh()
            var retries = 0
            if (!initial) {
                while (snapshot?.latest == baseline && retries < wakeRetryCount.coerceAtLeast(0)) {
                    retries += 1
                    wakeDelay(wakeRetryDelayMillis)
                    snapshot = readWakeLogFresh() ?: snapshot
                }
            }
            applyWakeSnapshot(snapshot, initial)
        } finally {
            lock.withLock { wakeScanScheduled = false }
            finishWakeScan()
        }
    }

    /*
     * The wake log command is expensive. The cache serves repeated refreshes for
     * up to 60 seconds. A wake signal bypasses the cache with readWakeLogFresh().
     * A new timestamp or event kind therefore always bypasses a cached result.
     */
    private fun readWakeLog(): WakeLogSnapshot? {
        val cached = lock.withLock { cachedWakeLog }
        if (cached != null && wakeCacheNowMillis() - cached.readAtMillis in 0 until WAKE_LOG_CACHE_MILLIS) {
            return cached.snapshot
        }
        return readWakeLogFresh()
    }

    private fun readWakeLogFresh(): WakeLogSnapshot? {
        val snapshot = runCatching { wakeLogReader.read() }
            .onFailure { logger.warn("Cannot read pmset wake log", it) }
            .getOrNull()
        if (snapshot != null) {
            lock.withLock { cachedWakeLog = WakeLogCache(snapshot, wakeCacheNowMillis()) }
        }
        return snapshot
    }

    private fun applyWakeSnapshot(snapshot: WakeLogSnapshot?, initial: Boolean) {
        if (!currentConfig.darkWakeAwarenessEnabled) return
        val previous = lock.withLock { state.darkWake }
        if (snapshot == null) {
            logger.warn("Wake log parsing failed. Using FULL wake behavior.")
            lock.withLock {
                state = state.copy(
                    darkWake = previous.copy(available = false, scanning = false),
                )
                if (!initial) lastWakeEvent = null
            }
            publish()
            if (!initial) handleFullWake("Wake log is unavailable")
            return
        }

        val latest = snapshot.latest
        lock.withLock {
            state = state.copy(
                darkWake = DarkWakeStatus(
                    available = true,
                    scanning = false,
                    lastAtEpochSeconds = latest?.atEpochSeconds,
                    lastKind = latest?.kind,
                    lastReason = latest?.reason?.takeIf { it.isNotBlank() },
                    count24h = snapshot.darkWakeCount24h,
                ),
            )
        }
        publish()

        if (initial) {
            lock.withLock { lastWakeEvent = latest }
            return
        }

        val baseline = lock.withLock { lastWakeEvent }
        if (latest == null || latest == baseline) {
            logger.info("Wake log did not change after retries.")
            return
        }
        lock.withLock { lastWakeEvent = latest }
        when (latest.kind) {
            WakeKind.DARK -> handleDarkWake(latest.reason)
            WakeKind.FULL -> handleFullWake(latest.reason)
        }
    }

    private fun finishWakeScan() {
        val wasStarted = lock.withLock {
            if (started) {
                state = state.copy(darkWake = state.darkWake.copy(scanning = false))
                true
            } else {
                false
            }
        }
        if (!wasStarted) return
        publish()
    }

    private fun handleDarkWake(reason: String) {
        logger.info("DarkWake detected${reason.takeIf { it.isNotBlank() }?.let { ": $it" } ?: ""}.")
        if (restoreAfterSleep != null) return
        reconcilePolicy()
    }

    private fun handleFullWake(reason: String) {
        logger.info("Full wake detected${reason.takeIf { it.isNotBlank() }?.let { ": $it" } ?: ""}.")
        if (!restoreAfterSleep()) reconcilePolicy()
    }

    private fun restoreAfterSleep(): Boolean {
        val restore = lock.withLock { restoreAfterSleep } ?: return false
        val alreadyRestoring = lock.withLock {
            if (restoreInProgress) {
                true
            } else {
                restoreInProgress = true
                false
            }
        }
        if (alreadyRestoring) return true
        try {
            if (restore.restoreIdle) syncIdleState(holdLeases.resume())
            lock.withLock {
                restoreAfterSleep = null
                if (restore.lidDeadline != null) lidCancelAtMillis = restore.lidDeadline
            }
            reconcilePolicy()
            val battery = currentState.battery
            if (restore.restoreLid && battery != null && !lowBatterySleepRequired(battery)) {
                setLidSleepAvailable(false)
            }
            updateCountdowns(clock())
            publish()
        } finally {
            lock.withLock { restoreInProgress = false }
        }
        return true
    }

    private fun updateCountdowns(nowMillis: Long) {
        lock.withLock {
            state = state.copy(
                idleCancelRemainingSeconds = idleCancelAtMillis?.let { ((it - nowMillis) / 1_000L).coerceAtLeast(0L) },
                lidCancelRemainingSeconds = lidCancelAtMillis?.let { ((it - nowMillis) / 1_000L).coerceAtLeast(0L) },
            )
        }
        publish()
    }

    private fun publish() {
        stateListener.onState(currentState)
    }

    private data class RestorePoint(
        val restoreIdle: Boolean,
        val restoreLid: Boolean,
        val lidDeadline: Long?,
    )

    /** `updateConfig` 在锁内算出的结果。锁函数不是 inline，所以用值传出。 */
    private data class ConfigChange(
        val previous: AppConfig,
        val enabledChanged: Boolean,
        val darkWakeChanged: Boolean,
    )

    private data class Deadlines(val idle: Long?, val lid: Long?)

    private data class SleepPlan(
        val fixIdle: Boolean,
        val fixLid: Boolean,
        val shouldRestore: Boolean,
    )

    private data class LidHoldResult(
        val released: Boolean,
        val success: Boolean,
    )

    private data class WakeLogCache(
        val snapshot: WakeLogSnapshot,
        val readAtMillis: Long,
    )

    companion object {
        private const val WAKE_LOG_CACHE_MILLIS = 60_000L
        private const val LID_LEASE_STATUS_REFRESH_MILLIS = 5_000L
        private const val IDLE_MANUAL_LEASE_ID = "idle/manual"
        private const val IDLE_TIMER_LEASE_ID = "idle/timer"
        private const val IDLE_CHARGING_RULE_LEASE_ID = "idle/rule/charging"
    }
}
