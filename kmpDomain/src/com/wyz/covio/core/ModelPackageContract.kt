package com.wyz.covio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** 模型包清单的稳定版本。平台适配层不能各自解释不同版本。 */
const val MODEL_PACKAGE_SCHEMA_VERSION = 1

/** 下载状态的持久化版本。 */
const val MODEL_DOWNLOAD_STATUS_SCHEMA_VERSION = 1

/** 模型包中的一个文件。 */
@Serializable
data class ModelPackageFileContract(
    @SerialName("path") val path: String,
    @SerialName("size") val size: Long,
    @SerialName("sha256") val sha256: String,
)

/**
 * App 内模型清单的共享合同。
 *
 * 远端只能提供文件字节。模型身份、revision、许可证和文件集合都由这份清单决定。
 */
@Serializable
data class ModelPackageManifestContract(
    @SerialName("schemaVersion") val schemaVersion: Int,
    @SerialName("tier") val tier: String,
    @SerialName("modelID") val modelId: String,
    @SerialName("revision") val revision: String,
    @SerialName("displayName") val displayName: String,
    @SerialName("runtimeDirectory") val runtimeDirectory: String,
    @SerialName("license") val license: String,
    @SerialName("licenseFile") val licenseFile: String,
    @SerialName("noticeFile") val noticeFile: String,
    @SerialName("totalBytes") val totalBytes: Long,
    @SerialName("files") val files: List<ModelPackageFileContract>,
)

/** 某个平台和 runtime 信任的模型身份。 */
@Serializable
data class ModelPackageExpectationContract(
    @SerialName("tier") val tier: String,
    @SerialName("modelID") val modelId: String,
    @SerialName("revision") val revision: String,
    @SerialName("runtimeDirectory") val runtimeDirectory: String,
    @SerialName("totalBytes") val totalBytes: Long,
    @SerialName("license") val license: String,
)

/** 共享清单校验的稳定错误码。 */
enum class ModelPackageContractError(val wire: String) {
    MANIFEST_UNREADABLE("manifestUnreadable"),
    UNSUPPORTED_SCHEMA("unsupportedSchema"),
    TIER_MISMATCH("tierMismatch"),
    MODEL_MISMATCH("modelMismatch"),
    REVISION_MISMATCH("revisionMismatch"),
    LICENSE_REJECTED("licenseRejected"),
    INVALID_PATH("invalidPath"),
    FILE_MISSING("fileMissing"),
    TOTAL_SIZE_MISMATCH("totalSizeMismatch"),
}

/** 清单校验结果。平台适配层只映射错误码，不改写规则。 */
data class ModelPackageContractValidation(
    val valid: Boolean,
    val errorCode: String?,
    val detail: String,
)

/** 下载阶段。JSON 写法同时是持久化状态与 UI 的稳定接口。 */
@Serializable
enum class ModelDownloadPhaseContract(val wire: String) {
    @SerialName("notDownloaded") NOT_DOWNLOADED("notDownloaded"),
    @SerialName("downloading") DOWNLOADING("downloading"),
    @SerialName("paused") PAUSED("paused"),
    @SerialName("verifying") VERIFYING("verifying"),
    @SerialName("ready") READY("ready"),
    @SerialName("failed") FAILED("failed"),
}

/** 下载错误码。平台适配层只提供错误事实。 */
@Serializable
enum class ModelDownloadErrorCodeContract(val wire: String) {
    @SerialName("busy") BUSY("busy"),
    @SerialName("sourceUnavailable") SOURCE_UNAVAILABLE("sourceUnavailable"),
    @SerialName("manifestInvalid") MANIFEST_INVALID("manifestInvalid"),
    @SerialName("insufficientHardware") INSUFFICIENT_HARDWARE("insufficientHardware"),
    @SerialName("insufficientMemory") INSUFFICIENT_MEMORY("insufficientMemory"),
    @SerialName("insufficientDisk") INSUFFICIENT_DISK("insufficientDisk"),
    @SerialName("cancelled") CANCELLED("cancelled"),
    @SerialName("downloadFailed") DOWNLOAD_FAILED("downloadFailed"),
    @SerialName("verificationFailed") VERIFICATION_FAILED("verificationFailed"),
    @SerialName("existingPackageInvalid") EXISTING_PACKAGE_INVALID("existingPackageInvalid"),
    @SerialName("activationFailed") ACTIVATION_FAILED("activationFailed"),
}

/** 下载状态的共享线格式。Swift 与 JVM 写入同一组字段。 */
@Serializable
data class ModelDownloadStatusContract(
    @SerialName("schemaVersion") val schemaVersion: Int = MODEL_DOWNLOAD_STATUS_SCHEMA_VERSION,
    @SerialName("tier") val tier: String,
    @SerialName("modelID") val modelId: String,
    @SerialName("displayName") val displayName: String,
    @SerialName("revision") val revision: String,
    @SerialName("license") val license: String,
    @SerialName("totalBytes") val totalBytes: Long,
    @SerialName("phase") val phase: ModelDownloadPhaseContract,
    @SerialName("fractionCompleted") val fractionCompleted: Double,
    @SerialName("downloadedBytes") val downloadedBytes: Long,
    @SerialName("errorCode") val errorCode: ModelDownloadErrorCodeContract? = null,
    @SerialName("detail") val detail: String? = null,
    @SerialName("updatedAtEpochMilliseconds") val updatedAtEpochMilliseconds: Long,
)

/** 已登记模型的共享字段。目录路径由各平台自己生成。 */
@Serializable
data class ModelPackageRegistrationContract(
    @SerialName("tier") val tier: String,
    @SerialName("directoryPath") val directoryPath: String,
    @SerialName("modelID") val modelId: String,
    @SerialName("revision") val revision: String,
    @SerialName("totalBytes") val totalBytes: Long,
    @SerialName("license") val license: String,
    @SerialName("verifiedAtEpochMilliseconds") val verifiedAtEpochMilliseconds: Long,
)

/** 模型登记表的共享线格式。 */
@Serializable
data class ModelPackageRegistryContract(
    @SerialName("selectedTier") val selectedTier: String? = null,
    @SerialName("packages") val packages: List<ModelPackageRegistrationContract> = emptyList(),
)

/**
 * 跨平台模型包合同。
 *
 * 平台适配层只回答三个问题：
 * 1. 文件如何下载？
 * 2. 文件如何安全移动？
 * 3. registry 如何原子写入？
 *
 * 模型身份、路径规则、状态和登记规则都留在这里。
 */
object ModelPackageContract {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun decodeManifest(text: String): ModelPackageManifestContract? = runCatching {
        json.decodeFromString(ModelPackageManifestContract.serializer(), text)
    }.getOrNull()

    fun encodeManifest(manifest: ModelPackageManifestContract): String =
        json.encodeToString(ModelPackageManifestContract.serializer(), manifest)

    fun decodeStatus(text: String): ModelDownloadStatusContract? = runCatching {
        json.decodeFromString(ModelDownloadStatusContract.serializer(), text)
    }.getOrNull()

    fun encodeStatus(status: ModelDownloadStatusContract): String =
        json.encodeToString(ModelDownloadStatusContract.serializer(), status)

    fun decodeRegistry(text: String): ModelPackageRegistryContract? = runCatching {
        json.decodeFromString(ModelPackageRegistryContract.serializer(), text)
    }.getOrNull()

    fun encodeRegistry(registry: ModelPackageRegistryContract): String =
        json.encodeToString(ModelPackageRegistryContract.serializer(), registry)

    /** Swift 侧传入原始 JSON，避免再复制一份校验规则。 */
    fun validateManifestText(
        manifestText: String,
        expectedTier: String,
        expectedModelId: String,
        expectedRevision: String,
        expectedRuntimeDirectory: String,
        expectedTotalBytes: Long,
        expectedLicense: String,
    ): ModelPackageContractValidation {
        val manifest = decodeManifest(manifestText)
            ?: return rejected(
                ModelPackageContractError.MANIFEST_UNREADABLE,
                "The model manifest is not valid.",
            )
        return validateManifest(
            manifest = manifest,
            expectation = ModelPackageExpectationContract(
                tier = expectedTier,
                modelId = expectedModelId,
                revision = expectedRevision,
                runtimeDirectory = expectedRuntimeDirectory,
                totalBytes = expectedTotalBytes,
                license = expectedLicense,
            ),
        )
    }

    fun validateManifest(
        manifest: ModelPackageManifestContract,
        expectation: ModelPackageExpectationContract,
    ): ModelPackageContractValidation {
        if (manifest.schemaVersion != MODEL_PACKAGE_SCHEMA_VERSION) {
            return rejected(
                ModelPackageContractError.UNSUPPORTED_SCHEMA,
                "The model manifest schema is not supported.",
            )
        }
        if (manifest.tier != expectation.tier || manifest.runtimeDirectory != expectation.runtimeDirectory) {
            return rejected(
                ModelPackageContractError.TIER_MISMATCH,
                "The model package does not match the selected tier.",
            )
        }
        if (manifest.modelId != expectation.modelId) {
            return rejected(
                ModelPackageContractError.MODEL_MISMATCH,
                "The model package identity is not allowed for this tier.",
            )
        }
        if (manifest.revision != expectation.revision || !isPinnedRevision(manifest.revision)) {
            return rejected(
                ModelPackageContractError.REVISION_MISMATCH,
                "The model package revision does not match the pinned revision.",
            )
        }
        if (manifest.license != expectation.license || manifest.license != "Apache-2.0") {
            return rejected(
                ModelPackageContractError.LICENSE_REJECTED,
                "The model package license is not accepted.",
            )
        }
        if (manifest.totalBytes < 0 || manifest.totalBytes != expectation.totalBytes) {
            return rejected(
                ModelPackageContractError.TOTAL_SIZE_MISMATCH,
                "The model package size does not match the trusted definition.",
            )
        }
        if (manifest.files.isEmpty()) {
            return rejected(
                ModelPackageContractError.FILE_MISSING,
                "The model package has no model files.",
            )
        }

        var totalBytes = 0L
        val seen = mutableSetOf<String>()
        for (file in manifest.files) {
            if (file.size < 0) {
                return rejected(
                    ModelPackageContractError.TOTAL_SIZE_MISMATCH,
                    "The model package contains a negative file size.",
                )
            }
            val nextTotal = totalBytes + file.size
            if (nextTotal < totalBytes) {
                return rejected(
                    ModelPackageContractError.TOTAL_SIZE_MISMATCH,
                    "The model package size overflows.",
                )
            }
            totalBytes = nextTotal
            if (!isSafeFileName(file.path) || !seen.add(file.path)) {
                return rejected(
                    ModelPackageContractError.INVALID_PATH,
                    "The model package contains an invalid file path.",
                )
            }
        }
        if (manifest.totalBytes != totalBytes) {
            return rejected(
                ModelPackageContractError.TOTAL_SIZE_MISMATCH,
                "The model package size does not match its files.",
            )
        }
        if (!isSafeFileName(manifest.licenseFile) || !isSafeFileName(manifest.noticeFile)) {
            return rejected(
                ModelPackageContractError.INVALID_PATH,
                "The model package contains an invalid attribution path.",
            )
        }
        return ModelPackageContractValidation(valid = true, errorCode = null, detail = "")
    }

    /** manifest 与 attribution 只接受不含目录的通配文件名。 */
    fun isSafeFileName(name: String): Boolean {
        if (name.isEmpty() || name == "." || name == "..") return false
        if (name.any { it.code < 0x20 || it in "\\/:*?\"<>|[]" }) return false
        if (name.endsWith(' ') || name.endsWith('.')) return false
        val stem = name.substringBefore('.').uppercase()
        if (stem in WINDOWS_RESERVED_NAMES) return false
        return true
    }

    private fun isPinnedRevision(value: String): Boolean =
        value.length == 40 && value.all { it.digitToIntOrNull(16) != null }

    private fun rejected(
        error: ModelPackageContractError,
        detail: String,
    ): ModelPackageContractValidation =
        ModelPackageContractValidation(valid = false, errorCode = error.wire, detail = detail)

    private val WINDOWS_RESERVED_NAMES = buildSet {
        addAll(listOf("CON", "PRN", "AUX", "NUL"))
        for (index in 1..9) {
            add("COM$index")
            add("LPT$index")
        }
    }
}

/** 两个平台共用的进度与中断状态规则。 */
object ModelDownloadStatePolicy {
    fun clampProgress(value: Double): Double =
        if (value.isFinite()) value.coerceIn(0.0, 1.0) else 0.0

    fun downloadedBytes(fractionCompleted: Double, totalBytes: Long): Long {
        if (totalBytes <= 0L) return 0L
        return (clampProgress(fractionCompleted) * totalBytes.toDouble()).toLong()
    }

    fun phaseKeyAfterInterruption(phaseKey: String): String = when (phaseKey) {
        "downloading", "verifying" -> "paused"
        else -> phaseKey
    }

    fun phaseKeyAfterFailure(paused: Boolean): String = if (paused) "paused" else "failed"
}

/** 文件下载端口。macOS 使用 Swift Hub，JVM 使用自己的 HTTP 客户端。 */
interface ModelPackageTransport {
    suspend fun download(
        manifest: ModelPackageManifestContract,
        downloadBase: String,
        onProgress: (Double) -> Unit,
    ): String
}

/**
 * 文件系统端口。
 *
 * [moveAtomically] 回答文件如何安全移动。
 * [writeTextAtomically] 回答 registry 如何原子写入。
 */
interface ModelPackageStorage {
    fun availableDiskBytes(path: String): Long?
    fun moveAtomically(source: String, destination: String)
    fun writeTextAtomically(path: String, text: String)
}
