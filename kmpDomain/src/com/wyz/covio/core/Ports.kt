package com.wyz.covio.core

fun interface StateListener {
    fun onState(state: AppState)
}

interface PowerSource {
    fun read(): BatteryStatus?
    fun subscribe(listener: () -> Unit)
    fun stop()
}

/**
 * 电源策略需要的系统观察端口。
 *
 * 本端口不读取 helper 状态。
 * 上层把结果与 helper 状态组装为 [PowerSnapshot]。
 */
interface PowerObservationSource {
    fun read(): PowerObservation
    fun subscribe(listener: () -> Unit)
    fun stop()
}

interface LidSensor {
    fun read(): LidState
    fun subscribe(listener: (LidState) -> Unit)
    fun stop()
}

interface IdleSensor {
    fun idleSeconds(): Long
}

interface SleepController {
    fun sleep()
    fun displaySleep()

    /**
     * 设置空闲睡眠断言，并回读系统实际状态。
     *
     * 屏幕断言已经阻止系统空闲睡眠。
     * 因此 [IdleSleepPrevention.SYSTEM_AND_DISPLAY] 只创建屏幕断言。
     */
    fun applyIdleSleepPrevention(prevention: IdleSleepPrevention): IdleSleepAssertionResult

    /** 回读 Covio 自己的断言。无法确认时返回 [IdleSleepPrevention.UNKNOWN]。 */
    fun readIdleSleepPrevention(): IdleSleepPrevention

    fun systemIdleSleepTimeoutSeconds(): Long?
}

interface SleepWatcher {
    fun subscribe(listener: (SleepEvent) -> Unit)
    fun stop()
}

fun interface WakeLogReader {
    fun read(): WakeLogSnapshot?
}

interface PrivilegedOps {
    fun isInstalled(): Boolean
    fun status(): HelperStatus
    fun helperVersion(): String?
    fun install(): Boolean
    fun uninstall(): Boolean
    fun setDisableSleep(disabled: Boolean): Boolean
    fun lidLeaseStatus(): LidLeaseStatus
    fun hibernateMode(): Int?
    fun setHibernateMode(mode: Int): Boolean
}

interface LoginItem {
    fun isEnabled(): Boolean
    fun enable(): Boolean
    fun disable(): Boolean
}

interface UpdateChecker {
    fun latestRelease(): UpdateInfo?
}

interface Notifier {
    fun notify(title: String, subtitle: String = "", message: String = "", releaseUrl: String? = null)
}

interface AppLogger {
    fun info(message: String)
    fun warn(message: String, error: Throwable? = null)
    fun error(message: String, error: Throwable? = null)
    fun logFile(): String
}

fun interface ConfigChanged {
    fun onChanged(config: AppConfig)
}
