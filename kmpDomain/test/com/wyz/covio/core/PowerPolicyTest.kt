package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PowerPolicyTest {
    @Test
    fun `power defaults match the reviewed surface`() {
        val config = PowerConfig.defaults()

        assertTrue(config.enabled)
        assertTrue(config.keepAwakeOnAdapter)
        assertFalse(config.keepAwakeOnBattery)
        assertTrue(config.allowClosedLid)
        assertTrue(config.pauseClosedLidWithExternalDisplay)
        assertEquals(15, config.batteryFloorPercent)
        assertEquals(20, config.batteryFloorRecoveryPercent)
        assertTrue(config.yieldOnLowPowerMode)
        assertTrue(config.heatGuardEnabled)
        assertEquals(240, config.closedLidTimeCapMinutes)
    }

    @Test
    fun `disabled power blocks active leases and automatic rules`() {
        val decision = decide(
            config = config(enabled = false),
            lease = lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.POWER_DISABLED), decision.safetyVetoes)
    }

    @Test
    fun `runtime pause blocks active leases and automatic rules`() {
        val decision = decide(
            paused = true,
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot(),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.EXPLICITLY_PAUSED), decision.safetyVetoes)
    }

    @Test
    fun `multiple leases merge at the highest level`() {
        val decision = decide(
            leases = listOf(
                lease(HoldLeaseLevel.SYSTEM, id = "manual"),
                lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY, id = "timer"),
            ),
        )

        assertTrue(decision.preventUserIdleSystemSleep)
        assertTrue(decision.preventUserIdleDisplaySleep)
        assertFalse(decision.preventLidSleep)
        assertEquals(HoldLeaseLevel.SYSTEM_AND_DISPLAY, decision.appliedLeaseLevel)
        assertEquals(listOf("manual", "timer"), decision.activeLeaseIds)
    }

    @Test
    fun `closed lid lease holds the system and lid but not the display account`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot(),
        )

        assertTrue(decision.preventUserIdleSystemSleep)
        assertFalse(decision.preventUserIdleDisplaySleep)
        assertTrue(decision.preventLidSleep)
        assertEquals(HoldLeaseLevel.CLOSED_LID, decision.appliedLeaseLevel)
        assertTrue(decision.safetyVetoes.isEmpty())
    }

    @Test
    fun `closed lid lease keeps a separate display lease`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            leases = listOf(
                lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY, id = "display"),
                lease(HoldLeaseLevel.CLOSED_LID, id = "lid"),
            ),
            snapshot = safeClosedLidSnapshot(),
        )

        assertTrue(decision.preventUserIdleSystemSleep)
        assertTrue(decision.preventUserIdleDisplaySleep)
        assertTrue(decision.preventLidSleep)
        assertEquals(HoldLeaseLevel.CLOSED_LID, decision.appliedLeaseLevel)
        assertEquals(listOf("display", "lid"), decision.activeLeaseIds)
    }

    @Test
    fun `expired lease falls back to an automatic rule`() {
        val decision = decide(
            lease = lease(
                level = HoldLeaseLevel.SYSTEM_AND_DISPLAY,
                expiresAtEpochSeconds = NOW,
            ),
        )

        assertTrue(decision.preventUserIdleSystemSleep)
        assertFalse(decision.preventUserIdleDisplaySleep)
        assertTrue(decision.automaticRuleApplied)
        assertEquals(null, decision.appliedLeaseLevel)
    }

    @Test
    fun `closed lid lease requires the installed helper`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot().copy(helperStatus = HelperStatus.NOT_INSTALLED),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.HELPER_UNAVAILABLE), decision.safetyVetoes)
    }

    @Test
    fun `closed lid rule can disable a closed lid lease`() {
        val decision = decide(
            config = config(
                keepAwakeOnAdapter = false,
                allowClosedLid = false,
            ),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot(),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.CLOSED_LID_DISABLED), decision.safetyVetoes)
    }

    @Test
    fun `external display pauses a closed lid lease`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot().withExternalDisplayCount(1),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.EXTERNAL_DISPLAY_CONNECTED), decision.safetyVetoes)
    }

    @Test
    fun `unknown external display state fails closed`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot().withExternalDisplayCount(null),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.EXTERNAL_DISPLAY_UNKNOWN), decision.safetyVetoes)
    }

    @Test
    fun `lower lease remains active when a closed lid lease is vetoed`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            leases = listOf(
                lease(HoldLeaseLevel.SYSTEM, id = "system"),
                lease(HoldLeaseLevel.CLOSED_LID, id = "lid"),
            ),
            snapshot = safeClosedLidSnapshot().withExternalDisplayCount(1),
        )

        assertTrue(decision.preventUserIdleSystemSleep)
        assertFalse(decision.preventLidSleep)
        assertEquals(HoldLeaseLevel.SYSTEM, decision.appliedLeaseLevel)
        assertEquals(listOf(SafetyVeto.EXTERNAL_DISPLAY_CONNECTED), decision.safetyVetoes)
    }

    @Test
    fun `closed lid state is unknown until sleep disabled is readable`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot().copy(sleepDisabled = null),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.SLEEP_DISABLED_STATE_UNKNOWN), decision.safetyVetoes)
    }

    @Test
    fun `external sleep disabled state is not treated as Covio ownership`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot().copy(
                sleepDisabled = true,
                covioOwnsSleepDisabled = false,
            ),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.EXTERNAL_SLEEP_DISABLED_CONFLICT), decision.safetyVetoes)
    }

    @Test
    fun `Covio owned sleep disabled state permits a closed lid lease`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot().copy(
                sleepDisabled = true,
                covioOwnsSleepDisabled = true,
            ),
        )

        assertTrue(decision.preventLidSleep)
        assertTrue(decision.safetyVetoes.isEmpty())
    }

    @Test
    fun `unknown battery capacity prevents a closed lid lease`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.CLOSED_LID),
            snapshot = safeClosedLidSnapshot().withBattery(percent = null, hasBattery = true),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.BATTERY_STATE_UNKNOWN), decision.safetyVetoes)
    }

    @Test
    fun `battery guard latches at the floor and clears only at recovery`() {
        val systemLease = lease(HoldLeaseLevel.SYSTEM)
        val atFloor = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = systemLease,
            snapshot = batterySnapshot(percent = 15),
        )
        assertTrue(atFloor.sleepAllowed)
        assertTrue(atFloor.batteryGuardLatched)
        assertEquals(listOf(SafetyVeto.BATTERY_FLOOR), atFloor.safetyVetoes)

        val belowRecovery = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = systemLease,
            snapshot = batterySnapshot(percent = 19),
            batteryGuardLatched = atFloor.batteryGuardLatched,
        )
        assertTrue(belowRecovery.sleepAllowed)
        assertTrue(belowRecovery.batteryGuardLatched)

        val atRecovery = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = systemLease,
            snapshot = batterySnapshot(percent = 20),
            batteryGuardLatched = belowRecovery.batteryGuardLatched,
        )
        assertTrue(atRecovery.preventUserIdleSystemSleep)
        assertFalse(atRecovery.batteryGuardLatched)
        assertTrue(atRecovery.safetyVetoes.isEmpty())
    }

    @Test
    fun `adapter power clears a latched battery guard`() {
        val decision = decide(
            lease = lease(HoldLeaseLevel.SYSTEM),
            snapshot = batterySnapshot(percent = 5).withPowerState(PowerState.CHARGING),
            batteryGuardLatched = true,
        )

        assertTrue(decision.preventUserIdleSystemSleep)
        assertFalse(decision.batteryGuardLatched)
        assertTrue(decision.safetyVetoes.isEmpty())
    }

    @Test
    fun `thermal critical always releases every lease`() {
        val decision = decide(
            config = config(
                keepAwakeOnAdapter = false,
                heatGuardEnabled = false,
            ),
            lease = lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY),
            snapshot = baseSnapshot().withThermalState(ThermalState.CRITICAL),
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.THERMAL_CRITICAL), decision.safetyVetoes)
    }

    @Test
    fun `thermal serious applies only when the heat guard is enabled`() {
        val blocked = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.SYSTEM),
            snapshot = baseSnapshot().withThermalState(ThermalState.SERIOUS),
        )
        assertTrue(blocked.sleepAllowed)
        assertEquals(listOf(SafetyVeto.THERMAL_SERIOUS), blocked.safetyVetoes)

        val allowed = decide(
            config = config(
                keepAwakeOnAdapter = false,
                heatGuardEnabled = false,
            ),
            lease = lease(HoldLeaseLevel.SYSTEM),
            snapshot = baseSnapshot().withThermalState(ThermalState.SERIOUS),
        )
        assertTrue(allowed.preventUserIdleSystemSleep)
    }

    @Test
    fun `low power mode yields when configured`() {
        val blocked = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(HoldLeaseLevel.SYSTEM),
            snapshot = baseSnapshot().withLowPowerMode(true),
        )
        assertTrue(blocked.sleepAllowed)
        assertEquals(listOf(SafetyVeto.LOW_POWER_MODE), blocked.safetyVetoes)

        val allowed = decide(
            config = config(
                keepAwakeOnAdapter = false,
                yieldOnLowPowerMode = false,
            ),
            lease = lease(HoldLeaseLevel.SYSTEM),
            snapshot = baseSnapshot().withLowPowerMode(true),
        )
        assertTrue(allowed.preventUserIdleSystemSleep)
    }

    @Test
    fun `automatic adapter and battery rules create a system hold`() {
        val adapter = decide(
            config = config(
                keepAwakeOnAdapter = true,
                keepAwakeOnBattery = false,
            ),
            snapshot = baseSnapshot().withPowerState(PowerState.AC_POWER),
        )
        assertTrue(adapter.preventUserIdleSystemSleep)
        assertFalse(adapter.preventUserIdleDisplaySleep)
        assertTrue(adapter.automaticRuleApplied)

        val battery = decide(
            config = config(
                keepAwakeOnAdapter = false,
                keepAwakeOnBattery = true,
            ),
            snapshot = batterySnapshot(percent = 80),
        )
        assertTrue(battery.preventUserIdleSystemSleep)
        assertTrue(battery.automaticRuleApplied)
    }

    @Test
    fun `unknown state defaults to allowing sleep`() {
        val decision = decide(
            config = PowerConfig.defaults(),
            snapshot = PowerSnapshot(),
        )

        assertTrue(decision.sleepAllowed)
        assertFalse(decision.automaticRuleApplied)
        assertEquals(null, decision.appliedLeaseLevel)
    }

    @Test
    fun `ordinary lease expiry is not reported as a safety cap`() {
        val decision = decide(
            config = config(keepAwakeOnAdapter = false),
            lease = lease(
                level = HoldLeaseLevel.CLOSED_LID,
                createdAtEpochSeconds = 1_000L,
                expiresAtEpochSeconds = NOW,
            ),
            snapshot = safeClosedLidSnapshot(),
        )

        assertTrue(decision.sleepAllowed)
        assertTrue(decision.safetyVetoes.isEmpty())
    }

    @Test
    fun `closed lid time cap expires the lease`() {
        val createdAt = 1_000L
        val decision = decide(
            config = config(
                keepAwakeOnAdapter = false,
                closedLidTimeCapMinutes = 1,
            ),
            lease = lease(
                level = HoldLeaseLevel.CLOSED_LID,
                createdAtEpochSeconds = createdAt,
            ),
            snapshot = safeClosedLidSnapshot(),
            nowEpochSeconds = createdAt + 60L,
        )

        assertTrue(decision.sleepAllowed)
        assertEquals(listOf(SafetyVeto.CLOSED_LID_TIME_CAP), decision.safetyVetoes)
    }

    @Test
    fun `invalid observations become unknown instead of clamped values`() {
        val normalized = PowerObservation(
            batteryPercent = 101,
            hasBattery = true,
            externalDisplayCount = -1,
        ).normalized()

        assertEquals(null, normalized.batteryPercent)
        assertEquals(null, normalized.externalDisplayCount)

        val noBattery = PowerObservation(
            batteryPercent = 80,
            hasBattery = false,
        ).normalized()
        assertEquals(null, noBattery.batteryPercent)
    }

    @Test
    fun `normalization keeps a recovery gap and valid time cap`() {
        val config = PowerConfig(
            batteryFloorPercent = 105,
            batteryFloorRecoveryPercent = -1,
            closedLidTimeCapMinutes = 0,
        ).normalized()

        assertEquals(99, config.batteryFloorPercent)
        assertEquals(100, config.batteryFloorRecoveryPercent)
        assertEquals(1, config.closedLidTimeCapMinutes)
    }

    private fun decide(
        config: PowerConfig = PowerConfig(),
        snapshot: PowerSnapshot = baseSnapshot(),
        lease: HoldLease? = null,
        leases: List<HoldLease> = listOfNotNull(lease),
        nowEpochSeconds: Long = NOW,
        paused: Boolean = false,
        batteryGuardLatched: Boolean = false,
    ): PowerDecision = PowerPolicy.decide(
        config = config,
        snapshot = snapshot,
        leases = leases,
        nowEpochSeconds = nowEpochSeconds,
        paused = paused,
        batteryGuardLatched = batteryGuardLatched,
    )

    private fun config(
        enabled: Boolean = true,
        keepAwakeOnAdapter: Boolean = true,
        keepAwakeOnBattery: Boolean = false,
        allowClosedLid: Boolean = true,
        pauseClosedLidWithExternalDisplay: Boolean = true,
        yieldOnLowPowerMode: Boolean = true,
        heatGuardEnabled: Boolean = true,
        closedLidTimeCapMinutes: Int = 240,
    ): PowerConfig = PowerConfig(
        enabled = enabled,
        keepAwakeOnAdapter = keepAwakeOnAdapter,
        keepAwakeOnBattery = keepAwakeOnBattery,
        allowClosedLid = allowClosedLid,
        pauseClosedLidWithExternalDisplay = pauseClosedLidWithExternalDisplay,
        yieldOnLowPowerMode = yieldOnLowPowerMode,
        heatGuardEnabled = heatGuardEnabled,
        closedLidTimeCapMinutes = closedLidTimeCapMinutes,
    )

    private fun baseSnapshot(): PowerSnapshot = PowerSnapshot(
        observation = PowerObservation(
            batteryPercent = 80,
            hasBattery = true,
            powerState = PowerState.CHARGING,
            externalDisplayCount = 0,
            lidState = LidState.OPEN,
            thermalState = ThermalState.NOMINAL,
            lowPowerModeEnabled = false,
        ),
        helperStatus = HelperStatus.INSTALLED,
        sleepDisabled = false,
        covioOwnsSleepDisabled = null,
    )

    private fun safeClosedLidSnapshot(): PowerSnapshot = baseSnapshot()

    private fun batterySnapshot(percent: Int): PowerSnapshot = baseSnapshot().copy(
        observation = baseSnapshot().observation.copy(
            batteryPercent = percent,
            powerState = PowerState.DISCHARGING,
        ),
    )

    private fun PowerSnapshot.withExternalDisplayCount(count: Int?): PowerSnapshot = copy(
        observation = observation.copy(externalDisplayCount = count),
    )

    private fun PowerSnapshot.withPowerState(state: PowerState): PowerSnapshot = copy(
        observation = observation.copy(powerState = state),
    )

    private fun PowerSnapshot.withThermalState(state: ThermalState): PowerSnapshot = copy(
        observation = observation.copy(thermalState = state),
    )

    private fun PowerSnapshot.withLowPowerMode(enabled: Boolean): PowerSnapshot = copy(
        observation = observation.copy(lowPowerModeEnabled = enabled),
    )

    private fun PowerSnapshot.withBattery(percent: Int?, hasBattery: Boolean): PowerSnapshot = copy(
        observation = observation.copy(
            batteryPercent = percent,
            hasBattery = hasBattery,
        ),
    )

    private fun lease(
        level: HoldLeaseLevel,
        id: String = "lease",
        createdAtEpochSeconds: Long = 1_000L,
        expiresAtEpochSeconds: Long? = null,
    ): HoldLease = HoldLease(
        id = id,
        level = level,
        source = HoldLeaseSource.MANUAL,
        createdAtEpochSeconds = createdAtEpochSeconds,
        expiresAtEpochSeconds = expiresAtEpochSeconds,
    )

    private companion object {
        const val NOW = 2_000L
    }
}
