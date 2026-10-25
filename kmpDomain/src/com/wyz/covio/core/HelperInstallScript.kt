package com.wyz.covio.core

/**
 * 特权 helper 的安装脚本、卸载脚本与 LaunchDaemon plist。
 *
 * 两端的安装器都调用这里：macOS 宿主的 Swift 版与 Compose 版的 Kotlin 版。
 * 生成文本逐行一致，所以两端不会安装出不同形状的 helper。
 * 新版应用可以移除旧版装上的 helper。
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
        val binaryDirectory = shellEscaped(HELPER_BINARY_DIRECTORY)
        val binaryPath = shellEscaped(HELPER_BINARY_PATH)
        val temporaryBinary = shellEscaped("$HELPER_BINARY_PATH.new")
        val allowedUid = shellEscaped(HELPER_ALLOWED_UID_PATH)
        val requirementPath = shellEscaped(HELPER_CLIENT_REQUIREMENT_PATH)
        val versionPath = shellEscaped(HELPER_VERSION_PATH)
        val appPath = shellEscaped(HELPER_APP_PATH_FILE)
        val plistPath = shellEscaped(HELPER_PLIST_PATH)
        val temporaryPlist = shellEscaped("$HELPER_PLIST_PATH.new")
        append("set -e\n")
        append("install -d -m 0755 '$directory'\n")
        append("chown root:wheel '$directory'\n")
        append("chmod 0755 '$directory'\n")
        append("install -d -m 0755 '$binaryDirectory'\n")
        append("chown root:wheel '$binaryDirectory'\n")
        append("chmod 0755 '$binaryDirectory'\n")
        append("rm -f '$temporaryBinary' '$temporaryPlist'\n")
        append("/usr/bin/ditto '${shellEscaped(executablePath)}' '$temporaryBinary'\n")
        append("chown root:wheel '$temporaryBinary'\n")
        append("chmod 0755 '$temporaryBinary'\n")
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
        append("cat > '$temporaryPlist' <<'PLIST'\n")
        append(plistText(HELPER_BINARY_PATH)).append('\n')
        append("PLIST\n")
        append("chown root:wheel '$temporaryPlist'\n")
        append("chmod 0644 '$temporaryPlist'\n")
        append("/bin/launchctl bootout system '$plistPath' 2>/dev/null || true\n")
        append("mv '$temporaryBinary' '$binaryPath'\n")
        append("mv '$temporaryPlist' '$plistPath'\n")
        append("/bin/launchctl bootstrap system '$plistPath'\n")
    }

    /**
     * 卸载脚本。
     *
     * 充电状态文件存在时拒绝继续。应用必须先恢复原 MCL 策略。否则删除
     * `state.json` 会丢失恢复所需的信息，系统可能一直保留错误的充电目标。
     *
     * 通过检查后先清 `disablesleep`：helper 删掉之后，这个标志没有任何进程能清，
     * 机器会一直不睡。
     */
    fun uninstallScript(): String = buildString {
        val plistPath = shellEscaped(HELPER_PLIST_PATH)
        val binaryDirectory = shellEscaped(HELPER_BINARY_DIRECTORY)
        val statePath = shellEscaped(HELPER_CHARGE_LIMIT_STATE_PATH)
        val runtimePath = shellEscaped(HELPER_CHARGE_LIMIT_RUNTIME_PATH)
        val clientRequirement = shellEscaped(HELPER_CLIENT_REQUIREMENT_PATH)
        val allowedUid = shellEscaped(HELPER_ALLOWED_UID_PATH)
        val versionPath = shellEscaped(HELPER_VERSION_PATH)
        val appPath = shellEscaped(HELPER_APP_PATH_FILE)
        val sleepOwner = shellEscaped(HELPER_SLEEP_OWNER_PATH)
        val socketPath = shellEscaped(HELPER_SOCKET_PATH)
        val logPath = shellEscaped(HELPER_LOG_PATH)
        append("set -e\n")
        append("if [ -e '$statePath' ] || [ -e '$runtimePath' ]; then\n")
        append("  printf '%s\\n' 'Covio charge limit state is still active. Restore it in Covio before uninstalling the helper.' >&2\n")
        append("  exit 1\n")
        append("fi\n")
        append("/usr/bin/pmset -a disablesleep 0 || true\n")
        append("/bin/launchctl bootout system '$plistPath' 2>/dev/null || true\n")
        append("rm -f '$plistPath'\n")
        append("rm -rf '$binaryDirectory'\n")
        append("rm -f '$allowedUid' '$clientRequirement' '$versionPath' '$appPath' '$sleepOwner' '$socketPath' '$logPath'\n")
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
        |    </array>
        |    <key>MachServices</key>
        |    <dict>
        |        <key>$HELPER_XPC_SERVICE_NAME</key>
        |        <true/>
        |    </dict>
        |    <key>RunAtLoad</key>
        |    <true/>
        |    <key>KeepAlive</key>
        |    <true/>
        |    <key>ProcessType</key>
        |    <string>Interactive</string>
        |    <key>ThrottleInterval</key>
        |    <integer>5</integer>
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
