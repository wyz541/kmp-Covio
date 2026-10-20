package com.wyz.covio.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * 特权 helper 的线上协议：编解码、校验与回复构造。
 *
 * 两端的 helper 都调用这里：macOS 宿主的 Swift 版与 Compose 版的 Kotlin 版。
 * 协议只有一份实现，两侧不可能漂移。
 *
 * 分成三类：
 * - 协议值（socket 上限、权限位、命令名）在这里定义。
 * - 套接字读写与进程启动是 OS 调用，留在各宿主。
 * - 路径、版本号与命令白名单在 `HelperContract.kt`。
 *
 * 错误文案是线上契约。客户端按文案判断失败原因，
 * 所以下面这些字符串要逐字保留，改字等于改协议。
 */
object HelperWire {
    /** 单条请求的字节上限。超过就断开，防止内存被撑爆。 */
    const val MAX_REQUEST_BYTES = 64 * 1024

    /** 单条回复的字节上限。客户端按它读回包。 */
    const val MAX_REPLY_BYTES = 64 * 1024

    /** socket 文件的权限位 `0666`。任意用户可连，uid 校验在连接后做。 */
    const val SOCKET_PERMISSIONS = 0x1B6

    const val COMMAND_VERSION = "version"
    const val COMMAND_SET_DISABLE_SLEEP = "setDisableSleep"
    const val COMMAND_SET_HIBERNATE_MODE = "setHibernateMode"
    const val COMMAND_CHARGE_LIMIT_STATUS = "chargeLimitStatus"
    const val COMMAND_CHARGE_LIMIT_CONFIGURE = "chargeLimitConfigure"
    const val COMMAND_CHARGE_LIMIT_RESTORE = "chargeLimitRestore"

    /**
     * 线上 JSON 的形状。
     *
     * 三个开关都是为了对齐 0.4.2 已经发出的字节：
     * - `ignoreUnknownKeys`：新版客户端加字段后，旧版 helper 还要能读。
     * - `encodeDefaults = false`：空 `payload` 不写出来。
     * - `explicitNulls = false`：`result` 与 `error` 为 null 时整个键不写。
     */
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
        explicitNulls = false
    }

    // MARK: 编解码

    /**
     * 编码一条请求。
     *
     * 不会失败：`HelperRequest` 是固定形状的可序列化类型，没有自定义序列化器。
     */
    fun encodeRequest(request: HelperRequest): String = json.encodeToString(request)

    fun decodeRequest(line: String): HelperRequest? =
        runCatching { json.decodeFromString<HelperRequest>(line) }.getOrNull()

    /** 编码一条回复。同 [encodeRequest]，不会失败。 */
    fun encodeReply(reply: HelperReply): String = json.encodeToString(reply)

    fun decodeReply(line: String): HelperReply? =
        runCatching { json.decodeFromString<HelperReply>(line) }.getOrNull()

    // MARK: 回复构造

    /**
     * 成功回复。
     *
     * `result` 为空时不写出这个键。空对象不携带信息，
     * 省略它与写出 `{}` 对客户端等价。
     */
    fun success(requestId: String, result: Map<String, String> = emptyMap()): HelperReply =
        HelperReply(HELPER_PROTOCOL_VERSION, requestId, true, result.ifEmpty { null }, null)

    fun failure(requestId: String, message: String): HelperReply =
        HelperReply(HELPER_PROTOCOL_VERSION, requestId, false, null, message)

    fun versionReply(requestId: String): HelperReply =
        success(requestId, mapOf("version" to APP_VERSION))

    // MARK: 校验

    /**
     * 校验一条请求。返回 null 表示通过，否则返回拒绝原因。
     *
     * 只检查协议层：版本、请求号、命令白名单与命令自己的取值。
     * uid 校验不在这里，它属于宿主。
     */
    fun validate(request: HelperRequest): String? {
        if (request.version != HELPER_PROTOCOL_VERSION) return "Unsupported protocol version"
        if (request.requestId.isBlank()) return "Missing requestId"
        if (request.command !in HELPER_ALLOWED_COMMANDS) return "Command is not allowed"
        if (request.command == COMMAND_SET_DISABLE_SLEEP) {
            val value = request.payload["disabled"] ?: return "Missing disabled value"
            if (value != "true" && value != "false") return "Invalid disabled value"
        }
        if (request.command == COMMAND_SET_HIBERNATE_MODE) {
            val mode = request.payload["mode"]?.toIntOrNull() ?: return "Missing hibernate mode"
            if (mode !in SUPPORTED_HIBERNATE_MODES) return "Invalid hibernate mode"
        }
        if (request.command == COMMAND_CHARGE_LIMIT_CONFIGURE) {
            val percent = request.payload["percent"]?.toIntOrNull() ?: return "Missing charge limit"
            if (!ChargeLimitPolicy.isValidUpperLimit(percent)) return "Invalid charge limit"
        }
        return null
    }

    /** 充电控制命令需要调用方代码签名，不能只靠已安装用户的 uid。 */
    fun isChargeLimitCommand(command: String): Boolean = command == COMMAND_CHARGE_LIMIT_STATUS ||
        command == COMMAND_CHARGE_LIMIT_CONFIGURE ||
        command == COMMAND_CHARGE_LIMIT_RESTORE

    // MARK: pmset 调用

    /**
     * 这条请求要跑的命令行。
     *
     * 返回 null 表示这条命令不跑 `pmset`。`version` 不跑，
     * 白名单外的命令在 [validate] 就已被拒绝。
     */
    fun pmsetArguments(request: HelperRequest): List<String>? = when (request.command) {
        COMMAND_SET_DISABLE_SLEEP -> listOf(
            "-a",
            "disablesleep",
            if (request.payload["disabled"] == "true") "1" else "0",
        )

        COMMAND_SET_HIBERNATE_MODE -> request.payload["mode"]
            ?.toIntOrNull()
            ?.let { listOf("-a", "hibernatemode", it.toString()) }

        else -> null
    }

    /**
     * `pmset` 跑完之后的回复。
     *
     * `pmset` 失败时把它的输出当错误文案。没有输出时用退出码拼一句，
     * 好让日志里看得出是哪一步失败。
     */
    fun pmsetReply(requestId: String, exitCode: Int, output: String): HelperReply {
        if (exitCode == 0) return success(requestId)
        val text = output.trim()
        return failure(requestId, text.ifEmpty { "pmset exited with $exitCode" })
    }
}
