package com.wyz.covio.core

import okio.Path.Companion.toPath

/**
 * 截图库的文件判断规则。
 *
 * 路径用 String 表示。Kotlin/Native 没有 `java.nio.file.Path`。
 */
val SHELF_IMAGE_EXTENSIONS: Set<String> = setOf(
    "png",
    "jpg",
    "jpeg",
    "heic",
    "tif",
    "tiff",
    "gif",
    "webp",
)

/** 按扩展名判断。只看文件名，不看目录。 */
fun isShelfImageFileName(fileName: String): Boolean =
    fileName.substringAfterLast('.', "").lowercase() in SHELF_IMAGE_EXTENSIONS

/** 按扩展名判断。路径的最后一段是文件名。 */
fun isShelfImageFile(path: String): Boolean {
    val name = runCatching { path.toPath().name }.getOrDefault(path.substringAfterLast('/'))
    return isShelfImageFileName(name)
}

/**
 * 判断某个文件是否该进截图库。
 *
 * 进入条件有两条，满足其一即可：
 * 1. 文件在专用目录里。
 * 2. 文件带系统的截图属性。
 *
 * 两条都不满足时不接收，例如桌面上的普通图片。
 */
fun acceptsShelfFile(
    path: String,
    dedicatedDirectory: String,
    hasScreenCaptureAttribute: (String) -> Boolean,
): Boolean {
    if (!isShelfImageFile(path)) return false
    if (isPathInside(path, dedicatedDirectory)) return true
    return hasScreenCaptureAttribute(path)
}

/**
 * 包含关系判断。
 *
 * 与 `java.nio.file.Path.startsWith` 一样按路径段比较，不是按字符串前缀。
 * 所以 `/a/bc` 不在 `/a/b` 内。
 */
fun isPathInside(path: String, directory: String): Boolean {
    val child = canonicalOrNull(path) ?: return false
    val parent = canonicalOrNull(directory) ?: return false
    if (child == parent) return true
    val relative = runCatching { child.relativeTo(parent) }.getOrNull() ?: return false
    return relative.segments.firstOrNull() != ".."
}

private fun canonicalOrNull(value: String) = runCatching {
    val path = value.toPath()
    (if (path.isAbsolute) path else ShelfStore.canonicalPath(value).toPath()).normalized()
}.getOrNull()
