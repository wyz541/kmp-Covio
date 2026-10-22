package com.wyz.covio.core

import okio.FileSystem
import okio.Path.Companion.toPath
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 设计合同读取器的测试。
 *
 * 一份是对着真合同的：读得到、解析得出、动效取值自洽。
 * 一份是对着造出来的坏合同的：每种坏法都要变成诊断，不能抛异常。
 *
 * 真合同的路径按工作目录找。Amper 跑测试时工作目录是模块目录或仓库根目录，
 * 所以几个位置都试。都找不到就直接失败——找不到说明路径猜错了，
 * 那几条测试会静默跳过，等于没测。
 */
class DesignContractTest {
    private val realContractPath: String? = sequenceOf(
        "docs/covio-design-contract.json",
        "../docs/covio-design-contract.json",
        "../../docs/covio-design-contract.json",
    ).firstOrNull { FileSystem.SYSTEM.exists(it.toPath()) }

    private fun readRealContract(): DesignContract {
        val path = realContractPath
        val workingDirectory = FileSystem.SYSTEM.canonicalize(".".toPath())
        assertNotNull(path, "找不到设计合同。工作目录是 $workingDirectory")
        val result = DesignContractReader.read(path)
        assertTrue(result.isValid, "真合同应当通过校验：${result.errors.map { it.describe() }}")
        return assertNotNull(result.contract)
    }

    @Test
    fun `the shipped contract parses and validates`() {
        val contract = readRealContract()

        assertTrue(contract.schemaVersion.isNotBlank())
        assertTrue(contract.tokens.size > 100, "令牌条数太少：${contract.tokens.size}")
        assertTrue(contract.copy.size > 100, "文案条数太少：${contract.copy.size}")
        assertEquals(30, contract.components.size, "组件数被改动了")
        assertEquals(33, contract.platformMappings.size, "平台映射数被改动了")
    }

    @Test
    fun `the shipped contract carries the motion tokens`() {
        val contract = readRealContract()

        assertEquals(11, contract.motionTokens.size, "动效令牌少了一条或多了一条")
        for (token in contract.motionTokens) {
            assertTrue(token.hasValidMotionRange, "${token.key} 的范围不成立")
            assertNotNull(token.curve, "${token.key} 缺 curve")
        }
    }

    @Test
    fun `the shipped contract keeps the hub state copy`() {
        val contract = readRealContract()

        // M1 的状态机按这些键取文案，两条状态机各六个状态。
        val hubStates = listOf("hidden", "hover", "open", "active", "exit", "error")
        for (slug in hubStates) {
            assertNotNull(contract.entry("copy/notch-hub/state/$slug"), "缺 $slug 的文案")
        }
        val outputStates = listOf("collapsed", "ready", "expanded", "drag-target", "processing")
        for (slug in outputStates) {
            assertNotNull(contract.entry("copy/notch-hub/state/$slug"), "缺 $slug 的文案")
        }
    }

    @Test
    fun `a lookup returns the entry for a known key`() {
        val contract = readRealContract()

        val entry = assertNotNull(contract.entry("copy/app/name"))
        assertTrue(entry.en.isNotBlank())
        assertTrue(entry.zhHans.isNotBlank())
        assertNull(contract.entry("copy/没有这个键"))
        assertNull(contract.token("token/没有这个令牌"))
    }

    @Test
    fun `broken json becomes a diagnostic`() {
        val result = DesignContractReader.parse("{ 这不是 JSON")

        assertFalse(result.isValid)
        assertNull(result.contract)
        assertEquals(1, result.errors.size)
        assertEquals(DesignContractSeverity.ERROR, result.errors.first().severity)
    }

    @Test
    fun `a non object root becomes a diagnostic`() {
        val result = DesignContractReader.parse("[1, 2, 3]")

        assertFalse(result.isValid)
        assertNull(result.contract)
    }

    @Test
    fun `missing sections are reported one by one`() {
        val result = DesignContractReader.parse("""{"schemaVersion": "1.0.0"}""")

        assertFalse(result.isValid)
        val paths = result.errors.map { it.path }.toSet()
        assertEquals(setOf("tokens", "copy", "components", "platformMapping"), paths)
    }

    @Test
    fun `a blank schema version is rejected`() {
        val result = DesignContractReader.parse(minimal(schemaVersion = "   "))

        assertFalse(result.isValid)
        assertTrue(result.errors.any { it.path == "schemaVersion" })
    }

    @Test
    fun `a color token without both values is rejected`() {
        val result = DesignContractReader.parse(
            minimal(tokens = """{"token/color/ink": {"type": "color", "light": "#000000"}}""")
        )

        assertFalse(result.isValid)
        assertTrue(result.errors.any { it.path == "tokens/token/color/ink" })
    }

    @Test
    fun `an unknown token type is rejected`() {
        val result = DesignContractReader.parse(
            minimal(tokens = """{"token/x/y": {"type": "gradient", "purpose": "x"}}""")
        )

        assertFalse(result.isValid)
        assertTrue(result.errors.any { "认不出的令牌类型" in it.message })
    }

    @Test
    fun `a motion token with an inverted range is rejected`() {
        val result = DesignContractReader.parse(
            minimal(
                tokens = """{"token/motion/x": {"type": "duration", "purpose": "x",
                    "durationMs": 100, "minMs": 200, "maxMs": 300}}"""
            )
        )

        assertFalse(result.isValid)
        assertTrue(result.errors.any { it.path == "tokens/token/motion/x" })
    }

    @Test
    fun `a motion token whose reduced duration is longer is rejected`() {
        val result = DesignContractReader.parse(
            minimal(
                tokens = """{"token/motion/x": {"type": "duration", "purpose": "x",
                    "durationMs": 120, "minMs": 120, "maxMs": 120, "reducedMotionMs": 500}}"""
            )
        )

        assertFalse(result.isValid)
        assertTrue(result.errors.any { it.path == "tokens/token/motion/x" })
    }

    @Test
    fun `a motion token with a valid range is accepted`() {
        val result = DesignContractReader.parse(
            minimal(
                tokens = """{"token/motion/x": {"type": "duration", "purpose": "x", "curve": "缓出",
                    "durationMs": 250, "minMs": 220, "maxMs": 280, "reducedMotionMs": 120}}"""
            )
        )

        assertTrue(result.isValid, result.errors.map { it.describe() }.toString())
        val token = assertNotNull(result.contract?.token("token/motion/x"))
        assertTrue(token.isMotion)
        assertEquals(220.0, token.minMs)
        assertEquals(250.0, token.durationMs)
        assertEquals(280.0, token.maxMs)
        assertEquals(120.0, token.reducedMotionMs)
        assertEquals("缓出", token.curve)
    }

    @Test
    fun `copy needs both languages`() {
        val result = DesignContractReader.parse(
            minimal(copy = """{"copy/a": {"en": "Hello"}}""")
        )

        assertFalse(result.isValid)
        assertTrue(result.errors.any { it.path == "copy/copy/a" })
    }

    @Test
    fun `a component without a swift mapping is rejected`() {
        val result = DesignContractReader.parse(
            minimal(components = """{"component/x": {"name": "X"}}""")
        )

        assertFalse(result.isValid)
        assertTrue(result.errors.any { it.path == "components/component/x" })
    }

    @Test
    fun `a platform mapping without a swift target is rejected`() {
        val result = DesignContractReader.parse(
            minimal(platformMapping = """{"platform/system/menus": {"status": "native-source-mapped"}}""")
        )

        assertFalse(result.isValid)
        assertTrue(result.errors.any { "swiftRuntimeTarget" in it.message })
    }

    @Test
    fun `a missing purpose is only a warning`() {
        val result = DesignContractReader.parse(
            minimal(tokens = """{"token/color/ink": {"type": "color", "light": "#000", "dark": "#fff"}}""")
        )

        assertTrue(result.isValid, result.errors.map { it.describe() }.toString())
        assertEquals(1, result.warnings.size)
        assertEquals("tokens/token/color/ink", result.warnings.first().path)
    }

    @Test
    fun `a missing file becomes a diagnostic instead of an exception`() {
        val path = FileSystem.SYSTEM_TEMPORARY_DIRECTORY
            .resolve("covio-没有这个合同-${Random.nextLong().toString(16)}.json")
        val result = DesignContractReader.read(path.toString())

        assertFalse(result.isValid)
        assertNull(result.contract)
        assertTrue(result.errors.first().message.startsWith("读不到合同文件"))
    }

    @Test
    fun `the default path points at the repository contract`() {
        assertEquals("docs/covio-design-contract.json", DesignContractReader.defaultContractPath())
    }

    /** 拼一份最小的合法合同，再按参数换掉其中一段。 */
    private fun minimal(
        schemaVersion: String = "1.3.0",
        tokens: String = """{"token/color/ink": {"type": "color", "light": "#000", "dark": "#fff", "purpose": "x"}}""",
        copy: String = """{"copy/app/name": {"en": "Covio", "zh-Hans": "Covio"}}""",
        components: String = """{"component/x": {"name": "X", "swiftMapping": {"target": "MacX", "behavior": "b"}}}""",
        platformMapping: String = """{"platform/system/menus": {"status": "native-source-mapped", "swiftRuntimeTarget": "StatusItemController"}}""",
    ): String = """
        {
          "schemaVersion": "$schemaVersion",
          "tokens": $tokens,
          "copy": $copy,
          "components": $components,
          "platformMapping": $platformMapping
        }
    """.trimIndent()
}
