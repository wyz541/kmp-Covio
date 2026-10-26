package com.wyz.covio.core

/** 充电上限的最小值。 */
const val CHARGE_LIMIT_MIN_PERCENT = 40

/** 充电上限的最大值。 */
const val CHARGE_LIMIT_MAX_PERCENT = 100

/** UI 与配置使用的充电上限步长。 */
const val CHARGE_LIMIT_STEP_PERCENT = 5

/** 从上限回到恢复充电所需的电量差。 */
const val CHARGE_LIMIT_HYSTERESIS_PERCENT = 5

/** 最低恢复阈值。上限为 40% 时，从 35% 恢复充电。 */
const val CHARGE_LIMIT_MIN_RESUME_PERCENT = 35

/** 首次启用时的默认上限。 */
const val DEFAULT_CHARGE_LIMIT_PERCENT = 70

/** MCL 能力探测结果。 */
enum class ChargeLimitSupport {
    SUPPORTED,
    UNSUPPORTED,
    UNKNOWN,
}

/** 充电上限策略对外状态。 */
enum class ChargeLimitPhase {
    OFF,
    NO_BATTERY,
    UNPLUGGED,
    APPLYING,
    DISCHARGING,
    STOPPING_DISCHARGE,
    CHARGING,
    SAILING,
    HOLDING,
    ABOVE_LIMIT,
    FULL,
    CALIBRATION,
    SYSTEM_PROTECTION,
    CONFLICT,
    ERROR,
    UNSUPPORTED,
    HELPER_MISSING,
}

/** helper 下一步要执行的写入动作。 */
enum class ChargeLimitAction {
    NONE,
    SET_TARGET,
    RELEASE_TARGET,
}

/**
 * 策略输入。OS 读取与 helper 调用留在宿主，这个数据类只承载结论所需的事实。
 *
 * [currentPercent] 必须是电池包的原始 state of charge。界面显示值可能四舍五入，
 * 直接拿来写 MCL 会让系统把电池主动放电到更低的目标。
 */
data class ChargeLimitObservation(
    val enabled: Boolean,
    val upperLimitPercent: Int,
    val adapterConnected: Boolean,
    val currentPercent: Int?,
    val helperInstalled: Boolean = true,
    val support: ChargeLimitSupport = ChargeLimitSupport.SUPPORTED,
    val batteryPresent: Boolean = true,
    val isCharged: Boolean = false,
    val calibrationActive: Boolean = false,
    val systemProtectionActive: Boolean = false,
    val conflict: Boolean = false,
    val errorMessage: String? = null,
    val observedTargetPercent: Int? = null,
    val writePending: Boolean = false,
    val bypassEngaged: Boolean = false,
    val activeDischargeEnabled: Boolean = false,
    val activelyDischarging: Boolean = false,
)

/** 需要跨一次判定保存的输入。 */
data class ChargeLimitPolicyState(
    val chargingLatch: Boolean = false,
)

/** 一次策略判定的结果。 */
data class ChargeLimitDecision(
    val phase: ChargeLimitPhase,
    val action: ChargeLimitAction = ChargeLimitAction.NONE,
    val targetPercent: Int? = null,
    val resumeThresholdPercent: Int = 0,
    val chargingLatch: Boolean = false,
    val bypassEngaged: Boolean = false,
    val errorMessage: String? = null,
)

/**
 * 充电上限的纯状态机。
 *
 * 状态机不读取系统，也不写系统。宿主把观察值交给 [evaluate]，再执行返回的动作。
 * helper 负责把动作去重、节流和校验；本对象只保证同一组输入得到同一组输出。
 */
object ChargeLimitPolicy {
    /** 判断上限是否合法。合法值必须在 40 到 100 之间，并能被 5 整除。 */
    fun isValidUpperLimit(percent: Int): Boolean =
        percent in CHARGE_LIMIT_MIN_PERCENT..CHARGE_LIMIT_MAX_PERCENT &&
            percent % CHARGE_LIMIT_STEP_PERCENT == 0

    /**
     * 规范化保存的上限。
     *
     * 旧配置没有这个键，或磁盘里出现非法值时，回到 70%。不把非法值静默夹到
     * 最近档位，避免用户看到一个未主动选择的策略。
     */
    fun normalizeUpperLimit(percent: Int): Int =
        percent.takeIf(::isValidUpperLimit) ?: DEFAULT_CHARGE_LIMIT_PERCENT

    /** 恢复充电的阈值。 */
    fun resumeThreshold(upperLimitPercent: Int): Int =
        maxOf(CHARGE_LIMIT_MIN_RESUME_PERCENT, upperLimitPercent - CHARGE_LIMIT_HYSTERESIS_PERCENT)

    /**
     * 计算当前策略状态。
     *
     * 规则顺序很重要。系统保护、校准、helper 失败都先于正常充电判定，
     * 防止 Covio 在系统已经接管时继续写 MCL。
     */
    fun evaluate(
        observation: ChargeLimitObservation,
        previous: ChargeLimitPolicyState = ChargeLimitPolicyState(),
    ): ChargeLimitDecision {
        val upper = observation.upperLimitPercent
        val resume = if (isValidUpperLimit(upper)) resumeThreshold(upper) else 0
        fun decision(
            phase: ChargeLimitPhase,
            latch: Boolean = previous.chargingLatch,
            action: ChargeLimitAction = ChargeLimitAction.NONE,
            targetPercent: Int? = null,
            errorMessage: String? = null,
        ) = ChargeLimitDecision(
            phase = phase,
            action = action,
            targetPercent = targetPercent,
            resumeThresholdPercent = resume,
            chargingLatch = latch,
            errorMessage = errorMessage,
        )

        if (!isValidUpperLimit(upper)) {
            return decision(ChargeLimitPhase.ERROR, errorMessage = "充电上限必须是 40 到 100 之间的 5% 档位")
        }
        if (!observation.enabled) return decision(ChargeLimitPhase.OFF, latch = false)
        if (!observation.helperInstalled) return decision(ChargeLimitPhase.HELPER_MISSING)
        if (observation.support == ChargeLimitSupport.UNSUPPORTED) {
            return decision(ChargeLimitPhase.UNSUPPORTED)
        }
        if (observation.support == ChargeLimitSupport.UNKNOWN) {
            return decision(ChargeLimitPhase.ERROR, errorMessage = "无法确认 MCL 能力")
        }
        if (observation.errorMessage != null) {
            return decision(ChargeLimitPhase.ERROR, errorMessage = observation.errorMessage)
        }
        if (!observation.batteryPresent) return decision(ChargeLimitPhase.NO_BATTERY, latch = false)
        if (observation.systemProtectionActive) {
            return decision(ChargeLimitPhase.SYSTEM_PROTECTION)
        }
        if (observation.calibrationActive) return decision(ChargeLimitPhase.CALIBRATION)
        if (observation.currentPercent == null) {
            return decision(ChargeLimitPhase.ERROR, errorMessage = "无法读取电池电量")
        }
        if (!observation.adapterConnected) {
            return decision(ChargeLimitPhase.UNPLUGGED, latch = false)
        }
        if (observation.conflict) return decision(ChargeLimitPhase.CONFLICT)

        val current = observation.currentPercent.coerceIn(0, 100)
        val raw = if (upper == CHARGE_LIMIT_MAX_PERCENT) {
            evaluateFullCharge(observation, current, ::decision)
        } else {
            evaluateLimitedCharge(
                observation,
                current,
                upper,
                resume,
                previous.chargingLatch,
                observation.activeDischargeEnabled,
                ::decision,
            )
        }

        val action = when {
            observation.writePending -> ChargeLimitAction.NONE
            raw.action == ChargeLimitAction.RELEASE_TARGET -> {
                if (observation.observedTargetPercent == null) ChargeLimitAction.NONE
                else ChargeLimitAction.RELEASE_TARGET
            }
            raw.action == ChargeLimitAction.SET_TARGET -> {
                if (observation.observedTargetPercent == raw.targetPercent) ChargeLimitAction.NONE
                else ChargeLimitAction.SET_TARGET
            }
            else -> ChargeLimitAction.NONE
        }
        val phase = if (observation.writePending || action != ChargeLimitAction.NONE) {
            ChargeLimitPhase.APPLYING
        } else {
            raw.phase
        }
        val bypass = observation.bypassEngaged && phase in HOLDING_PHASES
        return raw.copy(
            phase = phase,
            action = action,
            bypassEngaged = bypass,
        )
    }

    private fun evaluateFullCharge(
        observation: ChargeLimitObservation,
        current: Int,
        decision: (ChargeLimitPhase, Boolean, ChargeLimitAction, Int?, String?) -> ChargeLimitDecision,
    ): ChargeLimitDecision {
        val full = observation.isCharged || current >= CHARGE_LIMIT_MAX_PERCENT
        return decision(
            if (full) ChargeLimitPhase.FULL else ChargeLimitPhase.CHARGING,
            false,
            ChargeLimitAction.RELEASE_TARGET,
            null,
            null,
        )
    }

    private fun evaluateLimitedCharge(
        observation: ChargeLimitObservation,
        current: Int,
        upper: Int,
        resume: Int,
        latch: Boolean,
        activeDischargeEnabled: Boolean,
        decision: (ChargeLimitPhase, Boolean, ChargeLimitAction, Int?, String?) -> ChargeLimitDecision,
    ): ChargeLimitDecision {
        if (current > upper) {
            val target = if (activeDischargeEnabled) upper else current
            val phase = when {
                activeDischargeEnabled -> ChargeLimitPhase.DISCHARGING
                observation.activelyDischarging -> ChargeLimitPhase.STOPPING_DISCHARGE
                else -> ChargeLimitPhase.ABOVE_LIMIT
            }
            return decision(phase, false, ChargeLimitAction.SET_TARGET, target, null)
        }
        if (current == upper) {
            return decision(ChargeLimitPhase.HOLDING, false, ChargeLimitAction.SET_TARGET, current, null)
        }
        if (latch) {
            return decision(ChargeLimitPhase.CHARGING, true, ChargeLimitAction.SET_TARGET, upper, null)
        }
        if (current <= resume) {
            return decision(ChargeLimitPhase.CHARGING, true, ChargeLimitAction.SET_TARGET, upper, null)
        }
        return decision(ChargeLimitPhase.SAILING, false, ChargeLimitAction.SET_TARGET, current, null)
    }

    private val HOLDING_PHASES = setOf(
        ChargeLimitPhase.SAILING,
        ChargeLimitPhase.HOLDING,
        ChargeLimitPhase.ABOVE_LIMIT,
    )
}
