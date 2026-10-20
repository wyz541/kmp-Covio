package com.wyz.covio.core

import com.wyz.covio.domain.EngineLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okio.FileSystem
import okio.Path.Companion.toPath

/** 电源历史的固定上限。达到上限时先丢最旧的记录。 */
const val POWER_HISTORY_MAX_EVENTS = 200

/** 电源历史的保留天数。页面只显示最近 24 小时。 */
const val POWER_HISTORY_MAX_AGE_DAYS = 7

private const val SECONDS_PER_DAY = 24L * 60 * 60

/** 一类电源事件。字符串只用于持久化，不用于界面文案。 */
@Serializable
enum class PowerHistoryKind {
    ADAPTER_CONNECTED,
    ADAPTER_DISCONNECTED,
    SLEPT,
    DARK_WAKE,
    FULL_WAKE,
    HOLD_STARTED,
    GUARD_RELEASED,
    EXTERNAL_CONFLICT,
    EXTERNAL_CONFLICT_CLEARED,
}

/**
 * 一条电源事件。
 *
 * [detail] 保存诊断信息，例如热状态或唤醒原因。
 * 界面不为它编故事，只显示实际字符串。
 */
@Serializable
data class PowerHistoryEvent(
    @SerialName("id") val id: String,
    @SerialName("kind") val kind: PowerHistoryKind,
    @SerialName("atEpochSeconds") val atEpochSeconds: Long,
    @SerialName("detail") val detail: String = "",
) {
    fun normalized(): PowerHistoryEvent = copy(
        id = id.trim(),
        atEpochSeconds = atEpochSeconds.coerceAtLeast(0L),
        detail = detail.trim(),
    )

    val isUsable: Boolean get() = id.isNotBlank()
}

/** 历史文件的内容。 */
@Serializable
data class PowerHistoryState(
    @SerialName("schemaVersion") val schemaVersion: Int = 1,
    @SerialName("events") val events: List<PowerHistoryEvent> = emptyList(),
) {
    fun normalized(nowEpochSeconds: Long, policy: PowerHistoryPolicy = PowerHistoryPolicy()): PowerHistoryState =
        copy(
            schemaVersion = 1,
            events = PowerHistoryLogic.prune(events, policy, nowEpochSeconds),
        )
}

/** 有界保留策略。 */
data class PowerHistoryPolicy(
    val maxEvents: Int = POWER_HISTORY_MAX_EVENTS,
    val maxAgeDays: Int = POWER_HISTORY_MAX_AGE_DAYS,
) {
    fun normalized(): PowerHistoryPolicy = copy(
        maxEvents = maxEvents.coerceIn(1, 10_000),
        maxAgeDays = maxAgeDays.coerceIn(1, 365),
    )
}

/** 历史事件的纯逻辑。没有 IO。 */
object PowerHistoryLogic {
    fun prune(
        events: List<PowerHistoryEvent>,
        policy: PowerHistoryPolicy,
        nowEpochSeconds: Long,
    ): List<PowerHistoryEvent> {
        val rules = policy.normalized()
        val now = nowEpochSeconds.coerceAtLeast(0L)
        val cutoff = if (now > rules.maxAgeDays.toLong() * SECONDS_PER_DAY) {
            now - rules.maxAgeDays.toLong() * SECONDS_PER_DAY
        } else {
            0L
        }
        return events
            .asSequence()
            .map(PowerHistoryEvent::normalized)
            .filter { it.isUsable && it.atEpochSeconds in cutoff..now }
            .distinctBy(PowerHistoryEvent::id)
            .sortedByDescending(PowerHistoryEvent::atEpochSeconds)
            .take(rules.maxEvents)
            .toList()
    }

    fun recent(
        events: List<PowerHistoryEvent>,
        nowEpochSeconds: Long,
        windowSeconds: Long = SECONDS_PER_DAY,
    ): List<PowerHistoryEvent> {
        val now = nowEpochSeconds.coerceAtLeast(0L)
        val cutoff = (now - windowSeconds.coerceAtLeast(0L)).coerceAtLeast(0L)
        return events
            .asSequence()
            .map(PowerHistoryEvent::normalized)
            .filter { it.isUsable && it.atEpochSeconds in cutoff..now }
            .distinctBy(PowerHistoryEvent::id)
            .sortedByDescending(PowerHistoryEvent::atEpochSeconds)
            .toList()
    }
}

/**
 * 电源历史的持久化。
 *
 * 文件先写 `.tmp`，再原子改名。写失败返回 `null`，不阻塞策略执行。
 */
class PowerHistoryStore(
    val path: String = defaultPowerHistoryPath(),
    private val fileSystem: FileSystem = FileSystem.SYSTEM,
    private val json: Json = defaultJson(),
) {
    private val lock = EngineLock()

    fun load(nowEpochSeconds: Long): PowerHistoryState = lock.withLock {
        loadLocked(nowEpochSeconds)
    }

    /**
     * 追加一条事件，并返回落盘后的完整状态。
     *
     * 返回 `null` 表示写盘失败。内存状态不能冒充落盘成功。
     */
    fun append(
        event: PowerHistoryEvent,
        nowEpochSeconds: Long,
        policy: PowerHistoryPolicy = PowerHistoryPolicy(),
    ): PowerHistoryState? = lock.withLock {
        val normalizedEvent = event.normalized()
        if (!normalizedEvent.isUsable) return@withLock null
        val previous = loadLocked(nowEpochSeconds)
        val next = previous.copy(events = listOf(normalizedEvent) + previous.events)
            .normalized(nowEpochSeconds, policy)
        if (!writeAtomically(json.encodeToString(PowerHistoryState.serializer(), next))) {
            return@withLock null
        }
        next
    }

    /** Swift 不能省略 Kotlin 默认参数，所以给出无策略参数的重载。 */
    fun append(event: PowerHistoryEvent, nowEpochSeconds: Long): PowerHistoryState? =
        append(event = event, nowEpochSeconds = nowEpochSeconds, policy = PowerHistoryPolicy())

    fun clear(): Boolean = lock.withLock {
        runCatching {
            val target = path.toPath()
            fileSystem.delete(target, mustExist = false)
            fileSystem.delete(temporaryPath(target), mustExist = false)
        }.isSuccess
    }

    private fun loadLocked(nowEpochSeconds: Long): PowerHistoryState {
        val state = runCatching {
            val target = path.toPath()
            if (!fileSystem.exists(target)) return@runCatching null
            json.decodeFromString<PowerHistoryState>(fileSystem.read(target) { readUtf8() })
        }.getOrNull() ?: PowerHistoryState()
        return state.normalized(nowEpochSeconds)
    }

    private fun writeAtomically(text: String): Boolean = runCatching {
        val target = path.toPath()
        target.parent?.let { fileSystem.createDirectories(it) }
        val temporary = temporaryPath(target)
        fileSystem.write(temporary) { writeUtf8(text) }
        fileSystem.atomicMove(temporary, target)
    }.isSuccess

    private fun temporaryPath(target: okio.Path): okio.Path =
        target.parent!!.resolve(target.name + ".tmp")

    companion object {
        fun create(path: String): PowerHistoryStore =
            PowerHistoryStore(path = path, fileSystem = FileSystem.SYSTEM, json = defaultJson())

        internal fun defaultJson(): Json = Json {
            prettyPrint = true
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        fun defaultDirectory(): String = "${AppDirectories.support}/Power"

        fun defaultPath(): String = "${defaultDirectory()}/history.json"
    }
}

internal fun defaultPowerHistoryPath(): String = PowerHistoryStore.defaultPath()
