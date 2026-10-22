package com.wyz.covio.core

import com.wyz.covio.domain.EngineDefaults
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EngineTest {
    @Test
    fun `start scans wake log and updates dark wake status`() {
        val event = WakeEvent(WakeKind.DARK, 1_000L, "RTC")
        var reads = 0
        val fixture = Fixture(
            wakeLogReader = WakeLogReader {
                reads += 1
                WakeLogSnapshot(listOf(event), darkWakeCount24h = 1)
            },
        )
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()

        assertEquals(1, reads)
        assertTrue(fixture.engine.currentState.darkWake.available)
        assertEquals(1_000L, fixture.engine.currentState.darkWake.lastAtEpochSeconds)
        assertEquals("RTC", fixture.engine.currentState.darkWake.lastReason)
        assertEquals(1, fixture.engine.currentState.darkWake.count24h)
    }

    @Test
    fun `dark wake does not restore sleep now restrictions`() {
        var snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "Initial")),
            darkWakeCount24h = 1,
        )
        val fixture = Fixture(
            wakeLogReader = WakeLogReader { snapshot },
        )
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(false)
        fixture.engine.setLidSleepAvailable(false)
        fixture.engine.sleepNow()
        assertTrue(fixture.engine.currentState.idleSleepAvailable)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)

        snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 2_000L, "RTC")),
            darkWakeCount24h = 2,
        )
        fixture.watcher.wake()

        assertTrue(fixture.engine.currentState.idleSleepAvailable)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
        assertEquals(2_000L, fixture.engine.currentState.darkWake.lastAtEpochSeconds)
    }

    @Test
    fun `full wake restores sleep now restrictions`() {
        var snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "Initial")),
            darkWakeCount24h = 1,
        )
        val fixture = Fixture(
            wakeLogReader = WakeLogReader { snapshot },
        )
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(false)
        fixture.engine.setLidSleepAvailable(false)
        fixture.engine.sleepNow()

        snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.FULL, 2_000L, "UserActivity")),
            darkWakeCount24h = 1,
        )
        fixture.watcher.wake()

        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertFalse(fixture.engine.currentState.lidSleepAvailable)
    }

    @Test
    fun `overlapping wake signals share one log scan`() {
        var snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "Initial")),
            darkWakeCount24h = 1,
        )
        val queued = mutableListOf<() -> Unit>()
        var reads = 0
        val fixture = Fixture(
            wakeLogReader = WakeLogReader {
                reads += 1
                snapshot
            },
            wakeScanExecutor = { queued += it },
        )
        fixture.engine.start()
        assertEquals(1, queued.size)
        queued.removeAt(0).invoke()
        assertEquals(1, reads)

        snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 2_000L, "RTC")),
            darkWakeCount24h = 2,
        )
        fixture.watcher.wake()
        fixture.watcher.wake()

        assertEquals(1, queued.size)
        queued.removeAt(0).invoke()
        assertEquals(2, reads)
    }

    @Test
    fun `wake scan retries an unchanged log snapshot`() {
        val initial = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "Initial")),
            darkWakeCount24h = 1,
        )
        val updated = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 2_000L, "RTC")),
            darkWakeCount24h = 2,
        )
        var reads = 0
        var delays = 0
        val fixture = Fixture(
            wakeLogReader = WakeLogReader {
                reads += 1
                if (reads <= 2) initial else updated
            },
            wakeDelay = { delays += 1 },
        )
        fixture.engine.start()
        fixture.watcher.wake()

        assertEquals(3, reads)
        assertEquals(2, delays)
        assertEquals(2_000L, fixture.engine.currentState.darkWake.lastAtEpochSeconds)
    }

    @Test
    fun `wake log failure restores sleep now restrictions and marks status unavailable`() {
        var snapshot: WakeLogSnapshot? = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "Initial")),
            darkWakeCount24h = 1,
        )
        val fixture = Fixture(
            wakeLogReader = WakeLogReader { snapshot },
        )
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(false)
        fixture.engine.setLidSleepAvailable(false)
        fixture.engine.sleepNow()

        snapshot = null
        fixture.watcher.wake()

        assertFalse(fixture.engine.currentState.darkWake.available)
        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertFalse(fixture.engine.currentState.lidSleepAvailable)
        assertTrue(fixture.logger.messages.any { it.contains("Wake log parsing failed") })
    }

    @Test
    fun `wake log refresh is cached for 60 seconds`() {
        var nowMillis = 1_000_000L
        var snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "Initial")),
            darkWakeCount24h = 1,
        )
        var reads = 0
        val fixture = Fixture(
            wakeLogReader = WakeLogReader {
                reads += 1
                snapshot
            },
            wakeCacheNowMillis = { nowMillis },
        )
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()
        assertEquals(1, reads)

        fixture.engine.stop()
        snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 2_000L, "RTC")),
            darkWakeCount24h = 2,
        )
        nowMillis += 61_000L
        fixture.engine.start()

        assertEquals(2, reads)
        assertEquals(2_000L, fixture.engine.currentState.darkWake.lastAtEpochSeconds)
    }

    @Test
    fun `new wake event bypasses the cache`() {
        var snapshot = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "Initial")),
            darkWakeCount24h = 1,
        )
        val fixture = Fixture(
            wakeLogReader = WakeLogReader { snapshot },
        )
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()

        snapshot = WakeLogSnapshot(
            listOf(
                WakeEvent(WakeKind.DARK, 1_000L, "Initial"),
                WakeEvent(WakeKind.FULL, 2_000L, "UserActivity"),
            ),
            darkWakeCount24h = 1,
        )
        fixture.watcher.wake()

        assertEquals(2_000L, fixture.engine.currentState.darkWake.lastAtEpochSeconds)
        assertEquals("UserActivity", fixture.engine.currentState.darkWake.lastReason)
    }

    @Test
    fun `wake log failure keeps the previous status data`() {
        var snapshot: WakeLogSnapshot? = WakeLogSnapshot(
            listOf(WakeEvent(WakeKind.DARK, 1_000L, "RTC")),
            darkWakeCount24h = 1,
        )
        val fixture = Fixture(
            wakeLogReader = WakeLogReader { snapshot },
        )
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()

        snapshot = null
        fixture.watcher.wake()

        val status = fixture.engine.currentState.darkWake
        assertFalse(status.available)
        assertEquals(1_000L, status.lastAtEpochSeconds)
        assertEquals("RTC", status.lastReason)
        assertEquals(1, status.count24h)
    }

    @Test
    fun `battery policy holds lid sleep on battery power`() {
        val fixture = Fixture(
            AppConfig(
                disableLidSleepOnBattery = true,
                lidSleepImmediateOnClose = false,
            ),
        )
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, 3_600L)
        fixture.engine.start()

        assertFalse(fixture.engine.currentState.lidSleepAvailable)
        assertTrue(fixture.privileged.disableSleepValues.contains(true))
    }

    @Test
    fun `manual lid hold is released on request`() {
        val fixture = Fixture(AppConfig(lidSleepImmediateOnClose = false))
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, 3_600L)
        fixture.engine.start()

        fixture.engine.setManualLidSleepAvailable(false)
        assertFalse(fixture.engine.currentState.lidSleepAvailable)

        fixture.engine.setManualLidSleepAvailable(true)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    @Test
    fun `low battery policy overrides battery lid hold`() {
        val fixture = Fixture(
            AppConfig(
                disableLidSleepOnBattery = true,
                lowBatteryCapacity = 10,
                lidSleepImmediateOnClose = false,
            ),
        )
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(5, PowerState.DISCHARGING, 3_600L)
        fixture.engine.start()

        assertEquals(1, fixture.sleep.sleepCalls)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
        assertFalse(fixture.privileged.disableSleepValues.contains(true))
    }

    @Test
    fun `helper failure rolls back lid policy config`() {
        val fixture = Fixture(AppConfig(lidSleepImmediateOnClose = false))
        fixture.privileged.installed = true
        fixture.privileged.disableSleepResult = false
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, 3_600L)
        fixture.engine.start()

        val success = fixture.engine.updateConfig(
            fixture.engine.currentConfig.copy(disableLidSleepOnBattery = true),
        )

        assertFalse(success)
        assertFalse(fixture.engine.currentConfig.disableLidSleepOnBattery)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    @Test
    fun `low battery capacity triggers sleep only while discharging`() {
        val fixture = Fixture(AppConfig(lowBatteryCapacity = 6))
        fixture.power.value = BatteryStatus(6, PowerState.DISCHARGING, null)
        fixture.engine.start()
        assertEquals(1, fixture.sleep.sleepCalls)
        fixture.power.value = BatteryStatus(5, PowerState.CHARGING, null)
        fixture.power.emit()
        assertEquals(1, fixture.sleep.sleepCalls)
    }

    @Test
    fun `low remaining time triggers sleep`() {
        val fixture = Fixture(AppConfig(lowTimeRemainingMinutes = 10))
        fixture.power.value = BatteryStatus(50, PowerState.DISCHARGING, 600)
        fixture.engine.start()
        assertEquals(1, fixture.sleep.sleepCalls)
    }

    @Test
    fun `charging rules prevent idle and lid sleep then restore on battery`() {
        val fixture = Fixture(
            AppConfig(
                disableIdleSleepInCharging = true,
                disableLidSleepInCharging = true,
                lidSleepImmediateOnClose = false,
            ),
        )
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(80, PowerState.CHARGING, null)
        fixture.engine.start()
        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertFalse(fixture.engine.currentState.lidSleepAvailable)

        fixture.power.value = BatteryStatus(75, PowerState.DISCHARGING, 3_600)
        fixture.power.emit()
        assertTrue(fixture.engine.currentState.idleSleepAvailable)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    @Test
    fun `lid charging policy is skipped when the helper is not installed`() {
        val fixture = Fixture(
            AppConfig(
                disableIdleSleepInCharging = true,
                disableLidSleepInCharging = true,
                lidSleepImmediateOnClose = false,
            ),
        )
        fixture.privileged.installed = false
        fixture.power.value = BatteryStatus(80, PowerState.CHARGING, null)
        fixture.engine.start()
        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
        assertTrue(fixture.privileged.disableSleepValues.isEmpty())
    }

    @Test
    fun `start does not touch disablesleep when the helper is not installed`() {
        val fixture = Fixture()
        fixture.power.value = BatteryStatus(90, PowerState.DISCHARGING, null)
        fixture.privileged.installed = false
        fixture.engine.start()
        assertTrue(fixture.privileged.disableSleepValues.isEmpty())
    }

    @Test
    fun `lid close sleeps immediately when available`() {
        val fixture = Fixture(AppConfig(lidSleepImmediateOnClose = true))
        fixture.power.value = BatteryStatus(80, PowerState.DISCHARGING, null)
        fixture.engine.start()
        fixture.lid.state = LidState.CLOSED
        fixture.lid.emit(LidState.CLOSED)
        assertEquals(1, fixture.sleep.sleepCalls)
    }

    @Test
    fun `lid close only turns display off while sleep is prevented`() {
        val fixture = Fixture(AppConfig(lidSleepImmediateOnClose = false))
        fixture.power.value = BatteryStatus(80, PowerState.CHARGING, null)
        fixture.engine.start()
        fixture.engine.setLidSleepAvailable(false)
        fixture.lid.emit(LidState.CLOSED)
        assertEquals(1, fixture.sleep.displayCalls)
        assertEquals(0, fixture.sleep.sleepCalls)
    }

    @Test
    fun `idle compensation sleeps after system timeout`() {
        val fixture = Fixture(AppConfig(lidSleepImmediateOnClose = false))
        fixture.power.value = BatteryStatus(80, PowerState.CHARGING, null)
        fixture.engine.start()
        fixture.engine.setLidSleepAvailable(false)
        fixture.sleep.timeoutSeconds = 60
        fixture.idle.seconds = 61
        fixture.engine.tick()
        assertEquals(1, fixture.sleep.sleepCalls)
    }

    @Test
    fun `cancel timer restores idle availability`() {
        var now = 1_000L
        val fixture = Fixture(clock = { now })
        fixture.engine.scheduleCancelIdle(300)
        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        now += 301_000L
        fixture.engine.tick(now)
        assertTrue(fixture.engine.currentState.idleSleepAvailable)
    }

    @Test
    fun `display idle hold exposes the readback level`() {
        val fixture = Fixture()
        fixture.engine.start()

        assertTrue(fixture.engine.setIdleSleepPrevention(IdleSleepPrevention.SYSTEM_AND_DISPLAY))

        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertEquals(
            IdleSleepPrevention.SYSTEM_AND_DISPLAY,
            fixture.engine.currentState.idleSleepPrevention,
        )
        assertEquals(IdleSleepPrevention.SYSTEM_AND_DISPLAY, fixture.sleep.prevention)
    }

    @Test
    fun `assertion failure leaves the real state available and records the error`() {
        val fixture = Fixture()
        fixture.engine.start()
        fixture.sleep.failAssertion = true

        assertFalse(fixture.engine.setIdleSleepPrevention(IdleSleepPrevention.SYSTEM))

        assertTrue(fixture.engine.currentState.idleSleepAvailable)
        assertEquals(IdleSleepPrevention.NONE, fixture.engine.currentState.idleSleepPrevention)
        assertEquals("assertion failure", fixture.engine.currentState.lastError)
    }

    @Test
    fun `idle timer expiry keeps a separate manual hold`() {
        var now = 1_000L
        val fixture = Fixture(clock = { now })
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(false)
        fixture.engine.scheduleCancelIdle(300)

        now += 301_000L
        fixture.engine.tick(now)

        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertEquals(IdleSleepPrevention.SYSTEM, fixture.engine.currentState.idleSleepPrevention)
    }

    @Test
    fun `manual idle off leaves the charging rule active`() {
        val fixture = Fixture(AppConfig(disableIdleSleepInCharging = true))
        fixture.power.value = BatteryStatus(80, PowerState.CHARGING, null)
        fixture.engine.start()
        assertFalse(fixture.engine.currentState.idleSleepAvailable)

        fixture.engine.setIdleSleepAvailable(false)
        fixture.engine.setIdleSleepAvailable(true)

        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertEquals(IdleSleepPrevention.SYSTEM, fixture.engine.currentState.idleSleepPrevention)
    }

    @Test
    fun `sleep now temporarily restores restrictions and wake restores them`() {
        val fixture = Fixture()
        fixture.power.value = BatteryStatus(90, PowerState.CHARGING, null)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(false)
        fixture.engine.setLidSleepAvailable(false)
        assertTrue(fixture.engine.currentState.idleSleepAvailable.not())

        fixture.engine.sleepNow()
        assertEquals(1, fixture.sleep.sleepCalls)
        assertTrue(fixture.engine.currentState.idleSleepAvailable)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)

        fixture.watcher.wake()
        assertFalse(fixture.engine.currentState.idleSleepAvailable)
        assertFalse(fixture.engine.currentState.lidSleepAvailable)
    }

    @Test
    fun `cancel timer restores lid availability`() {
        var now = 5_000L
        val fixture = Fixture(clock = { now })
        fixture.privileged.installed = true
        fixture.engine.scheduleCancelLid(600)
        assertFalse(fixture.engine.currentState.lidSleepAvailable)
        now += 601_000L
        fixture.engine.tick(now)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    @Test
    fun `stop restores sleep availability and clears disablesleep`() {
        val fixture = Fixture(AppConfig(lidSleepImmediateOnClose = false))
        fixture.privileged.installed = true
        fixture.power.value = BatteryStatus(90, PowerState.CHARGING, null)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(false)
        fixture.engine.setLidSleepAvailable(false)
        assertTrue(fixture.privileged.disableSleepValues.contains(true))

        fixture.engine.stop()
        assertTrue(fixture.engine.currentState.idleSleepAvailable)
        assertTrue(fixture.engine.currentState.lidSleepAvailable)
        assertFalse(fixture.sleep.prevented)
        assertEquals(false, fixture.privileged.disableSleepValues.last())
    }

    @Test
    fun `start removes stale disablesleep flag when no charging policy needs it`() {
        val fixture = Fixture()
        fixture.power.value = BatteryStatus(90, PowerState.DISCHARGING, null)
        fixture.privileged.installed = true
        fixture.engine.start()
        assertTrue(fixture.privileged.disableSleepValues.contains(false))
    }
}

private class Fixture(
    config: AppConfig = AppConfig(),
    clock: () -> Long = { EngineDefaults.nowMillis() },
    wakeLogReader: WakeLogReader = WakeLogReader { null },
    wakeScanExecutor: (() -> Unit) -> Unit = { it() },
    wakeDelay: (Long) -> Unit = {},
    wakeCacheNowMillis: () -> Long = { EngineDefaults.nowMillis() },
) {
    val power = FakePower()
    val lid = FakeLid()
    val idle = FakeIdle()
    val sleep = FakeSleepController()
    val watcher = FakeSleepWatcher()
    val privileged = FakePrivilegedOps()
    val logger = MemoryLogger()
    val engine = Engine(
        initialConfig = config,
        power = power,
        lid = lid,
        idle = idle,
        sleepController = sleep,
        sleepWatcher = watcher,
        privileged = privileged,
        logger = logger,
        wakeLogReader = wakeLogReader,
        clock = clock,
        wakeScanExecutor = wakeScanExecutor,
        wakeDelay = wakeDelay,
        wakeCacheNowMillis = wakeCacheNowMillis,
    )
}

private class FakePower(var value: BatteryStatus? = null) : PowerSource {
    private var listener: (() -> Unit)? = null
    override fun read() = value
    override fun subscribe(listener: () -> Unit) { this.listener = listener }
    override fun stop() { listener = null }
    fun emit() { listener?.invoke() }
}

private class FakeLid(var state: LidState = LidState.OPEN) : LidSensor {
    private var listener: ((LidState) -> Unit)? = null
    override fun read() = state
    override fun subscribe(listener: (LidState) -> Unit) { this.listener = listener }
    override fun stop() { listener = null }
    fun emit(value: LidState) { state = value; listener?.invoke(value) }
}

private class FakeIdle(var seconds: Long = 0L) : IdleSensor {
    override fun idleSeconds() = seconds
}

private class FakeSleepController : SleepController {
    var sleepCalls = 0
    var displayCalls = 0
    var prevention = IdleSleepPrevention.NONE
    var failAssertion = false
    val appliedPrevention = mutableListOf<IdleSleepPrevention>()
    var timeoutSeconds: Long? = 600
    val prevented: Boolean get() = prevention.isActive
    override fun sleep() { sleepCalls++ }
    override fun displaySleep() { displayCalls++ }
    override fun applyIdleSleepPrevention(prevention: IdleSleepPrevention): IdleSleepAssertionResult {
        appliedPrevention += prevention
        if (failAssertion) {
            return IdleSleepAssertionResult(prevention, this.prevention, false, "assertion failure")
        }
        this.prevention = prevention
        return IdleSleepAssertionResult(prevention, prevention, true)
    }
    override fun readIdleSleepPrevention() = prevention
    override fun systemIdleSleepTimeoutSeconds() = timeoutSeconds
}

private class FakeSleepWatcher : SleepWatcher {
    private var listener: ((SleepEvent) -> Unit)? = null
    override fun subscribe(listener: (SleepEvent) -> Unit) { this.listener = listener }
    override fun stop() { listener = null }
    fun willSleep() { listener?.invoke(SleepEvent.WillSleep) }
    fun wake() { listener?.invoke(SleepEvent.WakeSignal) }
}

private class FakePrivilegedOps : PrivilegedOps {
    var installed = false
    var disableSleepResult = true
    val disableSleepValues = mutableListOf<Boolean>()
    override fun isInstalled() = installed
    override fun status() = if (installed) HelperStatus.INSTALLED else HelperStatus.NOT_INSTALLED
    override fun helperVersion() = APP_VERSION
    override fun install() = true
    override fun uninstall() = true
    override fun hibernateMode(): Int? = null
    override fun setHibernateMode(mode: Int) = true
    override fun setDisableSleep(disabled: Boolean): Boolean {
        disableSleepValues += disabled
        return disableSleepResult
    }
}

private class MemoryLogger : AppLogger {
    val messages = mutableListOf<String>()
    override fun info(message: String) { messages += message }
    override fun warn(message: String, error: Throwable?) { messages += message }
    override fun error(message: String, error: Throwable?) { messages += message }
    override fun logFile() = ""
}
