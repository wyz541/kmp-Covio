package com.wyz.covio.domain

/**
 * `Engine` 的互斥锁。
 *
 * `Engine` 的方法会嵌套调用：`reconcilePolicy()` 调 `setLidSleepAvailable()`，
 * 两者都取锁。所以锁必须是可重入的。
 *
 * JVM 用 `synchronized`，它天然可重入。macosArm64 用递归的 pthread 互斥量。
 * 两边语义相同。
 *
 * 验证见 `kmpDomain/test/.../EngineLockTest.kt`。其中一条专门验证嵌套取锁，
 * 写成非递归锁会死锁。
 */
internal expect class EngineLock() {
    fun <T> withLock(block: () -> T): T
}
