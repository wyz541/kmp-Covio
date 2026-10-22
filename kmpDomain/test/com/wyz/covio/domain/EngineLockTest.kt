package com.wyz.covio.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `EngineLock` 的行为测试。
 *
 * 这些断言在两个平台上都必须通过。`nestedAcquisitionDoesNotDeadlock` 是最关键的一条：
 * `Engine.reconcilePolicy()` 会嵌套调用同样取锁的 `setLidSleepAvailable()`。
 * 若 macosArm64 侧用非递归互斥量，这条测试会死锁而不是失败。
 */
class EngineLockTest {
    @Test
    fun lockRunsTheBlockAndReturnsItsValue() {
        val lock = EngineLock()
        assertEquals(42, lock.withLock { 42 })
    }

    @Test
    fun nestedAcquisitionDoesNotDeadlock() {
        val lock = EngineLock()
        val result = lock.withLock {
            lock.withLock {
                lock.withLock { "deep" }
            }
        }
        assertEquals("deep", result)
    }

    @Test
    fun lockIsReleasedAfterAnException() {
        val lock = EngineLock()
        runCatching { lock.withLock { throw IllegalStateException("boom") } }
        // 上一步若没释放锁，这一句在单线程上会死锁。
        assertEquals("ok", lock.withLock { "ok" })
    }

    @Test
    fun lockSerializesNestedStateMutation() {
        val lock = EngineLock()
        var value = 0
        lock.withLock {
            value += 1
            lock.withLock { value += 1 }
        }
        assertEquals(2, value)
        assertTrue(lock.withLock { true })
    }
}
