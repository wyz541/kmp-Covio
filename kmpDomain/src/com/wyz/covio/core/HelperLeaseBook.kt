package com.wyz.covio.core

/** 当前有效租约的最小视图。 */
data class HelperLeaseSnapshot(
    val activeLeaseIds: List<String> = emptyList(),
    val expiresAtEpochSeconds: Long? = null,
) {
    val activeCount: Int get() = activeLeaseIds.size
    val hasActiveLease: Boolean get() = activeLeaseIds.isNotEmpty()
}

/**
 * helper 进程内的租约账本。
 *
 * 时间只由调用方传入，便于测试与由 helper 统一控制。
 * 本类型不上锁，helper 的串行协调器负责线程安全。
 */
class HelperLeaseBook {
    private val leases = linkedMapOf<String, Long>()

    /**
     * 新增或续租。
     *
     * 返回 false 表示已达到租约上限，调用方必须拒绝请求。
     */
    fun upsert(leaseId: String, nowEpochSeconds: Long, expiresAtEpochSeconds: Long): Boolean {
        if (leaseId.isBlank()) return false
        prune(nowEpochSeconds)
        if (leaseId !in leases && leases.size >= HELPER_LEASE_MAX_ACTIVE) return false
        if (expiresAtEpochSeconds <= nowEpochSeconds) {
            leases.remove(leaseId)
        } else {
            leases[leaseId] = expiresAtEpochSeconds
        }
        return true
    }

    fun release(leaseId: String, nowEpochSeconds: Long): HelperLeaseSnapshot {
        prune(nowEpochSeconds)
        leases.remove(leaseId)
        return snapshot()
    }

    fun prune(nowEpochSeconds: Long): HelperLeaseSnapshot {
        leases.entries.removeAll { (_, expiresAt) -> expiresAt <= nowEpochSeconds }
        return snapshot()
    }

    fun clear(): HelperLeaseSnapshot {
        leases.clear()
        return snapshot()
    }

    fun snapshot(): HelperLeaseSnapshot = HelperLeaseSnapshot(
        activeLeaseIds = leases.keys.sorted(),
        expiresAtEpochSeconds = leases.values.minOrNull(),
    )
}
