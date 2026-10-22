package com.wyz.covio.core

/** 文件区条目的来源。 */
enum class FileAreaOrigin {
    SCREENSHOT,
    WORKSPACE,
}

/** 文件区卡片的展示类型。 */
enum class FileAreaKind {
    SCREENSHOT,
    IMAGE,
    TEXT,
    PDF,
    AUDIO,
    FILE,
}

/** 文件区条目的可用状态。 */
enum class FileAreaAvailability {
    LOCAL,
    REMOTE,
    FETCHING,
    UNAVAILABLE,
}

/** 文件区筛选。传输筛选与类型筛选可以重叠。 */
enum class FileAreaFilter {
    ALL,
    SCREENSHOTS,
    FILES,
    TEXT,
    TRANSFERS,
}

/**
 * 一个来源能执行的动作。
 *
 * 投影只描述能力，动作仍由截图运行时或工作区运行时执行。
 */
data class FileAreaCapabilities(
    val canOpen: Boolean = false,
    val canCopy: Boolean = false,
    val canCopyText: Boolean = false,
    val canMarkup: Boolean = false,
    val canDragOut: Boolean = false,
    val canSaveToWorkspace: Boolean = false,
    val canReveal: Boolean = false,
    val canPin: Boolean = false,
    val canRemove: Boolean = false,
    val canDownload: Boolean = false,
    val canCancel: Boolean = false,
)

/**
 * 文件区的只读条目。
 *
 * [id] 带来源前缀，避免截图路径与工作区摘要撞车。
 * [itemId] 是来源自己的标识：截图是路径，工作区是内容摘要。
 * 本模型不持久化，也不改变任何来源的数据。
 */
data class FileAreaItem(
    val id: String,
    val origin: FileAreaOrigin,
    val itemId: String,
    val displayName: String,
    val kind: FileAreaKind,
    val createdAtEpochSeconds: Long = 0L,
    val byteSize: Long = 0L,
    val originDeviceId: String = "",
    val expiresAtEpochSeconds: Long = 0L,
    val availability: FileAreaAvailability = FileAreaAvailability.LOCAL,
    val pinned: Boolean = false,
    val capabilities: FileAreaCapabilities = FileAreaCapabilities(),
) {
    /** 是否属于传输状态筛选。 */
    val isTransfer: Boolean get() = availability != FileAreaAvailability.LOCAL
}

/**
 * 把截图与工作区投影成一个文件区列表。
 *
 * 持久化模型保持分开。两个来源都保留自己的 id、动作和删除语义。
 */
object FileAreaProjection {
    /**
     * 生成排序后的文件区快照。
     *
     * [existingScreenshotPaths] 由宿主提供。不在列表中的截图不进入投影，
     * 因此原文件消失后不会留下幽灵卡片。
     */
    fun build(
        shelfItems: List<ShelfItem>,
        workspaceEntries: List<WorkspaceEntry>,
        existingScreenshotPaths: List<String>,
    ): List<FileAreaItem> {
        val existing = existingScreenshotPaths
            .asSequence()
            .filter { it.isNotBlank() }
            .map(ShelfStore::canonicalPath)
            .toSet()

        val seenScreenshots = HashSet<String>()
        val screenshots = shelfItems.mapNotNull { raw ->
            val item = raw.normalized()
            if (item.path.isBlank()) return@mapNotNull null
            val path = ShelfStore.canonicalPath(item.path)
            if (path !in existing || !seenScreenshots.add(path)) return@mapNotNull null
            FileAreaItem(
                id = "screenshot:$path",
                origin = FileAreaOrigin.SCREENSHOT,
                itemId = path,
                displayName = fileName(path),
                kind = FileAreaKind.SCREENSHOT,
                createdAtEpochSeconds = item.addedAtEpochSeconds.coerceAtLeast(0L),
                availability = FileAreaAvailability.LOCAL,
                capabilities = FileAreaCapabilities(
                    canOpen = true,
                    canCopy = true,
                    canMarkup = true,
                    canDragOut = true,
                    canSaveToWorkspace = true,
                    canRemove = true,
                ),
            )
        }

        val workspace = workspaceEntries.mapNotNull { raw ->
            val entry = raw.normalized()
            if (!entry.isUsable) return@mapNotNull null
            val availability = entry.availability.toFileAreaAvailability()
            val local = availability == FileAreaAvailability.LOCAL
            val kind = entry.kind.toFileAreaKind()
            FileAreaItem(
                id = "workspace:${entry.entryId}",
                origin = FileAreaOrigin.WORKSPACE,
                itemId = entry.entryId,
                displayName = entry.displayName.ifBlank { entry.entryId.take(12) },
                kind = kind,
                createdAtEpochSeconds = entry.createdAtEpochSeconds.coerceAtLeast(0L),
                byteSize = entry.byteSize.coerceAtLeast(0L),
                originDeviceId = entry.originDeviceId,
                expiresAtEpochSeconds = entry.expiresAtEpochSeconds.coerceAtLeast(0L),
                availability = availability,
                pinned = entry.pinned,
                capabilities = FileAreaCapabilities(
                    canOpen = local,
                    canCopy = local && kind != FileAreaKind.TEXT,
                    canCopyText = local && kind == FileAreaKind.TEXT,
                    canDragOut = local,
                    canReveal = local,
                    canPin = true,
                    canRemove = true,
                    canDownload = availability == FileAreaAvailability.REMOTE,
                    canCancel = availability == FileAreaAvailability.FETCHING,
                ),
            )
        }

        return (screenshots + workspace).sortedWith(
            compareByDescending<FileAreaItem> { it.pinned }
                .thenByDescending { it.createdAtEpochSeconds }
                .thenBy { it.origin.ordinal }
                .thenBy { it.id },
        )
    }

    /** 按文件区筛选。筛选不改变来源，也不复制条目。 */
    fun filter(items: List<FileAreaItem>, filter: FileAreaFilter): List<FileAreaItem> =
        items.filter { it.matches(filter) }
}

/** 单条投影是否匹配筛选。 */
fun FileAreaItem.matches(filter: FileAreaFilter): Boolean = when (filter) {
    FileAreaFilter.ALL -> true
    FileAreaFilter.SCREENSHOTS -> origin == FileAreaOrigin.SCREENSHOT
    FileAreaFilter.FILES -> origin == FileAreaOrigin.WORKSPACE &&
        kind != FileAreaKind.TEXT &&
        kind != FileAreaKind.SCREENSHOT
    FileAreaFilter.TEXT -> kind == FileAreaKind.TEXT
    FileAreaFilter.TRANSFERS -> isTransfer
}

private fun WorkspaceAvailability.toFileAreaAvailability(): FileAreaAvailability = when (this) {
    WorkspaceAvailability.LOCAL -> FileAreaAvailability.LOCAL
    WorkspaceAvailability.REMOTE -> FileAreaAvailability.REMOTE
    WorkspaceAvailability.FETCHING -> FileAreaAvailability.FETCHING
    WorkspaceAvailability.EVICTED -> FileAreaAvailability.UNAVAILABLE
}

private fun WorkspaceKind.toFileAreaKind(): FileAreaKind = when (this) {
    WorkspaceKind.IMAGE -> FileAreaKind.IMAGE
    WorkspaceKind.TEXT -> FileAreaKind.TEXT
    WorkspaceKind.PDF -> FileAreaKind.PDF
    WorkspaceKind.AUDIO -> FileAreaKind.AUDIO
    WorkspaceKind.FILE -> FileAreaKind.FILE
}

private fun fileName(path: String): String =
    path.substringAfterLast('/').substringAfterLast('\\').ifBlank { path }
