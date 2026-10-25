package com.wyz.covio.app.helper

import com.wyz.covio.core.APP_VERSION
import com.wyz.covio.core.HelperInstallScript

/**
 * 安装与卸载特权 helper。
 *
 * 生成的 shell 脚本与 plist 来自共享模块的 `HelperInstallScript`。
 * SwiftUI 版调用同一份，所以两端使用相同的路径和 plist 契约。
 *
 * **警告：** 安装会用 `osascript` 请求管理员权限。脚本以 root 运行，
 * 会写入 `/Library/LaunchDaemons`。调用前先确认用户已经同意。
 */
object HelperInstaller {
    fun install(executablePath: String, logger: (String) -> Unit = {}): Boolean {
        val script = installScript(executablePath, currentUid(), APP_VERSION)
        logger("Installing privileged helper")
        return runAppleScriptWithAdministrator(script)
    }

    fun uninstall(logger: (String) -> Unit = {}): Boolean {
        val script = uninstallScript()
        logger("Uninstalling privileged helper")
        return runAppleScriptWithAdministrator(script)
    }

    /** 安装脚本。可单独测试，不需要管理员权限。 */
    internal fun installScript(
        executablePath: String,
        uid: String,
        version: String = APP_VERSION,
    ): String = HelperInstallScript.installScript(executablePath, uid, version)

    /** 卸载脚本。 */
    fun uninstallScript(): String = HelperInstallScript.uninstallScript()

    fun plistText(executablePath: String): String = HelperInstallScript.plistText(executablePath)

    private fun runAppleScriptWithAdministrator(shellScript: String): Boolean {
        val process = ProcessBuilder(
            "/usr/bin/osascript",
            "-e",
            "do shell script \"${HelperInstallScript.appleScriptEscaped(shellScript)}\" with administrator privileges",
        ).redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText()
        val exit = process.waitFor()
        if (exit != 0) {
            System.err.println(output)
            return false
        }
        return true
    }

    private fun currentUid(): String =
        ProcessBuilder("/usr/bin/id", "-u").start().inputStream.bufferedReader().readText().trim()
}
