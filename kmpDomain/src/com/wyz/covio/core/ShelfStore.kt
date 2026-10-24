package com.wyz.covio.core

import com.wyz.covio.domain.EngineLock
import kotlinx.serialization.json.Json
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath

/**
 * 截图索引状态的持久化。
 *
 * 用 okio 而不是 `java.nio.file`，因为同一份代码要跑在 jvm 与 macosArm64 上。
 * 写入沿用「先写 `.tmp` 再原子改名」的做法，避免掉电留下半个文件。
 *
 * 三个方法都取同一把可重入锁。实例会被多个线程用到：
 * 多处读取和写入共用同一把锁。
 */
class ShelfStore(
    val path: String = defaultShelfPath(),
    private val fileSystem: FileSystem = FileSystem.SYSTEM,
    private val json: Json = defaultJson(),
) {
    private val lock = EngineLock()

    fun load(): ShelfStoreState = lock.withLock {
        if (!fileSystem.exists(path.toPath())) return@withLock ShelfStoreState()
        runCatching {
            json.decodeFromString<ShelfStoreState>(fileSystem.read(path.toPath()) { readUtf8() })
        }.getOrElse { ShelfStoreState() }.normalized()
    }

    /**
     * 写入状态，返回规范化之后的状态。
     *
     * **写盘失败不抛异常。** Kotlin 的异常跨到 Swift 没有接收方，
     * 会直接终止进程（`Function doesn't have or inherit @Throws annotation`）。
     * 磁盘满、目录被删、权限不对都会走到这里，而调用方是每次改卡片都会跑的落盘。
     * 所以失败时和 [load] 与 [clear] 一样咽掉：内存里的状态照常更新，只是这一版没落盘。
     */
    fun save(state: ShelfStoreState): ShelfStoreState = lock.withLock {
        val normalized = state.normalized()
        runCatching {
            val target = path.toPath()
            target.parent?.let { fileSystem.createDirectories(it) }
            val temporary = temporaryPath(target)
            fileSystem.write(temporary) { writeUtf8(json.encodeToString(ShelfStoreState.serializer(), normalized)) }
            fileSystem.atomicMove(temporary, target)
        }
        normalized
    }

    fun clear(): Boolean = lock.withLock {
        runCatching {
            val target = path.toPath()
            fileSystem.delete(target, mustExist = false)
            fileSystem.delete(temporaryPath(target), mustExist = false)
        }.isSuccess
    }

    private fun temporaryPath(target: Path): Path = target.parent!!.resolve(target.name + ".tmp")

    companion object {
        const val MAX_ITEMS = 12

        /**
         * 按路径构造一个截图索引存储。
         *
         * Swift 侧不能走主构造函数：`json` 与 `fileSystem` 的默认值在 Kotlin 里，
         * 默认参数不导出到 Swift，从 Swift 就得自己拼一个 `Json`。
         * 拼出来的设置可能与这里不一致，那会让两版写出的 `shelf.json` 不同。
         * 所以统一从这一个入口构造。与 `ConfigStore.create` 同一个理由。
         */
        fun create(path: String): ShelfStore =
            ShelfStore(path = path, fileSystem = FileSystem.SYSTEM, json = defaultJson())

        internal fun defaultJson(): Json = Json {
            prettyPrint = true
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        /**
         * 规范路径。与 0.4.2 的 `Path.toAbsolutePath().normalize()` 行为一致：
         * 只做词法处理，不解析符号链接。
         */
        fun canonicalPath(value: String): String {
            val parsed = runCatching { value.toPath() }.getOrNull() ?: return value
            return runCatching {
                val absolute = if (parsed.isAbsolute) parsed else workingDirectory().resolve(parsed)
                absolute.normalized().toString()
            }.getOrDefault(value)
        }

        fun normalizeItems(
            items: List<ShelfItem>,
            limit: Int = MAX_ITEMS,
            exists: (String) -> Boolean = { FileSystem.SYSTEM.exists(it.toPath()) },
        ): List<ShelfItem> {
            val seen = LinkedHashSet<String>()
            return items.asSequence()
                .map(ShelfItem::normalized)
                .filter { it.path.isNotBlank() }
                .filter { item -> seen.add(canonicalPath(item.path)) }
                .filter { exists(it.path) }
                .toList()
                .takeLast(limit.coerceAtLeast(0))
        }

        private var cachedWorkingDirectory: Path? = null

        private fun workingDirectory(): Path = cachedWorkingDirectory ?: runCatching {
            FileSystem.SYSTEM.canonicalize(".".toPath())
        }.getOrElse { "/".toPath() }.also { cachedWorkingDirectory = it }
    }
}

private fun ShelfStoreState.normalized(): ShelfStoreState = copy(
    items = ShelfStore.normalizeItems(items),
)
