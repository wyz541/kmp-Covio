package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** 文件区只读投影与筛选。 */
class FileAreaProjectionTest {
    private val screenshotPath = "/tmp/covio-file-area-shot.png"

    private fun workspace(
        id: String,
        kind: WorkspaceKind = WorkspaceKind.FILE,
        name: String = "entry.bin",
        createdAt: Long = 1,
        availability: WorkspaceAvailability = WorkspaceAvailability.LOCAL,
        pinned: Boolean = false,
    ): WorkspaceEntry = WorkspaceEntry(
        entryId = id.repeat(64),
        kind = kind,
        displayName = name,
        byteSize = 42,
        createdAtEpochSeconds = createdAt,
        originDeviceId = "device-a",
        expiresAtEpochSeconds = 99,
        availability = availability,
        pinned = pinned,
    )

    @Test
    fun `builds screenshot and workspace capabilities without merging sources`() {
        val image = workspace("a", WorkspaceKind.IMAGE, "image.heic", createdAt = 20, pinned = true)
        val text = workspace("b", WorkspaceKind.TEXT, "note.txt", createdAt = 10)

        val items = FileAreaProjection.build(
            shelfItems = listOf(ShelfItem(screenshotPath, 5)),
            workspaceEntries = listOf(text, image),
            existingScreenshotPaths = listOf(screenshotPath),
        )

        assertEquals(3, items.size)
        assertEquals(FileAreaOrigin.WORKSPACE, items[0].origin, "置顶工作区排第一")
        assertTrue(items[0].pinned)

        val shot = items.single { it.origin == FileAreaOrigin.SCREENSHOT }
        assertEquals("screenshot:$screenshotPath", shot.id)
        assertEquals("covio-file-area-shot.png", shot.displayName)
        assertEquals(FileAreaKind.SCREENSHOT, shot.kind)
        assertTrue(shot.capabilities.canMarkup)
        assertTrue(shot.capabilities.canSaveToWorkspace)
        assertTrue(shot.capabilities.canDragOut)
        assertFalse(shot.capabilities.canPin)

        val textItem = items.single { it.itemId == text.entryId }
        assertTrue(textItem.capabilities.canCopyText)
        assertFalse(textItem.capabilities.canCopy)
        assertTrue(textItem.capabilities.canReveal)
    }

    @Test
    fun `missing duplicate and malformed entries do not create ghost items`() {
        val items = FileAreaProjection.build(
            shelfItems = listOf(
                ShelfItem(" ", 1),
                ShelfItem(screenshotPath, 5),
                ShelfItem(screenshotPath, 6),
            ),
            workspaceEntries = listOf(
                WorkspaceEntry(entryId = "not-a-digest", displayName = "bad.bin"),
            ),
            existingScreenshotPaths = listOf(screenshotPath),
        )

        assertEquals(1, items.size)
        assertEquals(FileAreaOrigin.SCREENSHOT, items.single().origin)
    }

    @Test
    fun `workspace availability maps to file area states and actions`() {
        val entries = listOf(
            workspace("a", availability = WorkspaceAvailability.REMOTE),
            workspace("b", availability = WorkspaceAvailability.FETCHING),
            workspace("c", availability = WorkspaceAvailability.EVICTED),
        )

        val items = FileAreaProjection.build(emptyList(), entries, emptyList())
        val remote = items.single { it.itemId == entries[0].entryId }
        val fetching = items.single { it.itemId == entries[1].entryId }
        val unavailable = items.single { it.itemId == entries[2].entryId }

        assertEquals(FileAreaAvailability.REMOTE, remote.availability)
        assertTrue(remote.capabilities.canDownload)
        assertFalse(remote.capabilities.canOpen)

        assertEquals(FileAreaAvailability.FETCHING, fetching.availability)
        assertTrue(fetching.capabilities.canCancel)

        assertEquals(FileAreaAvailability.UNAVAILABLE, unavailable.availability)
        assertTrue(unavailable.capabilities.canRemove)
        assertTrue(unavailable.isTransfer)
    }

    @Test
    fun `pinned items stay first and the rest use newest first`() {
        val entries = listOf(
            workspace("a", name = "old.bin", createdAt = 1),
            workspace("b", name = "new.bin", createdAt = 30),
            workspace("c", name = "pinned.bin", createdAt = 2, pinned = true),
        )

        val items = FileAreaProjection.build(emptyList(), entries, emptyList())

        assertEquals(listOf("pinned.bin", "new.bin", "old.bin"), items.map { it.displayName })
    }

    @Test
    fun `the same content in two sources stays as two items`() {
        val shot = ShelfItem(screenshotPath, 1)
        val entry = workspace("a", WorkspaceKind.IMAGE, "covio-file-area-shot.png")
        val items = FileAreaProjection.build(listOf(shot), listOf(entry), listOf(screenshotPath))

        assertEquals(2, items.size)
        assertEquals(setOf(FileAreaOrigin.SCREENSHOT, FileAreaOrigin.WORKSPACE), items.map { it.origin }.toSet())
        assertEquals(2, items.map { it.id }.toSet().size)
    }

    @Test
    fun `filters can overlap by type and transfer state`() {
        val entries = listOf(
            workspace("a", WorkspaceKind.IMAGE, "image.heic"),
            workspace("b", WorkspaceKind.TEXT, "note.txt"),
            workspace("c", WorkspaceKind.PDF, "remote.pdf", availability = WorkspaceAvailability.REMOTE),
        )
        val items = FileAreaProjection.build(
            listOf(ShelfItem(screenshotPath, 1)),
            entries,
            listOf(screenshotPath),
        )

        assertEquals(4, FileAreaProjection.filter(items, FileAreaFilter.ALL).size)
        assertEquals(1, FileAreaProjection.filter(items, FileAreaFilter.SCREENSHOTS).size)
        assertEquals(
            setOf(entries[0].entryId, entries[2].entryId),
            FileAreaProjection.filter(items, FileAreaFilter.FILES).map { it.itemId }.toSet(),
        )
        assertEquals(entries[1].entryId, FileAreaProjection.filter(items, FileAreaFilter.TEXT).single().itemId)
        assertEquals(entries[2].entryId, FileAreaProjection.filter(items, FileAreaFilter.TRANSFERS).single().itemId)
    }
}
