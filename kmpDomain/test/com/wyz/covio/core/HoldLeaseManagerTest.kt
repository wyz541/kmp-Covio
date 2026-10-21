package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class HoldLeaseManagerTest {
    @Test
    fun `display lease requests only the display assertion`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })

        val snapshot = manager.upsert(lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY))

        assertEquals(listOf(IdleSleepPrevention.SYSTEM_AND_DISPLAY), controller.applied)
        assertEquals(IdleSleepPrevention.SYSTEM_AND_DISPLAY, snapshot.actualPrevention)
        assertTrue(snapshot.systemSleepPrevented)
        assertTrue(snapshot.displaySleepPrevented)
        assertEquals(1, controller.activeAssertionCount)
    }

    @Test
    fun `ending one lease keeps the other lease active`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })

        manager.upsert(lease(HoldLeaseLevel.SYSTEM, id = "manual"))
        manager.upsert(lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY, id = "timer", source = HoldLeaseSource.TIMER))
        val afterTimerCancel = manager.cancel("timer")

        assertEquals(IdleSleepPrevention.SYSTEM, afterTimerCancel.actualPrevention)
        assertEquals(listOf("manual"), afterTimerCancel.leases.map { it.id })
        assertEquals(1, controller.activeAssertionCount)

        val afterManualCancel = manager.cancel("manual")
        assertEquals(IdleSleepPrevention.NONE, afterManualCancel.actualPrevention)
        assertTrue(afterManualCancel.leases.isEmpty())
        assertEquals(0, controller.activeAssertionCount)
    }

    @Test
    fun `replace source keeps leases owned by other sources`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })
        manager.upsert(lease(HoldLeaseLevel.SYSTEM, id = "manual", source = HoldLeaseSource.MANUAL))
        manager.replaceSource(
            HoldLeaseSource.AGENT,
            listOf(lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY, id = "agent", source = HoldLeaseSource.MANUAL)),
        )

        val snapshot = manager.replaceSource(HoldLeaseSource.AGENT, emptyList())

        assertEquals(listOf("manual"), snapshot.leases.map { it.id })
        assertEquals(IdleSleepPrevention.SYSTEM, snapshot.actualPrevention)
    }

    @Test
    fun `expired timer does not clear a manual lease`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })
        manager.upsert(lease(HoldLeaseLevel.SYSTEM, id = "manual"))
        manager.upsert(
            lease(
                level = HoldLeaseLevel.SYSTEM,
                id = "timer",
                source = HoldLeaseSource.TIMER,
                expiresAtEpochSeconds = 2L,
            ),
        )

        val snapshot = manager.tick(2_000L)

        assertEquals(listOf("manual"), snapshot.leases.map { it.id })
        assertEquals(IdleSleepPrevention.SYSTEM, snapshot.actualPrevention)
    }

    @Test
    fun `extend moves the expiry without replacing the lease`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })
        manager.upsert(
            lease(
                level = HoldLeaseLevel.SYSTEM,
                id = "timer",
                source = HoldLeaseSource.TIMER,
                expiresAtEpochSeconds = 2L,
            ),
        )

        assertEquals(1, manager.tick(1_500L).leases.size)
        manager.extend("timer", expiresAtEpochSeconds = 4L)
        val stillActive = manager.tick(2_500L)

        assertEquals(1, stillActive.leases.size)
        assertEquals(IdleSleepPrevention.SYSTEM, stillActive.actualPrevention)
    }

    @Test
    fun `suspend releases the assertion and resume restores the lease`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })
        manager.upsert(lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY))

        val suspended = manager.suspend()
        assertTrue(suspended.suspended)
        assertEquals(IdleSleepPrevention.NONE, suspended.actualPrevention)
        assertEquals(1, suspended.leases.size)

        val resumed = manager.resume()
        assertFalse(resumed.suspended)
        assertEquals(IdleSleepPrevention.SYSTEM_AND_DISPLAY, resumed.actualPrevention)
    }

    @Test
    fun `failed assertion reports actual state and can retry`() {
        val controller = FakeAssertionController(failuresRemaining = 1)
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })

        val failed = manager.upsert(lease(HoldLeaseLevel.SYSTEM))
        assertEquals(IdleSleepPrevention.NONE, failed.actualPrevention)
        assertEquals("assertion failure", failed.lastError)
        assertEquals(IdleSleepPrevention.SYSTEM, failed.desiredPrevention)

        val retried = manager.tick(NOW_MILLIS)
        assertEquals(IdleSleepPrevention.SYSTEM, retried.actualPrevention)
        assertEquals(null, retried.lastError)
    }

    @Test
    fun `readback mismatch is a failure even when the driver claims success`() {
        val controller = FakeAssertionController(returnWrongReadback = true)
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })

        val snapshot = manager.upsert(lease(HoldLeaseLevel.SYSTEM))

        assertEquals(IdleSleepPrevention.SYSTEM_AND_DISPLAY, snapshot.actualPrevention)
        assertNotNull(snapshot.lastError)
        assertTrue(snapshot.lastError.orEmpty().contains("mismatch"))
    }

    @Test
    fun `closed lid lease maps to the system assertion in this layer`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })

        val snapshot = manager.upsert(lease(HoldLeaseLevel.CLOSED_LID))

        assertEquals(IdleSleepPrevention.SYSTEM, snapshot.desiredPrevention)
        assertEquals(IdleSleepPrevention.SYSTEM, snapshot.actualPrevention)
    }

    @Test
    fun `closed lid lease does not remove a display lease`() {
        val controller = FakeAssertionController()
        val manager = HoldLeaseManager(controller, clock = { NOW_MILLIS })
        manager.upsert(lease(HoldLeaseLevel.SYSTEM_AND_DISPLAY, id = "display"))
        manager.upsert(lease(HoldLeaseLevel.CLOSED_LID, id = "lid"))

        val snapshot = manager.currentSnapshot()

        assertEquals(IdleSleepPrevention.SYSTEM_AND_DISPLAY, snapshot.desiredPrevention)
        assertEquals(IdleSleepPrevention.SYSTEM_AND_DISPLAY, snapshot.actualPrevention)
    }

    private fun lease(
        level: HoldLeaseLevel,
        id: String = "lease",
        source: HoldLeaseSource = HoldLeaseSource.MANUAL,
        expiresAtEpochSeconds: Long? = null,
    ): HoldLease = HoldLease(
        id = id,
        level = level,
        source = source,
        createdAtEpochSeconds = NOW_MILLIS / 1_000L,
        expiresAtEpochSeconds = expiresAtEpochSeconds,
    )

    private companion object {
        const val NOW_MILLIS = 1_000L
    }
}

private class FakeAssertionController(
    private var failuresRemaining: Int = 0,
    private val returnWrongReadback: Boolean = false,
) : SleepController {
    var actual = IdleSleepPrevention.NONE
        private set
    var activeAssertionCount = 0
        private set
    val applied = mutableListOf<IdleSleepPrevention>()

    override fun sleep() = Unit
    override fun displaySleep() = Unit

    override fun applyIdleSleepPrevention(prevention: IdleSleepPrevention): IdleSleepAssertionResult {
        applied += prevention
        if (failuresRemaining > 0) {
            failuresRemaining -= 1
            return IdleSleepAssertionResult(
                requested = prevention,
                actual = actual,
                success = false,
                error = "assertion failure",
            )
        }
        actual = if (returnWrongReadback && prevention == IdleSleepPrevention.SYSTEM) {
            IdleSleepPrevention.SYSTEM_AND_DISPLAY
        } else {
            prevention
        }
        activeAssertionCount = if (actual == IdleSleepPrevention.NONE) 0 else 1
        return IdleSleepAssertionResult(
            requested = prevention,
            actual = actual,
            success = true,
        )
    }

    override fun readIdleSleepPrevention(): IdleSleepPrevention = actual

    override fun systemIdleSleepTimeoutSeconds(): Long? = 600L
}
