package com.wyz.covio.preview.previews.files

/** 文件区的筛选。传输是状态筛选，可以和类型筛选重叠。 */
internal enum class FileFilter(val label: String) {
    ALL("全部"),
    SCREENSHOTS("截图"),
    FILES("文件"),
    TEXT("文本"),
    TRANSFERS("传输"),
}

/** 统一文件卡片的演示类型。 */
internal enum class DemoFileKind {
    SCREENSHOT,
    IMAGE,
    TEXT,
    PDF,
    AUDIO,
    ARCHIVE,
    VIDEO,
}

/** 卡片当前可用性。 */
internal enum class DemoAvailability {
    LOCAL,
    REMOTE,
    FETCHING,
    FAILED,
    UNAVAILABLE,
}

/** 打样用的文件条目。真实实现使用 #200 的只读投影。 */
internal data class DemoFile(
    val id: String,
    val name: String,
    val kind: DemoFileKind,
    val availability: DemoAvailability,
    val meta: String,
    val detail: String,
    val origin: String = "这台 Mac",
    val pinned: Boolean = false,
    val progress: Float = 0f,
)

internal val demoFiles: List<DemoFile> = listOf(
    DemoFile(
        id = "shot-1",
        name = "截屏 2026-10-21 14.32.png",
        kind = DemoFileKind.SCREENSHOT,
        availability = DemoAvailability.LOCAL,
        meta = "1.8 MB · 今天 14:32",
        detail = "产品评审",
    ),
    DemoFile(
        id = "shot-2",
        name = "截屏 2026-10-21 14.28.png",
        kind = DemoFileKind.SCREENSHOT,
        availability = DemoAvailability.LOCAL,
        meta = "2.4 MB · 今天 14:28",
        detail = "首页布局",
    ),
    DemoFile(
        id = "shot-3",
        name = "截屏 2026-10-20 09.15.png",
        kind = DemoFileKind.SCREENSHOT,
        availability = DemoAvailability.LOCAL,
        meta = "640 KB · 昨天 09:15",
        detail = "错误状态",
    ),
    DemoFile(
        id = "text-1",
        name = "发布说明草稿.txt",
        kind = DemoFileKind.TEXT,
        availability = DemoAvailability.LOCAL,
        meta = "842 字节 · 今天 13:48",
        detail = "文件区不再分截图页。截图只是文件区的一种筛选。右键可以复制全部正文。",
        pinned = true,
    ),
    DemoFile(
        id = "pdf-1",
        name = "Covio Design Contract v1.3.pdf",
        kind = DemoFileKind.PDF,
        availability = DemoAvailability.LOCAL,
        meta = "6.4 MB · 今天 11:20",
        detail = "设计合同",
    ),
    DemoFile(
        id = "zip-1",
        name = "covio-preview-build.zip",
        kind = DemoFileKind.ARCHIVE,
        availability = DemoAvailability.LOCAL,
        meta = "42.8 MB · 昨天 18:06",
        detail = "ZIP 归档",
    ),
    DemoFile(
        id = "image-remote",
        name = "iPhone 参考.heic",
        kind = DemoFileKind.IMAGE,
        availability = DemoAvailability.REMOTE,
        meta = "3.2 MB · 来自 iPhone",
        detail = "等待取回",
        origin = "iPhone",
    ),
    DemoFile(
        id = "video-fetching",
        name = "交互录屏 03.mov",
        kind = DemoFileKind.VIDEO,
        availability = DemoAvailability.FETCHING,
        meta = "128 MB · 正在取回",
        detail = "交互演示",
        origin = "iPad",
        progress = 0.62f,
    ),
    DemoFile(
        id = "pdf-failed",
        name = "客户反馈.pdf",
        kind = DemoFileKind.PDF,
        availability = DemoAvailability.FAILED,
        meta = "2.1 MB · 传输失败",
        detail = "无法连接对端",
        origin = "MacBook Air",
    ),
    DemoFile(
        id = "audio-old",
        name = "旧录音.m4a",
        kind = DemoFileKind.AUDIO,
        availability = DemoAvailability.UNAVAILABLE,
        meta = "18.5 MB · 内容已淘汰",
        detail = "不可恢复",
        origin = "旧设备",
    ),
)

/** 地址栏锚点对应的初始筛选。 */
internal fun initialFilter(anchor: String): FileFilter = when (anchor) {
    "screenshots" -> FileFilter.SCREENSHOTS
    "files" -> FileFilter.FILES
    "text" -> FileFilter.TEXT
    "transfers" -> FileFilter.TRANSFERS
    else -> FileFilter.ALL
}

/** 一个筛选中的条目数。 */
internal fun filterCount(filter: FileFilter): Int = demoFiles.count { matches(filter, it) }

/** 搜索与筛选同时生效。 */
internal fun visibleFiles(
    filter: FileFilter,
    query: String,
): List<DemoFile> = demoFiles.filter { file ->
    matches(filter, file) && file.matchesQuery(query)
}

internal fun matches(filter: FileFilter, file: DemoFile): Boolean = when (filter) {
    FileFilter.ALL -> true
    FileFilter.SCREENSHOTS -> file.kind == DemoFileKind.SCREENSHOT
    FileFilter.FILES -> file.kind !in setOf(DemoFileKind.SCREENSHOT, DemoFileKind.TEXT)
    FileFilter.TEXT -> file.kind == DemoFileKind.TEXT
    FileFilter.TRANSFERS -> file.availability != DemoAvailability.LOCAL
}

private fun DemoFile.matchesQuery(query: String): Boolean {
    if (query.isBlank()) return true
    val needle = query.trim()
    return listOf(name, detail, meta, origin).any { it.contains(needle, ignoreCase = true) }
}

/** 卡片下方的状态文字。 */
internal fun DemoFile.statusText(): String = when (availability) {
    DemoAvailability.LOCAL -> meta
    DemoAvailability.REMOTE -> "在另一台设备"
    DemoAvailability.FETCHING -> "正在取回 ${(progress * 100).toInt()}%"
    DemoAvailability.FAILED -> "传输失败"
    DemoAvailability.UNAVAILABLE -> "内容不可用"
}

/** 卡片右上的类型或状态标记。 */
internal fun DemoFile.badgeText(): String = when {
    availability == DemoAvailability.FAILED -> "失败"
    availability == DemoAvailability.FETCHING -> "传输中"
    availability == DemoAvailability.REMOTE -> "远端"
    availability == DemoAvailability.UNAVAILABLE -> "不可用"
    kind == DemoFileKind.SCREENSHOT -> "截图"
    kind == DemoFileKind.TEXT -> "文本"
    else -> kind.name
}

/** 悬停动作。最多两个。 */
internal fun DemoFile.quickActions(): List<String> = when (availability) {
    DemoAvailability.FETCHING -> listOf("取消")
    DemoAvailability.REMOTE -> listOf("下载", "删除")
    DemoAvailability.FAILED -> listOf("重试", "删除")
    DemoAvailability.UNAVAILABLE -> listOf("删除")
    DemoAvailability.LOCAL -> when (kind) {
        DemoFileKind.SCREENSHOT -> listOf("复制", "打开")
        DemoFileKind.TEXT -> listOf("复制正文", "打开")
        else -> listOf("打开", "显示位置")
    }
}

/** 右键菜单的完整动作。 */
internal fun DemoFile.menuActions(): List<String> = buildList {
    when (availability) {
        DemoAvailability.FETCHING -> add("取消传输")
        DemoAvailability.REMOTE -> add("下载")
        DemoAvailability.FAILED -> add("重试")
        DemoAvailability.UNAVAILABLE -> Unit
        DemoAvailability.LOCAL -> {
            add(if (kind == DemoFileKind.TEXT) "复制正文" else "复制")
            add("打开")
            if (kind == DemoFileKind.SCREENSHOT) add("标注")
        }
    }
    if (kind == DemoFileKind.SCREENSHOT) add("存入工作区")
    if (kind != DemoFileKind.SCREENSHOT && availability == DemoAvailability.LOCAL) add("在访达中显示")
    if (availability == DemoAvailability.LOCAL && kind != DemoFileKind.SCREENSHOT) add(if (pinned) "取消置顶" else "置顶")
    add("删除")
}
