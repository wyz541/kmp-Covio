package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HelperLeaseBookTest {
    @Test
    fun `renew updates one lease without changing another`() {
        val book = HelperLeaseBook()
        assertTrue(book.upsert("a", nowEpochSeconds = 10, expiresAtEpochSeconds = 70))
        assertTrue(book.upsert("b", nowEpochSeconds = 10, expiresAtEpochSeconds = 20))

        assertTrue(book.upsert("b", nowEpochSeconds = 15, expiresAtEpochSeconds = 75))
        val snapshot = book.snapshot()

        assertEquals(listOf("a", "b"), snapshot.activeLeaseIds)
        assertEquals(70, snapshot.expiresAtEpochSeconds)
    }

    @Test
    fun `prune removes only expired leases`() {
        val book = HelperLeaseBook()
        book.upsert("short", nowEpochSeconds = 10, expiresAtEpochSeconds = 20)
        book.upsert("long", nowEpochSeconds = 10, expiresAtEpochSeconds = 70)

        val snapshot = book.prune(nowEpochSeconds = 20)

        assertEquals(listOf("long"), snapshot.activeLeaseIds)
        assertEquals(70, snapshot.expiresAtEpochSeconds)
    }

    @Test
    fun `release leaves other leases active`() {
        val book = HelperLeaseBook()
        book.upsert("a", nowEpochSeconds = 10, expiresAtEpochSeconds = 70)
        book.upsert("b", nowEpochSeconds = 10, expiresAtEpochSeconds = 70)

        val snapshot = book.release("a", nowEpochSeconds = 20)

        assertEquals(listOf("b"), snapshot.activeLeaseIds)
        assertTrue(snapshot.hasActiveLease)
    }

    @Test
    fun `active lease count is bounded`() {
        val book = HelperLeaseBook()
        repeat(HELPER_LEASE_MAX_ACTIVE) { index ->
            assertTrue(
                book.upsert(
                    "lease-$index",
                    nowEpochSeconds = 10,
                    expiresAtEpochSeconds = 70,
                ),
            )
        }

        assertFalse(
            book.upsert(
                "too-many",
                nowEpochSeconds = 10,
                expiresAtEpochSeconds = 70,
            ),
        )
        assertEquals(HELPER_LEASE_MAX_ACTIVE, book.snapshot().activeCount)
    }
}
