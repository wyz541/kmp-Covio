package com.wyz.covio.core

/**
 * 系统截图偏好的解析与取值规则。
 *
 * 系统截图偏好放在 `com.apple.screencapture` 这个 defaults 域里。
 * 新版只读取截图目录。旧版接管留下的快照仍用同一套解析规则恢复。
 *
 * 跑 `defaults` 命令是 OS 调用，留在各宿主。这里只有文本进来、值出去。
 */
object ScreenshotPreferencePolicy {
    /** `defaults` 子进程的超时，单位毫秒。 */
    const val COMMAND_TIMEOUT_MILLIS = 5_000L

    /** 系统截图偏好的 defaults 域。 */
    const val DOMAIN = "com.apple.screencapture"

    const val KEY_LOCATION = "location"
    const val KEY_LOCATION_SCREENSHOT = "location-screenshot"
    const val KEY_SHOW_THUMBNAIL = "show-thumbnail"

    /**
     * 读一个字符串键。
     *
     * 命令失败或输出为空时返回 null。输出的首尾成对引号去掉。
     */
    fun parseString(exitCode: Int, output: String): String? {
        if (exitCode != 0) return null
        val trimmed = output.trim()
        val unquoted =
            if (trimmed.length >= 2 && trimmed.startsWith("\"") && trimmed.endsWith("\"")) {
                trimmed.substring(1, trimmed.length - 1)
            } else {
                trimmed
            }
        return unquoted.ifEmpty { null }
    }

    /**
     * 读一个布尔键。取值不认识时返回 null，不猜。
     *
     * 「键不存在」与「键的值是 false」是两种结果，调用方靠 null 区分。
     */
    fun parseBoolean(exitCode: Int, output: String): Boolean? {
        if (exitCode != 0) return null
        return when (output.trim().lowercase()) {
            "1", "true", "yes" -> true
            "0", "false", "no" -> false
            else -> null
        }
    }

    /**
     * 快照值换成 `defaults write` 认的字面量。
     *
     * 字符串原样写回。布尔值在快照里存成 "1" 或 "0"，要换成 `-bool` 认的字面量。
     */
    fun writeArgument(value: String, isString: Boolean): String =
        if (isString) value else if (value == "1") "true" else "false"

    /** 删键的成败判断。键本来就不存在时 `defaults delete` 报错，这算还原成功。 */
    fun deleteIsSuccess(exitCode: Int, output: String): Boolean =
        exitCode == 0 || output.contains("does not exist", ignoreCase = true)
}
