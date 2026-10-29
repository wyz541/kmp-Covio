package com.wyz.covio.core

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath

/**
 * `config.json` 的读写。
 *
 * 两条兼容性约束，来自 0.4.2 的既有行为：
 *
 * 1. 单个键的类型不对时，只有那个键回退到默认值，不影响其它键。
 * 2. 保存时先读回现有 JSON 再合并，所以本版不认识的键会被保留。
 *    两版共存期间这条不能破，否则老版本写的字段会被新版本抹掉。
 *
 * 用 okio 而不是 `java.nio.file`，以便同一份代码跑在 jvm 与 macosArm64 上。
 */
class ConfigStore(
    val path: String = defaultConfigPath(),
    private val fileSystem: FileSystem = FileSystem.SYSTEM,
    private val json: Json = defaultJson(),
) {
    fun load(): AppConfig {
        if (!fileSystem.exists(path.toPath())) {
            val config = AppConfig().normalized()
            save(config)
            return config
        }
        return runCatching {
            val root = json.parseToJsonElement(fileSystem.read(path.toPath()) { readUtf8() }) as? JsonObject
                ?: return@runCatching AppConfig()
            decode(root)
        }.getOrElse { AppConfig() }
    }

    /**
     * 写入配置。保留文件里本版不认识的键。
     *
     * `fileNaming` 是嵌套对象，保存时单独合并它，避免抹掉新版写入的未知子键。
     *
     * **写盘失败不抛异常。** Kotlin 的异常跨到 Swift 没有接收方，
     * 会直接终止进程。磁盘满、目录被删、权限不对都会走到这里。
     * 与 [load] 和 [clear] 一样咽掉：内存里的配置照常生效，只是这一版没落盘。
     */
    fun save(config: AppConfig) {
        val normalized = config.normalized()
        runCatching {
            val target = path.toPath()
            target.parent?.let { fileSystem.createDirectories(it) }

            val existing = runCatching {
                json.parseToJsonElement(fileSystem.read(target) { readUtf8() }) as? JsonObject
            }.getOrNull() ?: JsonObject(emptyMap())

            val encoded = json.encodeToJsonElement(AppConfig.serializer(), normalized) as JsonObject
            val mergedObject = existing.toMutableMap().apply { putAll(encoded) }

            val previousPower = existing["power"] as? JsonObject
            val nextPower = encoded["power"] as? JsonObject
            if (previousPower != null && nextPower != null) {
                mergedObject["power"] = JsonObject(previousPower + nextPower)
            }

            val previousDisplay = existing["display"] as? JsonObject
            val nextDisplay = encoded["display"] as? JsonObject
            if (previousDisplay != null && nextDisplay != null) {
                mergedObject["display"] = JsonObject(previousDisplay + nextDisplay)
            }

            val existingFileNaming = existing["fileNaming"] as? JsonObject
            val encodedFileNaming = encoded["fileNaming"] as? JsonObject
            if (existingFileNaming != null && encodedFileNaming != null) {
                mergedObject["fileNaming"] = JsonObject(existingFileNaming + encodedFileNaming)
            }

            val merged = JsonObject(mergedObject)

            val temporary = temporaryPath(target)
            fileSystem.write(temporary) { writeUtf8(json.encodeToString(JsonObject.serializer(), merged)) }
            fileSystem.atomicMove(temporary, target)
        }
    }

    fun clear(): Boolean = runCatching {
        val target = path.toPath()
        fileSystem.delete(target, mustExist = false)
        fileSystem.delete(temporaryPath(target), mustExist = false)
    }.isSuccess

    private fun temporaryPath(target: Path): Path = target.parent!!.resolve(target.name + ".tmp")

    private fun decode(root: JsonObject): AppConfig {
        val defaults = AppConfig()
        fun bool(name: String, fallback: Boolean): Boolean =
            root[name]?.jsonPrimitive?.booleanOrNull ?: fallback
        fun int(name: String, fallback: Int): Int =
            root[name]?.jsonPrimitive?.intOrNull ?: fallback
        fun long(name: String, fallback: Long): Long =
            root[name]?.jsonPrimitive?.longOrNull ?: fallback
        fun string(name: String, fallback: String): String =
            root[name]?.jsonPrimitive?.contentOrNull ?: fallback
        fun nullableInt(name: String): Int? =
            root[name]?.jsonPrimitive?.intOrNull

        val powerRoot = root["power"] as? JsonObject ?: JsonObject(emptyMap())
        fun powerBool(name: String, fallback: Boolean): Boolean =
            powerRoot[name]?.jsonPrimitive?.booleanOrNull ?: fallback
        fun powerInt(name: String, fallback: Int): Int =
            powerRoot[name]?.jsonPrimitive?.intOrNull ?: fallback
        val powerDefaults = PowerConfig()
        val decodedPower = PowerConfig(
            enabled = powerBool("enabled", powerDefaults.enabled),
            keepAwakeOnAdapter = powerBool("keepAwakeOnAdapter", powerDefaults.keepAwakeOnAdapter),
            keepAwakeOnBattery = powerBool("keepAwakeOnBattery", powerDefaults.keepAwakeOnBattery),
            allowClosedLid = powerBool("allowClosedLid", powerDefaults.allowClosedLid),
            pauseClosedLidWithExternalDisplay = powerBool(
                "pauseClosedLidWithExternalDisplay",
                powerDefaults.pauseClosedLidWithExternalDisplay,
            ),
            batteryFloorPercent = powerInt("batteryFloorPercent", powerDefaults.batteryFloorPercent),
            batteryFloorRecoveryPercent = powerInt(
                "batteryFloorRecoveryPercent",
                powerDefaults.batteryFloorRecoveryPercent,
            ),
            yieldOnLowPowerMode = powerBool("yieldOnLowPowerMode", powerDefaults.yieldOnLowPowerMode),
            heatGuardEnabled = powerBool("heatGuardEnabled", powerDefaults.heatGuardEnabled),
            closedLidTimeCapMinutes = powerInt(
                "closedLidTimeCapMinutes",
                powerDefaults.closedLidTimeCapMinutes,
            ),
            closedLidZeroBrightness = powerBool(
                "closedLidZeroBrightness",
                powerDefaults.closedLidZeroBrightness,
            ),
        )

        val legacyKeepsAwakeOnAdapter = bool(
            "disableLidSleepInCharging",
            defaults.disableLidSleepInCharging,
        )
        val legacyKeepsAwakeOnBattery = bool(
            "disableLidSleepOnBattery",
            defaults.disableLidSleepOnBattery,
        )
        val displayRoot = root["display"] as? JsonObject
        val displayDefaults = DisplayConfig.fromLegacy(
            power = decodedPower,
            keepsAwakeOnAdapter = legacyKeepsAwakeOnAdapter,
            keepsAwakeOnBattery = legacyKeepsAwakeOnBattery,
        )
        val decodedDisplay = displayRoot?.let { display ->
            fun displayBool(name: String, fallback: Boolean): Boolean =
                display[name]?.jsonPrimitive?.booleanOrNull ?: fallback
            fun displayInt(name: String, fallback: Int): Int =
                display[name]?.jsonPrimitive?.intOrNull ?: fallback
            val keepAwakeWhenLidClosed = displayBool(
                "keepAwakeWhenLidClosed",
                displayDefaults.keepAwakeWhenLidClosed,
            )
            val policy = display["closedLidPowerPolicy"]?.let { value ->
                runCatching {
                    json.decodeFromJsonElement(ClosedLidPowerPolicy.serializer(), value)
                }.getOrNull()
            } ?: if (keepAwakeWhenLidClosed) {
                displayDefaults.closedLidPowerPolicy
            } else {
                ClosedLidPowerPolicy.SLEEP
            }
            val mode = display["closedLidDisplayMode"]?.let { value ->
                runCatching {
                    json.decodeFromJsonElement(ClosedLidDisplayMode.serializer(), value)
                }.getOrNull()
            } ?: displayDefaults.closedLidDisplayMode
            DisplayConfig(
                schemaVersion = displayInt("schemaVersion", displayDefaults.schemaVersion),
                keepAwakeWhenLidClosed = keepAwakeWhenLidClosed,
                closedLidPowerPolicy = policy,
                closedLidDisplayMode = mode,
                pauseWhenExternalDisplayConnected = displayBool(
                    "pauseWhenExternalDisplayConnected",
                    displayDefaults.pauseWhenExternalDisplayConnected,
                ),
            )
        }

        return AppConfig(
            schemaVersion = int("schemaVersion", defaults.schemaVersion),
            language = string("language", defaults.language),
            enabled = bool("enabled", defaults.enabled),
            launchAtLogin = bool("launchAtLogin", defaults.launchAtLogin),
            lowBatteryCapacitySleep = bool("lowBatteryCapacitySleep", defaults.lowBatteryCapacitySleep),
            lowBatteryCapacity = int("lowBatteryCapacity", defaults.lowBatteryCapacity),
            lowTimeRemainingMinutes = int("lowTimeRemaining", defaults.lowTimeRemainingMinutes),
            disableIdleSleepInCharging = bool("disableIdleSleepInCharging", defaults.disableIdleSleepInCharging),
            disableLidSleepInCharging = legacyKeepsAwakeOnAdapter,
            disableLidSleepOnBattery = legacyKeepsAwakeOnBattery,
            darkWakeAwarenessEnabled = bool("darkWakeAwarenessEnabled", defaults.darkWakeAwarenessEnabled),
            lidSleepImmediateOnClose = bool("lidSleepImmediateOnClose", defaults.lidSleepImmediateOnClose),
            notificationsEnabled = bool("notificationsEnabled", defaults.notificationsEnabled),
            updateCheckEnabled = bool("updateCheckEnabled", defaults.updateCheckEnabled),
            updateCheckIntervalHours = int("updateCheckIntervalHours", defaults.updateCheckIntervalHours),
            lastUpdateCheckEpochSeconds = long("lastUpdateCheckEpochSeconds", defaults.lastUpdateCheckEpochSeconds),
            hibernateMode = nullableInt("hibernateMode")?.takeIf { it in SUPPORTED_HIBERNATE_MODES },
            firstRun = bool("firstRun", defaults.firstRun),
            shelfEnabled = bool("shelfEnabled", defaults.shelfEnabled),
            screenshotInboxEnabled = bool("screenshotInboxEnabled", defaults.screenshotInboxEnabled),
            shelfSoundsEnabled = bool("shelfSoundsEnabled", defaults.shelfSoundsEnabled),
            clipboardEnabled = bool("clipboardEnabled", defaults.clipboardEnabled),
            clipboardPasteStackHotKey = string("clipboardPasteStackHotKey", defaults.clipboardPasteStackHotKey),
            clipboardCaptureHotKey = string("clipboardCaptureHotKey", defaults.clipboardCaptureHotKey),
            power = decodedPower,
            display = decodedDisplay,
            chargeLimitEnabled = bool("chargeLimitEnabled", defaults.chargeLimitEnabled),
            chargeLimitPercent = int("chargeLimitPercent", defaults.chargeLimitPercent),
            chargeLimitActiveDischarge = bool(
                "chargeLimitActiveDischarge",
                defaults.chargeLimitActiveDischarge,
            ),
            fileNaming = decodeFileNaming(root["fileNaming"], defaults.fileNaming),
        ).normalized()
    }

    /**
     * 文件命名配置是嵌套对象。旧配置没有它，坏掉的字段只回退该字段。
     */
    private fun decodeFileNaming(
        element: JsonElement?,
        fallback: FileNamingPolicy,
    ): FileNamingPolicy {
        val root = element as? JsonObject ?: return fallback
        fun bool(name: String, defaultValue: Boolean): Boolean =
            root[name]?.jsonPrimitive?.booleanOrNull ?: defaultValue
        fun int(name: String, defaultValue: Int): Int =
            root[name]?.jsonPrimitive?.intOrNull ?: defaultValue
        fun double(name: String, defaultValue: Double): Double =
            root[name]?.jsonPrimitive?.doubleOrNull ?: defaultValue
        fun string(name: String, defaultValue: String): String =
            root[name]?.jsonPrimitive?.contentOrNull ?: defaultValue
        fun <T> decoded(name: String, serializer: DeserializationStrategy<T>, defaultValue: T): T =
            root[name]?.let { value ->
                runCatching { json.decodeFromJsonElement(serializer, value) }.getOrNull()
            } ?: defaultValue

        return FileNamingPolicy(
            schemaVersion = int("schemaVersion", fallback.schemaVersion),
            template = string("template", fallback.template),
            maxUTF8Bytes = int("maxUTF8Bytes", fallback.maxUTF8Bytes),
            separator = string("separator", fallback.separator),
            lowercaseLatin = bool("lowercaseLatin", fallback.lowercaseLatin),
            preserveExtension = bool("preserveExtension", fallback.preserveExtension),
            dateSource = decoded("dateSource", FileNamingDateSource.serializer(), fallback.dateSource),
            conflictPolicy = decoded(
                "conflictPolicy",
                FileNamingConflictPolicy.serializer(),
                fallback.conflictPolicy,
            ),
            conflictSuffix = string("conflictSuffix", fallback.conflictSuffix),
            minConfidence = double("minConfidence", fallback.minConfidence),
            requirePreview = bool("requirePreview", fallback.requirePreview),
            allowVision = bool("allowVision", fallback.allowVision),
        ).normalized()
    }

    companion object {
        internal fun defaultJson(): Json = Json {
            prettyPrint = true
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        /**
         * 用本版约定的 Json 设置构造。
         *
         * Swift 侧不能走主构造函数：`json` 与 `fileSystem` 的默认值在 Kotlin 里，
         * 默认参数不导出到 Swift，从 Swift 就得自己拼一个 `Json`。
         * 拼出来的设置可能与这里不一致，那会让两版写出的 `config.json` 不同。
         * 所以统一从这一个入口构造。
         */
        fun create(path: String = defaultConfigPath()): ConfigStore =
            ConfigStore(path = path, fileSystem = FileSystem.SYSTEM, json = defaultJson())

        /**
         * 本版默认配置，等价于 `AppConfig()`。
         *
         * Swift 侧调用 `AppConfig()` 要写全全部参数，默认值又抄不过去。
         * 清除配置时从这一个入口取默认值。
         */
        fun defaults(): AppConfig = AppConfig()
    }
}
