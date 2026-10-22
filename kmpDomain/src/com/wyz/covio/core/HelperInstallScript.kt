package com.wyz.covio.core

/**
 * 特权 helper 的安装脚本、卸载脚本与 LaunchDaemon plist。
 *
 * 两端的安装器都调用这里：macOS 宿主的 Swift 版与 Compose 版的 Kotlin 版。
 * 生成的文本逐行一致，所以新版应用能卸掉旧版装上的 helper，反之亦然。
 *
 * 留在各宿主的部分：
 * - 取得管理员权限并运行脚本（Swift 用 `osascript`，Kotlin 同样，但进程 API 不同）。
 * - 读取当前用户的 uid。
 *
 * 脚本以 root 运行。写进 plist 的路径与标签取自 `HelperContract.kt`，
 * 不在这里另写一份字面量。
 */
object HelperInstallScript {
    /**
     * 安装脚本。
     *
     * 除了写文件与 plist，还要重启 LaunchDaemon：
     * 先 `bootout` 再 `bootstrap`，这样旧版进程会被换掉。
     */
    fun installScript(
        executablePath: String,
        uid: String,
        version: String = APP_VERSION,
        clientRequirement: String? = null,
    ): String = buildString {
        val directory = shellEscaped(HELPER_DIRECTORY)
        val allowedUid = shellEscaped(HELPER_ALLOWED_UID_PATH)
        val requirementPath = shellEscaped(HELPER_CLIENT_REQUIREMENT_PATH)
        val versionPath = shellEscaped(HELPER_VERSION_PATH)
        val appPath = shellEscaped(HELPER_APP_PATH_FILE)
        val plistPath = shellEscaped(HELPER_PLIST_PATH)
        append("set -e\n")
        append("install -d -m 0755 '$directory'\n")
        append("chown root:wheel '$directory'\n")
        append("chmod 0755 '$directory'\n")
        append("printf '%s\\n' '${shellEscaped(uid)}' > '$allowedUid'\n")
        append("printf '%s\\n' '${shellEscaped(version)}' > '$versionPath'\n")
        append("printf '%s\\n' '${shellEscaped(executablePath)}' > '$appPath'\n")
        append("chown root:wheel '$allowedUid' '$versionPath' '$appPath'\n")
        append("chmod 0644 '$allowedUid' '$versionPath' '$appPath'\n")
        if (clientRequirement.isNullOrBlank()) {
            append("rm -f '$requirementPath'\n")
        } else {
            append("printf '%s\\n' '${shellEscaped(clientRequirement)}' > '$requirementPath'\n")
            append("chown root:wheel '$requirementPath'\n")
            append("chmod 0644 '$requirementPath'\n")
        }
        append("cat > '$plistPath' <<'PLIST'\n")
        append(plistText(executablePath)).append('\n')
        append("PLIST\n")
        append("chown root:wheel '$plistPath'\n")
        append("chmod 0644 '$plistPath'\n")
        append("/bin/launchctl bootout system '$plistPath' 2>/dev/null || true\n")
        append("/bin/launchctl bootstrap system '$plistPath'\n")
    }

    /**
     * 卸载脚本。
     *
     * 先清 `disablesleep`：helper 删掉之后，这个标志没有任何进程能清，
     * 机器会一直不睡。
     */
    fun uninstallScript(): String = buildString {
        val plistPath = shellEscaped(HELPER_PLIST_PATH)
        append("set -e\n")
        append("/usr/bin/pmset -a disablesleep 0 || true\n")
        append("/bin/launchctl bootout system '$plistPath' 2>/dev/null || true\n")
        append("rm -f '$plistPath'\n")
        append("rm -rf '${shellEscaped(HELPER_DIRECTORY)}'\n")
    }

    /** LaunchDaemon 的 plist。标签与命令行参数都取自共享常量。 */
    fun plistText(executablePath: String): String = """
        |<?xml version="1.0" encoding="UTF-8"?>
        |<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        |<plist version="1.0">
        |<dict>
        |    <key>Label</key>
        |    <string>$HELPER_LAUNCH_DAEMON_LABEL</string>
        |    <key>ProgramArguments</key>
        |    <array>
        |        <string>${xmlEscaped(executablePath)}</string>
        |        <string>$HELPER_ARGUMENT</string>
        |    </array>
        |    <key>RunAtLoad</key>
        |    <true/>
        |    <key>KeepAlive</key>
        |    <true/>
        |    <key>StandardOutPath</key>
        |    <string>${xmlEscaped(HELPER_LOG_PATH)}</string>
        |    <key>StandardErrorPath</key>
        |    <string>${xmlEscaped(HELPER_LOG_PATH)}</string>
        |</dict>
        |</plist>
    """.trimMargin()

    /** 把单引号转成 shell 里的安全写法。 */
    fun shellEscaped(value: String): String = value.replace("'", "'\\''")

    /** 转义 XML 里的五个保留字符。路径里出现 `&` 时 plist 仍然合法。 */
    fun xmlEscaped(value: String): String = value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")

    /**
     * 转义 AppleScript 字符串字面量。回车直接丢掉。
     *
     * 只在把脚本交给 `osascript` 时用。转义规则要跟着上面的脚本走：
     * 脚本里新增反斜杠或引号时，这里也要跟上。
     */
    fun appleScriptEscaped(script: String): String = buildString {
        for (character in script) {
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> Unit
                else -> append(character)
            }
        }
    }
}
