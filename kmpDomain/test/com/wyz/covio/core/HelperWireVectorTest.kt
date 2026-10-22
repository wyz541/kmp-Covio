package com.wyz.covio.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okio.FileSystem
import okio.Path.Companion.toPath
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 共享语料的检验。
 *
 * `kmpDomain/test/fixtures/helper-wire-vectors.json` 同时被 Swift 侧的
 * `HelperWireParityTests` 读。这份测试钉住协议行为，那份钉住导出形状。
 *
 * 语料里的 `line` 是线上真实的字节。用例失败时先看 `line`：
 * 它要么来自 0.4.2 的客户端，要么是对着新实现的输出抄的。
 *
 * 语料的路径按工作目录找，与 `DesignContractTest` 同一手法。
 * 都找不到就直接失败：静默跳过等于没测。
 */
class HelperWireVectorTest {
    private val fixturePath: String? = sequenceOf(
        "kmpDomain/test/fixtures/helper-wire-vectors.json",
        "../kmpDomain/test/fixtures/helper-wire-vectors.json",
        "../../kmpDomain/test/fixtures/helper-wire-vectors.json",
    ).firstOrNull { FileSystem.SYSTEM.exists(it.toPath()) }

    @Test
    fun `the corpus is where the tests expect it`() {
        val workingDirectory = FileSystem.SYSTEM.canonicalize(".".toPath())
        val path = assertNotNull(fixturePath, "找不到线上协议语料。工作目录是 $workingDirectory")

        // 路径对了但内容空了，下面的用例会全过。所以先确认规模。
        assertTrue(requests().size >= 15, "$path 里的请求太少")
        assertTrue(replies().size >= 5, "$path 里的回复太少")
        assertTrue(constructed().size >= 5, "$path 里的构造用例太少")
    }

    @Test
    fun `every request vector behaves as the corpus says`() {
        for (vector in requests()) {
            val name = indicator(vector)
            val line = assertNotNull(vector.string("line"), name)
            val decoded = HelperWire.decodeRequest(line)

            if (vector.string("decode") != "ok") {
                assertNull(decoded, "$name：这行不该解得出来")
                continue
            }

            val request = assertNotNull(decoded, "$name：这行应该解得出来")
            assertEquals(vector.string("validate"), HelperWire.validate(request), "$name：拒绝原因不同")
            assertEquals(
                vector.stringArray("pmsetArguments"),
                HelperWire.pmsetArguments(request),
                "$name：pmset 参数不同",
            )
            assertEquals(
                vector.string("reencoded"),
                HelperWire.encodeRequest(request),
                "$name：再编码的字节不同",
            )
        }
    }

    @Test
    fun `every reply vector behaves as the corpus says`() {
        for (vector in replies()) {
            val name = indicator(vector)
            val line = assertNotNull(vector.string("line"), name)
            val decoded = HelperWire.decodeReply(line)

            if (vector.string("decode") != "ok") {
                assertNull(decoded, "$name：这行不该解得出来")
                continue
            }

            val reply = assertNotNull(decoded, "$name：这行应该解得出来")
            assertEquals(vector.bool("ok"), reply.ok, "$name：ok 不同")
            assertEquals(vector.string("resultVersion"), reply.result?.get("version"), "$name：result 不同")
            assertEquals(vector.string("error"), reply.error, "$name：error 不同")
            assertEquals(
                vector.string("reencoded"),
                HelperWire.encodeReply(reply),
                "$name：再编码的字节不同",
            )
        }
    }

    @Test
    fun `every constructed reply is byte for byte the expected one`() {
        for (vector in constructed()) {
            val name = indicator(vector)
            val requestId = assertNotNull(vector.string("requestId"), name)
            val reply = when (val call = vector.string("call")) {
                "success" -> HelperWire.success(requestId, vector.stringMap("result") ?: emptyMap())
                "failure" -> HelperWire.failure(requestId, assertNotNull(vector.string("message"), name))
                "pmsetReply" -> HelperWire.pmsetReply(
                    requestId,
                    assertNotNull(vector.int("exitCode"), name),
                    assertNotNull(vector.string("output"), name),
                )

                else -> throw AssertionError("$name：语料里的 call 认不出来：$call")
            }

            assertEquals(vector.string("expected"), HelperWire.encodeReply(reply), name)
        }
    }

    /** 版本应答带的是本版的版本号，语料里写死会随版本升级而过期，所以单独测。 */
    @Test
    fun `the version reply carries the shipped version`() {
        val reply = HelperWire.versionReply("r")

        assertTrue(reply.ok)
        assertEquals(APP_VERSION, reply.result?.get("version"))
        assertEquals("""{"version":"4","requestId":"r","ok":true,"result":{"version":"$APP_VERSION"}}""", HelperWire.encodeReply(reply))
    }

    private fun read(): JsonObject {
        val path = assertNotNull(fixturePath, "找不到线上协议语料")
        val text = FileSystem.SYSTEM.read(path.toPath()) { readUtf8() }
        return Json.parseToJsonElement(text) as JsonObject
    }

    private fun requests(): List<JsonObject> = read().array("requests").map { it.jsonObject }
    private fun replies(): List<JsonObject> = read().array("replies").map { it.jsonObject }
    private fun constructed(): List<JsonObject> = read().array("constructed").map { it.jsonObject }

    /** 用例的名字。失败信息里带上它，一眼知道是哪条语料。 */
    private fun indicator(vector: JsonObject): String =
        vector.string("name") ?: vector.toString()

    private fun JsonObject.array(key: String): JsonArray =
        assertNotNull(this[key] as? JsonArray, "语料缺 $key")

    private fun JsonObject.string(key: String): String? =
        (this[key] as? JsonPrimitive)?.contentOrNull

    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.intOrNull

    private fun JsonObject.bool(key: String): Boolean? =
        (this[key] as? JsonPrimitive)?.contentOrNull?.toBooleanStrictOrNull()

    private fun JsonObject.stringArray(key: String): List<String>? =
        (this[key] as? JsonArray)?.map { it.jsonPrimitive.content }

    private fun JsonObject.stringMap(key: String): Map<String, String>? =
        (this[key] as? JsonObject)?.mapValues { (_, value) -> value.jsonPrimitive.content }
}
