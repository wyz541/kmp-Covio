package com.wyz.covio.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okio.FileSystem
import okio.Path.Companion.toPath
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * 模型包合同的共享语料。
 *
 * Swift 侧的 `ModelPackageContractParityTests` 读取同一份文件。
 * Kotlin 侧钉住业务规则，Swift 侧钉住导出形状与本地 Codable 镜像。
 */
class ModelPackageContractTest {
    private val fixturePath: String? = sequenceOf(
        "kmpDomain/test/fixtures/model-package-vectors.json",
        "../kmpDomain/test/fixtures/model-package-vectors.json",
        "../../kmpDomain/test/fixtures/model-package-vectors.json",
    ).firstOrNull { FileSystem.SYSTEM.exists(it.toPath()) }

    @Test
    fun `the valid corpus passes the shared contract`() {
        val (manifest, expectation) = manifestAndExpectation()
        val validation = ModelPackageContract.validateManifest(manifest, expectation)

        assertTrue(validation.valid, validation.detail)
        assertEquals(null, validation.errorCode)
    }

    @Test
    fun `unsafe file paths are rejected before any platform moves files`() {
        val (manifest, expectation) = manifestAndExpectation()
        for (path in listOf("../model.safetensors", "CON", "model:weights")) {
            val unsafe = manifest.copy(
                files = listOf(manifest.files.single().copy(path = path)),
            )
            val validation = ModelPackageContract.validateManifest(unsafe, expectation)

            assertFalse(validation.valid, path)
            assertEquals(ModelPackageContractError.INVALID_PATH.wire, validation.errorCode, path)
        }
    }

    @Test
    fun `revision and total size come from the trusted expectation`() {
        val (manifest, expectation) = manifestAndExpectation()

        val wrongRevision = ModelPackageContract.validateManifest(
            manifest.copy(revision = "b".repeat(40)),
            expectation,
        )
        val wrongSize = ModelPackageContract.validateManifest(
            manifest.copy(totalBytes = 7),
            expectation,
        )

        assertEquals(ModelPackageContractError.REVISION_MISMATCH.wire, wrongRevision.errorCode)
        assertEquals(ModelPackageContractError.TOTAL_SIZE_MISMATCH.wire, wrongSize.errorCode)
    }

    @Test
    fun `status and registry keep the shared JSON field names`() {
        val document = document()
        val status = ModelPackageContract.decodeStatus(document.getValue("status").toString())
        val registry = ModelPackageContract.decodeRegistry(document.getValue("registry").toString())

        assertNotNull(status)
        assertEquals("2b", status.tier)
        assertEquals(ModelDownloadPhaseContract.DOWNLOADING, status.phase)
        assertEquals(3L, status.downloadedBytes)
        assertNotNull(registry)
        assertEquals("2b", registry.selectedTier)
        assertEquals(status.modelId, registry.packages.single().modelId)
    }

    @Test
    fun `interrupted phases become paused and progress stays bounded`() {
        assertEquals("paused", ModelDownloadStatePolicy.phaseKeyAfterInterruption("downloading"))
        assertEquals("paused", ModelDownloadStatePolicy.phaseKeyAfterInterruption("verifying"))
        assertEquals("ready", ModelDownloadStatePolicy.phaseKeyAfterInterruption("ready"))
        assertEquals("paused", ModelDownloadStatePolicy.phaseKeyAfterFailure(paused = true))
        assertEquals("failed", ModelDownloadStatePolicy.phaseKeyAfterFailure(paused = false))
        assertEquals(0.0, ModelDownloadStatePolicy.clampProgress(-1.0))
        assertEquals(1.0, ModelDownloadStatePolicy.clampProgress(2.0))
        assertEquals(3L, ModelDownloadStatePolicy.downloadedBytes(0.5, 6L))
    }

    @Test
    fun `phase and error wire keys are stable`() {
        assertEquals(
            listOf("notDownloaded", "downloading", "paused", "verifying", "ready", "failed"),
            ModelDownloadPhaseContract.entries.map { it.wire },
        )
        assertEquals(
            listOf(
                "busy",
                "sourceUnavailable",
                "manifestInvalid",
                "insufficientHardware",
                "insufficientMemory",
                "insufficientDisk",
                "cancelled",
                "downloadFailed",
                "verificationFailed",
                "existingPackageInvalid",
                "activationFailed",
            ),
            ModelDownloadErrorCodeContract.entries.map { it.wire },
        )
    }

    private fun manifestAndExpectation(): Pair<ModelPackageManifestContract, ModelPackageExpectationContract> {
        val document = document()
        val manifest = assertNotNull(
            ModelPackageContract.decodeManifest(document.getValue("manifest").toString()),
        )
        val expectation = Json.decodeFromString(
            ModelPackageExpectationContract.serializer(),
            document.getValue("expectation").toString(),
        )
        return manifest to expectation
    }

    private fun document(): JsonObject {
        val path = assertNotNull(
            fixturePath,
            "找不到模型包合同语料。工作目录是 ${FileSystem.SYSTEM.canonicalize(".".toPath())}",
        )
        return Json.parseToJsonElement(FileSystem.SYSTEM.read(path.toPath()) { readUtf8() }).jsonObject
    }
}
