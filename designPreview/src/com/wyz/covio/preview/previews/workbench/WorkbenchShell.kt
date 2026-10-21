package com.wyz.covio.preview.previews.workbench

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/**
 * 挂帘的外壳：假桌面、菜单栏、收起态胶囊、展开态玻璃面板、tab bar。
 *
 * 画的是需求文档第 5 节的 S1、S2、S3 与第 6 节的版式。
 */

/** 菜单栏高。系统值，合同里没有这一条。 */
private val menuBarHeight = 28.dp

/** 页签之间的间距。 */
private val tabGap = 4.dp

/**
 * 假桌面。壁纸有明暗结构，面板透不透光一眼看得出来。
 *
 * 真机上壁纸是用户自己选的。打样固定一张，评审时按同一张比。
 */
@Composable
internal fun Wallpaper(modifier: Modifier = Modifier) {
    Box(
        modifier.background(
            Brush.linearGradient(
                listOf(Color(0xFF2B3A67), Color(0xFF6E5A8F), Color(0xFFC98A6B), Color(0xFFE8C39E)),
            ),
        ),
    ) {
        // 两块亮斑。面板盖上去还能不能看见它们，就是「桌面透出来」这一条。
        Box(
            Modifier
                .offset(x = 120.dp, y = 90.dp)
                .width(280.dp)
                .height(180.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(Color(0x33FFFFFF)),
        )
        Box(
            Modifier
                .offset(x = 620.dp, y = 420.dp)
                .width(360.dp)
                .height(240.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(Color(0x26FFFFFF)),
        )
    }
}

/**
 * 菜单栏。中间是刘海，刘海右边是收起态胶囊。
 *
 * 刘海与胶囊合起来是「刘海热区」。指针进来就展开，见 S2 与 R2。
 */
@Composable
internal fun MenuBar(
    capsuleVisible: Boolean,
    onHotspotEnter: () -> Unit,
    onCapsuleClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()

    // 指针进入热区就展开。composition 里不能直接回调，放进 effect。
    LaunchedEffect(hovered) {
        if (hovered) onHotspotEnter()
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(menuBarHeight)
            .background(Color(0xE61C1C1E))
            .hoverable(interaction)
            .clickable(onClick = onCapsuleClick),
    ) {
        // 左侧的系统菜单。
        Row(
            Modifier.align(Alignment.CenterStart),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Spacer(Modifier.width(12.dp))
            MenuBarLabel("◉")
            MenuBarLabel("访达")
            MenuBarLabel("文件")
            MenuBarLabel("编辑")
        }

        // 刘海。位置固定在正中，与真机一致。没有可见元素的备用入口。
        Box(
            Modifier
                .align(Alignment.Center)
                .width(120.dp)
                .height(menuBarHeight)
                .background(Color(0xFF000000)),
        )

        // 右侧：胶囊紧挨刘海，然后是状态项。
        Row(
            Modifier.align(Alignment.CenterEnd),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            MenuBarLabel("82%")
            MenuBarLabel("14:32")
            Spacer(Modifier.width(12.dp))
        }

        if (capsuleVisible) {
            Row(
                Modifier.align(Alignment.Center).offset(x = 120.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(Modifier.width(6.dp))
                Capsule(hovered = hovered)
            }
        }
    }
}

/** 收起态胶囊。含应用图标与名称。见 ADR-0002 决策 3。 */
@Composable
private fun Capsule(hovered: Boolean) {
    Row(
        modifier = Modifier
            .height(Tokens.capsuleHeight.dp)
            .clip(RoundedCornerShape(Tokens.pillRadius.dp))
            .background(if (hovered) Tokens.brand.copy(alpha = 0.82f) else Tokens.brand)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text("◈", color = Tokens.textOnAccent, fontSize = 9.sp)
        Text("Covio", color = Tokens.textOnAccent, fontSize = 10.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun MenuBarLabel(text: String) {
    Text(text, color = Color(0xFFF5F5F7), fontSize = 11.sp, modifier = Modifier.padding(horizontal = 7.dp))
}

/**
 * 展开态面板。玻璃材质，圆角 22 点，1 点细边框，轻量阴影。
 *
 * 面板主体透明，桌面透出来。见 ADR-0002 决策 2。
 *
 * [progress] 是展开进度：0 是收起，1 是展开完。高度跟着内容走。
 * 减弱动态效果打开时只有透明度在动，位移和弹性都去掉。见需求文档第 6 节。
 *
 * **已知边界：** 真机用 `NSVisualEffectView` 的模糊。浏览器里没有对应的模糊，
 * 打样只用半透明填充。模糊本身的观感是真机验收的事，见 #107 的已知边界第 2 条。
 */
@Composable
internal fun CurtainPanel(progress: Float, reducedMotion: Boolean, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(Tokens.panelRadius.dp)
    val density = LocalDensity.current.density
    val slide = if (reducedMotion) 0f else (1f - progress) * -14f

    Box(
        Modifier
            .widthIn(min = Tokens.panelMinWidth.dp)
            .width(Tokens.panelWidth.dp)
            .offset { IntOffset(0, (slide * density).roundToInt()) }
            .alpha(progress)
            .shadow(elevation = 18.dp, shape = shape)
            .clip(shape)
            .background(Tokens.materialThick)
            .border(1.dp, Tokens.divider.copy(alpha = 0.7f), shape),
    ) {
        content()
    }
}

/**
 * tab bar。高 46 点。
 *
 * 左端是固定的首页入口，首页右边是搜索，中间是工作区页签，右端是当前页的动作。
 *
 * **待评审：** ADR-0002 决策 1 写「左端是搜索入口」，决策 4 写「首页固定在 tab bar 左端」。
 * 两句话都要「左端」。打样把首页放在最左，搜索紧挨着它。这一条提给评审判断。
 */
@Composable
internal fun TabBar(
    panes: List<Pane>,
    homeSelected: Boolean,
    selectedId: String?,
    query: String,
    editing: Boolean,
    pageAction: String,
    searchPlaceholder: String = "搜索工作区与设置",
    onQueryChange: (String) -> Unit,
    onHome: () -> Unit,
    onSelect: (String) -> Unit,
    onPageAction: () -> Unit,
    onReorder: (from: Int, to: Int) -> Unit,
) {
    val visible = panes.filterNot { it.hidden }
    val offsets = remember { mutableStateMapOf<Int, Dp>() }
    val density = LocalDensity.current
    val selectedIndex = visible.indexOfFirst { it.id == selectedId }
    val selected = !homeSelected && selectedIndex >= 0

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(Tokens.tabBarHeight.dp)
            .padding(horizontal = Tokens.panelPadding.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        HomeEntry(selected = homeSelected, onClick = onHome)
        SearchField(
            query = query,
            placeholder = searchPlaceholder,
            onQueryChange = onQueryChange,
            enabled = !editing,
        )

        Box(Modifier.weight(1f)) {
            Box(Modifier.horizontalScroll(rememberScrollState())) {
                Box {
                    // 选中态的胶囊滑块。位置跟着选中页签走，160 毫秒横向滑动。
                    val start = offsets[selectedIndex]
                    val end = offsets[selectedIndex + 1]
                    if (selected && start != null && end != null) {
                        val x by animateDpAsState(start, tween(Tokens.TAB_SWITCH_MS), label = "pill-x")
                        val w by animateDpAsState((end - start - tabGap).coerceAtLeast(24.dp), tween(Tokens.TAB_SWITCH_MS), label = "pill-w")
                        Box(
                            Modifier
                                .offset(x = x)
                                .height(Tokens.tabHeight.dp)
                                .width(w)
                                .clip(RoundedCornerShape(Tokens.pillRadius.dp))
                                .background(Tokens.actionFill),
                        )
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(tabGap)) {
                        visible.forEachIndexed { index, pane ->
                            Tab(
                                pane = pane,
                                index = index,
                                selected = selected && pane.id == selectedId,
                                editing = editing,
                                onSelect = { onSelect(pane.id) },
                                onReorder = onReorder,
                                onMeasured = { x -> offsets[index] = with(density) { x.toDp() } },
                            )
                        }
                        // 哨兵。最后一条页签的宽度靠它算出来。
                        Box(
                            Modifier
                                .height(Tokens.tabHeight.dp)
                                .width(1.dp)
                                .onGloballyPositioned {
                                    offsets[visible.size] = with(density) { it.positionInParent().x.toDp() }
                                },
                        )
                    }
                }
            }
        }

        PageAction(label = pageAction, onClick = onPageAction)
    }
}

/** 首页入口。固定在 tab bar 左端，不参与排序，也不随页签滚动。 */
@Composable
private fun HomeEntry(selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .height(Tokens.tabHeight.dp)
            .width(36.dp)
            .clip(RoundedCornerShape(Tokens.controlRadius.dp))
            .background(if (selected) Tokens.actionFill else Color(0x14000000))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text("▦", color = if (selected) Tokens.textOnAccent else Tokens.textPrimary, fontSize = 14.sp)
    }
}

/** 搜索入口。F3：输入即过滤。按 Escape 先清空。 */
@Composable
private fun SearchField(
    query: String,
    placeholder: String,
    onQueryChange: (String) -> Unit,
    enabled: Boolean,
) {
    Box(
        modifier = Modifier
            .height(Tokens.tabHeight.dp)
            .width(170.dp)
            .clip(RoundedCornerShape(Tokens.controlRadius.dp))
            .background(if (enabled) Tokens.controlFill else Color(0x0F000000))
            .border(1.dp, Tokens.divider, RoundedCornerShape(Tokens.controlRadius.dp)),
        contentAlignment = Alignment.CenterStart,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(8.dp))
            Text("⌕", color = Tokens.textSecondary, fontSize = 13.sp)
            Spacer(Modifier.width(5.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) {
                    Text(placeholder, color = Tokens.textSecondary, fontSize = 12.sp)
                }
                if (enabled) {
                    BasicTextField(
                        value = query,
                        onValueChange = onQueryChange,
                        singleLine = true,
                        textStyle = TextStyle(color = Tokens.textPrimary, fontSize = 12.sp),
                        cursorBrush = SolidColor(Tokens.actionFill),
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else if (query.isNotEmpty()) {
                    Text(query, color = Tokens.textPrimary, fontSize = 12.sp)
                }
            }
            Spacer(Modifier.width(8.dp))
        }
    }
}

/** 当前页的动作。右端。 */
@Composable
private fun PageAction(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .height(Tokens.tabHeight.dp)
            .clip(RoundedCornerShape(Tokens.controlRadius.dp))
            .background(Color(0x14000000))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Tokens.textPrimary, fontSize = 12.sp)
    }
}

/** 一条页签。选中态由滑块画，页签自己只放字。编辑模式里可拖动排序。 */
@Composable
private fun Tab(
    pane: Pane,
    index: Int,
    selected: Boolean,
    editing: Boolean,
    onSelect: () -> Unit,
    onReorder: (from: Int, to: Int) -> Unit,
    onMeasured: (Float) -> Unit,
) {
    val density = LocalDensity.current
    // 拖动累计的横向位移。跨过一条页签的宽度就换一次位置。
    val dragged = remember(pane.id) { FloatArray(1) }

    Box(
        modifier = Modifier
            .onGloballyPositioned { onMeasured(it.positionInParent().x) }
            .height(Tokens.tabHeight.dp)
            .clip(RoundedCornerShape(Tokens.pillRadius.dp))
            .clickable(enabled = !editing, onClick = onSelect)
            .then(
                if (editing) {
                    Modifier.pointerInput(pane.id) {
                        detectDragGestures(
                            onDragEnd = { dragged[0] = 0f },
                            onDragCancel = { dragged[0] = 0f },
                        ) { _, delta ->
                            dragged[0] += delta.x
                            val step = with(density) { tabStepPx() }
                            val moves = (dragged[0] / step).toInt()
                            if (moves != 0) {
                                onReorder(index, index + moves)
                                dragged[0] -= moves * step
                            }
                        }
                    }
                } else {
                    Modifier
                },
            )
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            if (editing) {
                Text("⣿", color = Tokens.textSecondary, fontSize = 11.sp)
            }
            Text(pane.displayIcon, color = if (selected) Tokens.textOnAccent else Tokens.textSecondary, fontSize = 11.sp)
            Text(
                pane.displayTitle,
                color = if (selected) Tokens.textOnAccent else Tokens.textPrimary,
                fontSize = 12.sp,
                fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
            )
        }
    }
}

/** 一条页签的宽度估值。拖动换位时用它算跨过了几条。 */
private fun tabStepPx(): Float = 84f

/**
 * 面板的展开进度。
 *
 * 展开 250 毫秒弹性曲线，收起 190 毫秒缓出曲线。见需求文档第 6 节。
 * 减弱动态效果打开时 120 毫秒，而且只用透明度。
 */
@Composable
internal fun rememberCurtainProgress(open: Boolean, reducedMotion: Boolean): Float {
    val spec = when {
        reducedMotion -> tween<Float>(Tokens.REDUCED_MOTION_MS)
        open -> spring(dampingRatio = 0.78f, stiffness = 380f)
        else -> tween(Tokens.COLLAPSE_MS, easing = FastOutSlowInEasing)
    }
    val progress by animateFloatAsState(if (open) 1f else 0f, spec, label = "curtain")
    return progress
}

/** 面板内容区的内边距。 */
internal val contentPadding = Tokens.panelPadding.dp

/** 面板内容区的宽度。 */
internal val contentWidth = (Tokens.panelWidth - Tokens.panelPadding * 2).dp

/** 网格列的宽度。四列，间距 12 点。 */
internal val columnWidth = (contentWidth - Tokens.gridGap.dp * (Tokens.gridColumns - 1)) / Tokens.gridColumns

/** 网格行高。 */
internal val rowHeight = Tokens.gridRowHeight.dp

/** 组件卡片占的像素宽度。 */
internal fun cardWidthPx(size: WidgetSize, density: Float): Float =
    ((columnWidth.value * size.columns) + (Tokens.gridGap * (size.columns - 1))) * density

/** 组件卡片占的像素高度。 */
internal fun cardHeightPx(size: WidgetSize, density: Float): Float =
    ((rowHeight.value * size.rows) + (Tokens.gridGap * (size.rows - 1))) * density

/** 一列的像素宽度。拖动吸附时按它算落在哪一列。 */
internal fun columnStepPx(density: Float): Float = (columnWidth.value + Tokens.gridGap) * density

/** 一行的像素高度。 */
internal fun rowStepPx(density: Float): Float = (rowHeight.value + Tokens.gridGap) * density

/** 面板内容区左上角的像素坐标。 */
internal fun contentOriginPx(density: Float): Float = Tokens.panelPadding * density

/** 面板在页面上的宽度。 */
internal val panelWidth = Tokens.panelWidth.dp
