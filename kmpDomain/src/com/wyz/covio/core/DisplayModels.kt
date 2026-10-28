package com.wyz.covio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 合盖时屏幕采用的行为。
 *
 * [SYSTEM] 表示不启动合盖保持运行，由 macOS 执行默认合盖行为。
 */
@Serializable
enum class ClosedLidDisplayMode {
    @SerialName("system")
    SYSTEM,

    @SerialName("displayOff")
    DISPLAY_OFF,

    @SerialName("blackScreenPipeline")
    BLACK_SCREEN_PIPELINE,
}

/**
 * 屏幕 card 的持久化用户意图。
 *
 * 本类型只保存偏好。
 * 当前屏幕状态、亮度读数和会话租约不进入本类型。
 */
@Serializable
data class DisplayConfig(
    @SerialName("schemaVersion") val schemaVersion: Int = 1,
    @SerialName("keepAwakeWhenLidClosed") val keepAwakeWhenLidClosed: Boolean = true,
    @SerialName("closedLidDisplayMode") val closedLidDisplayMode: ClosedLidDisplayMode = ClosedLidDisplayMode.BLACK_SCREEN_PIPELINE,
    @SerialName("pauseWhenExternalDisplayConnected") val pauseWhenExternalDisplayConnected: Boolean = true,
) {
    fun normalized(): DisplayConfig = copy(schemaVersion = 1)

    companion object {
        fun defaults(): DisplayConfig = DisplayConfig()

        /** 从旧 PowerConfig 推导屏幕配置，保证升级后的行为不变。 */
        fun fromLegacy(power: PowerConfig): DisplayConfig = DisplayConfig(
            keepAwakeWhenLidClosed = power.allowClosedLid,
            closedLidDisplayMode = if (power.closedLidZeroBrightness) {
                ClosedLidDisplayMode.BLACK_SCREEN_PIPELINE
            } else {
                ClosedLidDisplayMode.DISPLAY_OFF
            },
            pauseWhenExternalDisplayConnected = power.pauseClosedLidWithExternalDisplay,
        )
    }
}
