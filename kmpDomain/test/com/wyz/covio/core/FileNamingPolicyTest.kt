package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class FileNamingPolicyTest {
    private fun request(
        id: String = "candidate-1",
        originalName: String = "untitled.txt",
        title: String = "季度预算评审",
        category: String = "产品规划",
        date: String? = null,
        language: String? = "zh",
        confidence: Double = 0.95,
        kind: FileNamingKind = FileNamingKind.TEXT,
    ): FileNamingRequest = FileNamingRequest(
        candidateId = id,
        originalName = originalName,
        facts = NamingFacts(
            title = title,
            category = category,
            date = date,
            language = language,
            confidence = confidence,
            kind = kind,
        ),
    )

    @Test
    fun `defaults preserve the extension and force preview`() {
        val policy = FileNamingPolicy(preserveExtension = false, requirePreview = false).normalized()

        assertTrue(policy.preserveExtension)
        assertTrue(policy.requirePreview)
        assertEquals(DEFAULT_FILE_NAMING_TEMPLATE, policy.template)
        assertEquals(240, policy.maxUTF8Bytes)
        assertEquals(emptyList(), policy.validationErrors())
    }

    @Test
    fun `the default template renders the title and keeps the original extension`() {
        val plan = FileNamingPlanner.plan(request(), FileNamingPolicy(), emptySet())

        assertTrue(plan.canApply)
        assertEquals("季度预算评审.txt", plan.targetName)
        assertEquals(".txt", plan.extension)
        assertEquals(emptyList(), plan.warnings)
    }

    @Test
    fun `the template supports category date language and latin lowering`() {
        val plan = FileNamingPlanner.plan(
            request(
                originalName = "draft.pdf",
                title = "Quarterly Review",
                category = "Finance",
                date = "2026-10-20",
                language = "EN",
            ),
            FileNamingPolicy(
                template = "{date}-{category}-{title}-{language}",
                dateSource = FileNamingDateSource.CONTENT,
                lowercaseLatin = true,
            ),
            emptySet(),
        )

        assertEquals("2026-10-20-finance-quarterly review-en.pdf", plan.targetName)
        assertTrue(plan.canApply)
        assertTrue(plan.warnings.isEmpty())
    }

    @Test
    fun `the date token is empty when the policy says none`() {
        val plan = FileNamingPlanner.plan(
            request(title = "Review", date = "2026-10-20"),
            FileNamingPolicy(template = "{date}-{title}", dateSource = FileNamingDateSource.NONE),
            emptySet(),
        )

        assertEquals("-Review.txt", plan.targetName)
        assertFalse(plan.targetName!!.contains("2026"))
    }

    @Test
    fun `forbidden characters in model facts become the configured separator`() {
        val plan = FileNamingPlanner.plan(
            request(title = "A/B:C", category = "D*E?F"),
            FileNamingPolicy(template = "{title}-{category}", separator = "_"),
            emptySet(),
        )

        assertEquals("A_B_C-D_E_F.txt", plan.targetName)
        assertTrue(plan.canApply)
    }

    @Test
    fun `a hidden source file is blocked`() {
        val plan = FileNamingPlanner.plan(request(originalName = ".env"), FileNamingPolicy(), setOf(".env"))

        assertFalse(plan.canApply)
        assertEquals(null, plan.targetName)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.HIDDEN_FILE_UNSUPPORTED })
    }

    @Test
    fun `unknown type is blocked`() {
        val plan = FileNamingPlanner.plan(request(kind = FileNamingKind.UNKNOWN), FileNamingPolicy(), emptySet())

        assertFalse(plan.canApply)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.UNKNOWN_TYPE })
    }

    @Test
    fun `mixed input is allowed but carries a warning`() {
        val plan = FileNamingPlanner.plan(request(kind = FileNamingKind.MIXED), FileNamingPolicy(), emptySet())

        assertTrue(plan.canApply)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.MIXED_INPUT })
    }

    @Test
    fun `confidence below the policy floor is blocked`() {
        val plan = FileNamingPlanner.plan(
            request(confidence = 0.64),
            FileNamingPolicy(minConfidence = 0.65),
            emptySet(),
        )

        assertFalse(plan.canApply)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.LOW_CONFIDENCE })
    }

    @Test
    fun `an empty title is blocked`() {
        val plan = FileNamingPlanner.plan(request(title = "  "), FileNamingPolicy(), emptySet())

        assertFalse(plan.canApply)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.EMPTY_TITLE })
    }

    @Test
    fun `unsafe final names are blocked`() {
        val dot = FileNamingPlanner.plan(
            request(title = "."),
            FileNamingPolicy(),
            emptySet(),
        )
        val reserved = FileNamingPlanner.plan(
            request(title = "CON"),
            FileNamingPolicy(),
            emptySet(),
        )

        assertFalse(dot.canApply)
        assertTrue(
            dot.warnings.any {
                it.code == FileNamingWarningCode.EMPTY_TITLE ||
                    it.code == FileNamingWarningCode.UNSAFE_NAME
            },
        )
        assertFalse(reserved.canApply)
        assertTrue(reserved.warnings.any { it.code == FileNamingWarningCode.UNSAFE_NAME })
    }

    @Test
    fun `long names are truncated by UTF-8 byte budget`() {
        val plan = FileNamingPlanner.plan(
            request(originalName = "notes.txt", title = "预算评审"),
            FileNamingPolicy(template = "{title}", maxUTF8Bytes = 10),
            emptySet(),
        )

        assertEquals("预算.txt", plan.targetName)
        assertTrue(plan.targetName!!.encodeToByteArray().size <= 10)
        assertTrue(plan.canApply)
    }

    @Test
    fun `a collision appends the configured number`() {
        val plan = FileNamingPlanner.plan(
            request(originalName = "old.txt", title = "季度预算评审"),
            FileNamingPolicy(conflictSuffix = " ({n})"),
            setOf("季度预算评审.txt"),
        )

        assertEquals("季度预算评审 (2).txt", plan.targetName)
        assertTrue(plan.canApply)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.CONFLICT_APPENDED })
    }

    @Test
    fun `a collision is case insensitive`() {
        val plan = FileNamingPlanner.plan(
            request(originalName = "old.txt", title = "Report"),
            FileNamingPolicy(lowercaseLatin = true),
            setOf("REPORT.TXT"),
        )

        assertEquals("report (2).txt", plan.targetName)
    }

    @Test
    fun `batch planning does not reuse a target`() {
        val plans = FileNamingPlanner.planBatch(
            listOf(
                request(id = "one", originalName = "one.txt", title = "报告"),
                request(id = "two", originalName = "two.txt", title = "报告"),
            ),
            FileNamingPolicy(),
            emptySet(),
        )

        assertEquals("报告.txt", plans[0].targetName)
        assertEquals("报告 (2).txt", plans[1].targetName)
        assertTrue(plans.all { it.canApply })
    }

    @Test
    fun `block conflict policy never overwrites`() {
        val plan = FileNamingPlanner.plan(
            request(originalName = "old.txt", title = "报告"),
            FileNamingPolicy(conflictPolicy = FileNamingConflictPolicy.BLOCK),
            setOf("报告.txt"),
        )

        assertFalse(plan.canApply)
        assertEquals("报告.txt", plan.targetName)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.CONFLICT_BLOCKED })
    }

    @Test
    fun `unchanged target carries a warning`() {
        val plan = FileNamingPlanner.plan(
            request(originalName = "季度预算评审.txt", title = "季度预算评审"),
            FileNamingPolicy(),
            setOf("季度预算评审.txt"),
        )

        assertTrue(plan.canApply)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.UNCHANGED })
    }

    @Test
    fun `an unknown token blocks every plan in the batch`() {
        val policy = FileNamingPolicy(template = "{title}-{owner}")
        val plan = FileNamingPlanner.plan(request(), policy, emptySet())

        assertFalse(plan.canApply)
        assertTrue(plan.warnings.any { it.code == FileNamingWarningCode.INVALID_POLICY })
        assertTrue(FileNamingPolicyError.UNKNOWN_TOKEN in policy.validationErrors())
    }

    @Test
    fun `invalid separators suffixes and missing title are reported`() {
        assertTrue(
            FileNamingPolicyError.INVALID_SEPARATOR in
                FileNamingPolicy(separator = "/").validationErrors(),
        )
        assertTrue(
            FileNamingPolicyError.INVALID_CONFLICT_SUFFIX in
                FileNamingPolicy(conflictSuffix = "").validationErrors(),
        )
        assertTrue(
            FileNamingPolicyError.MISSING_TITLE_TOKEN in
                FileNamingPolicy(template = "{category}").validationErrors(),
        )
    }

    @Test
    fun `a config without file naming uses defaults without changing old fields`() {
        withTemporaryDirectory("file-naming-config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"schemaVersion":3,"enabled":false,"clipboardEnabled":false}""")

            val loaded = ConfigStore(path.toString()).load()

            assertFalse(loaded.enabled)
            assertFalse(loaded.clipboardEnabled)
            assertEquals(FileNamingPolicy.defaults(), loaded.fileNaming)
        }
    }

    @Test
    fun `file naming settings survive a save and load`() {
        withTemporaryDirectory("file-naming-config") { directory ->
            val path = directory.resolve("config.json")
            val store = ConfigStore(path.toString())
            store.save(
                AppConfig(
                    fileNaming = FileNamingPolicy(
                        template = "{date}-{title}",
                        dateSource = FileNamingDateSource.FILE_CREATED,
                        conflictPolicy = FileNamingConflictPolicy.BLOCK,
                        minConfidence = 0.8,
                    ),
                ),
            )

            val loaded = store.load()

            assertEquals("{date}-{title}", loaded.fileNaming.template)
            assertEquals(FileNamingDateSource.FILE_CREATED, loaded.fileNaming.dateSource)
            assertEquals(FileNamingConflictPolicy.BLOCK, loaded.fileNaming.conflictPolicy)
            assertEquals(0.8, loaded.fileNaming.minConfidence)
        }
    }

    @Test
    fun `an unknown nested file naming key survives save`() {
        withTemporaryDirectory("file-naming-config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """{"schemaVersion":3,"fileNaming":{"template":"{title}","futureOption":42}}""",
            )
            val store = ConfigStore(path.toString())
            val loaded = store.load().copy(enabled = false)

            store.save(loaded)

            assertTrue(path.readText().contains("\"futureOption\""))
            assertTrue(path.readText().contains("42"))
        }
    }

    @Test
    fun `a malformed file naming object falls back without breaking the rest of the config`() {
        withTemporaryDirectory("file-naming-config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"schemaVersion":3,"enabled":false,"fileNaming":"bad"}""")

            val loaded = ConfigStore(path.toString()).load()

            assertFalse(loaded.enabled)
            assertEquals(FileNamingPolicy.defaults(), loaded.fileNaming)
        }
    }

    @Test
    fun `a malformed nested field only falls back that field`() {
        withTemporaryDirectory("file-naming-config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """
                {
                  "schemaVersion": 3,
                  "fileNaming": {
                    "template": "{category}-{title}",
                    "maxUTF8Bytes": "bad",
                    "minConfidence": 0.8
                  }
                }
                """.trimIndent(),
            )

            val loaded = ConfigStore(path.toString()).load()

            assertEquals("{category}-{title}", loaded.fileNaming.template)
            assertEquals(240, loaded.fileNaming.maxUTF8Bytes)
            assertEquals(0.8, loaded.fileNaming.minConfidence)
        }
    }

    @Test
    fun `policy and plan warnings keep stable enums`() {
        val plan = FileNamingPlanner.plan(request(), FileNamingPolicy(), emptySet())
        val policy = FileNamingPolicy()

        assertNotNull(plan.targetName)
        assertEquals(FileNamingPlanStatus.READY, plan.status)
        assertEquals(FILE_NAMING_SCHEMA_VERSION, policy.schemaVersion)
    }
}
