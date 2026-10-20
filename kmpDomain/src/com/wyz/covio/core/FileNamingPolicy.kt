package com.wyz.covio.core

private const val MAX_CONFLICT_ATTEMPTS = 10_000
private const val FORBIDDEN_FILE_NAME_CHARS = "<>:\"/\\|?*"
private val TEMPLATE_TOKEN = Regex("\\{([^{}]+)}")
private val ALLOWED_TEMPLATE_TOKENS = setOf("title", "category", "date", "language")
private val FILE_EXISTS_TOKEN = Regex("\\{n}")
private val WINDOWS_RESERVED_NAMES = setOf(
    "con", "prn", "aux", "nul",
    "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
    "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
)

internal fun validateFileNamingPolicy(policy: FileNamingPolicy): List<FileNamingPolicyError> {
    val errors = ArrayList<FileNamingPolicyError>()
    val template = policy.template.trim()
    val tokens = TEMPLATE_TOKEN.findAll(template).map { it.groupValues[1] }.toList()
    val withoutTokens = TEMPLATE_TOKEN.replace(template, "")

    if ("title" !in tokens) errors += FileNamingPolicyError.MISSING_TITLE_TOKEN
    if (tokens.any { it !in ALLOWED_TEMPLATE_TOKENS }) errors += FileNamingPolicyError.UNKNOWN_TOKEN
    if (withoutTokens.contains('{') || withoutTokens.contains('}')) {
        errors += FileNamingPolicyError.UNBALANCED_TOKEN
    }
    if (withoutTokens.any(::isUnsafeFileCharacter)) {
        errors += FileNamingPolicyError.UNSAFE_TEMPLATE
    }
    if (!isValidSeparator(policy.separator)) {
        errors += FileNamingPolicyError.INVALID_SEPARATOR
    }
    if (policy.conflictPolicy == FileNamingConflictPolicy.APPEND_NUMBER &&
        !isValidConflictSuffix(policy.conflictSuffix)
    ) {
        errors += FileNamingPolicyError.INVALID_CONFLICT_SUFFIX
    }
    return errors.distinct()
}

internal fun isUnsafeFileCharacter(ch: Char): Boolean =
    isControlCharacter(ch) || ch in FORBIDDEN_FILE_NAME_CHARS

private fun isControlCharacter(ch: Char): Boolean =
    ch.code <= 0x1F || ch.code in 0x7F..0x9F

private fun isValidSeparator(value: String): Boolean =
    value.isNotEmpty() &&
        value.length <= 3 &&
        value.all { it.isLetterOrDigit() || it in "-_.()" } &&
        !value.any(::isUnsafeFileCharacter)

private fun isValidConflictSuffix(value: String): Boolean {
    if (value.isEmpty() || !value.contains("{n}")) return false
    val withoutCounter = FILE_EXISTS_TOKEN.replace(value, "")
    return !withoutCounter.contains('{') &&
        !withoutCounter.contains('}') &&
        withoutCounter.none(::isUnsafeFileCharacter)
}

/**
 * 文件名的纯规划器。
 *
 * 它不访问磁盘。调用方传入同目录已有名称，规划器负责批量去重。
 * KMP 与 Swift 因此可以共享同一套模板、冲突和拒绝规则。
 */
object FileNamingPlanner {
    fun plan(
        request: FileNamingRequest,
        policy: FileNamingPolicy,
        existingNames: Set<String>,
    ): FileNamingPlan = planBatch(listOf(request), policy, existingNames).single()

    fun planBatch(
        requests: List<FileNamingRequest>,
        policy: FileNamingPolicy,
        existingNames: Set<String>,
    ): List<FileNamingPlan> {
        val rules = policy.normalized()
        val policyErrors = rules.validationErrors()
        val existing = existingNames.mapNotNull(::lookupName).toMutableSet()
        val used = existing.toMutableSet()

        return requests.map { request ->
            val originalName = fileNameOnly(request.originalName)
            val extension = extensionOf(originalName)
            val confidence = request.facts.confidence.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 0.0
            val warnings = ArrayList<FileNamingWarning>()

            if (request.candidateId.isBlank()) {
                warnings += warning(FileNamingWarningCode.INVALID_REQUEST, "Candidate ID is empty")
                return@map blocked(request, originalName, extension, confidence, warnings)
            }
            if (policyErrors.isNotEmpty()) {
                warnings += warning(FileNamingWarningCode.INVALID_POLICY, policyErrors.joinToString(","))
                return@map blocked(request, originalName, extension, confidence, warnings)
            }
            if (!isSafeOriginalName(originalName)) {
                warnings += warning(
                    if (originalName.startsWith('.')) {
                        FileNamingWarningCode.HIDDEN_FILE_UNSUPPORTED
                    } else {
                        FileNamingWarningCode.INVALID_ORIGINAL_NAME
                    },
                    originalName,
                )
                return@map blocked(request, originalName, extension, confidence, warnings)
            }
            if (request.facts.kind == FileNamingKind.UNKNOWN) {
                warnings += warning(FileNamingWarningCode.UNKNOWN_TYPE)
                return@map blocked(request, originalName, extension, confidence, warnings)
            }
            if (confidence < rules.minConfidence) {
                warnings += warning(
                    FileNamingWarningCode.LOW_CONFIDENCE,
                    "$confidence < ${rules.minConfidence}",
                )
                return@map blocked(request, originalName, extension, confidence, warnings)
            }
            if (request.facts.title.isBlank()) {
                warnings += warning(FileNamingWarningCode.EMPTY_TITLE)
                return@map blocked(request, originalName, extension, confidence, warnings)
            }
            if (request.facts.kind == FileNamingKind.MIXED) {
                warnings += warning(FileNamingWarningCode.MIXED_INPUT)
            }

            val rendered = renderStem(request.facts, rules, extension)
            if (rendered.isEmpty()) {
                warnings += warning(FileNamingWarningCode.EMPTY_TITLE)
                return@map blocked(request, originalName, extension, confidence, warnings)
            }

            val remainingBytes = rules.maxUTF8Bytes - extension.encodeToByteArray().size
            if (remainingBytes <= 0) {
                warnings += warning(FileNamingWarningCode.NAME_TOO_LONG, "Extension uses the byte budget")
                return@map blocked(request, originalName, extension, confidence, warnings)
            }

            val fitted = truncateUtf8(rendered, remainingBytes)
            if (fitted.isEmpty()) {
                warnings += warning(FileNamingWarningCode.EMPTY_TITLE)
                return@map blocked(request, originalName, extension, confidence, warnings)
            }

            val ownLookup = lookupName(originalName)
            var targetName = fitted + extension
            if (!isSafeTargetName(targetName, rules)) {
                warnings += warning(FileNamingWarningCode.UNSAFE_NAME, targetName)
                return@map blocked(request, originalName, extension, confidence, warnings, targetName)
            }

            val isOwnName = lookupName(targetName) == ownLookup
            if (!isOwnName && lookupName(targetName) in used) {
                when (rules.conflictPolicy) {
                    FileNamingConflictPolicy.BLOCK -> {
                        warnings += warning(FileNamingWarningCode.CONFLICT_BLOCKED, targetName)
                        return@map blocked(request, originalName, extension, confidence, warnings, targetName)
                    }

                    FileNamingConflictPolicy.APPEND_NUMBER -> {
                        val unique = uniqueTarget(
                            stem = fitted,
                            extension = extension,
                            policy = rules,
                            used = used,
                        )
                        if (unique == null) {
                            warnings += warning(FileNamingWarningCode.CONFLICT_BLOCKED, targetName)
                            return@map blocked(request, originalName, extension, confidence, warnings, targetName)
                        }
                        targetName = unique
                        warnings += warning(FileNamingWarningCode.CONFLICT_APPENDED, targetName)
                    }
                }
            }

            if (lookupName(targetName) == ownLookup) {
                warnings += warning(FileNamingWarningCode.UNCHANGED)
            }
            lookupName(targetName)?.let(used::add)
            FileNamingPlan(
                candidateId = request.candidateId,
                originalName = originalName,
                targetName = targetName,
                extension = extension,
                confidence = confidence,
                status = FileNamingPlanStatus.READY,
                warnings = warnings,
            )
        }
    }

    private fun renderStem(
        facts: NamingFacts,
        policy: FileNamingPolicy,
        originalExtension: String,
    ): String {
        val date = if (policy.dateSource == FileNamingDateSource.NONE) "" else facts.date.orEmpty()
        val values = mapOf(
            "title" to facts.title,
            "category" to facts.category,
            "date" to date,
            "language" to facts.language.orEmpty(),
        )
        var rendered = policy.template
        for ((token, value) in values) {
            rendered = rendered.replace("{$token}", sanitizeValue(value, policy.separator))
        }
        rendered = rendered
            .replace(Regex("\\s+"), " ")
            .trim()
            .trim(' ', '.')

        if (policy.lowercaseLatin) {
            rendered = rendered.map { ch ->
                if (ch in 'A'..'Z') ch.lowercaseChar() else ch
            }.joinToString("")
        }
        if (originalExtension.isNotEmpty() && rendered.endsWith(originalExtension, ignoreCase = true)) {
            rendered = rendered.dropLast(originalExtension.length).trim(' ', '.')
        }
        return rendered
    }

    private fun sanitizeValue(value: String, separator: String): String {
        val output = StringBuilder()
        var lastWasReplacement = false
        for (ch in value.trim()) {
            when {
                ch.isWhitespace() -> {
                    if (output.isNotEmpty() && output.last() != ' ') output.append(' ')
                    lastWasReplacement = false
                }

                ch.isLetterOrDigit() || ch in "-_.()" -> {
                    output.append(ch)
                    lastWasReplacement = false
                }

                !isControlCharacter(ch) -> {
                    if (output.isNotEmpty() && !lastWasReplacement) {
                        output.append(separator)
                        lastWasReplacement = true
                    }
                }
            }
        }
        return output.toString().trim(' ', '.')
    }

    private fun uniqueTarget(
        stem: String,
        extension: String,
        policy: FileNamingPolicy,
        used: Set<String>,
    ): String? {
        for (number in 2..MAX_CONFLICT_ATTEMPTS) {
            val suffix = policy.conflictSuffix.replace("{n}", number.toString())
            val maxStemBytes = policy.maxUTF8Bytes -
                extension.encodeToByteArray().size -
                suffix.encodeToByteArray().size
            if (maxStemBytes <= 0) return null
            val candidateStem = truncateUtf8(stem, maxStemBytes) + suffix
            val candidate = candidateStem + extension
            if (isSafeTargetName(candidate, policy) && lookupName(candidate) !in used) {
                return candidate
            }
        }
        return null
    }

    private fun isSafeOriginalName(value: String): Boolean =
        value.isNotEmpty() &&
            value != "." &&
            value != ".." &&
            !value.startsWith('.') &&
            value == value.trim() &&
            !value.endsWith('.') &&
            value.none(::isUnsafeFileCharacter)

    private fun isSafeTargetName(value: String, policy: FileNamingPolicy): Boolean {
        if (value.isEmpty() || value == "." || value == "..") return false
        if (value != value.trim() || value.startsWith('.') || value.endsWith('.')) return false
        if (value.encodeToByteArray().size > policy.maxUTF8Bytes) return false
        if (value.any(::isUnsafeFileCharacter)) return false
        val stem = extensionOf(value).let { extension -> value.removeSuffix(extension) }
        if (stem.isEmpty()) return false
        if (stem.lowercase() in WINDOWS_RESERVED_NAMES) return false
        return true
    }

    private fun truncateUtf8(value: String, maxBytes: Int): String {
        if (value.encodeToByteArray().size <= maxBytes) return value
        val output = StringBuilder()
        var used = 0
        var index = 0
        while (index < value.length) {
            val length = if (
                index + 1 < value.length &&
                value[index].isHighSurrogate() &&
                value[index + 1].isLowSurrogate()
            ) {
                2
            } else {
                1
            }
            val segment = value.substring(index, index + length)
            val bytes = segment.encodeToByteArray().size
            if (used + bytes > maxBytes) break
            output.append(segment)
            used += bytes
            index += length
        }
        return output.toString().trim(' ', '.')
    }

    private fun fileNameOnly(value: String): String =
        value.trim().substringAfterLast('/').substringAfterLast('\\').trim()

    private fun extensionOf(fileName: String): String {
        val dot = fileName.lastIndexOf('.')
        if (dot <= 0 || dot == fileName.lastIndex) return ""
        return fileName.substring(dot)
    }

    private fun lookupName(value: String): String? {
        val leaf = fileNameOnly(value)
        return if (leaf.isEmpty()) null else leaf.lowercase()
    }

    private fun blocked(
        request: FileNamingRequest,
        originalName: String,
        extension: String,
        confidence: Double,
        warnings: List<FileNamingWarning>,
        targetName: String? = null,
    ): FileNamingPlan = FileNamingPlan(
        candidateId = request.candidateId,
        originalName = originalName,
        targetName = targetName,
        extension = extension,
        confidence = confidence,
        status = FileNamingPlanStatus.BLOCKED,
        warnings = warnings,
    )

    private fun warning(code: FileNamingWarningCode, detail: String = ""): FileNamingWarning =
        FileNamingWarning(code = code, detail = detail)
}

private fun Char.isHighSurrogate(): Boolean = code in 0xD800..0xDBFF

private fun Char.isLowSurrogate(): Boolean = code in 0xDC00..0xDFFF
