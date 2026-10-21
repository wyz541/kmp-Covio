package com.wyz.covio.preview.previews.files

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wyz.covio.preview.DeepLink
import com.wyz.covio.preview.LocalPreviewFontStatus
import com.wyz.covio.preview.previews.workbench.MenuBar
import com.wyz.covio.preview.previews.workbench.Pane
import com.wyz.covio.preview.previews.workbench.PaneKind
import com.wyz.covio.preview.previews.workbench.TabBar
import com.wyz.covio.preview.previews.workbench.Tokens
import com.wyz.covio.preview.previews.workbench.Wallpaper
import com.wyz.covio.preview.previews.workbench.defaultPanes
import com.wyz.covio.preview.previews.workbench.defaultWidgets
import com.wyz.covio.preview.previews.workbench.rememberCurtainProgress
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/**
 * 统一文件区预览。
 *
 * | 锚点 | 画面 |
 * | --- | --- |
 * | `all` | 全部卡片 |
 * | `screenshots` | 截图筛选 |
 * | `files` | 普通文件筛选 |
 * | `text` | 文本筛选 |
 * | `transfers` | 传输状态 |
 * | `empty` | 空文件区 |
 * | `nomatch` | 无匹配状态 |
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
internal fun UnifiedFilesPreview() {
    val anchor = DeepLink.anchor
    var open by remember { mutableStateOf(anchor != "closed") }
    var homeSelected by remember { mutableStateOf(false) }
    var selectedId by remember { mutableStateOf(PaneKind.FILES.defaultId()) }
    var query by remember { mutableStateOf(if (anchor == "nomatch") "不存在的条目" else "") }
    var filter by remember { mutableStateOf(initialFilter(anchor)) }
    var reducedMotion by remember { mutableStateOf(false) }
    var compact by remember { mutableStateOf(false) }
    var demoState by remember {
        mutableStateOf(
            when (anchor) {
                "empty" -> DemoState.EMPTY
                "nomatch" -> DemoState.NO_MATCH
                else -> DemoState.NORMAL
            },
        )
    }
    var toast by remember { mutableStateOf<String?>(null) }
    var panes by remember {
        mutableStateOf(defaultPanes().filterNot { it.kind == PaneKind.SCREENSHOTS })
    }
    val progress = rememberCurtainProgress(open, reducedMotion)
    val density = LocalDensity.current.density
    val slide = if (reducedMotion) 0f else (1f - progress) * -14f

    LaunchedEffect(toast) {
        val current = toast ?: return@LaunchedEffect
        delay(1_600)
        if (toast == current) toast = null
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val maxPanelHeight = maxHeight - 120.dp
        val panelWidth = if (compact) 720.dp else Tokens.panelWidth.dp

        Wallpaper(Modifier.fillMaxSize())

        Box(
            Modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { open = false },
        )

        Column(
            Modifier.align(Alignment.TopCenter),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            MenuBar(
                capsuleVisible = true,
                onHotspotEnter = { open = true },
                onCapsuleClick = { open = !open },
            )

            if (progress > 0.01f) {
                Column(
                    Modifier
                        .width(panelWidth)
                        .offset { IntOffset(0, (slide * density).roundToInt()) }
                        .alpha(progress),
                    verticalArrangement = Arrangement.spacedBy(11.dp),
                ) {
                    GlassPlate(RoundedCornerShape(23.dp)) {
                        TabBar(
                            panes = panes,
                            homeSelected = homeSelected,
                            selectedId = selectedId,
                            query = query,
                            editing = false,
                            pageAction = "设置",
                            searchPlaceholder = "搜索文件",
                            onQueryChange = {
                                query = it
                                if (demoState == DemoState.NO_MATCH) demoState = DemoState.NORMAL
                            },
                            onHome = {
                                homeSelected = true
                                query = ""
                                demoState = DemoState.NORMAL
                            },
                            onSelect = { id ->
                                selectedId = id
                                homeSelected = false
                                demoState = DemoState.NORMAL
                            },
                            onPageAction = { toast = "打开当前工作区设置" },
                            onReorder = { from, to ->
                                panes = panes.toMutableList().also { list ->
                                    val moved = list.removeAt(from)
                                    list.add(to.coerceIn(0, list.size), moved)
                                }
                            },
                        )
                    }

                    GlassPlate(RoundedCornerShape(23.dp)) {
                        Column(
                            Modifier
                                .heightIn(max = maxPanelHeight - 57.dp)
                                .verticalScroll(rememberScrollState())
                                .padding(24.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (homeSelected) {
                                Text("首页", color = Tokens.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                                com.wyz.covio.preview.previews.workbench.HomeGrid(
                                    widgets = defaultWidgets(),
                                    editing = false,
                                    onMove = { _, _ -> },
                                    onResize = { _, _ -> },
                                    onDelete = { },
                                )
                            } else if (selectedId == PaneKind.FILES.defaultId()) {
                                FilesPage(
                                    filter = filter,
                                    query = query,
                                    demoState = demoState,
                                    onFilter = { filter = it },
                                    onAction = { toast = it },
                                    onClearFilters = {
                                        filter = FileFilter.ALL
                                        query = ""
                                        demoState = DemoState.NORMAL
                                    },
                                )
                            } else {
                                OtherPane(panes.firstOrNull { it.id == selectedId })
                            }
                        }
                    }
                }
            }
        }

        PreviewHarness(
            modifier = Modifier.align(Alignment.BottomCenter),
            screen = screenName(homeSelected, selectedId, filter, demoState),
            open = open,
            reducedMotion = reducedMotion,
            compact = compact,
            demoState = demoState,
            onToggleOpen = { open = !open },
            onToggleReducedMotion = { reducedMotion = !reducedMotion },
            onToggleWidth = { compact = !compact },
            onCycleDemoState = {
                demoState = when (demoState) {
                    DemoState.NORMAL -> DemoState.NO_MATCH
                    DemoState.NO_MATCH -> DemoState.EMPTY
                    DemoState.EMPTY -> DemoState.NORMAL
                }
                if (demoState == DemoState.NO_MATCH) query = "不存在的条目" else if (demoState == DemoState.NORMAL) query = ""
            },
        )

        toast?.let { message ->
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 104.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color(0xE61C1C1E))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            ) {
                Text(message, color = Color(0xFFF5F5F7), fontSize = 11.sp)
            }
        }
    }
}

private fun PaneKind.defaultId(): String = name.lowercase()

private enum class DemoState { NORMAL, EMPTY, NO_MATCH }

private fun screenName(
    homeSelected: Boolean,
    selectedId: String,
    filter: FileFilter,
    demoState: DemoState,
): String = when {
    homeSelected -> "首页"
    selectedId != "files" -> "其他工作区"
    demoState == DemoState.EMPTY -> "文件 · 空状态"
    demoState == DemoState.NO_MATCH -> "文件 · 无匹配"
    else -> "文件 · ${filter.label}"
}

@Composable
private fun FilesPage(
    filter: FileFilter,
    query: String,
    demoState: DemoState,
    onFilter: (FileFilter) -> Unit,
    onAction: (String) -> Unit,
    onClearFilters: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("文件", color = Tokens.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    "截图、临时文件、文本和跨设备传输。",
                    color = Tokens.textSecondary,
                    fontSize = 11.sp,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallAction("＋ 加入", primary = true) { onAction("打开加入菜单") }
                SmallAction("更多") { onAction("打开文件区更多菜单") }
            }
        }

        FilterBar(filter = filter, onFilter = onFilter)

        if (demoState != DemoState.EMPTY && filter == FileFilter.TRANSFERS) {
            TransferSummary()
        }

        when {
            demoState == DemoState.EMPTY -> EmptyFiles(onAction)
            demoState == DemoState.NO_MATCH || visibleFiles(filter, query).isEmpty() -> NoMatch(onClearFilters)
            else -> FileGrid(
                files = visibleFiles(filter, query),
                onAction = onAction,
            )
        }
    }
}

@Composable
private fun FilterBar(filter: FileFilter, onFilter: (FileFilter) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        FileFilter.entries.forEach { item ->
            FilterChip(
                label = item.label,
                count = filterCount(item),
                selected = item == filter,
                onClick = { onFilter(item) },
            )
        }
    }
}

@Composable
private fun FilterChip(label: String, count: Int, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .height(28.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) Tokens.actionFill else Color(0x12000000))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            color = if (selected) Tokens.textOnAccent else Tokens.textPrimary,
            fontSize = 11.sp,
            fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
        )
        Text(
            count.toString(),
            color = if (selected) Tokens.textOnAccent.copy(alpha = 0.72f) else Tokens.textSecondary,
            fontSize = 10.sp,
        )
    }
}

@Composable
private fun TransferSummary() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Color(0x0F0A84FF))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("↓", color = Tokens.actionFill, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        Text("2 个任务进行中", color = Tokens.textPrimary, fontSize = 11.sp, fontWeight = FontWeight.Medium)
        Text("1 个失败", color = Tokens.errorText, fontSize = 11.sp)
        Spacer(Modifier.weight(1f))
        Text("完成后回到文件视图", color = Tokens.textSecondary, fontSize = 10.sp)
    }
}

@Composable
private fun FileGrid(files: List<DemoFile>, onAction: (String) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gap = 16.dp
        val cardWidth = 150.dp
        val columns = ((maxWidth + gap) / (cardWidth + gap)).toInt().coerceIn(3, 5)
        Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            files.chunked(columns).forEach { rowFiles ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = if (rowFiles.size == columns) {
                        Arrangement.SpaceBetween
                    } else {
                        Arrangement.spacedBy(gap)
                    },
                ) {
                    rowFiles.forEach { file ->
                        FileCard(file = file, onAction = onAction)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun FileCard(file: DemoFile, onAction: (String) -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    var menuOpen by remember { mutableStateOf(false) }

    Box {
        Column(
            modifier = Modifier
                .width(150.dp)
                .height(200.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xEDFFFFFF))
                .border(
                    width = if (hovered) 1.dp else 0.5.dp,
                    color = if (hovered) Color(0x33000000) else Tokens.divider.copy(alpha = 0.65f),
                    shape = RoundedCornerShape(12.dp),
                )
                .hoverable(interaction)
                .combinedClickable(
                    onClick = {},
                    onDoubleClick = { onAction("打开：${file.name}") },
                )
                .onPointerEvent(PointerEventType.Press) { event ->
                    if (event.buttons.isSecondaryPressed) menuOpen = true
                }
                .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(Modifier.width(134.dp).height(120.dp).clip(RoundedCornerShape(9.dp))) {
                FilePreview(file)
                StatusOverlay(file)
                if (file.pinned) PinBadge(Modifier.align(Alignment.TopStart))
                Badge(file, Modifier.align(Alignment.TopEnd))
                if (hovered) {
                    HoverActions(file, Modifier.align(Alignment.BottomCenter), onAction)
                }
            }
            FileDetails(file)
        }

        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false },
            shape = RoundedCornerShape(9.dp),
            containerColor = Color(0xF2FFFFFF),
            shadowElevation = 8.dp,
            border = androidx.compose.foundation.BorderStroke(1.dp, Tokens.divider.copy(alpha = 0.75f)),
        ) {
            file.menuActions().forEach { action ->
                DropdownMenuItem(
                    text = { Text(action, fontSize = 12.sp, color = Tokens.textPrimary) },
                    onClick = {
                        menuOpen = false
                        onAction("$action：${file.name}")
                    },
                    colors = MenuDefaults.itemColors(textColor = Tokens.textPrimary),
                )
            }
        }
    }
}

@Composable
private fun FilePreview(file: DemoFile) {
    when (file.kind) {
        DemoFileKind.SCREENSHOT, DemoFileKind.IMAGE -> WindowPreview(file.kind)
        DemoFileKind.TEXT -> TextPreview(file.detail)
        DemoFileKind.PDF -> DocumentPreview("PDF", Color(0xFFD70015))
        DemoFileKind.ARCHIVE -> DocumentPreview("ZIP", Color(0xFF0A84FF))
        DemoFileKind.AUDIO -> AudioPreview()
        DemoFileKind.VIDEO -> VideoPreview()
    }
}

@Composable
private fun WindowPreview(kind: DemoFileKind) {
    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    if (kind == DemoFileKind.SCREENSHOT) {
                        listOf(Color(0xFF6F83C7), Color(0xFFE0A27E), Color(0xFFF1D4B4))
                    } else {
                        listOf(Color(0xFF162A46), Color(0xFF517A92), Color(0xFFB5D6D2))
                    },
                ),
            ),
    ) {
        Row(
            Modifier.fillMaxWidth().height(14.dp).background(Color(0xB31C1C1E)).padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            listOf(Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)).forEach { color ->
                Box(Modifier.size(4.dp).clip(CircleShape).background(color))
            }
        }
        Column(
            Modifier
                .padding(start = 16.dp, top = 32.dp, end = 38.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(5.dp))
                .background(Color(0xC7FFFFFF))
                .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Box(Modifier.fillMaxWidth(0.64f).height(5.dp).clip(CircleShape).background(Color(0xAA1D1D1F)))
            Box(Modifier.fillMaxWidth(0.90f).height(3.dp).clip(CircleShape).background(Color(0x771D1D1F)))
            Box(Modifier.fillMaxWidth(0.78f).height(3.dp).clip(CircleShape).background(Color(0x551D1D1F)))
        }
        Box(
            Modifier
                .align(Alignment.BottomEnd)
                .padding(10.dp)
                .width(38.dp)
                .height(44.dp)
                .clip(RoundedCornerShape(5.dp))
                .background(Color(0x6BFFFFFF)),
        )
    }
}

@Composable
private fun TextPreview(text: String) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFFFFFBEA))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text("TEXT", color = Color(0xFF9A7A2E), fontSize = 8.sp, fontWeight = FontWeight.Bold)
        Text(
            text,
            color = Color(0xFF302D25),
            fontSize = 10.sp,
            lineHeight = 14.sp,
            maxLines = 5,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun DocumentPreview(label: String, accent: Color) {
    Box(
        Modifier.fillMaxSize().background(Color(0xFFF2F3F7)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .width(58.dp)
                .height(76.dp)
                .clip(RoundedCornerShape(7.dp))
                .background(Color.White)
                .border(1.dp, Tokens.divider, RoundedCornerShape(7.dp))
                .padding(9.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(label, color = accent, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun AudioPreview() {
    Box(
        Modifier.fillMaxSize().background(Color(0xFFF1EEF8)),
        contentAlignment = Alignment.Center,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
            listOf(12, 24, 38, 56, 31, 46, 22, 14).forEach { height ->
                Box(
                    Modifier
                        .width(4.dp)
                        .height(height.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF7654B7)),
                )
            }
        }
    }
}

@Composable
private fun VideoPreview() {
    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(Color(0xFF1D2430), Color(0xFF485D72)))),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(38.dp)
                .clip(CircleShape)
                .background(Color(0xB3FFFFFF)),
            contentAlignment = Alignment.Center,
        ) {
            Text("▶", color = Color(0xFF1D1D1F), fontSize = 16.sp)
        }
    }
}

@Composable
private fun PinBadge(modifier: Modifier = Modifier) {
    Box(
        modifier
            .padding(6.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(Color(0xB3FFFFFF))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text("置顶", color = Tokens.textPrimary, fontSize = 8.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun Badge(file: DemoFile, modifier: Modifier = Modifier) {
    val color = when (file.availability) {
        DemoAvailability.FAILED -> Tokens.errorText
        DemoAvailability.REMOTE, DemoAvailability.FETCHING -> Tokens.actionFill
        DemoAvailability.UNAVAILABLE -> Tokens.disabledText
        DemoAvailability.LOCAL -> Tokens.textSecondary
    }
    Box(
        modifier
            .padding(6.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(Color(0xD9FFFFFF))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text(file.badgeText(), color = color, fontSize = 8.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun HoverActions(file: DemoFile, modifier: Modifier = Modifier, onAction: (String) -> Unit) {
    Row(
        modifier
            .fillMaxWidth()
            .height(28.dp)
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xCC000000))))
            .padding(horizontal = 5.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        file.quickActions().take(2).forEach { action ->
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(5.dp))
                    .background(Color(0xCCFFFFFF))
                    .clickable { onAction("$action：${file.name}") },
                contentAlignment = Alignment.Center,
            ) {
                Text(action, color = Tokens.textPrimary, fontSize = 9.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun StatusOverlay(file: DemoFile) {
    when (file.availability) {
        DemoAvailability.LOCAL -> Unit
        DemoAvailability.REMOTE -> FullStatus("另一台设备", "下载后可打开", Color(0xA61C1C1E))
        DemoAvailability.FETCHING -> {
            Box(Modifier.fillMaxSize()) {
                Column(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Color(0xCC1C1C1E)).padding(6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text("正在取回 ${(file.progress * 100).toInt()}%", color = Color.White, fontSize = 9.sp)
                    Box(Modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(Color(0x44FFFFFF))) {
                        Box(Modifier.fillMaxWidth(file.progress).height(3.dp).background(Tokens.actionFill))
                    }
                }
            }
        }
        DemoAvailability.FAILED -> {
            Box(Modifier.fillMaxSize()) {
                Box(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Color(0xD9D70015)).padding(6.dp),
                ) {
                    Text("传输失败 · 重试", color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
        DemoAvailability.UNAVAILABLE -> FullStatus("内容不可用", "只能删除索引", Color(0xB31C1C1E))
    }
}

@Composable
private fun FullStatus(title: String, detail: String, background: Color) {
    Column(
        Modifier.fillMaxSize().background(background).padding(8.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(2.dp))
        Text(detail, color = Color(0xCCFFFFFF), fontSize = 8.sp, textAlign = TextAlign.Center)
    }
}

@Composable
private fun FileDetails(file: DemoFile) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            file.name,
            color = Tokens.textPrimary,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            lineHeight = 12.5.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            file.statusText(),
            color = when (file.availability) {
                DemoAvailability.FAILED -> Tokens.errorText
                DemoAvailability.REMOTE, DemoAvailability.FETCHING -> Tokens.actionFill
                else -> Tokens.textSecondary
            },
            fontSize = 9.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (file.origin != "这台 Mac") {
            Text(
                file.origin,
                color = Tokens.disabledText,
                fontSize = 8.sp,
                lineHeight = 9.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun EmptyFiles(onAction: (String) -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .height(300.dp)
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, Tokens.divider, RoundedCornerShape(14.dp))
            .background(Color(0x47FFFFFF)),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("▢", color = Tokens.textSecondary, fontSize = 30.sp)
        Spacer(Modifier.height(8.dp))
        Text("文件区还是空的", color = Tokens.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(4.dp))
        Text("把截图、文件或文字拖到这里。", color = Tokens.textSecondary, fontSize = 11.sp)
        Spacer(Modifier.height(14.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallAction("放入文件…", primary = true) { onAction("打开文件选择器") }
            SmallAction("新建文本…") { onAction("打开文本编辑器") }
        }
    }
}

@Composable
private fun NoMatch(onClear: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().height(240.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("⌕", color = Tokens.textSecondary, fontSize = 28.sp)
        Spacer(Modifier.height(8.dp))
        Text("没有匹配的文件", color = Tokens.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        Text("换一个关键词，或清除当前筛选。", color = Tokens.textSecondary, fontSize = 11.sp)
        Spacer(Modifier.height(12.dp))
        SmallAction("清除筛选", primary = false, onClick = onClear)
    }
}

@Composable
private fun OtherPane(pane: Pane?) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(pane?.displayTitle ?: "工作区", color = Tokens.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        Text(
            "这份打样只评审文件区。切回「文件」继续检查。",
            color = Tokens.textSecondary,
            fontSize = 11.sp,
        )
        Box(
            Modifier.fillMaxWidth().height(240.dp).clip(RoundedCornerShape(12.dp)).background(Color(0x2EFFFFFF)),
            contentAlignment = Alignment.Center,
        ) {
            Text("其他工作区内容", color = Tokens.textSecondary, fontSize = 12.sp)
        }
    }
}

@Composable
private fun SmallAction(label: String, primary: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier
            .height(28.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(if (primary) Tokens.actionFill else Color(0x14000000))
            .clickable(onClick = onClick)
            .padding(horizontal = 11.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = if (primary) Tokens.textOnAccent else Tokens.textPrimary,
            fontSize = 11.sp,
            fontWeight = if (primary) FontWeight.Medium else FontWeight.Normal,
        )
    }
}

@Composable
private fun GlassPlate(shape: Shape, content: @Composable () -> Unit) {
    Box(
        Modifier
            .clip(shape)
            .background(Color(0x99FFFFFF))
            .border(1.dp, Brush.verticalGradient(listOf(Color(0xCCFFFFFF), Color(0x24FFFFFF))), shape),
    ) {
        content()
    }
}

@Composable
private fun PreviewHarness(
    modifier: Modifier,
    screen: String,
    open: Boolean,
    reducedMotion: Boolean,
    compact: Boolean,
    demoState: DemoState,
    onToggleOpen: () -> Unit,
    onToggleReducedMotion: () -> Unit,
    onToggleWidth: () -> Unit,
    onCycleDemoState: () -> Unit,
) {
    Column(
        modifier
            .padding(12.dp)
            .widthIn(max = 760.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xE61C1C1E))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("统一文件区", color = Color(0xFFF5F5F7), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Text(screen, color = Color(0xFF8E8E93), fontSize = 10.sp)
            Text(LocalPreviewFontStatus.current, color = Color(0xFF8E8E93), fontSize = 10.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            HarnessButton(if (open) "收起" else "展开", onToggleOpen)
            HarnessButton(
                when (demoState) {
                    DemoState.NORMAL -> "状态：正常"
                    DemoState.NO_MATCH -> "状态：无匹配"
                    DemoState.EMPTY -> "状态：空"
                },
                onCycleDemoState,
            )
            HarnessButton(if (compact) "宽度：720" else "宽度：960", onToggleWidth)
            HarnessButton(if (reducedMotion) "减弱动态：开" else "减弱动态：关", onToggleReducedMotion)
            Text("悬停卡片看快捷动作，右键看完整菜单", color = Color(0xFF8E8E93), fontSize = 9.sp)
        }
    }
}

@Composable
private fun HarnessButton(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .height(24.dp)
            .clip(RoundedCornerShape(6.dp))
            .border(1.dp, Color(0x33FFFFFF), RoundedCornerShape(6.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color(0xFFF5F5F7), fontSize = 9.sp)
    }
}
