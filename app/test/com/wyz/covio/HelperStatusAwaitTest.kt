package com.wyz.covio.app

import com.wyz.covio.app.helper.awaitHelperStatus
import com.wyz.covio.core.HelperStatus
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals

class HelperStatusAwaitTest {
    @Test
    fun `returns installed after startup completes`() = runBlocking {
        var calls = 0
        val status = awaitHelperStatus(HelperStatus.MISSING, 1_000L, 1L) {
            calls += 1
            if (calls >= 2) HelperStatus.MATCH else HelperStatus.UNTRUSTED
        }
        assertEquals(HelperStatus.MATCH, status)
        assertEquals(2, calls)
    }

    @Test
    fun `returns last status after timeout`() = runBlocking {
        val status = awaitHelperStatus(HelperStatus.MISSING, 20L, 1L) {
            HelperStatus.UNTRUSTED
        }
        assertEquals(HelperStatus.UNTRUSTED, status)
    }

    @Test
    fun `installed status returns immediately`() = runBlocking {
        val status = awaitHelperStatus(HelperStatus.MATCH, 1_000L, 1L) {
            error("status provider must not run")
        }
        assertEquals(HelperStatus.MATCH, status)
    }
}
