package com.wyz.covio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 电源管理区持久化的用户意图。
 *
 * 本类型只保存规则和阈值。
 * 当前会话、租约和系统观察不进入本类型。
 */
@Serializable
data class PowerConfig(
    @SerialName("enabled") val enabled: Boolean = true,
    @SerialName("keepAwakeOnAdapter") val keepAwakeOnAdapter: Boolean = true,
    @SerialName("keepAwakeOnBattery") val keepAwakeOnBattery: Boolean = false,
    @SerialName("allowClosedLid") val allowClosedLid: Boolean = true,
    @SerialName("pauseClosedLidWithExternalDisplay") val pauseClosedLidWithExternalDisplay: Boolean = true,
    @SerialName("batteryFloorPercent") val batteryFloorPercent: Int = 15,
    @SerialName("batteryFloorRecoveryPercent") val batteryFloorRecoveryPercent: Int = 20,
    @SerialName("yieldOnLowPowerMode") val yieldOnLowPowerMode: Boolean = true,
    @SerialName("heatGuardEnabled") val heatGuardEnabled: Boolean = true,
    @SerialName("closedLidTimeCapMinutes") val closedLidTimeCapMinutes: Int = 240,
) {
    fun normalized(): PowerConfig {
        val floor = batteryFloorPercent.coerceIn(0, 99)
        return copy(
            batteryFloorPercent = floor,
            batteryFloorRecoveryPercent = batteryFloorRecoveryPercent.coerceIn(floor + 1, 100),
            closedLidTimeCapMinutes = closedLidTimeCapMinutes.coerceIn(1, 1_440),
        )
    }

    companion object {
        /** 默认配置。Swift 侧调用主构造函数要写全所有参数，所以留一个入口。 */
        fun defaults(): PowerConfig = PowerConfig()
    }
}

/** macOS 的热状态。未知值不按正常处理。 */
enum class ThermalState {
    NOMINAL,
    FAIR,
    SERIOUS,
    CRITICAL,
    UNKNOWN,
}

/** 一次电源相关的系统观察。所有缺失指标保留为 null。 */
data class PowerObservation(
    val batteryPercent: Int? = null,
    val hasBattery: Boolean? = null,
    val powerState: PowerState = PowerState.UNKNOWN,
    val externalDisplayCount: Int? = null,
    val lidState: LidState = LidState.UNKNOWN,
    val thermalState: ThermalState = ThermalState.UNKNOWN,
    val lowPowerModeEnabled: Boolean? = null,
) {
    fun normalized(): PowerObservation {
        val validPercent = batteryPercent?.takeIf { it in 0..100 }
        return copy(
            batteryPercent = validPercent.takeUnless { hasBattery == false },
            externalDisplayCount = externalDisplayCount?.takeIf { it >= 0 },
        )
    }
}

/**
 * 一次策略求值使用的完整快照。
 *
 * [observation] 来自公开系统 API。
 * [helperStatus]、[sleepDisabled] 和 [covioOwnsSleepDisabled] 来自 helper。
 */
data class PowerSnapshot(
    val observation: PowerObservation = PowerObservation(),
    val helperStatus: HelperStatus = HelperStatus.ERROR,
    val sleepDisabled: Boolean? = null,
    val covioOwnsSleepDisabled: Boolean? = null,
) {
    fun normalized(): PowerSnapshot = copy(observation = observation.normalized())
}

/** 租约来源。来源只用于解释和审计，不改变优先级。 */
enum class HoldLeaseSource {
    MANUAL,
    TIMER,
    RULE,
    AGENT,
    TEST,
}

/**
 * 租约等级。
 *
 * [SYSTEM] 只阻止系统因空闲睡眠。
 * [SYSTEM_AND_DISPLAY] 同时阻止系统与显示器进入空闲睡眠。
 * [CLOSED_LID] 在前两者上增加合盖保持唤醒请求。
 */
enum class HoldLeaseLevel {
    SYSTEM,
    SYSTEM_AND_DISPLAY,
    CLOSED_LID,
}

/**
 * 一个运行时保持唤醒租约。
 *
 * [expiresAtEpochSeconds] 为 null 表示用户手动结束前有效。
 * [createdAtEpochSeconds] 用于合盖安全时长上限。
 */
data class HoldLease(
    val id: String,
    val level: HoldLeaseLevel,
    val source: HoldLeaseSource = HoldLeaseSource.MANUAL,
    val reason: String = "",
    val createdAtEpochSeconds: Long = 0L,
    val expiresAtEpochSeconds: Long? = null,
)

/** Covio 当前持有的空闲睡眠断言。 */
enum class IdleSleepPrevention {
    UNKNOWN,
    NONE,
    SYSTEM,
    SYSTEM_AND_DISPLAY;

    val isActive: Boolean
        get() = this == SYSTEM || this == SYSTEM_AND_DISPLAY
}

/** 一次断言请求与系统回读结果。 */
data class IdleSleepAssertionResult(
    val requested: IdleSleepPrevention,
    val actual: IdleSleepPrevention,
    val success: Boolean,
    val error: String? = null,
)

/** 运行时租约管理器的一次完整视图。 */
data class HoldLeaseSnapshot(
    val leases: List<HoldLease> = emptyList(),
    val desiredPrevention: IdleSleepPrevention = IdleSleepPrevention.NONE,
    val actualPrevention: IdleSleepPrevention = IdleSleepPrevention.UNKNOWN,
    val suspended: Boolean = false,
    val lastError: String? = null,
) {
    val systemSleepPrevented: Boolean
        get() = actualPrevention == IdleSleepPrevention.SYSTEM ||
            actualPrevention == IdleSleepPrevention.SYSTEM_AND_DISPLAY

    val displaySleepPrevented: Boolean
        get() = actualPrevention == IdleSleepPrevention.SYSTEM_AND_DISPLAY
}

/** helper 的合盖租约与系统状态。 */
data class LidLeaseStatus(
    val available: Boolean = false,
    val protocolVersion: String? = null,
    val sleepDisabled: Boolean? = null,
    val covioOwned: Boolean? = null,
    val activeLeaseCount: Int = 0,
    val expiresAtEpochSeconds: Long? = null,
    val error: String? = null,
) {
    val leaseActive: Boolean
        get() = activeLeaseCount > 0 && covioOwned == true
}

/** 阻止保持唤醒的原因。安全原因优先于用户强制模式。 */
enum class SafetyVeto {
    POWER_DISABLED,
    EXPLICITLY_PAUSED,
    BATTERY_FLOOR,
    THERMAL_SERIOUS,
    THERMAL_CRITICAL,
    LOW_POWER_MODE,
    CLOSED_LID_TIME_CAP,
    CLOSED_LID_DISABLED,
    HELPER_UNAVAILABLE,
    BATTERY_STATE_UNKNOWN,
    EXTERNAL_DISPLAY_CONNECTED,
    EXTERNAL_DISPLAY_UNKNOWN,
    SLEEP_DISABLED_STATE_UNKNOWN,
    EXTERNAL_SLEEP_DISABLED_CONFLICT,
}

/** 一次纯策略求值的结果。执行器只执行这里的结果。 */
data class PowerDecision(
    val preventUserIdleSystemSleep: Boolean = false,
    val preventUserIdleDisplaySleep: Boolean = false,
    val preventLidSleep: Boolean = false,
    val appliedLeaseLevel: HoldLeaseLevel? = null,
    val activeLeaseIds: List<String> = emptyList(),
    val automaticRuleApplied: Boolean = false,
    val safetyVetoes: List<SafetyVeto> = emptyList(),
    val batteryGuardLatched: Boolean = false,
) {
    /** 三个动作都关闭时，执行器允许系统按系统设置睡眠。 */
    val sleepAllowed: Boolean
        get() = !preventUserIdleSystemSleep && !preventUserIdleDisplaySleep && !preventLidSleep
}

/**
 * 电源策略的唯一求值入口。
 *
 * 本对象不执行 I/O，也不保存状态。
 * 调用方保存 [PowerDecision.batteryGuardLatched]，下次求值时传回。
 */
object PowerPolicy {
    fun decide(
        config: PowerConfig,
        snapshot: PowerSnapshot,
        leases: List<HoldLease>,
        nowEpochSeconds: Long,
        paused: Boolean = false,
        batteryGuardLatched: Boolean = false,
    ): PowerDecision {
        val normalizedConfig = config.normalized()
        val normalizedSnapshot = snapshot.normalized()
        val observation = normalizedSnapshot.observation
        val nextBatteryGuardLatched = nextBatteryGuardLatched(
            config = normalizedConfig,
            observation = observation,
            previous = batteryGuardLatched,
        )

        if (!normalizedConfig.enabled) {
            return blocked(listOf(SafetyVeto.POWER_DISABLED), nextBatteryGuardLatched)
        }
        if (paused) {
            return blocked(listOf(SafetyVeto.EXPLICITLY_PAUSED), nextBatteryGuardLatched)
        }

        val safetyVetoes = safetyVetoes(normalizedConfig, observation, nextBatteryGuardLatched)
        if (safetyVetoes.isNotEmpty()) {
            return blocked(safetyVetoes, nextBatteryGuardLatched)
        }

        val capReached = leases.any {
            it.level == HoldLeaseLevel.CLOSED_LID &&
                !deadlineReached(it, nowEpochSeconds) &&
                closedLidCapReached(it, normalizedConfig, nowEpochSeconds)
        }
        val activeLeases = leases.filter { isLeaseActive(it, normalizedConfig, nowEpochSeconds) }
        val lidVeto = if (activeLeases.any { it.level == HoldLeaseLevel.CLOSED_LID }) {
            closedLidVeto(normalizedConfig, normalizedSnapshot)
        } else {
            null
        }
        val usableLeases = activeLeases.filterNot { it.level == HoldLeaseLevel.CLOSED_LID && lidVeto != null }
        val appliedLease = usableLeases.maxByOrNull { it.level.ordinal }
        val vetoes = buildList {
            if (capReached) add(SafetyVeto.CLOSED_LID_TIME_CAP)
            if (lidVeto != null) add(lidVeto)
        }

        if (appliedLease != null) {
            return decisionFor(
                level = appliedLease.level,
                activeLeaseIds = activeLeases.map { it.id }.filter { it.isNotBlank() }.distinct(),
                automaticRuleApplied = false,
                safetyVetoes = vetoes,
                batteryGuardLatched = nextBatteryGuardLatched,
            )
        }

        if (automaticRuleApplies(normalizedConfig, observation)) {
            return decisionFor(
                level = HoldLeaseLevel.SYSTEM,
                activeLeaseIds = emptyList(),
                automaticRuleApplied = true,
                safetyVetoes = vetoes,
                batteryGuardLatched = nextBatteryGuardLatched,
            )
        }

        return PowerDecision(
            safetyVetoes = vetoes,
            batteryGuardLatched = nextBatteryGuardLatched,
        )
    }

    private fun safetyVetoes(
        config: PowerConfig,
        observation: PowerObservation,
        batteryGuardLatched: Boolean,
    ): List<SafetyVeto> = buildList {
        if (batteryGuardLatched) add(SafetyVeto.BATTERY_FLOOR)
        if (config.heatGuardEnabled && observation.thermalState == ThermalState.SERIOUS) {
            add(SafetyVeto.THERMAL_SERIOUS)
        }
        if (observation.thermalState == ThermalState.CRITICAL) {
            add(SafetyVeto.THERMAL_CRITICAL)
        }
        if (config.yieldOnLowPowerMode && observation.lowPowerModeEnabled == true) {
            add(SafetyVeto.LOW_POWER_MODE)
        }
    }

    private fun nextBatteryGuardLatched(
        config: PowerConfig,
        observation: PowerObservation,
        previous: Boolean,
    ): Boolean {
        val percent = observation.batteryPercent ?: return false
        if (observation.powerState == PowerState.CHARGING ||
            observation.powerState == PowerState.CHARGED ||
            observation.powerState == PowerState.AC_POWER
        ) {
            return false
        }
        if (percent <= config.batteryFloorPercent) return true
        return previous && percent < config.batteryFloorRecoveryPercent
    }

    private fun closedLidVeto(config: PowerConfig, snapshot: PowerSnapshot): SafetyVeto? {
        val observation = snapshot.observation
        if (!config.allowClosedLid) return SafetyVeto.CLOSED_LID_DISABLED
        if (snapshot.helperStatus != HelperStatus.INSTALLED) return SafetyVeto.HELPER_UNAVAILABLE
        if (observation.hasBattery != false && observation.batteryPercent == null) {
            return SafetyVeto.BATTERY_STATE_UNKNOWN
        }
        if (config.pauseClosedLidWithExternalDisplay) {
            when {
                observation.externalDisplayCount == null -> return SafetyVeto.EXTERNAL_DISPLAY_UNKNOWN
                observation.externalDisplayCount > 0 -> return SafetyVeto.EXTERNAL_DISPLAY_CONNECTED
            }
        }
        return when {
            snapshot.sleepDisabled == null -> SafetyVeto.SLEEP_DISABLED_STATE_UNKNOWN
            snapshot.sleepDisabled && snapshot.covioOwnsSleepDisabled != true -> {
                SafetyVeto.EXTERNAL_SLEEP_DISABLED_CONFLICT
            }
            else -> null
        }
    }

    private fun isLeaseActive(
        lease: HoldLease,
        config: PowerConfig,
        nowEpochSeconds: Long,
    ): Boolean {
        if (lease.id.isBlank()) return false
        if (deadlineReached(lease, nowEpochSeconds)) return false
        if (lease.level == HoldLeaseLevel.CLOSED_LID && closedLidCapReached(lease, config, nowEpochSeconds)) {
            return false
        }
        return true
    }

    private fun deadlineReached(lease: HoldLease, nowEpochSeconds: Long): Boolean {
        val expiresAt = lease.expiresAtEpochSeconds ?: return false
        return expiresAt <= nowEpochSeconds
    }

    private fun closedLidCapReached(
        lease: HoldLease,
        config: PowerConfig,
        nowEpochSeconds: Long,
    ): Boolean {
        if (lease.level != HoldLeaseLevel.CLOSED_LID) return false
        val createdAt = lease.createdAtEpochSeconds
        if (createdAt <= 0L || nowEpochSeconds < createdAt) return true
        return nowEpochSeconds - createdAt >= config.closedLidTimeCapMinutes.toLong() * 60L
    }

    private fun automaticRuleApplies(config: PowerConfig, observation: PowerObservation): Boolean =
        when (observation.powerState) {
            PowerState.DISCHARGING -> config.keepAwakeOnBattery
            PowerState.CHARGING, PowerState.CHARGED, PowerState.AC_POWER -> config.keepAwakeOnAdapter
            PowerState.UNKNOWN -> false
        }

    private fun decisionFor(
        level: HoldLeaseLevel,
        activeLeaseIds: List<String>,
        automaticRuleApplied: Boolean,
        safetyVetoes: List<SafetyVeto>,
        batteryGuardLatched: Boolean,
    ): PowerDecision = PowerDecision(
        preventUserIdleSystemSleep = true,
        preventUserIdleDisplaySleep = level != HoldLeaseLevel.SYSTEM,
        preventLidSleep = level == HoldLeaseLevel.CLOSED_LID,
        appliedLeaseLevel = if (automaticRuleApplied) null else level,
        activeLeaseIds = activeLeaseIds,
        automaticRuleApplied = automaticRuleApplied,
        safetyVetoes = safetyVetoes,
        batteryGuardLatched = batteryGuardLatched,
    )

    private fun blocked(
        safetyVetoes: List<SafetyVeto>,
        batteryGuardLatched: Boolean,
    ): PowerDecision = PowerDecision(
        safetyVetoes = safetyVetoes,
        batteryGuardLatched = batteryGuardLatched,
    )
}
