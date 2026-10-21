package com.wyz.covio.core

import com.wyz.covio.domain.EngineDefaults
import com.wyz.covio.domain.EngineLock

/**
 * 管理运行时保持唤醒租约，并同步 Covio 的空闲睡眠断言。
 *
 * 管理器只处理用户态断言。
 * 合盖保持唤醒仍由 helper 执行。
 */
class HoldLeaseManager(
    private val sleepController: SleepController,
    private val clock: () -> Long = { EngineDefaults.nowMillis() },
) {
    private val lock = EngineLock()
    private val leases = linkedMapOf<String, HoldLease>()
    private var suspended = false
    private var actualPrevention = IdleSleepPrevention.UNKNOWN
    private var lastError: String? = null

    /** 新建或替换一个租约。相同 ID 的租约不会产生第二条断言。 */
    fun upsert(lease: HoldLease): HoldLeaseSnapshot {
        require(lease.id.isNotBlank()) { "lease.id must not be blank" }
        lock.withLock { leases[lease.id] = lease }
        return reconcile(clock())
    }

    /** 延长一个租约。租约不存在时保持原状态。 */
    fun extend(id: String, expiresAtEpochSeconds: Long): HoldLeaseSnapshot {
        val found = lock.withLock {
            val current = leases[id]
            if (current == null) {
                false
            } else {
                leases[id] = current.copy(expiresAtEpochSeconds = expiresAtEpochSeconds)
                true
            }
        }
        return if (found) reconcile(clock()) else currentSnapshot()
    }

    /** 结束一个租约。其他租约继续生效。 */
    fun cancel(id: String): HoldLeaseSnapshot {
        lock.withLock { leases.remove(id) }
        return reconcile(clock())
    }

    /** 结束一组来源相同的租约。 */
    fun cancelSource(source: HoldLeaseSource): HoldLeaseSnapshot {
        lock.withLock { leases.entries.removeAll { it.value.source == source } }
        return reconcile(clock())
    }

    /** 用新列表替换一个来源的全部租约。 */
    fun replaceSource(source: HoldLeaseSource, nextLeases: List<HoldLease>): HoldLeaseSnapshot {
        lock.withLock {
            leases.entries.removeAll { it.value.source == source }
            nextLeases.forEach { lease ->
                if (lease.id.isNotBlank()) {
                    leases[lease.id] = lease.copy(source = source)
                }
            }
        }
        return reconcile(clock())
    }
    /** 一次结束多个来源的租约。 */
    fun cancelSources(sources: List<HoldLeaseSource>): HoldLeaseSnapshot {
        val sourceSet = sources.toSet()
        lock.withLock { leases.entries.removeAll { it.value.source in sourceSet } }
        return reconcile(clock())
    }

    /** 删除到期租约，并按剩余租约回读系统状态。 */
    fun tick(nowMillis: Long = clock()): HoldLeaseSnapshot = reconcile(nowMillis)

    /** 睡眠前释放断言，但保留租约意图。 */
    fun suspend(): HoldLeaseSnapshot {
        lock.withLock { suspended = true }
        return reconcile(clock())
    }

    /** 唤醒后恢复仍有效的租约。 */
    fun resume(): HoldLeaseSnapshot {
        lock.withLock { suspended = false }
        return reconcile(clock())
    }

    /** 停止引擎时删除全部租约并释放断言。 */
    fun clear(): HoldLeaseSnapshot {
        lock.withLock {
            leases.clear()
            suspended = false
        }
        return reconcile(clock())
    }

    /** 只回读实际断言，不改变租约。 */
    fun refresh(): HoldLeaseSnapshot {
        val desired = lock.withLock { desiredPreventionLocked() }
        val actual = runCatching { sleepController.readIdleSleepPrevention() }
            .getOrDefault(IdleSleepPrevention.UNKNOWN)
        return lock.withLock {
            actualPrevention = actual
            lastError = when {
                actual == IdleSleepPrevention.UNKNOWN -> "Cannot read idle sleep assertion state"
                actual != desired -> "Assertion state mismatch: requested $desired, actual $actual"
                else -> null
            }
            snapshotLocked(desired)
        }
    }

    /** 返回最近一次操作的快照。本方法不执行 I/O。边界使用 [refresh]。 */
    fun currentSnapshot(): HoldLeaseSnapshot = lock.withLock {
        snapshotLocked(desiredPreventionLocked())
    }

    private fun reconcile(nowMillis: Long): HoldLeaseSnapshot {
        val desired = lock.withLock {
            pruneExpiredLocked(nowMillis)
            desiredPreventionLocked()
        }
        val result = runCatching {
            sleepController.applyIdleSleepPrevention(desired)
        }.getOrElse { error ->
            IdleSleepAssertionResult(
                requested = desired,
                actual = IdleSleepPrevention.UNKNOWN,
                success = false,
                error = error.message ?: "Idle sleep assertion request failed",
            )
        }
        val readbackError = when {
            !result.success -> result.error ?: "Idle sleep assertion request failed"
            result.actual != desired -> "Assertion readback mismatch: requested $desired, actual ${result.actual}"
            else -> null
        }
        return lock.withLock {
            actualPrevention = result.actual
            lastError = readbackError
            snapshotLocked(desired)
        }
    }

    private fun pruneExpiredLocked(nowMillis: Long) {
        leases.entries.removeAll { (_, lease) ->
            val expiresAt = lease.expiresAtEpochSeconds
            expiresAt != null && expiresAt * 1_000L <= nowMillis
        }
    }

    private fun desiredPreventionLocked(): IdleSleepPrevention {
        if (suspended) return IdleSleepPrevention.NONE
        val levels = leases.values.map { it.level }
        return when {
            levels.any { it == HoldLeaseLevel.SYSTEM_AND_DISPLAY } -> IdleSleepPrevention.SYSTEM_AND_DISPLAY
            levels.any { it == HoldLeaseLevel.SYSTEM || it == HoldLeaseLevel.CLOSED_LID } ->
                IdleSleepPrevention.SYSTEM
            else -> IdleSleepPrevention.NONE
        }
    }

    private fun snapshotLocked(desired: IdleSleepPrevention): HoldLeaseSnapshot = HoldLeaseSnapshot(
        leases = leases.values.sortedWith(compareBy({ it.createdAtEpochSeconds }, { it.id })),
        desiredPrevention = desired,
        actualPrevention = actualPrevention,
        suspended = suspended,
        lastError = lastError,
    )
}
