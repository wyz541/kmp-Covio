package com.wyz.covio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** 合盖时保持系统运行采用的电源条件。 */
@Serializable
enum class ClosedLidPowerPolicy {
    @SerialName("sleep")
    SLEEP,

    @SerialName("adapter")
    ADAPTER,

    @SerialName("battery")
    BATTERY,

    @SerialName("any")
    ANY;

    val keepsAwake: Boolean
        get() = this != SLEEP

    val keepsAwakeOnAdapter: Boolean
        get() = this == ADAPTER || this == ANY

    val keepsAwakeOnBattery: Boolean
        get() = this == BATTERY || this == ANY

    fun appliesTo(powerState: PowerState): Boolean = when {
        powerState == PowerState.DISCHARGING -> keepsAwakeOnBattery
        powerState == PowerState.CHARGING ||
            powerState == PowerState.CHARGED ||
            powerState == PowerState.AC_POWER -> keepsAwakeOnAdapter
        else -> false
    }

    companion object {
        /** 把旧版布尔规则收敛成一个互斥策略。 */
        fun resolve(
            keepAwakeWhenLidClosed: Boolean,
            keepsAwakeOnAdapter: Boolean,
            keepsAwakeOnBattery: Boolean,
        ): ClosedLidPowerPolicy {
            if (!keepAwakeWhenLidClosed) return SLEEP
            return when {
                keepsAwakeOnAdapter && keepsAwakeOnBattery -> ANY
                keepsAwakeOnBattery -> BATTERY
                else -> ADAPTER
            }
        }
    }
}

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
    @SerialName("schemaVersion") val schemaVersion: Int = 2,
    // 旧版字段只作兼容镜像；新逻辑以 closedLidPowerPolicy 为准。
    @SerialName("keepAwakeWhenLidClosed") val keepAwakeWhenLidClosed: Boolean = true,
    @SerialName("closedLidPowerPolicy") val closedLidPowerPolicy: ClosedLidPowerPolicy = ClosedLidPowerPolicy.ADAPTER,
    @SerialName("closedLidDisplayMode") val closedLidDisplayMode: ClosedLidDisplayMode = ClosedLidDisplayMode.BLACK_SCREEN_PIPELINE,
    @SerialName("pauseWhenExternalDisplayConnected") val pauseWhenExternalDisplayConnected: Boolean = true,
) {
    fun normalized(): DisplayConfig = copy(
        schemaVersion = 2,
        keepAwakeWhenLidClosed = closedLidPowerPolicy.keepsAwake,
    )

    companion object {
        fun defaults(): DisplayConfig = DisplayConfig()

        /** 从旧 PowerConfig 推导屏幕配置，保证升级后的行为不变。 */
        fun fromLegacy(
            power: PowerConfig,
            keepsAwakeOnAdapter: Boolean = false,
            keepsAwakeOnBattery: Boolean = false,
        ): DisplayConfig {
            val policy = ClosedLidPowerPolicy.resolve(
                keepAwakeWhenLidClosed = power.allowClosedLid,
                keepsAwakeOnAdapter = keepsAwakeOnAdapter,
                keepsAwakeOnBattery = keepsAwakeOnBattery,
            )
            return DisplayConfig(
                schemaVersion = 2,
                keepAwakeWhenLidClosed = policy.keepsAwake,
                closedLidPowerPolicy = policy,
                closedLidDisplayMode = if (power.closedLidZeroBrightness) {
                    ClosedLidDisplayMode.BLACK_SCREEN_PIPELINE
                } else {
                    ClosedLidDisplayMode.DISPLAY_OFF
                },
                pauseWhenExternalDisplayConnected = power.pauseClosedLidWithExternalDisplay,
            )
        }
    }
}
