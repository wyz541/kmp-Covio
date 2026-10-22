package com.wyz.covio.app.helper

import com.wyz.covio.core.HelperReply
import com.wyz.covio.core.HelperRequest
import com.wyz.covio.core.HelperWire
// 常量定义在共享模块的 `HelperContract.kt`，这里只是转发。
// 加别名是因为成员名与顶层常量名相同，不加则解析到自身。
import com.wyz.covio.core.HELPER_ALLOWED_COMMANDS as SHARED_ALLOWED_COMMANDS
import com.wyz.covio.core.HELPER_ALLOWED_UID_PATH as SHARED_ALLOWED_UID_PATH
import com.wyz.covio.core.HELPER_APP_PATH_FILE as SHARED_APP_PATH_FILE
import com.wyz.covio.core.HELPER_CLIENT_REQUIREMENT_PATH as SHARED_CLIENT_REQUIREMENT_PATH
import com.wyz.covio.core.HELPER_DIRECTORY as SHARED_DIRECTORY
import com.wyz.covio.core.HELPER_LOG_PATH as SHARED_LOG_PATH
import com.wyz.covio.core.HELPER_PLIST_PATH as SHARED_PLIST_PATH
import com.wyz.covio.core.HELPER_PROTOCOL_VERSION as SHARED_PROTOCOL_VERSION
import com.wyz.covio.core.HELPER_SOCKET_PATH as SHARED_SOCKET_PATH
import com.wyz.covio.core.HELPER_VERSION_PATH as SHARED_VERSION_PATH

/**
 * 本模块用到的协议入口。
 *
 * 协议本身只有一份实现，在共享模块的 `HelperWire.kt`。
 * SwiftUI 版的 helper 调用同一份，所以两侧不可能漂移。
 * 这里的成员只是改名转发，方便本模块的调用点。
 *
 * 本模块随 Compose 宿主一起退役，见迁移计划 M6。届时整个文件删除，
 * 调用点直接用 `HelperWire`。
 */
object HelperProtocol {
    const val PROTOCOL_VERSION = SHARED_PROTOCOL_VERSION
    const val SOCKET_PATH = SHARED_SOCKET_PATH
    const val HELPER_DIRECTORY = SHARED_DIRECTORY
    const val ALLOWED_UID_PATH = SHARED_ALLOWED_UID_PATH
    const val CLIENT_REQUIREMENT_PATH = SHARED_CLIENT_REQUIREMENT_PATH
    const val VERSION_PATH = SHARED_VERSION_PATH
    const val APP_PATH_FILE = SHARED_APP_PATH_FILE
    const val LOG_PATH = SHARED_LOG_PATH
    const val PLIST_PATH = SHARED_PLIST_PATH
    val allowedCommands = SHARED_ALLOWED_COMMANDS

    fun decodeRequest(line: String): HelperRequest? = HelperWire.decodeRequest(line)

    fun encodeRequest(request: HelperRequest): String = HelperWire.encodeRequest(request)

    fun encodeReply(reply: HelperReply): String = HelperWire.encodeReply(reply)

    fun decodeReply(line: String): HelperReply? = HelperWire.decodeReply(line)

    fun success(requestId: String, result: Map<String, String> = emptyMap()): HelperReply =
        HelperWire.success(requestId, result)

    fun failure(requestId: String, message: String): HelperReply =
        HelperWire.failure(requestId, message)

    fun validate(request: HelperRequest): String? = HelperWire.validate(request)

    fun versionReply(requestId: String): HelperReply = HelperWire.versionReply(requestId)
}
