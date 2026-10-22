package com.wyz.covio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

const val FILE_NAMING_SCHEMA_VERSION = 1
const val DEFAULT_FILE_NAMING_TEMPLATE = "{title}"
const val DEFAULT_FILE_NAMING_MAX_UTF8_BYTES = 240
const val DEFAULT_FILE_NAMING_MIN_CONFIDENCE = 0.65

/** 日期来源。日期值始终由 Swift 提取器提供，模型不能直接决定。 */
@Serializable
enum class FileNamingDateSource {
    @SerialName("none") NONE,
    @SerialName("content") CONTENT,
    @SerialName("fileCreated") FILE_CREATED,
}

/** 同名文件的处理方式。 */
@Serializable
enum class FileNamingConflictPolicy {
    @SerialName("appendNumber") APPEND_NUMBER,
    @SerialName("block") BLOCK,
}

/** 输入文件的内容类别。 */
@Serializable
enum class FileNamingKind {
    @SerialName("text") TEXT,
    @SerialName("pdf") PDF,
    @SerialName("image") IMAGE,
    @SerialName("code") CODE,
    @SerialName("mixed") MIXED,
    @SerialName("unknown") UNKNOWN,
}

/** 配置校验错误。错误码稳定，显示文案由 Swift 层负责。 */
@Serializable
enum class FileNamingPolicyError {
    @SerialName("missingTitleToken") MISSING_TITLE_TOKEN,
    @SerialName("unknownToken") UNKNOWN_TOKEN,
    @SerialName("unbalancedToken") UNBALANCED_TOKEN,
    @SerialName("invalidSeparator") INVALID_SEPARATOR,
    @SerialName("invalidConflictSuffix") INVALID_CONFLICT_SUFFIX,
    @SerialName("unsafeTemplate") UNSAFE_TEMPLATE,
}

/** 单条计划的告警。告警不表示模型错误，UI 必须显示风险。 */
@Serializable
enum class FileNamingWarningCode {
    @SerialName("invalidRequest") INVALID_REQUEST,
    @SerialName("invalidOriginalName") INVALID_ORIGINAL_NAME,
    @SerialName("hiddenFileUnsupported") HIDDEN_FILE_UNSUPPORTED,
    @SerialName("unknownType") UNKNOWN_TYPE,
    @SerialName("lowConfidence") LOW_CONFIDENCE,
    @SerialName("invalidPolicy") INVALID_POLICY,
    @SerialName("emptyTitle") EMPTY_TITLE,
    @SerialName("unsafeName") UNSAFE_NAME,
    @SerialName("nameTooLong") NAME_TOO_LONG,
    @SerialName("conflictBlocked") CONFLICT_BLOCKED,
    @SerialName("conflictAppended") CONFLICT_APPENDED,
    @SerialName("unchanged") UNCHANGED,
    @SerialName("mixedInput") MIXED_INPUT,
    @SerialName("missingTokenValue") MISSING_TOKEN_VALUE,
}

/** 计划状态。只有 READY 才允许进入应用阶段。 */
@Serializable
enum class FileNamingPlanStatus {
    @SerialName("ready") READY,
    @SerialName("blocked") BLOCKED,
}

@Serializable
data class FileNamingPolicy(
    @SerialName("schemaVersion") val schemaVersion: Int = FILE_NAMING_SCHEMA_VERSION,
    @SerialName("template") val template: String = DEFAULT_FILE_NAMING_TEMPLATE,
    @SerialName("maxUTF8Bytes") val maxUTF8Bytes: Int = DEFAULT_FILE_NAMING_MAX_UTF8_BYTES,
    @SerialName("separator") val separator: String = "-",
    @SerialName("lowercaseLatin") val lowercaseLatin: Boolean = false,
    @SerialName("preserveExtension") val preserveExtension: Boolean = true,
    @SerialName("dateSource") val dateSource: FileNamingDateSource = FileNamingDateSource.NONE,
    @SerialName("conflictPolicy") val conflictPolicy: FileNamingConflictPolicy = FileNamingConflictPolicy.APPEND_NUMBER,
    @SerialName("conflictSuffix") val conflictSuffix: String = " ({n})",
    @SerialName("minConfidence") val minConfidence: Double = DEFAULT_FILE_NAMING_MIN_CONFIDENCE,
    @SerialName("requirePreview") val requirePreview: Boolean = true,
    @SerialName("allowVision") val allowVision: Boolean = true,
) {
    /**
     * 兜底规范化。
     *
     * 扩展名和预览是产品安全底线，不能由配置关闭。
     */
    fun normalized(): FileNamingPolicy = copy(
        schemaVersion = FILE_NAMING_SCHEMA_VERSION,
        template = template.trim(),
        maxUTF8Bytes = maxUTF8Bytes.coerceIn(1, 255),
        separator = separator.trim(),
        preserveExtension = true,
        conflictSuffix = conflictSuffix.trimEnd(),
        minConfidence = minConfidence
            .takeIf { it.isFinite() }
            ?.coerceIn(0.0, 1.0)
            ?: DEFAULT_FILE_NAMING_MIN_CONFIDENCE,
        requirePreview = true,
    )

    fun validationErrors(): List<FileNamingPolicyError> = validateFileNamingPolicy(this)

    companion object {
        fun defaults(): FileNamingPolicy = FileNamingPolicy()
    }
}

/** 模型与本地规则共同形成的命名事实。 */
@Serializable
data class NamingFacts(
    @SerialName("title") val title: String,
    @SerialName("category") val category: String = "",
    @SerialName("date") val date: String? = null,
    @SerialName("language") val language: String? = null,
    @SerialName("confidence") val confidence: Double = 1.0,
    @SerialName("kind") val kind: FileNamingKind = FileNamingKind.TEXT,
)

/** 一个待规划的文件。文件路径只留在调用侧，本模型只接收显示文件名。 */
@Serializable
data class FileNamingRequest(
    @SerialName("candidateId") val candidateId: String,
    @SerialName("originalName") val originalName: String,
    @SerialName("facts") val facts: NamingFacts,
)

@Serializable
data class FileNamingWarning(
    @SerialName("code") val code: FileNamingWarningCode,
    @SerialName("detail") val detail: String = "",
)

/** UI 只需读取这个计划。写入路径由 Swift 在确认阶段重新校验。 */
@Serializable
data class FileNamingPlan(
    @SerialName("candidateId") val candidateId: String,
    @SerialName("originalName") val originalName: String,
    @SerialName("targetName") val targetName: String? = null,
    @SerialName("extension") val extension: String = "",
    @SerialName("confidence") val confidence: Double = 0.0,
    @SerialName("status") val status: FileNamingPlanStatus = FileNamingPlanStatus.BLOCKED,
    @SerialName("warnings") val warnings: List<FileNamingWarning> = emptyList(),
) {
    val canApply: Boolean get() = status == FileNamingPlanStatus.READY
}
