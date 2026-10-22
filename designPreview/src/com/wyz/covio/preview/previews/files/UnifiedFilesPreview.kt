package com.wyz.covio.preview.previews.files

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.ui.draw.shadow
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
import androidx.compose.ui.unit.Dp
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
import kotlin.math.ceil
import kotlin.math.roundToInt

private val heroHeight = 176.dp
private val quietTileHeight = 146.dp
private val stageGap = 16.dp
private val quietGap = 14.dp
private val quietColumns = 4

/**
 * 统一文件区预览。
 *
 * 第三版只保留一个详细焦点位：
 * 1. 顶部只有筛选菜单、数量和加入按钮。
 * 2. 一个当前焦点卡显示详细信息和动作。
 * 3. 其余条目退到安静的格子中。
 *
 * 点击任一格子，该条目进入焦点位。删除检查器与重复元数据。
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
                                Text("首页", color = Tokens.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
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
    var selectedFileId by remember { mutableStateOf<String?>(null) }
    val files = if (demoState == DemoState.NORMAL) visibleFiles(filter, query) else emptyList()
    val selectedFile = files.firstOrNull { it.id == selectedFileId } ?: files.firstOrNull()

    LaunchedEffect(filter, query, demoState) {
        if (files.isNotEmpty() && files.none { it.id == selectedFileId }) {
            selectedFileId = files.first().id
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (demoState == DemoState.NORMAL) {
            UtilityBar(
                filter = filter,
                itemCount = files.size,
                activeTransfers = demoFiles.count {
                    it.availability == DemoAvailability.FETCHING || it.availability == DemoAvailability.REMOTE
                },
                onFilter = onFilter,
                onAction = onAction,
            )
        }

        when {
            demoState == DemoState.EMPTY -> EmptyFiles(onAction)
            demoState == DemoState.NO_MATCH || files.isEmpty() -> NoMatch(onClearFilters)
            selectedFile != null -> FocusStage(
                files = files,
                selected = selectedFile,
                onSelect = { selectedFileId = it },
                onAction = onAction,
            )
        }
    }
}

@Composable
private fun UtilityBar(
    filter: FileFilter,
    itemCount: Int,
    activeTransfers: Int,
    onFilter: (FileFilter) -> Unit,
    onAction: (String) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().height(28.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FilterMenu(filter = filter, onFilter = onFilter)
        Text("$itemCount 项", color = Tokens.textSecondary, fontSize = 9.sp)
        if (activeTransfers > 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(5.dp).clip(CircleShape).background(Tokens.actionFill))
                Text("$activeTransfers 进行中", color = Tokens.textSecondary, fontSize = 9.sp)
            }
        }
        Spacer(Modifier.weight(1f))
        MiniToolbarButton("＋") { onAction("打开加入菜单") }
    }
}

@Composable
private fun FilterMenu(filter: FileFilter, onFilter: (FileFilter) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .height(28.dp)
                .clip(RoundedCornerShape(7.dp))
                .background(Color(0x12000000))
                .clickable { expanded = true }
                .padding(horizontal = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(filter.label, color = Tokens.textPrimary, fontSize = 10.sp, fontWeight = FontWeight.Medium)
            Text("⌄", color = Tokens.textSecondary, fontSize = 9.sp)
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.width(158.dp),
            shape = RoundedCornerShape(9.dp),
            containerColor = Color(0xF7FFFFFF),
            shadowElevation = 8.dp,
            border = BorderStroke(1.dp, Tokens.divider.copy(alpha = 0.75f)),
        ) {
            FileFilter.entries.forEach { item ->
                DropdownMenuItem(
                    modifier = Modifier.height(30.dp),
                    contentPadding = PaddingValues(horizontal = 10.dp),
                    text = {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                item.label,
                                color = Tokens.textPrimary,
                                fontSize = 11.sp,
                                fontWeight = if (item == filter) FontWeight.Medium else FontWeight.Normal,
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(filterCount(item).toString(), color = Tokens.textSecondary, fontSize = 9.sp)
                                Text(if (item == filter) "✓" else "", color = Tokens.actionFill, fontSize = 10.sp)
                            }
                        }
                    },
                    onClick = {
                        expanded = false
                        onFilter(item)
                    },
                    colors = MenuDefaults.itemColors(textColor = Tokens.textPrimary),
                )
            }
        }
    }
}

@Composable
private fun MiniToolbarButton(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(28.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(Color(0x12000000))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Tokens.textPrimary, fontSize = 15.sp)
    }
}

@Composable
private fun FocusStage(
    files: List<DemoFile>,
    selected: DemoFile,
    onSelect: (String) -> Unit,
    onAction: (String) -> Unit,
) {
    val remaining = files.filterNot { it.id == selected.id }
    Column(verticalArrangement = Arrangement.spacedBy(stageGap)) {
        HeroCard(file = selected, onAction = onAction)
        if (remaining.isNotEmpty()) {
            QuietGrid(files = remaining, onSelect = onSelect, onAction = onAction)
        }
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun HeroCard(file: DemoFile, onAction: (String) -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val shape = RoundedCornerShape(12.dp)
    val actions = file.inspectorActions().filterNot { it == "删除" }.take(3)

    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .height(heroHeight)
                .clip(shape)
                .background(if (hovered) Color(0xD9FFFFFF) else Color(0xC7FFFFFF))
                .border(0.7.dp, Tokens.divider.copy(alpha = 0.68f), shape)
                .hoverable(interaction)
                .combinedClickable(onClick = { }, onDoubleClick = { onAction("打开：${file.name}") })
                .onPointerEvent(PointerEventType.Press) { event ->
                    if (event.buttons.isSecondaryPressed) menuOpen = true
                },
        ) {
            Box(Modifier.weight(0.43f).fillMaxHeight()) {
                FilePreview(file)
                StatusOverlay(file)
                if (file.pinned) PinBadge(Modifier.align(Alignment.TopStart))
            }
            Column(
                Modifier
                    .weight(0.57f)
                    .fillMaxHeight()
                    .padding(horizontal = 17.dp, vertical = 14.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(file.typeLabel(), color = Tokens.textSecondary, fontSize = 9.sp, fontWeight = FontWeight.Medium)
                    Text(
                        "⋯",
                        color = Tokens.textSecondary,
                        fontSize = 13.sp,
                        modifier = Modifier
                            .clip(RoundedCornerShape(5.dp))
                            .clickable { menuOpen = true }
                            .padding(horizontal = 6.dp, vertical = 1.dp),
                    )
                }
                Spacer(Modifier.height(5.dp))
                Text(
                    file.name,
                    color = Tokens.textPrimary,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    lineHeight = 17.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(4.dp))
                Text("${file.origin}  ·  ${file.meta}", color = Tokens.textSecondary, fontSize = 9.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    actions.forEachIndexed { index, action ->
                        MiniAction(
                            label = action,
                            primary = index == 0,
                            onClick = { onAction("$action：${file.name}") },
                        )
                    }
                }
                Spacer(Modifier.height(7.dp))
                Text("↵ 打开   ⌘C 复制   ⌘⌫ 删除", color = Tokens.disabledText, fontSize = 8.sp)
            }
        }
        FileContextMenu(
            expanded = menuOpen,
            file = file,
            onDismiss = { menuOpen = false },
            onAction = onAction,
        )
    }
}

@Composable
private fun QuietGrid(files: List<DemoFile>, onSelect: (String) -> Unit, onAction: (String) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val tileWidth = (maxWidth - quietGap * (quietColumns - 1)) / quietColumns
        Column(verticalArrangement = Arrangement.spacedBy(quietGap)) {
            files.chunked(quietColumns).forEach { rowFiles ->
                Row(horizontalArrangement = Arrangement.spacedBy(quietGap)) {
                    rowFiles.forEach { file ->
                        QuietTile(
                            file = file,
                            width = tileWidth,
                            onSelect = { onSelect(file.id) },
                            onAction = onAction,
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun QuietTile(
    file: DemoFile,
    width: Dp,
    onSelect: () -> Unit,
    onAction: (String) -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    var menuOpen by remember { mutableStateOf(false) }

    Box {
        Column(
            Modifier
                .width(width)
                .height(quietTileHeight)
                .hoverable(interaction)
                .combinedClickable(onClick = onSelect, onDoubleClick = { onAction("打开：${file.name}") })
                .onPointerEvent(PointerEventType.Press) { event ->
                    if (event.buttons.isSecondaryPressed) menuOpen = true
                },
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(104.dp)
                    .clip(RoundedCornerShape(9.dp))
                    .border(
                        if (hovered) 1.dp else 0.5.dp,
                        if (hovered) Color(0x33000000) else Tokens.divider.copy(alpha = 0.55f),
                        RoundedCornerShape(9.dp),
                    ),
            ) {
                FilePreview(file)
                QuietStatusOverlay(file)
                if (file.pinned) PinBadge(Modifier.align(Alignment.TopStart))
                if (hovered) {
                    Row(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                            .height(25.dp)
                            .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xAA000000))))
                            .padding(horizontal = 4.dp, vertical = 3.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .clip(RoundedCornerShape(5.dp))
                                .background(Color(0xD9FFFFFF))
                                .clickable { onAction("${file.quickActions().first()}：${file.name}") },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(file.quickActions().first(), color = Tokens.textPrimary, fontSize = 8.sp, fontWeight = FontWeight.Medium)
                        }
                        Box(
                            Modifier
                                .size(21.dp)
                                .clip(RoundedCornerShape(5.dp))
                                .background(Color(0xD9FFFFFF))
                                .clickable { menuOpen = true },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("⋯", color = Tokens.textPrimary, fontSize = 9.sp)
                        }
                    }
                }
            }
            Text(
                file.name,
                color = Tokens.textPrimary,
                fontSize = 10.5.sp,
                fontWeight = FontWeight.Medium,
                lineHeight = 12.sp,
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
                fontSize = 8.3.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        FileContextMenu(
            expanded = menuOpen,
            file = file,
            onDismiss = { menuOpen = false },
            onAction = onAction,
        )
    }
}

@Composable
private fun QuietStatusOverlay(file: DemoFile) {
    when (file.availability) {
        DemoAvailability.LOCAL -> Unit
        DemoAvailability.REMOTE -> {
            Box(
                Modifier.fillMaxSize().background(Color(0x731C1C1E)),
                contentAlignment = Alignment.Center,
            ) {
                Text("另一台设备", color = Color.White, fontSize = 8.5.sp, fontWeight = FontWeight.Medium)
            }
        }
        DemoAvailability.FETCHING -> {
            Box(Modifier.fillMaxSize()) {
                Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(3.dp).background(Color(0x33000000))) {
                    Box(Modifier.fillMaxWidth(file.progress).height(3.dp).background(Tokens.actionFill))
                }
            }
        }
        DemoAvailability.FAILED -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("传输失败", color = Color.White, fontSize = 8.5.sp, fontWeight = FontWeight.Medium)
            }
        }
        DemoAvailability.UNAVAILABLE -> {
            Box(
                Modifier.fillMaxSize().background(Color(0xB31C1C1E)),
                contentAlignment = Alignment.Center,
            ) {
                Text("内容不可用", color = Color.White, fontSize = 8.5.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun FileContextMenu(
    expanded: Boolean,
    file: DemoFile,
    onDismiss: () -> Unit,
    onAction: (String) -> Unit,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        modifier = Modifier.width(152.dp),
        shape = RoundedCornerShape(9.dp),
        containerColor = Color(0xF7FFFFFF),
        shadowElevation = 8.dp,
        border = BorderStroke(1.dp, Tokens.divider.copy(alpha = 0.75f)),
    ) {
        file.menuActions().forEach { action ->
            if (action == "删除") {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                        .height(1.dp)
                        .background(Tokens.divider.copy(alpha = 0.6f)),
                )
            }
            DropdownMenuItem(
                modifier = Modifier.height(30.dp),
                contentPadding = PaddingValues(horizontal = 10.dp),
                text = {
                    Text(
                        action,
                        color = if (action == "删除") Tokens.errorText else Tokens.textPrimary,
                        fontSize = 11.sp,
                    )
                },
                onClick = {
                    onDismiss()
                    onAction("$action：${file.name}")
                },
                colors = MenuDefaults.itemColors(textColor = Tokens.textPrimary),
            )
        }
    }
}

@Composable
private fun MiniAction(label: String, primary: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .height(24.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(if (primary) Tokens.actionFill else Color(0x14000000))
            .clickable(onClick = onClick)
            .padding(horizontal = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = if (primary) Tokens.textOnAccent else Tokens.textPrimary,
            fontSize = 9.sp,
            fontWeight = if (primary) FontWeight.Medium else FontWeight.Normal,
        )
    }
}

@Composable
private fun FilePreview(file: DemoFile) {
    when (file.kind) {
        DemoFileKind.SCREENSHOT, DemoFileKind.IMAGE -> WindowPreview(file.kind, file.id)
        DemoFileKind.TEXT -> TextPreview(file.detail)
        DemoFileKind.PDF -> DocumentPreview("PDF", Color(0xFFD70015))
        DemoFileKind.ARCHIVE -> DocumentPreview("ZIP", Color(0xFF0A84FF))
        DemoFileKind.AUDIO -> AudioPreview()
        DemoFileKind.VIDEO -> VideoPreview()
    }
}

@Composable
private fun WindowPreview(kind: DemoFileKind, variant: String) {
    val palette = when {
        kind != DemoFileKind.SCREENSHOT -> listOf(Color(0xFF162A46), Color(0xFF517A92), Color(0xFFB5D6D2))
        variant.endsWith("2") -> listOf(Color(0xFF2F5251), Color(0xFF8DB5A4), Color(0xFFE4E0C8))
        else -> listOf(Color(0xFF687DBD), Color(0xFFD6A17F), Color(0xFFF1D6B6))
    }
    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(palette)),
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
                .padding(start = 16.dp, top = 31.dp, end = 34.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(5.dp))
                .background(Color(0xC7FFFFFF))
                .padding(7.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Box(Modifier.fillMaxWidth(0.64f).height(5.dp).clip(CircleShape).background(Color(0xAA1D1D1F)))
            Box(Modifier.fillMaxWidth(0.90f).height(3.dp).clip(CircleShape).background(Color(0x771D1D1F)))
            Box(Modifier.fillMaxWidth(0.78f).height(3.dp).clip(CircleShape).background(Color(0x551D1D1F)))
        }
        Box(
            Modifier
                .align(Alignment.BottomEnd)
                .padding(9.dp)
                .width(34.dp)
                .height(38.dp)
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
            fontSize = 9.5.sp,
            lineHeight = 13.sp,
            maxLines = 6,
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
            Text(label, color = accent, fontSize = 15.sp, fontWeight = FontWeight.Bold)
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
                .size(36.dp)
                .clip(CircleShape)
                .background(Color(0xB3FFFFFF)),
            contentAlignment = Alignment.Center,
        ) {
            Text("▶", color = Color(0xFF1D1D1F), fontSize = 15.sp)
        }
    }
}

@Composable
private fun PinBadge(modifier: Modifier = Modifier) {
    Box(
        modifier
            .padding(6.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(Color(0xD9FFFFFF))
            .padding(horizontal = 5.dp, vertical = 2.dp),
    ) {
        Text("置顶", color = Tokens.textPrimary, fontSize = 7.5.sp, fontWeight = FontWeight.Medium)
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
                    Text("正在取回 ${(file.progress * 100).toInt()}%", color = Color.White, fontSize = 8.5.sp)
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
                    Text("传输失败 · 重试", color = Color.White, fontSize = 8.5.sp, fontWeight = FontWeight.Medium)
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
        Text(title, color = Color.White, fontSize = 9.5.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(2.dp))
        Text(detail, color = Color(0xCCFFFFFF), fontSize = 7.5.sp, textAlign = TextAlign.Center)
    }
}

@Composable
private fun EmptyFiles(onAction: (String) -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(300.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier
                    .size(46.dp)
                    .clip(RoundedCornerShape(13.dp))
                    .background(Color(0x12000000)),
                contentAlignment = Alignment.Center,
            ) {
                Text("＋", color = Tokens.textPrimary, fontSize = 22.sp, fontWeight = FontWeight.Light)
            }
            Spacer(Modifier.height(11.dp))
            Text("把下一件内容放进来", color = Tokens.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.height(4.dp))
            Text("截图、文件或文本会停在最近使用的位置。", color = Tokens.textSecondary, fontSize = 10.sp)
            Spacer(Modifier.height(13.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                MiniAction("放入文件…", primary = true) { onAction("打开文件选择器") }
                MiniAction("新建文本…", primary = false) { onAction("打开文本编辑器") }
            }
            Spacer(Modifier.height(11.dp))
            Text("⌘O 放入文件   ⌘N 新建文本", color = Tokens.disabledText, fontSize = 8.sp)
        }
    }
}

@Composable
private fun NoMatch(onClear: () -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(260.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("⌕", color = Tokens.textSecondary, fontSize = 24.sp)
            Spacer(Modifier.height(7.dp))
            Text("没有匹配的文件", color = Tokens.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.height(3.dp))
            Text("换一个关键词，或清除当前筛选。", color = Tokens.textSecondary, fontSize = 10.sp)
            Spacer(Modifier.height(11.dp))
            MiniAction("清除筛选", primary = false, onClick = onClear)
        }
    }
}

@Composable
private fun OtherPane(pane: Pane?) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(pane?.displayTitle ?: "工作区", color = Tokens.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        Text("这份打样只评审文件区。切回「文件」继续检查。", color = Tokens.textSecondary, fontSize = 10.sp)
        Box(
            Modifier.fillMaxWidth().height(420.dp).clip(RoundedCornerShape(12.dp)).background(Color(0x1AFFFFFF)),
            contentAlignment = Alignment.Center,
        ) {
            Text("其他工作区内容", color = Tokens.textSecondary, fontSize = 11.sp)
        }
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
            Text("统一文件区 · v3", color = Color(0xFFF5F5F7), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
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
            Text("点任意条目进入焦点位 · 悬停快捷动作 · 右键完整菜单", color = Color(0xFF8E8E93), fontSize = 9.sp)
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
