package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChargeLimitPolicyTest {
    private fun observation(
        upper: Int = 85,
        current: Int? = 79,
        adapter: Boolean = true,
        observedTarget: Int? = upper,
        enabled: Boolean = true,
        helperInstalled: Boolean = true,
        support: ChargeLimitSupport = ChargeLimitSupport.SUPPORTED,
        batteryPresent: Boolean = true,
        charged: Boolean = false,
        calibration: Boolean = false,
        protection: Boolean = false,
        conflict: Boolean = false,
        error: String? = null,
        writePending: Boolean = false,
        bypass: Boolean = false,
        activeDischarge: Boolean = false,
        activelyDischarging: Boolean = false,
    ) = ChargeLimitObservation(
        enabled = enabled,
        upperLimitPercent = upper,
        adapterConnected = adapter,
        currentPercent = current,
        helperInstalled = helperInstalled,
        support = support,
        batteryPresent = batteryPresent,
        isCharged = charged,
        calibrationActive = calibration,
        systemProtectionActive = protection,
        conflict = conflict,
        errorMessage = error,
        observedTargetPercent = observedTarget,
        writePending = writePending,
        bypassEngaged = bypass,
        activeDischargeEnabled = activeDischarge,
        activelyDischarging = activelyDischarging,
    )

    @Test
    fun `limits use five point steps from forty to one hundred`() {
        assertTrue(ChargeLimitPolicy.isValidUpperLimit(40))
        assertTrue(ChargeLimitPolicy.isValidUpperLimit(75))
        assertTrue(ChargeLimitPolicy.isValidUpperLimit(100))
        assertFalse(ChargeLimitPolicy.isValidUpperLimit(39))
        assertFalse(ChargeLimitPolicy.isValidUpperLimit(79))
        assertFalse(ChargeLimitPolicy.isValidUpperLimit(101))
        assertEquals(80, ChargeLimitPolicy.normalizeUpperLimit(79))
        assertEquals(75, ChargeLimitPolicy.normalizeUpperLimit(75))
    }

    @Test
    fun `the resume threshold is five points lower with a floor of thirty five`() {
        assertEquals(35, ChargeLimitPolicy.resumeThreshold(40))
        assertEquals(45, ChargeLimitPolicy.resumeThreshold(50))
        assertEquals(95, ChargeLimitPolicy.resumeThreshold(100))
    }

    @Test
    fun `disabled policy does not request a write`() {
        val decision = ChargeLimitPolicy.evaluate(observation(enabled = false))

        assertEquals(ChargeLimitPhase.OFF, decision.phase)
        assertEquals(ChargeLimitAction.NONE, decision.action)
        assertFalse(decision.chargingLatch)
    }

    @Test
    fun `missing helper and unsupported MCL stop before charging logic`() {
        val missing = ChargeLimitPolicy.evaluate(observation(helperInstalled = false))
        val unsupported = ChargeLimitPolicy.evaluate(
            observation(support = ChargeLimitSupport.UNSUPPORTED),
        )

        assertEquals(ChargeLimitPhase.HELPER_MISSING, missing.phase)
        assertEquals(ChargeLimitPhase.UNSUPPORTED, unsupported.phase)
        assertEquals(ChargeLimitAction.NONE, missing.action)
        assertEquals(ChargeLimitAction.NONE, unsupported.action)
    }

    @Test
    fun `unknown MCL support is an error`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(support = ChargeLimitSupport.UNKNOWN),
        )

        assertEquals(ChargeLimitPhase.ERROR, decision.phase)
        assertEquals("无法确认 MCL 能力", decision.errorMessage)
    }

    @Test
    fun `no battery and unplugged states do not write`() {
        val noBattery = ChargeLimitPolicy.evaluate(observation(batteryPresent = false))
        val unplugged = ChargeLimitPolicy.evaluate(
            observation(adapter = false),
            previous = ChargeLimitPolicyState(chargingLatch = true),
        )

        assertEquals(ChargeLimitPhase.NO_BATTERY, noBattery.phase)
        assertEquals(ChargeLimitPhase.UNPLUGGED, unplugged.phase)
        assertEquals(ChargeLimitAction.NONE, unplugged.action)
        assertFalse(unplugged.chargingLatch)
    }

    @Test
    fun `below the resume threshold starts a charging latch`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 79, observedTarget = 85),
        )

        assertEquals(ChargeLimitPhase.CHARGING, decision.phase)
        assertEquals(ChargeLimitAction.NONE, decision.action)
        assertTrue(decision.chargingLatch)
    }

    @Test
    fun `the charging latch continues inside the hysteresis band`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 82, observedTarget = 85),
            previous = ChargeLimitPolicyState(chargingLatch = true),
        )

        assertEquals(ChargeLimitPhase.CHARGING, decision.phase)
        assertTrue(decision.chargingLatch)
    }

    @Test
    fun `without a latch the band holds the current level`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 82, observedTarget = 82),
        )

        assertEquals(ChargeLimitPhase.SAILING, decision.phase)
        assertEquals(82, decision.targetPercent)
        assertFalse(decision.chargingLatch)
    }

    @Test
    fun `at the limit the policy holds the current level`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 85, observedTarget = 85),
        )

        assertEquals(ChargeLimitPhase.HOLDING, decision.phase)
        assertEquals(85, decision.targetPercent)
        assertFalse(decision.chargingLatch)
    }

    @Test
    fun `above the limit the policy holds without draining`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 90, observedTarget = 90),
        )

        assertEquals(ChargeLimitPhase.ABOVE_LIMIT, decision.phase)
        assertEquals(90, decision.targetPercent)
        assertEquals(ChargeLimitAction.NONE, decision.action)
    }

    @Test
    fun `active discharge above the limit targets the upper limit`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(
                upper = 70,
                current = 80,
                observedTarget = 80,
                activeDischarge = true,
            ),
        )

        assertEquals(ChargeLimitPhase.APPLYING, decision.phase)
        assertEquals(70, decision.targetPercent)
        assertEquals(ChargeLimitAction.SET_TARGET, decision.action)
    }

    @Test
    fun `an applied active discharge reports discharging without another write`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(
                upper = 70,
                current = 78,
                observedTarget = 70,
                activeDischarge = true,
            ),
        )

        assertEquals(ChargeLimitPhase.DISCHARGING, decision.phase)
        assertEquals(70, decision.targetPercent)
        assertEquals(ChargeLimitAction.NONE, decision.action)
    }

    @Test
    fun `a disabled active discharge reports until battery current stops`() {
        val stopping = ChargeLimitPolicy.evaluate(
            observation(
                upper = 70,
                current = 80,
                observedTarget = 80,
                activelyDischarging = true,
            ),
        )
        val stopped = ChargeLimitPolicy.evaluate(
            observation(
                upper = 70,
                current = 80,
                observedTarget = 80,
            ),
        )

        assertEquals(ChargeLimitPhase.STOPPING_DISCHARGE, stopping.phase)
        assertEquals(ChargeLimitAction.NONE, stopping.action)
        assertEquals(ChargeLimitPhase.ABOVE_LIMIT, stopped.phase)
    }

    @Test
    fun `a target mismatch enters applying and requests the target`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 79, observedTarget = null),
        )

        assertEquals(ChargeLimitPhase.APPLYING, decision.phase)
        assertEquals(ChargeLimitAction.SET_TARGET, decision.action)
        assertEquals(85, decision.targetPercent)
    }

    @Test
    fun `an in-flight write keeps the card in applying`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(
                upper = 85,
                current = 79,
                observedTarget = 85,
                writePending = true,
            ),
        )

        assertEquals(ChargeLimitPhase.APPLYING, decision.phase)
        assertEquals(ChargeLimitAction.NONE, decision.action)
        assertTrue(decision.chargingLatch)
    }

    @Test
    fun `one hundred percent releases MCL instead of writing one hundred`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(
                upper = 100,
                current = 90,
                observedTarget = 80,
            ),
        )

        assertEquals(ChargeLimitPhase.APPLYING, decision.phase)
        assertEquals(ChargeLimitAction.RELEASE_TARGET, decision.action)
        assertEquals(null, decision.targetPercent)
        assertFalse(decision.chargingLatch)
    }

    @Test
    fun `a charged battery at one hundred percent is full`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(
                upper = 100,
                current = 100,
                charged = true,
                observedTarget = null,
            ),
        )

        assertEquals(ChargeLimitPhase.FULL, decision.phase)
        assertEquals(ChargeLimitAction.NONE, decision.action)
    }

    @Test
    fun `system protection and calibration take precedence over charging`() {
        val protection = ChargeLimitPolicy.evaluate(
            observation(protection = true),
        )
        val calibration = ChargeLimitPolicy.evaluate(
            observation(calibration = true),
        )

        assertEquals(ChargeLimitPhase.SYSTEM_PROTECTION, protection.phase)
        assertEquals(ChargeLimitPhase.CALIBRATION, calibration.phase)
        assertEquals(ChargeLimitAction.NONE, protection.action)
        assertEquals(ChargeLimitAction.NONE, calibration.action)
    }

    @Test
    fun `an external conflict is exposed without another write`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(conflict = true),
        )

        assertEquals(ChargeLimitPhase.CONFLICT, decision.phase)
        assertEquals(ChargeLimitAction.NONE, decision.action)
    }

    @Test
    fun `bypass is only exposed for a holding state`() {
        val holding = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 85, observedTarget = 85, bypass = true),
        )
        val charging = ChargeLimitPolicy.evaluate(
            observation(upper = 85, current = 79, observedTarget = 85, bypass = true),
        )

        assertTrue(holding.bypassEngaged)
        assertFalse(charging.bypassEngaged)
    }

    @Test
    fun `a missing battery reading is an error`() {
        val decision = ChargeLimitPolicy.evaluate(
            observation(current = null),
        )

        assertEquals(ChargeLimitPhase.ERROR, decision.phase)
        assertEquals("无法读取电池电量", decision.errorMessage)
    }
}
