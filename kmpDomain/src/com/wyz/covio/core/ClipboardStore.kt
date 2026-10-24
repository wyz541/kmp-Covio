package com.wyz.covio.core

import kotlinx.serialization.json.Json
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath

/**
 * 剪切板状态的持久化。
 *
 * **没有用 SQLDelight。** 计划里写的是 SQLDelight 加 `native-driver`，
 * 但 Amper 0.12.1 没有 sqldelight-codegen 插件（CLI 的 lib 里搜不到任何相关类），
 * 配不出来。所以改用与 [ShelfStore] 同一套做法：一个 `@Serializable` 状态对象，
 * 先用 okio 写 `.tmp`，再原子改名。条目数量有上限，整份读写足够快。
 *
 * 图片等二进制不放在这个文件里，只放路径。文件落在 [defaultClipboardDirectory]。
 */
class ClipboardStore(
    val path: String = defaultClipboardPath(),
    private val fileSystem: FileSystem = FileSystem.SYSTEM,
    private val json: Json = defaultJson(),
) {
    fun load(): ClipboardState {
        if (!fileSystem.exists(path.toPath())) return ClipboardState()
        return runCatching {
            json.decodeFromString<ClipboardState>(fileSystem.read(path.toPath()) { readUtf8() })
        }.getOrElse { ClipboardState() }
    }

    /**
     * 写入状态，返回写下去的那一份。
     *
     * **写盘失败不抛异常。** Kotlin 的异常跨到 Swift 没有接收方，
     * 会直接终止进程（`Function doesn't have or inherit @Throws annotation`）。
     * 每复制一次都会走到这里，磁盘满或目录被删都会失败。所以和 [load] 一样咽掉。
     */
    fun save(state: ClipboardState): ClipboardState {
        runCatching {
            val target = path.toPath()
            target.parent?.let { fileSystem.createDirectories(it) }
            val temporary = temporaryPath(target)
            fileSystem.write(temporary) { writeUtf8(json.encodeToString(ClipboardState.serializer(), state)) }
            fileSystem.atomicMove(temporary, target)
        }
        return state
    }

    fun clear(): Boolean = runCatching {
        val target = path.toPath()
        fileSystem.delete(target, mustExist = false)
        fileSystem.delete(temporaryPath(target), mustExist = false)
    }.isSuccess

    private fun temporaryPath(target: Path): Path = target.parent!!.resolve(target.name + ".tmp")

    companion object {
        /**
         * 按路径构造。理由同 [ShelfStore.create]：默认参数不导出到 Swift，
         * 从 Swift 拼一个 `Json` 会让两版写出的文件不同。
         */
        fun create(path: String): ClipboardStore =
            ClipboardStore(path = path, fileSystem = FileSystem.SYSTEM, json = defaultJson())

        internal fun defaultJson(): Json = Json {
            prettyPrint = true
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        /** 规范路径。与 [ShelfStore.canonicalPath] 同一套规则：只做词法处理。 */
        fun canonicalPath(value: String): String = ShelfStore.canonicalPath(value)

        /**
         * 剪贴板里那些条目的落盘目录。
         *
         * 沿用应用数据目录的写法，用 `APP_NAME` 而不是 `APP_ID`。
         */
        fun defaultDirectory(): String =
            "${AppDirectories.userApplicationSupport}/${APP_NAME}/Clipboard"
    }
}

/** 剪切板的纯逻辑。没有 IO，两个平台跑同一份。 */
object ClipboardLogic {
    private val LINK_PATTERN = Regex("""^https?://\S+$""", RegexOption.IGNORE_CASE)
    private val COLOR_PATTERN = Regex(
        """^(#[0-9a-f]{3}|#[0-9a-f]{4}|#[0-9a-f]{6}|#[0-9a-f]{8}|rgba?\([^)]*\)|hsla?\([^)]*\))$""",
        RegexOption.IGNORE_CASE,
    )

    /**
     * 判断一段文本属于哪一类。
     *
     * 只看整段文本的形态，不做语义分析。判断不了就算普通文本。
     */
    fun classify(text: String): ClipKind {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return ClipKind.TEXT
        if (LINK_PATTERN.matches(trimmed)) return ClipKind.LINK
        if (COLOR_PATTERN.matches(trimmed)) return ClipKind.COLOR
        return ClipKind.TEXT
    }

    /**
     * 按保留策略整理条目，返回新的列表。
     *
     * 顺序从新到旧。做四件事：
     *
     * 1. 丢掉正文与路径都为空的坏数据。
     * 2. 同一个标识只留最新的一条。
     * 3. 丢掉过期的条目。置顶的不过期。
     * 4. 先保住置顶的，再按新旧留到条数上限与总字节上限。
     */
    fun prune(
        items: List<ClipItem>,
        policy: ClipPolicy,
        nowEpochSeconds: Long,
        exists: (String) -> Boolean = { true },
    ): List<ClipItem> {
        val rules = policy.normalized()
        val oldestKept = if (rules.maxAgeDays <= 0) {
            Long.MIN_VALUE
        } else {
            nowEpochSeconds - rules.maxAgeDays.toLong() * SECONDS_PER_DAY
        }

        val seen = HashSet<String>()
        val kept = ArrayList<ClipItem>(items.size)
        for (item in items.sortedByDescending { it.createdAtEpochSeconds }) {
            val candidate = item.normalized()
            if (!candidate.isUsable) continue
            if (!seen.add(candidate.identity)) continue
            if (!candidate.pinned && candidate.createdAtEpochSeconds < oldestKept) continue
            if (!hasContent(candidate, exists)) continue
            kept.add(candidate)
        }

        val result = ArrayList<ClipItem>(kept.size)
        var totalBytes = 0L
        var unpinnedCount = 0
        for (item in kept) {
            if (item.pinned) {
                result.add(item)
                continue
            }
            if (unpinnedCount >= rules.maxItems) continue
            val nextTotal = totalBytes + item.byteSize
            if (nextTotal > rules.maxTotalBytes) continue
            totalBytes = nextTotal
            unpinnedCount += 1
            result.add(item)
        }
        return result
    }

    /**
     * 取出待粘贴的队首。
     *
     * 栈里的条目可能已经被删掉，所以顺带把失效的 id 清掉。
     * 返回剩下的栈与队首。
     */
    fun nextPaste(state: ClipboardState): Pair<ClipboardState, ClipItem?> {
        val byId = state.items.associateBy(ClipItem::id)
        val stack = ArrayDeque(state.pasteStack)
        while (stack.isNotEmpty()) {
            val head = stack.removeFirst()
            val item = byId[head] ?: continue
            return state.copy(pasteStack = stack.toList()) to item
        }
        return state.copy(pasteStack = emptyList()) to null
    }

    /** 入栈。已经在栈里的先摘掉，保证同一个条目只排一次。 */
    fun pushPasteStack(stack: List<String>, id: String): List<String> =
        stack.filterNot { it == id } + id

    /**
     * 条目里已经落盘、可以直接导入工作区的文件路径。
     *
     * 图片与文件条目才有路径。文件条目可能复制了多个文件：
     * `filePath` 是第一个，完整列表按行放在 `text` 里。
     * 文字、链接与颜色条目没有落盘文件，返回空表。
     */
    fun importPaths(item: ClipItem): List<String> = when (item.kind) {
        ClipKind.IMAGE -> listOf(item.filePath.trim()).filter(String::isNotEmpty)
        ClipKind.FILES -> (item.text.split('\n') + item.filePath)
            .map(String::trim)
            .filter(String::isNotEmpty)
            .distinct()
        else -> emptyList()
    }

    private fun hasContent(item: ClipItem, exists: (String) -> Boolean): Boolean = when (item.kind) {
        ClipKind.IMAGE, ClipKind.FILES -> item.filePath.isNotBlank() && exists(item.filePath)
        else -> item.text.isNotBlank()
    }

    private const val SECONDS_PER_DAY = 24L * 60 * 60
}

internal fun defaultClipboardPath(): String =
    "${ClipboardStore.defaultDirectory()}/clipboard.json"
