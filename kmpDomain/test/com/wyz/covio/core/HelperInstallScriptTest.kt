package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * 安装文本的钉子。
 *
 * 安装脚本与 plist 是 0.4.2 那份的逐行复制。新版应用要能卸掉旧版装上的 helper，
 * 也要能装成旧版认识的形状，所以这些字符串不能随手改。
 *
 * 这里同时钉住 Label 的来源：它必须取自 `HELPER_LAUNCH_DAEMON_LABEL`。
 * 曾经有一版把它写成字面量，改常量时 plist 不跟着变，launchd 就找不到守护进程。
 */
class HelperInstallScriptTest {
    private val executablePath = "/Applications/Covio.app/Contents/MacOS/Covio"
    private val uid = "501"

    /** `lines()` 会为末尾换行留一个空元素，这里去掉，方便按行断言。 */
    private fun installLines(): List<String> =
        HelperInstallScript.installScript(executablePath, uid, APP_VERSION).trimEnd('\n').lines()

    @Test
    fun `the plist is byte for byte the shipped one`() {
        assertEquals(
            listOf(
                """<?xml version="1.0" encoding="UTF-8"?>""",
                """<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">""",
                """<plist version="1.0">""",
                """<dict>""",
                """    <key>Label</key>""",
                """    <string>$HELPER_LAUNCH_DAEMON_LABEL</string>""",
                """    <key>ProgramArguments</key>""",
                """    <array>""",
                """        <string>$executablePath</string>""",
                """        <string>$HELPER_ARGUMENT</string>""",
                """    </array>""",
                """    <key>RunAtLoad</key>""",
                """    <true/>""",
                """    <key>KeepAlive</key>""",
                """    <true/>""",
                """    <key>StandardOutPath</key>""",
                """    <string>$HELPER_LOG_PATH</string>""",
                """    <key>StandardErrorPath</key>""",
                """    <string>$HELPER_LOG_PATH</string>""",
                """</dict>""",
                """</plist>""",
            ).joinToString("\n"),
            HelperInstallScript.plistText(executablePath),
        )
    }

    /**
     * Label 与 plist 的文件名必须对得上。
     *
     * `verify-helper-cutover.sh` 与 launchd 都按这个标签找守护进程。
     * 两边取自不同常量时，改一个就断。
     */
    @Test
    fun `the label matches the plist file name`() {
        assertEquals("com.wyz.covio.helper", HELPER_LAUNCH_DAEMON_LABEL)
        assertEquals(
            "/Library/LaunchDaemons/$HELPER_LAUNCH_DAEMON_LABEL.plist",
            HELPER_PLIST_PATH,
        )
    }

    @Test
    fun `the install script writes the four files and loads the daemon`() {
        val lines = installLines()

        assertEquals("set -e", lines.first())
        assertTrue(lines.contains("install -d -m 0755 '$HELPER_DIRECTORY'"))
        assertTrue(lines.contains("chown root:wheel '$HELPER_DIRECTORY'"))
        assertTrue(lines.contains("chmod 0755 '$HELPER_DIRECTORY'"))
        assertTrue(lines.contains("""printf '%s\n' '$uid' > '$HELPER_ALLOWED_UID_PATH'"""))
        assertTrue(lines.contains("""printf '%s\n' '$APP_VERSION' > '$HELPER_VERSION_PATH'"""))
        assertTrue(lines.contains("""printf '%s\n' '$executablePath' > '$HELPER_APP_PATH_FILE'"""))
        assertTrue(
            lines.contains(
                "chown root:wheel '$HELPER_ALLOWED_UID_PATH' '$HELPER_VERSION_PATH' '$HELPER_APP_PATH_FILE'",
            ),
        )
        assertTrue(
            lines.contains(
                "chmod 0644 '$HELPER_ALLOWED_UID_PATH' '$HELPER_VERSION_PATH' '$HELPER_APP_PATH_FILE'",
            ),
        )
        assertTrue(lines.contains("cat > '$HELPER_PLIST_PATH' <<'PLIST'"))
        assertTrue(lines.contains("PLIST"))
        assertTrue(lines.contains("chown root:wheel '$HELPER_PLIST_PATH'"))
        assertTrue(lines.contains("chmod 0644 '$HELPER_PLIST_PATH'"))
    }

    @Test
    fun `the install script stores the client signature requirement`() {
        val requirement = "identifier \"com.wyz.covio\" and certificate root = H\"abc\""
        val script = HelperInstallScript.installScript(
            executablePath,
            uid,
            APP_VERSION,
            clientRequirement = requirement,
        )

        assertTrue(
            script.contains("printf '%s\\n' '$requirement' > '$HELPER_CLIENT_REQUIREMENT_PATH'"),
        )
        assertTrue(script.contains("chown root:wheel '$HELPER_CLIENT_REQUIREMENT_PATH'"))
        assertTrue(script.contains("chmod 0644 '$HELPER_CLIENT_REQUIREMENT_PATH'"))
        assertFalse(script.contains("rm -f '$HELPER_CLIENT_REQUIREMENT_PATH'"))
    }

    @Test
    fun `the install script removes a stale client requirement`() {
        val script = HelperInstallScript.installScript(executablePath, uid, APP_VERSION)

        assertTrue(script.contains("rm -f '$HELPER_CLIENT_REQUIREMENT_PATH'"))
    }

    /** 先 bootout 再 bootstrap，否则旧版 helper 会一直占着 socket。 */
    @Test
    fun `the install script boots the old daemon out before bootstrapping`() {
        val lines = installLines()
        val bootout = lines.indexOf("/bin/launchctl bootout system '$HELPER_PLIST_PATH' 2>/dev/null || true")
        val bootstrap = lines.indexOf("/bin/launchctl bootstrap system '$HELPER_PLIST_PATH'")

        assertTrue(bootout >= 0, "安装脚本没有 bootout：$lines")
        assertTrue(bootstrap > bootout, "bootstrap 在 bootout 之前")
        assertEquals(lines[bootstrap], lines.last(), "bootstrap 之后不该还有指令")
    }

    /** 脚本里要有 plist 的正文，否则 launchd 读不到。 */
    @Test
    fun `the install script embeds the whole plist`() {
        val script = HelperInstallScript.installScript(executablePath, uid, APP_VERSION)

        assertTrue(script.contains(HelperInstallScript.plistText(executablePath)))
        assertTrue(script.contains("<string>$HELPER_ARGUMENT</string>"))
    }

    /** 充电状态仍存在时，卸载必须先停下，不能丢失恢复原策略所需的信息。 */
    @Test
    fun `the uninstall script is byte for byte the shipped one`() {
        assertEquals(
            listOf(
                "set -e",
                "if [ -e '$HELPER_CHARGE_LIMIT_STATE_PATH' ] || [ -e '$HELPER_CHARGE_LIMIT_RUNTIME_PATH' ]; then",
                "  printf '%s\\n' 'Covio charge limit state is still active. Restore it in Covio before uninstalling the helper.' >&2",
                "  exit 1",
                "fi",
                "/usr/bin/pmset -a disablesleep 0 || true",
                "/bin/launchctl bootout system '$HELPER_PLIST_PATH' 2>/dev/null || true",
                "rm -f '$HELPER_PLIST_PATH'",
                "rm -rf '$HELPER_DIRECTORY'",
                "",
            ).joinToString("\n"),
            HelperInstallScript.uninstallScript(),
        )
    }

    @Test
    fun `the uninstall guard runs before any cleanup`() {
        val lines = HelperInstallScript.uninstallScript().lines()
        val guard = lines.indexOfFirst { it.startsWith("if [ -e") }
        val sleepCleanup = lines.indexOf("/usr/bin/pmset -a disablesleep 0 || true")
        val stateRemoval = lines.indexOf("rm -rf '$HELPER_DIRECTORY'")

        assertTrue(guard >= 0, "卸载脚本没有充电状态检查：$lines")
        assertTrue(guard < sleepCleanup, "充电状态检查必须在睡眠清理之前")
        assertTrue(guard < stateRemoval, "充电状态检查必须在删除目录之前")
    }

    @Test
    fun `a quote in a path does not break out of the shell string`() {
        val script = HelperInstallScript.installScript("/tmp/it's here/Covio", uid, APP_VERSION)

        assertTrue(script.contains("""'/tmp/it'\''s here/Covio'"""), "单引号没转义：$script")
        assertFalse(script.contains("""'/tmp/it's here/Covio'"""))
    }

    @Test
    fun `an ampersand in a path does not break the plist`() {
        val plist = HelperInstallScript.plistText("/tmp/a&b<c>/Covio")

        assertTrue(plist.contains("<string>/tmp/a&amp;b&lt;c&gt;/Covio</string>"))
    }

    @Test
    fun `the apple script escape handles quotes backslashes and newlines`() {
        assertEquals(
            """echo \"hi\"\n""",
            HelperInstallScript.appleScriptEscaped("echo \"hi\"\n"),
        )
        // 回车丢掉：osascript 的字符串字面量里回车会截断整条命令。
        assertEquals("""a\nb""", HelperInstallScript.appleScriptEscaped("a\r\nb"))
    }
}
