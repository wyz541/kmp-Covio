package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * `pmset -g` 设置的断言。取值参照 `PmsetReader` 的既有实现。
 */
class PmsetConfigParserTest {
    /** 真机上 `pmset -g` 有多段，这里是裁剪过的两段。 */
    private val realOutput = """
        System-wide power settings:
        Currently in use:
         lidwake              1
         sleep                10
         hibernatemode        3
         disksleep            10
        AC Power:
         sleep                1
         hibernatemode        3
    """.trimIndent()

    @Test
    fun `minutes come back as seconds`() {
        assertEquals(600L, PmsetConfigParser.sleepTimeoutSeconds(" sleep                10\n"))
    }

    @Test
    fun `the smallest value wins across sections`() {
        assertEquals(60L, PmsetConfigParser.sleepTimeoutSeconds(realOutput))
    }

    @Test
    fun `tabs and leading blanks are accepted`() {
        assertEquals(300L, PmsetConfigParser.sleepTimeoutSeconds("\t  sleep\t5\t\n"))
    }

    @Test
    fun `null input is null`() {
        assertEquals(null, PmsetConfigParser.sleepTimeoutSeconds(null))
    }

    /** 0 表示永不睡眠，不是「立即睡眠」，所以不算超时。 */
    @Test
    fun `zero is not a timeout`() {
        assertEquals(null, PmsetConfigParser.sleepTimeoutSeconds(" sleep                0\n"))
    }

    /** `disksleep` 以 `sleep` 结尾，不能误匹配。 */
    @Test
    fun `a longer key name is not a match`() {
        assertEquals(null, PmsetConfigParser.sleepTimeoutSeconds(" disksleep            10\n"))
    }

    /** macOS 27 的真实键名是 SleepDisabled。 */
    @Test
    fun `sleep disabled accepts the real macOS key and tabs`() {
        val text = """
            System-wide power settings:
             SleepDisabled		0
            Currently in use:
             sleep                0 (sleep prevented by powerd)
        """.trimIndent()

        assertEquals(false, PmsetConfigParser.sleepDisabled(text))
    }

    /** 行尾有注释时不匹配。这是 Swift 版的既有行为，逐字保留。 */
    @Test
    fun `a trailing comment is not a match`() {
        assertEquals(null, PmsetConfigParser.sleepTimeoutSeconds(" sleep                1 (sleep prevented by powerd)\n"))
    }

    @Test
    fun `the hibernate mode comes from the first match`() {
        assertEquals(3, PmsetConfigParser.hibernateMode(realOutput))
    }

    @Test
    fun `a missing hibernate mode is null`() {
        assertEquals(null, PmsetConfigParser.hibernateMode(" sleep                10\n"))
        assertEquals(null, PmsetConfigParser.hibernateMode(null))
    }

    @Test
    fun `disablesleep reads both known values`() {
        assertEquals(true, PmsetConfigParser.sleepDisabled(" disablesleep         1\n"))
        assertEquals(false, PmsetConfigParser.sleepDisabled(" disablesleep         0"))
    }

    @Test
    fun `a missing or invalid disablesleep value is null`() {
        assertEquals(null, PmsetConfigParser.sleepDisabled(" sleep                10\n"))
        assertEquals(null, PmsetConfigParser.sleepDisabled(" disablesleep         yes\n"))
        assertEquals(null, PmsetConfigParser.sleepDisabled(null))
    }

    @Test
    fun `a line without a trailing newline still matches`() {
        assertEquals(120L, PmsetConfigParser.sleepTimeoutSeconds(" sleep                2"))
    }
}
