package com.wyz.covio.preview.previews.workbench

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wyz.covio.preview.DeepLink
import com.wyz.covio.preview.LocalPreviewFontStatus
import kotlinx.coroutines.delay

/**
 * 挂帘工作台的打样。对应 #107。
 *
 * 覆盖需求文档第 5 节的 S1 到 S8，第 7 节的收起方式，以及 F1 到 F7。
 * 评审逐条对照 #76 正文的「表现预期」栏。
 *
 * 打样自带假数据，不接 `kmpDomain`。`kmpDomain` 只有 `jvm` 与 `macosArm64`，接不上 wasmJs。
 * 见 #103 的后续动作第 2 条。
 *
 * 地址栏加锚点可以直接落到某一屏。截图与评审用，见 [StartScreen]。
 */
@Composable
internal fun WorkbenchPreview() {
    val start = remember { StartScreen.fromHash() }
    var open by remember { mutableStateOf(start.open) }
    var homeSelected by remember { mutableStateOf(start.home) }
    var selectedId by remember { mutableStateOf(start.pane) }
    var panes by remember { mutableStateOf(if (start.filledTabs) filledPanes() else defaultPanes()) }
    var widgets by remember { mutableStateOf(defaultWidgets()) }
    var query by remember { mutableStateOf(start.query) }
    var editing by remember { mutableStateOf(start.editing) }
    var error by remember { mutableStateOf(start.error) }
    var reducedMotion by remember { mutableStateOf(false) }
    var autoCollapse by remember { mutableStateOf(false) }
    var settingsOpen by remember { mutableStateOf(start.settings) }
    var paneSettings by remember { mutableStateOf(emptyMap<String, List<PaneSetting>>()) }

    val progress = rememberCurtainProgress(open, reducedMotion)

    val curtainInteraction = remember { MutableInteractionSource() }
    val hoveringCurtain by curtainInteraction.collectIsHoveredAsState()
    val focus = remember { FocusRequester() }

    LaunchedEffect(Unit) { focus.requestFocus() }

    // 指针移出挂帘 500 毫秒后收起。需求文档第 7 节。
    // 默认关掉：打样里评审要点来点去，自动收起会打断。
    LaunchedEffect(open, hoveringCurtain, autoCollapse) {
        if (open && autoCollapse && !hoveringCurtain) {
            delay(Tokens.POINTER_EXIT_MS.toLong())
            open = false
        }
    }

    val currentPane = panes.firstOrNull { it.id == selectedId } ?: panes.first()
    val paneSettingsFor = paneSettings[currentPane.id] ?: defaultPaneSettings(currentPane.kind)

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .focusRequester(focus)
            .focusable()
            .onKeyEvent { event ->
                // 按 Escape 收起。搜索框有内容时，第一次只清空。需求文档第 7 节。
                if (event.type != KeyEventType.KeyDown || event.key != Key.Escape) return@onKeyEvent false
                if (query.isNotEmpty()) query = "" else open = false
                true
            },
    ) {
        val maxPanelHeight = maxHeight - 120.dp

        Wallpaper(Modifier.fillMaxSize())

        // 点挂帘外部收起。需求文档第 7 节。
        Box(
            Modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { open = false },
        )

        Column(
            Modifier
                .align(Alignment.TopCenter)
                .hoverable(curtainInteraction),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            MenuBar(
                capsuleVisible = true,
                onHotspotEnter = { open = true },
                onCapsuleClick = { open = !open },
            )

            if (progress > 0.01f) {
                CurtainPanel(progress = progress, reducedMotion = reducedMotion) {
                    Column(
                        Modifier
                            .heightIn(max = maxPanelHeight)
                            .verticalScroll(rememberScrollState()),
                    ) {
                        TabBar(
                            panes = panes,
                            homeSelected = homeSelected,
                            selectedId = selectedId,
                            query = query,
                            editing = editing,
                            pageAction = pageAction(settingsOpen, editing, homeSelected),
                            onQueryChange = { query = it },
                            onHome = {
                                homeSelected = true
                                settingsOpen = false
                            },
                            onSelect = { id ->
                                selectedId = id
                                homeSelected = false
                                settingsOpen = false
                                editing = false
                            },
                            onPageAction = {
                                when {
                                    settingsOpen -> settingsOpen = false
                                    editing -> editing = false
                                    homeSelected -> editing = true
                                }
                            },
                            onReorder = { from, to ->
                                panes = panes.toMutableList().also { list ->
                                    val moved = list.removeAt(from)
                                    list.add(to.coerceIn(0, list.size), moved)
                                }
                            },
                        )

                        Box(Modifier.fillMaxWidth().height(1.dp).background(Tokens.divider.copy(alpha = 0.6f)))

                        Column(
                            Modifier.padding(contentPadding),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (editing) {
                                EditBanner(
                                    tabCount = panes.count { !it.hidden },
                                    widgetCount = widgets.size,
                                    onDone = { editing = false },
                                )
                            }

                            when {
                                error -> ErrorScreen(
                                    onRetry = { error = false },
                                    onOpenSettings = { error = false; selectedId = "settings"; homeSelected = false },
                                    onResetLayout = {
                                        error = false
                                        widgets = defaultWidgets()
                                        panes = defaultPanes()
                                        homeSelected = true
                                    },
                                )

                                query.isNotEmpty() -> SearchResults(
                                    query = query,
                                    panes = panes,
                                    onOpenPane = { id ->
                                        selectedId = id
                                        homeSelected = false
                                        query = ""
                                    },
                                )

                                settingsOpen -> PaneSettings(
                                    pane = currentPane,
                                    settings = paneSettingsFor,
                                    onRename = { name ->
                                        panes = panes.map { if (it.id == currentPane.id) it.copy(title = name) else it }
                                    },
                                    onIcon = { icon ->
                                        panes = panes.map { if (it.id == currentPane.id) it.copy(icon = icon) else it }
                                    },
                                    onHidden = { hidden ->
                                        panes = panes.map { if (it.id == currentPane.id) it.copy(hidden = hidden) else it }
                                        if (hidden) {
                                            homeSelected = true
                                            settingsOpen = false
                                        }
                                    },
                                    onSettingToggle = { key ->
                                        paneSettings = paneSettings + (
                                            currentPane.id to paneSettingsFor.map {
                                                if (it.key == key) it.copy(on = !it.on) else it
                                            }
                                            )
                                    },
                                    onReset = {
                                        panes = panes.map {
                                            if (it.id == currentPane.id) it.copy(title = "", icon = "", hidden = false) else it
                                        }
                                        paneSettings = paneSettings - currentPane.id
                                    },
                                    onDelete = {
                                        panes = panes.filterNot { it.id == currentPane.id }
                                        selectedId = panes.first().id
                                        homeSelected = true
                                        settingsOpen = false
                                    },
                                )

                                homeSelected -> if (widgets.isEmpty()) {
                                    EmptyHome(editing)
                                } else {
                                    HomeGrid(
                                        widgets = widgets,
                                        editing = editing,
                                        onMove = { from, to ->
                                            widgets = widgets.toMutableList().also { list ->
                                                val moved = list.removeAt(from)
                                                list.add(to.coerceIn(0, list.size), moved)
                                            }
                                        },
                                        onResize = { id, size ->
                                            widgets = widgets.map { if (it.id == id) it.copy(size = size) else it }
                                        },
                                        onDelete = { id -> widgets = widgets.filterNot { it.id == id } },
                                    )
                                }

                                else -> PaneContent(currentPane)
                            }
                        }
                    }
                }
            }
        }

        Harness(
            modifier = Modifier.align(Alignment.BottomCenter),
            screen = screenName(open, error, settingsOpen, editing, query, homeSelected),
            reducedMotion = reducedMotion,
            autoCollapse = autoCollapse,
            onReducedMotion = { reducedMotion = it },
            onAutoCollapse = { autoCollapse = it },
            onError = { error = true; open = true },
            onFillPanes = { panes = filledPanes() },
            onReset = {
                panes = defaultPanes()
                widgets = defaultWidgets()
                paneSettings = emptyMap()
                query = ""
                editing = false
                error = false
                homeSelected = true
                selectedId = "now"
                settingsOpen = false
            },
        )
    }
}

/** 右端那个动作按钮上的字。 */
private fun pageAction(settingsOpen: Boolean, editing: Boolean, homeSelected: Boolean): String? = when {
    settingsOpen -> "返回"
    editing -> "完成"
    homeSelected -> "编辑"
    else -> null
}

/**
 * 打样的起始画面。
 *
 * 地址栏加锚点可以直接落到某一屏。截图与评审用，省得点。
 * 锚点写在 issue 号后面，形如 `#107-edit`。见 [DeepLink]。
 *
 * | 锚点 | 画面 |
 * | --- | --- |
 * | 空 | S1 菜单栏，挂帘收起 |
 * | `home` | S4 挂帘展开 · 首页 |
 * | `pane` | S5 工作区内容页 |
 * | `search` | S3 搜索中 |
 * | `edit` | S6 编辑模式 |
 * | `settings` | S7 工作区设置页 |
 * | `error` | S8 错误与恢复 |
 * | `tabs` | S3 十二个页签的排版 |
 */
private data class StartScreen(
    val open: Boolean,
    val home: Boolean,
    val pane: String,
    val query: String,
    val editing: Boolean,
    val settings: Boolean,
    val error: Boolean,
    val filledTabs: Boolean,
) {
    companion object {
        fun fromHash(): StartScreen = when (val anchor = DeepLink.anchor) {
            "home" -> base(open = true)
            "pane" -> base(open = true, home = false, pane = "clipboard")
            "search" -> base(open = true, query = "文")
            "edit" -> base(open = true, editing = true)
            "settings" -> base(open = true, home = false, pane = "now", settings = true)
            "error" -> base(open = true, error = true)
            "tabs" -> base(open = true, filledTabs = true)
            else -> {
                check(anchor.isEmpty() || anchor == "closed") { "未知的锚点：$anchor" }
                base(open = false)
            }
        }

        private fun base(
            open: Boolean,
            home: Boolean = true,
            pane: String = "now",
            query: String = "",
            editing: Boolean = false,
            settings: Boolean = false,
            error: Boolean = false,
            filledTabs: Boolean = false,
        ) = StartScreen(open, home, pane, query, editing, settings, error, filledTabs)
    }
}

/** 当前画面对应的 S 编号。评审时对号用。 */
private fun screenName(
    open: Boolean,
    error: Boolean,
    settingsOpen: Boolean,
    editing: Boolean,
    query: String,
    homeSelected: Boolean,
): String = when {
    !open -> "S2 挂帘收起（S1 菜单栏在上方）"
    error -> "S8 错误与恢复"
    settingsOpen -> "S7 工作区设置页"
    editing -> "S6 编辑模式"
    query.isNotEmpty() -> "S3 挂帘展开 · 页签（搜索中）"
    homeSelected -> "S4 挂帘展开 · 首页"
    else -> "S5 工作区内容页"
}

/** F3：输入即过滤。工作区与设置项一起过滤。 */
@Composable
private fun SearchResults(query: String, panes: List<Pane>, onOpenPane: (String) -> Unit) {
    val matchedPanes = panes.filterNot { it.hidden }.filter { it.displayTitle.contains(query, ignoreCase = true) }
    val matchedSettings = panes
        .flatMap { pane -> contentRows(pane.kind).map { pane to it } }
        .filter { it.second.title.contains(query, ignoreCase = true) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("搜索结果", color = Tokens.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Medium)

        if (matchedPanes.isEmpty() && matchedSettings.isEmpty()) {
            Text("没有匹配的设置", color = Tokens.textSecondary, fontSize = 12.sp)
            return@Column
        }

        matchedPanes.forEach { pane ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Tokens.controlRadius.dp))
                    .background(Tokens.surface)
                    .clickable { onOpenPane(pane.id) }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(pane.displayIcon, color = Tokens.textSecondary, fontSize = 12.sp)
                Text(pane.displayTitle, color = Tokens.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                Spacer(Modifier.weight(1f))
                Text("工作区", color = Tokens.textSecondary, fontSize = 10.sp)
            }
        }

        matchedSettings.forEach { (pane, row) ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Tokens.controlRadius.dp))
                    .background(Tokens.surface)
                    .clickable { onOpenPane(pane.id) }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(row.title, color = Tokens.textPrimary, fontSize = 13.sp)
                    Text(row.detail, color = Tokens.textSecondary, fontSize = 11.sp)
                }
                Text("在「${pane.displayTitle}」里", color = Tokens.textSecondary, fontSize = 10.sp)
            }
        }
    }
}

/**
 * 打样的工具条。
 *
 * 这一条不是 Covio 的界面，是打样的操作台。深色，与产品界面分开。
 * 只放浏览器里做不出来的动作：系统设置、注入错误、造满页签。
 */
@Composable
private fun Harness(
    modifier: Modifier,
    screen: String,
    reducedMotion: Boolean,
    autoCollapse: Boolean,
    onReducedMotion: (Boolean) -> Unit,
    onAutoCollapse: (Boolean) -> Unit,
    onError: () -> Unit,
    onFillPanes: () -> Unit,
    onReset: () -> Unit,
) {
    Column(
        modifier
            .padding(16.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xE61C1C1E))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("打样操作台", color = Color(0xFFF5F5F7), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Text(screen, color = Color(0xFF8E8E93), fontSize = 11.sp)
            Text(LocalPreviewFontStatus.current, color = Color(0xFF8E8E93), fontSize = 11.sp)
        }
        Text(
            "悬停菜单栏胶囊或点它打开。点面板外面收起。按 Escape 收起；搜索框有内容时第一次只清空。",
            color = Color(0xFF8E8E93),
            fontSize = 10.sp,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HarnessToggle("减弱动态效果", reducedMotion, onReducedMotion)
            HarnessToggle("指针移出后自动收起", autoCollapse, onAutoCollapse)
            HarnessButton("触发错误画面", onError)
            HarnessButton("加到 12 个工作区", onFillPanes)
            HarnessButton("重置", onReset)
        }
    }
}

@Composable
private fun HarnessToggle(label: String, on: Boolean, onToggle: (Boolean) -> Unit) {
    Box(
        Modifier
            .height(24.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(if (on) Tokens.actionFill else Color(0x33FFFFFF))
            .clickable { onToggle(!on) }
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color(0xFFF5F5F7), fontSize = 10.sp)
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
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color(0xFFF5F5F7), fontSize = 10.sp)
    }
}
