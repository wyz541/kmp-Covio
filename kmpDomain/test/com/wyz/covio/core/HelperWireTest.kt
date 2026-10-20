package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * `HelperWire` 的断言。
 *
 * 这里钉住规则本身：错误文案、校验顺序、pmset 参数、回复里写不写空字段。
 * 线上字节由 `HelperWireVectorTest` 对着共享语料钉，两者分工不同。
 *
 * 错误文案是线上契约。客户端按文案判断失败原因，所以下面逐字写死。
 */
class HelperWireTest {
    private fun request(
        command: String,
        payload: Map<String, String> = emptyMap(),
        version: String = HELPER_PROTOCOL_VERSION,
        requestId: String = "r1",
    ) = HelperRequest(version, requestId, command, payload)

    // MARK: 错误文案

    @Test
    fun `an unknown protocol version is rejected`() {
        assertEquals(
            "Unsupported protocol version",
            HelperWire.validate(request(HelperWire.COMMAND_VERSION, version = "3")),
        )
    }

    @Test
    fun `a blank request id is rejected`() {
        assertEquals("Missing requestId", HelperWire.validate(request(HelperWire.COMMAND_VERSION, requestId = "")))
        assertEquals("Missing requestId", HelperWire.validate(request(HelperWire.COMMAND_VERSION, requestId = " \n ")))
    }

    @Test
    fun `a command outside the allow list is rejected`() {
        assertEquals("Command is not allowed", HelperWire.validate(request("runShell")))
    }

    @Test
    fun `a missing disabled value is rejected`() {
        assertEquals(
            "Missing disabled value",
            HelperWire.validate(request(HelperWire.COMMAND_SET_DISABLE_SLEEP)),
        )
    }

    @Test
    fun `a disabled value other than true and false is rejected`() {
        for (value in listOf("1", "TRUE", "yes", "")) {
            assertEquals(
                "Invalid disabled value",
                HelperWire.validate(request(HelperWire.COMMAND_SET_DISABLE_SLEEP, mapOf("disabled" to value))),
                "disabled=$value 应当被拒绝",
            )
        }
    }

    @Test
    fun `a hibernate mode that is not a number is rejected`() {
        assertEquals(
            "Missing hibernate mode",
            HelperWire.validate(request(HelperWire.COMMAND_SET_HIBERNATE_MODE, mapOf("mode" to "abc"))),
        )
        assertEquals(
            "Missing hibernate mode",
            HelperWire.validate(request(HelperWire.COMMAND_SET_HIBERNATE_MODE)),
        )
    }

    @Test
    fun `a hibernate mode outside the product list is rejected`() {
        for (mode in listOf("1", "2", "4", "57")) {
            assertEquals(
                "Invalid hibernate mode",
                HelperWire.validate(request(HelperWire.COMMAND_SET_HIBERNATE_MODE, mapOf("mode" to mode))),
                "mode=$mode 应当被拒绝",
            )
        }
    }

    @Test
    fun `every supported hibernate mode passes`() {
        for (mode in SUPPORTED_HIBERNATE_MODES) {
            assertNull(
                HelperWire.validate(request(HelperWire.COMMAND_SET_HIBERNATE_MODE, mapOf("mode" to mode.toString()))),
                "mode=$mode 应当通过",
            )
        }
    }

    @Test
    fun `charge limit configuration requires a five point limit`() {
        assertEquals(
            "Missing charge limit",
            HelperWire.validate(request(HelperWire.COMMAND_CHARGE_LIMIT_CONFIGURE)),
        )
        assertEquals(
            "Missing charge limit",
            HelperWire.validate(
                request(HelperWire.COMMAND_CHARGE_LIMIT_CONFIGURE, mapOf("percent" to "abc")),
            ),
        )
        for (percent in listOf("19", "79", "101")) {
            assertEquals(
                "Invalid charge limit",
                HelperWire.validate(
                    request(HelperWire.COMMAND_CHARGE_LIMIT_CONFIGURE, mapOf("percent" to percent)),
                ),
            )
        }
        for (percent in listOf("20", "70", "80", "100")) {
            assertNull(
                HelperWire.validate(
                    request(HelperWire.COMMAND_CHARGE_LIMIT_CONFIGURE, mapOf("percent" to percent)),
                ),
            )
        }
    }

    @Test
    fun `charge limit status and restore need no payload`() {
        assertNull(HelperWire.validate(request(HelperWire.COMMAND_CHARGE_LIMIT_STATUS)))
        assertNull(HelperWire.validate(request(HelperWire.COMMAND_CHARGE_LIMIT_RESTORE)))
    }

    @Test
    fun `only charge commands require client signature verification`() {
        assertTrue(HelperWire.isChargeLimitCommand(HelperWire.COMMAND_CHARGE_LIMIT_STATUS))
        assertTrue(HelperWire.isChargeLimitCommand(HelperWire.COMMAND_CHARGE_LIMIT_CONFIGURE))
        assertTrue(HelperWire.isChargeLimitCommand(HelperWire.COMMAND_CHARGE_LIMIT_RESTORE))
        assertFalse(HelperWire.isChargeLimitCommand(HelperWire.COMMAND_VERSION))
        assertFalse(HelperWire.isChargeLimitCommand(HelperWire.COMMAND_SET_DISABLE_SLEEP))
    }

    /**
     * 校验顺序是协议的一部分。
     *
     * 一条请求同时错好几处时，客户端看到的必须是第一处。
     * 顺序变了，旧版客户端会把「版本不对」读成「命令不合法」。
     */
    @Test
    fun `validation reports the first problem in a fixed order`() {
        val everythingWrong = HelperRequest("2", "", "runShell", emptyMap())
        assertEquals("Unsupported protocol version", HelperWire.validate(everythingWrong))

        val versionOk = HelperRequest(HELPER_PROTOCOL_VERSION, "", "runShell", emptyMap())
        assertEquals("Missing requestId", HelperWire.validate(versionOk))

        val idOk = HelperRequest(HELPER_PROTOCOL_VERSION, "r", "runShell", emptyMap())
        assertEquals("Command is not allowed", HelperWire.validate(idOk))
    }

    // MARK: 线上的字节

    @Test
    fun `an empty payload is left out of the request`() {
        val line = HelperWire.encodeRequest(request(HelperWire.COMMAND_VERSION))

        assertEquals("""{"version":"4","requestId":"r1","command":"version"}""", line)
    }

    @Test
    fun `a request with a payload keeps every key`() {
        val line = HelperWire.encodeRequest(
            request(HelperWire.COMMAND_SET_DISABLE_SLEEP, mapOf("disabled" to "true")),
        )

        assertEquals(
            """{"version":"4","requestId":"r1","command":"setDisableSleep","payload":{"disabled":"true"}}""",
            line,
        )
    }

    @Test
    fun `a request without a payload key decodes with an empty one`() {
        val decoded = assertNotNull(
            HelperWire.decodeRequest("""{"version":"3","requestId":"r","command":"version"}"""),
        )

        assertTrue(decoded.payload.isEmpty())
    }

    @Test
    fun `unknown keys are ignored on the way in and gone on the way out`() {
        val decoded = assertNotNull(
            HelperWire.decodeRequest("""{"version":"3","requestId":"r","command":"version","future":7}"""),
        )

        assertEquals("""{"version":"3","requestId":"r","command":"version"}""", HelperWire.encodeRequest(decoded))
    }

    @Test
    fun `a line that is not a request decodes to null`() {
        assertNull(HelperWire.decodeRequest("这不是 JSON"))
        assertNull(HelperWire.decodeRequest("{}"))
        assertNull(HelperWire.decodeRequest("""{"version":"3","requestId":"r"}"""))
    }

    @Test
    fun `a successful reply leaves an empty result out`() {
        assertEquals("""{"version":"4","requestId":"r","ok":true}""", HelperWire.encodeReply(HelperWire.success("r")))
    }

    @Test
    fun `a successful reply keeps a non empty result`() {
        assertEquals(
            """{"version":"4","requestId":"r","ok":true,"result":{"a":"b"}}""",
            HelperWire.encodeReply(HelperWire.success("r", mapOf("a" to "b"))),
        )
    }

    @Test
    fun `a failure reply carries only the message`() {
        assertEquals(
            """{"version":"4","requestId":"r","ok":false,"error":"boom"}""",
            HelperWire.encodeReply(HelperWire.failure("r", "boom")),
        )
    }

    @Test
    fun `a reply without result and error decodes with both null`() {
        val reply = assertNotNull(HelperWire.decodeReply("""{"version":"3","requestId":"r","ok":true}"""))

        assertTrue(reply.ok)
        assertNull(reply.result)
        assertNull(reply.error)
    }

    @Test
    fun `a line that is not a reply decodes to null`() {
        assertNull(HelperWire.decodeReply("{"))
        assertNull(HelperWire.decodeReply("not json at all"))
    }

    /**
     * 带引号的布尔值解得出来。
     *
     * kotlinx-serialization 把 `"true"` 收成 `true`。
     * 0.4.2 从没发过这种形状，所以收下它不会放行任何真实坏包。
     * 这里钉住现状：日后换解析器时，行为变化会被这个用例发现。
     */
    @Test
    fun `a quoted boolean is accepted by the lenient decoder`() {
        val reply = assertNotNull(HelperWire.decodeReply("""{"version":"3","requestId":"r","ok":"true"}"""))

        assertTrue(reply.ok)
        assertEquals("""{"version":"3","requestId":"r","ok":true}""", HelperWire.encodeReply(reply))
    }

    // MARK: pmset

    @Test
    fun `the version command does not run pmset`() {
        assertNull(HelperWire.pmsetArguments(request(HelperWire.COMMAND_VERSION)))
    }

    @Test
    fun `an unknown command does not run pmset`() {
        assertNull(HelperWire.pmsetArguments(request("runShell")))
    }

    @Test
    fun `disabling sleep becomes a pmset argument`() {
        assertEquals(
            listOf("-a", "disablesleep", "1"),
            HelperWire.pmsetArguments(request(HelperWire.COMMAND_SET_DISABLE_SLEEP, mapOf("disabled" to "true"))),
        )
        assertEquals(
            listOf("-a", "disablesleep", "0"),
            HelperWire.pmsetArguments(request(HelperWire.COMMAND_SET_DISABLE_SLEEP, mapOf("disabled" to "false"))),
        )
    }

    @Test
    fun `the hibernate mode becomes a pmset argument`() {
        assertEquals(
            listOf("-a", "hibernatemode", "25"),
            HelperWire.pmsetArguments(request(HelperWire.COMMAND_SET_HIBERNATE_MODE, mapOf("mode" to "25"))),
        )
    }

    @Test
    fun `a hibernate mode that is not a number produces no arguments`() {
        assertNull(
            HelperWire.pmsetArguments(request(HelperWire.COMMAND_SET_HIBERNATE_MODE, mapOf("mode" to "abc"))),
        )
    }

    /**
     * `setDisableSleep` 少了 `disabled` 时按 `false` 处理。
     *
     * 两个宿主历来都是这个行为，所以照抄。
     * 这条路径实际走不到：`validate` 先拒绝，服务器不会拿它去跑 pmset。
     * 钉住它只是为了让两侧的行为永远一致。
     */
    @Test
    fun `a missing disabled value falls back to zero`() {
        assertEquals(
            listOf("-a", "disablesleep", "0"),
            HelperWire.pmsetArguments(request(HelperWire.COMMAND_SET_DISABLE_SLEEP)),
        )
        assertEquals(
            listOf("-a", "disablesleep", "0"),
            HelperWire.pmsetArguments(request(HelperWire.COMMAND_SET_DISABLE_SLEEP, mapOf("disabled" to "1"))),
        )
    }

    @Test
    fun `a pmset run that exits zero succeeds`() {
        val reply = HelperWire.pmsetReply("r", 0, "anything")

        assertTrue(reply.ok)
        assertNull(reply.result)
        assertNull(reply.error)
    }

    @Test
    fun `a pmset run that fails reports its output`() {
        val reply = HelperWire.pmsetReply("r", 1, "pmset: bad\n")

        assertEquals("pmset: bad", reply.error)
        assertEquals(false, reply.ok)
    }

    @Test
    fun `a pmset run that fails without output reports its exit code`() {
        assertEquals("pmset exited with 3", HelperWire.pmsetReply("r", 3, "  \n").error)
    }

    // MARK: 协议值

    @Test
    fun `the allow list is exactly the commands the wire knows`() {
        assertEquals(
            setOf(
                HelperWire.COMMAND_VERSION,
                HelperWire.COMMAND_SET_DISABLE_SLEEP,
                HelperWire.COMMAND_SET_HIBERNATE_MODE,
                HelperWire.COMMAND_CHARGE_LIMIT_STATUS,
                HelperWire.COMMAND_CHARGE_LIMIT_CONFIGURE,
                HelperWire.COMMAND_CHARGE_LIMIT_RESTORE,
            ),
            HELPER_ALLOWED_COMMANDS,
        )
    }

    @Test
    fun `the byte limits and the socket mode keep their shipped values`() {
        assertEquals(64 * 1024, HelperWire.MAX_REQUEST_BYTES)
        assertEquals(64 * 1024, HelperWire.MAX_REPLY_BYTES)
        // 0o666：任意用户可连，uid 校验在连接后做。
        assertEquals(0x1B6, HelperWire.SOCKET_PERMISSIONS)
    }
}
