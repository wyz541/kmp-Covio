package com.wyz.covio.core

/**
 * `pmset -g` 当前设置的解析。
 *
 * 与 [PmsetWakeLogParser] 并列：那个解析 `pmset -g log` 的唤醒记录，
 * 这个读 `pmset -g` 的当前设置。
 *
 * 跑 `pmset` 是 OS 调用，留在各宿主。文本进，值出。
 */
object PmsetConfigParser {
    private val SLEEP_PATTERN = Regex("""^\s*sleep\s+(\d+)\s*$""", RegexOption.MULTILINE)
    private val HIBERNATE_MODE_PATTERN =
        Regex("""^\s*hibernatemode\s+(\d+)\s*$""", RegexOption.MULTILINE)
    private val DISABLE_SLEEP_PATTERN =
        Regex("""(?im)^\s*(?:disablesleep|sleepdisabled)\s+([01])\s*$""")

    /**
     * 系统空闲睡眠超时，单位秒。
     *
     * `pmset -g` 的输出可能有多段，取最小的那个 `sleep` 值。
     * 读不到、或者值为 0 时返回 null。0 表示永不睡眠，不是超时。
     */
    fun sleepTimeoutSeconds(text: String?): Long? {
        if (text == null) return null
        val smallest = SLEEP_PATTERN.findAll(text)
            .mapNotNull { it.groupValues[1].toLongOrNull() }
            .minOrNull()
            ?: return null
        val seconds = smallest * 60
        return if (seconds > 0) seconds else null
    }

    /** 当前休眠模式。输出不含该键时返回 null。取第一个匹配。 */
    fun hibernateMode(text: String?): Int? {
        if (text == null) return null
        return HIBERNATE_MODE_PATTERN.find(text)?.groupValues?.get(1)?.toIntOrNull()
    }

    /** 当前 `disablesleep` 值。输出不含该键时返回 null。取第一个匹配。 */
    fun sleepDisabled(text: String?): Boolean? {
        if (text == null) return null
        return when (DISABLE_SLEEP_PATTERN.find(text)?.groupValues?.get(1)) {
            "0" -> false
            "1" -> true
            else -> null
        }
    }
}
