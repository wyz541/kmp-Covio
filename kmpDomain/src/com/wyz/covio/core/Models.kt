package com.wyz.covio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 产品版本号。
 *
 * **这是唯一的版本来源。** Xcode 工程的 `MARKETING_VERSION`、
 * `scripts/create-release.sh` 的标签、helper 的版本比对、更新检查
 * 全部以它为准。0.5.0 是 SwiftUI 宿主成为发布物的那一版。
 */
const val APP_VERSION = "0.5.0"
const val APP_ID = "com.wyz.covio"
const val APP_NAME = "Covio"
val SUPPORTED_HIBERNATE_MODES = setOf(0, 3, 25)

@Serializable
data class AppConfig(
    @SerialName("schemaVersion") val schemaVersion: Int = 3,
    @SerialName("language") val language: String = "",
    @SerialName("enabled") val enabled: Boolean = true,
    @SerialName("launchAtLogin") val launchAtLogin: Boolean = false,
    @SerialName("lowBatteryCapacitySleep") val lowBatteryCapacitySleep: Boolean = true,
    @SerialName("lowBatteryCapacity") val lowBatteryCapacity: Int = 6,
    @SerialName("lowTimeRemaining") val lowTimeRemainingMinutes: Int = 10,
    @SerialName("disableIdleSleepInCharging") val disableIdleSleepInCharging: Boolean = false,
    @SerialName("disableLidSleepInCharging") val disableLidSleepInCharging: Boolean = false,
    @SerialName("disableLidSleepOnBattery") val disableLidSleepOnBattery: Boolean = false,
    @SerialName("darkWakeAwarenessEnabled") val darkWakeAwarenessEnabled: Boolean = true,
    @SerialName("lidSleepImmediateOnClose") val lidSleepImmediateOnClose: Boolean = true,
    @SerialName("notificationsEnabled") val notificationsEnabled: Boolean = true,
    @SerialName("updateCheckEnabled") val updateCheckEnabled: Boolean = true,
    @SerialName("updateCheckIntervalHours") val updateCheckIntervalHours: Int = 24,
    @SerialName("lastUpdateCheckEpochSeconds") val lastUpdateCheckEpochSeconds: Long = 0L,
    @SerialName("hibernateMode") val hibernateMode: Int? = null,
    @SerialName("firstRun") val firstRun: Boolean = true,
    @SerialName("shelfEnabled") val shelfEnabled: Boolean = true,
    @SerialName("screenshotInboxEnabled") val screenshotInboxEnabled: Boolean = true,
    @SerialName("shelfSoundsEnabled") val shelfSoundsEnabled: Boolean = true,
    @SerialName("clipboardEnabled") val clipboardEnabled: Boolean = true,
    @SerialName("clipboardPasteStackHotKey") val clipboardPasteStackHotKey: String = DEFAULT_PASTE_STACK_HOT_KEY,
    @SerialName("clipboardCaptureHotKey") val clipboardCaptureHotKey: String = DEFAULT_CAPTURE_HOT_KEY,
    @SerialName("power") val power: PowerConfig = PowerConfig(),
    @SerialName("chargeLimitEnabled") val chargeLimitEnabled: Boolean = false,
    @SerialName("chargeLimitPercent") val chargeLimitPercent: Int = DEFAULT_CHARGE_LIMIT_PERCENT,
    @SerialName("fileNaming") val fileNaming: FileNamingPolicy = FileNamingPolicy(),
) {
    fun normalized(): AppConfig = copy(
        schemaVersion = 3,
        lowBatteryCapacity = lowBatteryCapacity.coerceIn(0, 100),
        lowTimeRemainingMinutes = lowTimeRemainingMinutes.coerceAtLeast(0),
        updateCheckIntervalHours = updateCheckIntervalHours.coerceIn(1, 168),
        lastUpdateCheckEpochSeconds = lastUpdateCheckEpochSeconds.coerceAtLeast(0L),
        hibernateMode = hibernateMode?.takeIf { it in SUPPORTED_HIBERNATE_MODES },
        clipboardPasteStackHotKey = normalizeHotKeyBinding(clipboardPasteStackHotKey, DEFAULT_PASTE_STACK_HOT_KEY),
        clipboardCaptureHotKey = normalizeHotKeyBinding(clipboardCaptureHotKey, DEFAULT_CAPTURE_HOT_KEY),
        power = power.normalized(),
        chargeLimitPercent = ChargeLimitPolicy.normalizeUpperLimit(chargeLimitPercent),
        fileNaming = fileNaming.normalized(),
    )
}

/** 粘贴栈快捷键的默认写法。格式见 [normalizeHotKeyBinding]。 */
const val DEFAULT_PASTE_STACK_HOT_KEY = "shift+cmd+V"

/** 抓取选中内容快捷键的默认写法。 */
const val DEFAULT_CAPTURE_HOT_KEY = "shift+cmd+C"

/**
 * 快捷键写法的兜底。
 *
 * 只兜长度与空白，不校验键名。合法的键名表在 Swift 侧，这里再抄一份会两边漂移。
 * 认不出的写法由 Swift 回退到默认组合。改键功能要写入的也是这个字符串。
 */
internal fun normalizeHotKeyBinding(value: String, fallback: String): String {
    val trimmed = value.trim()
    return if (trimmed.isEmpty() || trimmed.length > 32) fallback else trimmed
}

enum class PowerState {
    DISCHARGING,
    CHARGING,
    CHARGED,
    AC_POWER,
    UNKNOWN;

    val isCharging: Boolean
        get() = this == CHARGING || this == CHARGED || this == AC_POWER
}

data class BatteryStatus(
    val percent: Int,
    val state: PowerState,
    val remainingSeconds: Long?,
) {
    val isDischarging: Boolean get() = state == PowerState.DISCHARGING
}

enum class LidState { UNKNOWN, OPEN, CLOSED }

enum class HelperStatus { NOT_INSTALLED, INSTALLED, OUTDATED, ERROR }

enum class SleepEvent { WillSleep, WakeSignal }

enum class WakeKind { DARK, FULL }

data class WakeEvent(
    val kind: WakeKind,
    val atEpochSeconds: Long,
    val reason: String = "",
)

data class WakeLogSnapshot(
    val events: List<WakeEvent>,
    val darkWakeCount24h: Int,
) {
    val latest: WakeEvent? get() = events.lastOrNull()
}

data class DarkWakeStatus(
    val available: Boolean = false,
    val scanning: Boolean = false,
    val lastAtEpochSeconds: Long? = null,
    val lastReason: String? = null,
    val count24h: Int = 0,
)

@Serializable
data class ShelfItem(
    @SerialName("path") val path: String,
    @SerialName("addedAtEpochSeconds") val addedAtEpochSeconds: Long = 0L,
) {
    fun normalized(): ShelfItem = copy(
        path = path.trim(),
        addedAtEpochSeconds = addedAtEpochSeconds.coerceAtLeast(0L),
    )
}

@Serializable
data class ScreenshotInboxSnapshot(
    @SerialName("location") val location: String? = null,
    @SerialName("locationScreenshot") val locationScreenshot: String? = null,
    @SerialName("showThumbnail") val showThumbnail: Boolean? = null,
)

@Serializable
data class ShelfStoreState(
    @SerialName("items") val items: List<ShelfItem> = emptyList(),
    @SerialName("revealed") val revealed: Boolean = true,
    @SerialName("preferenceSnapshot") val preferenceSnapshot: ScreenshotInboxSnapshot? = null,
) {
    companion object {
        /**
         * 空状态，等价于 `ShelfStoreState()`。
         *
         * Swift 侧调用主构造函数要写全三个参数，默认值又抄不过去。
         * 首次启动和清除配置时从这一个入口取。
         */
        fun defaults(): ShelfStoreState = ShelfStoreState()
    }
}

/** 剪切板条目的内容类型。 */
@Serializable
enum class ClipKind {
    TEXT,
    LINK,
    IMAGE,
    COLOR,
    FILES,
}

/**
 * 一条剪切板记录。
 *
 * 文本类条目把内容放在 [text]；图片与文件列表类条目把二进制落在磁盘上，
 * 只把路径放在 [filePath]。两者互斥，由 [kind] 决定读哪一个。
 */
@Serializable
data class ClipItem(
    @SerialName("id") val id: String,
    @SerialName("kind") val kind: ClipKind = ClipKind.TEXT,
    @SerialName("text") val text: String = "",
    @SerialName("filePath") val filePath: String = "",
    @SerialName("byteSize") val byteSize: Long = 0L,
    @SerialName("createdAtEpochSeconds") val createdAtEpochSeconds: Long = 0L,
    @SerialName("pinned") val pinned: Boolean = false,
    @SerialName("sourceBundleId") val sourceBundleId: String = "",
) {
    fun normalized(): ClipItem = copy(
        id = id.trim(),
        text = text,
        filePath = filePath.trim(),
        byteSize = byteSize.coerceAtLeast(0L),
        createdAtEpochSeconds = createdAtEpochSeconds.coerceAtLeast(0L),
    )

    /**
     * 判重用的标识。同一个标识只留最新的一条。
     *
     * 文本类看内容本身，图片与文件类看落盘路径。
     */
    val identity: String
        get() = when (kind) {
            ClipKind.IMAGE, ClipKind.FILES -> "f:${ClipboardStore.canonicalPath(filePath)}"
            else -> "t:${text.trim()}"
        }

    /** 正文为空又没有落盘文件的条目是坏数据。 */
    val isUsable: Boolean
        get() = text.isNotBlank() || filePath.isNotBlank()
}

/** 剪切板的保留策略。 */
@Serializable
data class ClipPolicy(
    @SerialName("maxItems") val maxItems: Int = 100,
    @SerialName("maxAgeDays") val maxAgeDays: Int = 7,
    @SerialName("maxTotalBytes") val maxTotalBytes: Long = 200L * 1024 * 1024,
) {
    fun normalized(): ClipPolicy = copy(
        maxItems = maxItems.coerceIn(1, 1000),
        maxAgeDays = maxAgeDays.coerceIn(0, 3650),
        maxTotalBytes = maxTotalBytes.coerceAtLeast(0L),
    )

    companion object {
        /** 默认策略。Swift 侧调主构造函数要写全三个参数，所以留一个入口。 */
        fun defaults(): ClipPolicy = ClipPolicy()
    }
}

/**
 * 剪切板的持久化状态。
 *
 * [pasteStack] 记的是待粘贴顺序，元素是 [ClipItem.id]。
 * [paused] 为真时不再收新条目，已有的照常保留。
 */
@Serializable
data class ClipboardState(
    @SerialName("items") val items: List<ClipItem> = emptyList(),
    @SerialName("pasteStack") val pasteStack: List<String> = emptyList(),
    @SerialName("paused") val paused: Boolean = false,
    @SerialName("policy") val policy: ClipPolicy = ClipPolicy(),
) {
    companion object {
        /** 空状态。理由同 [ShelfStoreState.defaults]。 */
        fun defaults(): ClipboardState = ClipboardState()
    }
}

/** 工作区条目的内容类别。 */
@Serializable
enum class WorkspaceKind {
    FILE,
    IMAGE,
    AUDIO,
    PDF,
    TEXT,
}

/**
 * 条目内容在这台设备上的状态。
 *
 * [LOCAL] 表示本机有完整内容。[REMOTE] 表示只同步了索引，内容还在对端。
 * [FETCHING] 表示正在取回。[EVICTED] 表示内容曾被淘汰，只剩索引。
 */
@Serializable
enum class WorkspaceAvailability {
    LOCAL,
    REMOTE,
    FETCHING,
    EVICTED,
}

/**
 * 工作区的一条条目。
 *
 * [entryId] 是内容摘要的十六进制写法。内容寻址让相同内容天然合并，也让同名不同内容分开。
 * 这是与 [ShelfItem] 的根本差别：晾衣线记录用户原文件的路径，工作区保存自己的副本。
 *
 * [expiresAtEpochSeconds] 为 0 表示不过期。[pinned] 是本机属性，不参与复制。
 * 字段名沿用 [ShelfItem] 与 [ClipItem] 的 `...EpochSeconds` 写法。
 */
@Serializable
data class WorkspaceEntry(
    @SerialName("entryId") val entryId: String,
    @SerialName("kind") val kind: WorkspaceKind = WorkspaceKind.FILE,
    @SerialName("displayName") val displayName: String = "",
    @SerialName("byteSize") val byteSize: Long = 0L,
    @SerialName("contentType") val contentType: String = "",
    @SerialName("createdAtEpochSeconds") val createdAtEpochSeconds: Long = 0L,
    @SerialName("originDeviceId") val originDeviceId: String = "",
    @SerialName("expiresAtEpochSeconds") val expiresAtEpochSeconds: Long = 0L,
    @SerialName("availability") val availability: WorkspaceAvailability = WorkspaceAvailability.LOCAL,
    @SerialName("pinned") val pinned: Boolean = false,
) {
    fun normalized(): WorkspaceEntry = copy(
        entryId = normalizeEntryId(entryId),
        displayName = normalizeDisplayName(displayName),
        byteSize = byteSize.coerceAtLeast(0L),
        contentType = contentType.trim().lowercase(),
        createdAtEpochSeconds = createdAtEpochSeconds.coerceAtLeast(0L),
        originDeviceId = originDeviceId.trim(),
        expiresAtEpochSeconds = expiresAtEpochSeconds.coerceAtLeast(0L),
    )

    /** 摘要不合法的条目是坏数据。合法写法见 [WorkspaceLogic.isValidEntryId]。 */
    val isUsable: Boolean get() = WorkspaceLogic.isValidEntryId(entryId)

    /** 这条条目占用的本机字节数。只同步索引的条目不占空间。 */
    val localBytes: Long
        get() = when (availability) {
            WorkspaceAvailability.LOCAL, WorkspaceAvailability.FETCHING -> byteSize
            WorkspaceAvailability.REMOTE, WorkspaceAvailability.EVICTED -> 0L
        }
}

/** 摘要统一成小写十六进制。比较与落盘都用这一份。 */
internal fun normalizeEntryId(value: String): String = value.trim().lowercase()

/**
 * 展示名只保留文件名。
 *
 * 工作区不保存原始路径：路径会泄露目录结构，跨设备也没有意义。
 * Windows 与 macOS 的分隔符都切掉。
 */
internal fun normalizeDisplayName(value: String): String =
    value.trim().substringAfterLast('/').substringAfterLast('\\').trim()

/**
 * 工作区的保留策略。
 *
 * 保留参数：总上限 5 GB，单条目 2 GB，保留期 30 天。
 * [lazyFetchThresholdBytes] 是「只复制索引」的门槛，超过它的大内容按需取回。
 *
 * [retentionDays] 为 0 表示不过期，与 [ClipPolicy.maxAgeDays] 同一套约定。
 */
@Serializable
data class WorkspacePolicy(
    @SerialName("maxTotalBytes") val maxTotalBytes: Long = 5L * 1024 * 1024 * 1024,
    @SerialName("maxEntryBytes") val maxEntryBytes: Long = 2L * 1024 * 1024 * 1024,
    @SerialName("retentionDays") val retentionDays: Int = 30,
    @SerialName("lazyFetchThresholdBytes") val lazyFetchThresholdBytes: Long = 50L * 1024 * 1024,
) {
    fun normalized(): WorkspacePolicy {
        val total = maxTotalBytes.coerceAtLeast(0L)
        return copy(
            maxTotalBytes = total,
            // 单条目上限不能超过总上限，否则那条永远放不进来。
            maxEntryBytes = maxEntryBytes.coerceIn(0L, total),
            retentionDays = retentionDays.coerceIn(0, 3650),
            lazyFetchThresholdBytes = lazyFetchThresholdBytes.coerceAtLeast(0L),
        )
    }

    companion object {
        /** 默认策略。Swift 侧调主构造函数要写全四个参数，所以留一个入口。 */
        fun defaults(): WorkspacePolicy = WorkspacePolicy()
    }
}

/**
 * 工作区的持久化状态。
 *
 * 与 [ShelfStoreState] 分开存放：晾衣线是用户文件的视图，工作区是自己的副本，
 * 两者的生命周期与清空时机都不同。
 */
@Serializable
data class WorkspaceState(
    @SerialName("schemaVersion") val schemaVersion: Int = 1,
    @SerialName("entries") val entries: List<WorkspaceEntry> = emptyList(),
    @SerialName("policy") val policy: WorkspacePolicy = WorkspacePolicy(),
) {
    companion object {
        /** 空状态。理由同 [ShelfStoreState.defaults]。 */
        fun defaults(): WorkspaceState = WorkspaceState()
    }
}

/**
 * 一条删除标记。
 *
 * 条目删掉之后留一条标记，拦住对端把它重新复制回来（方案第 7.7 节）。
 * 删除标记单独存放在 `tombstones.json` 里，布局见方案第 1.3 节。
 * 保留期见 [WorkspaceLogic.TOMBSTONE_RETENTION_DAYS]。
 *
 * [deletedAtEpochSeconds] 是本机删除的时间。时钟不一致时以本机为准：
 * 标记只需要说明「这条删过」，不需要精确顺序。
 */
@Serializable
data class WorkspaceTombstone(
    @SerialName("entryId") val entryId: String,
    @SerialName("deletedAtEpochSeconds") val deletedAtEpochSeconds: Long = 0L,
) {
    fun normalized(): WorkspaceTombstone = copy(
        entryId = normalizeEntryId(entryId),
        deletedAtEpochSeconds = deletedAtEpochSeconds.coerceAtLeast(0L),
    )

    /** 摘要不合法的标记是坏数据，与 [WorkspaceEntry.isUsable] 同一套判断。 */
    val isUsable: Boolean get() = WorkspaceLogic.isValidEntryId(entryId)
}

data class ShelfState(
    val items: List<ShelfItem> = emptyList(),
    val visible: Boolean = false,
    val revealed: Boolean = true,
    val takeoverActive: Boolean = false,
)

data class ShelfSettings(
    val shelfEnabled: Boolean = true,
    val screenshotInboxEnabled: Boolean = true,
    val shelfSoundsEnabled: Boolean = true,
)

data class UpdateInfo(
    val version: String,
    val title: String,
    val releaseUrl: String,
    val publishedAt: String = "",
)

data class AppState(
    val battery: BatteryStatus? = null,
    val lid: LidState = LidState.UNKNOWN,
    val enabled: Boolean = true,
    val idleSleepAvailable: Boolean = true,
    val lidSleepAvailable: Boolean = true,
    val idleCancelRemainingSeconds: Long? = null,
    val lidCancelRemainingSeconds: Long? = null,
    val darkWake: DarkWakeStatus = DarkWakeStatus(),
    val shelf: ShelfState = ShelfState(),
    val helperStatus: HelperStatus = HelperStatus.NOT_INSTALLED,
    val lastError: String? = null,
)

@Serializable
data class HelperReply(
    val version: String,
    val requestId: String,
    val ok: Boolean,
    val result: Map<String, String>? = null,
    val error: String? = null,
)

@Serializable
data class HelperRequest(
    val version: String,
    val requestId: String,
    val command: String,
    val payload: Map<String, String> = emptyMap(),
)
