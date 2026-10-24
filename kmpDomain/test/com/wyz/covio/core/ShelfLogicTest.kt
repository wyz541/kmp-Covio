package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ShelfLogicTest {
    @Test
    fun `dedicated folder accepts images while other folders require the screenshot tag`() =
        withTemporaryDirectory("accept") { root ->
            val fileSystem = okio.FileSystem.SYSTEM
            val dedicated = root.resolve("screenshots")
            fileSystem.createDirectories(dedicated)
            val inside = dedicated.resolve("capture.PNG")
            val outside = root.resolve("other.png")
            val notes = root.resolve("notes.txt")
            inside.writeText("image")
            outside.writeText("image")
            notes.writeText("image")

            // 专用目录里的大写扩展名也接收。
            assertTrue(acceptsShelfFile(inside.toString(), dedicated.toString()) { false })
            // 专用目录外的图片要有截图属性才接收。
            assertFalse(acceptsShelfFile(outside.toString(), dedicated.toString()) { false })
            assertTrue(acceptsShelfFile(outside.toString(), dedicated.toString()) { true })
            // 非图片扩展名一律不接收，即使带截图属性。
            assertFalse(acceptsShelfFile(notes.toString(), dedicated.toString()) { true })
            // 字符串前缀相同但不是子目录，不能算在专用目录里。
            val sibling = root.resolve("screenshots-backup")
            fileSystem.createDirectories(sibling)
            val siblingImage = sibling.resolve("shot.png")
            siblingImage.writeText("image")
            assertFalse(acceptsShelfFile(siblingImage.toString(), dedicated.toString()) { false })
        }

    @Test
    fun `image file detection reads only the last path segment`() {
        assertTrue(isShelfImageFile("/tmp/a/b/photo.HEIC"))
        assertTrue(isShelfImageFileName("photo.webp"))
        assertFalse(isShelfImageFileName("notes.txt"))
        assertFalse(isShelfImageFileName("noextension"))
        // 目录名里有扩展名不算。
        assertFalse(isShelfImageFile("/tmp/album.png/notes"))
    }
}
