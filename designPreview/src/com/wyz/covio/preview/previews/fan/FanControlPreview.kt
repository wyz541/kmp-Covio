package com.wyz.covio.preview.previews.fan

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wyz.covio.preview.DeepLink
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * 风扇控制能力补齐交互预览。对应 #331。
 *
 * 地址栏锚点：
 * - `#331-auto`：自动曲线
 * - `#331-manual`：手动曲线
 * - `#331-battery`：电池曲线
 * - `#331-night`：夜间模式
 * - `#331-alerts`：高温和风扇故障
 * - `#331-sensors`：传感器搜索和选择
 * - `#331-maintenance`：趋势、诊断和 helper
 * - `#331-helper`：helper 缺失
 * - `#331-dark`：深色
 * - `#331-reduced`：减少动态效果
 *
 * 打样只使用假数据，不接生产模块。
 */
@Composable
internal fun FanControlPreview() {
    val state = remember { FanPreviewState(FanPreviewStart.fromHash()) }
    val palette = FanPalette.forMode(state.dark)
    val previewTextStyle = LocalTextStyle.current

    MaterialTheme(
        colorScheme = if (state.dark) {
            darkColorScheme(
                primary = palette.accent,
                background = palette.window,
                surface = palette.surface,
                onPrimary = Color.White,
                onBackground = palette.textPrimary,
                onSurface = palette.textPrimary,
            )
        } else {
            lightColorScheme(
                primary = palette.accent,
                background = palette.window,
                surface = palette.surface,
                onPrimary = Color.White,
                onBackground = palette.textPrimary,
                onSurface = palette.textPrimary,
            )
        },
    ) {
        CompositionLocalProvider(LocalTextStyle provides previewTextStyle) {
            Box(Modifier.fillMaxSize().background(palette.desktop)) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 24.dp, vertical = 18.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.Top,
                ) {
                    ScenarioRail(state = state, palette = palette)
                    FanPopoverPreview(state = state, palette = palette)
                }
            }
        }
    }
}

@Composable
private fun ScenarioRail(state: FanPreviewState, palette: FanPalette) {
    Column(
        modifier = Modifier
            .width(238.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(palette.surface)
            .border(1.dp, palette.divider, RoundedCornerShape(18.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("评审状态", color = palette.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Text("点击切换完整主路径。截图使用同一地址栏锚点。", color = palette.textSecondary, fontSize = 10.sp)
        DividerLine(palette)
        FanScenario.entries.forEach { scenario ->
            val selected = state.scenario == scenario
            Surface(
                onClick = { state.applyScenario(scenario) },
                shape = RoundedCornerShape(9.dp),
                color = if (selected) palette.accent else palette.controlFill,
                contentColor = if (selected) Color.White else palette.textPrimary,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(scenario.label, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                    Spacer(Modifier.weight(1f))
                    Text(scenario.anchor, color = if (selected) Color.White.copy(alpha = 0.76f) else palette.textSecondary, fontSize = 8.sp)
                }
            }
        }
        DividerLine(palette)
        Text("固定宽度 420 点，内容滚动，不推动 Monitor 网格。", color = palette.textSecondary, fontSize = 9.sp)
        if (state.reducedMotion) {
            StatusBadge("减少动态：静态模式", palette.successText, palette.successBackground)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FanPopoverPreview(state: FanPreviewState, palette: FanPalette) {
    val scroll = rememberScrollState()
    var selectedPointIndex by remember { mutableStateOf(0) }
    val points = state.displayCurve()
    val maxPointIndex = (points.size - 1).coerceAtLeast(0)
    val curveRequester = remember { BringIntoViewRequester() }
    val manualRequester = remember { BringIntoViewRequester() }
    val nightRequester = remember { BringIntoViewRequester() }
    val alertRequester = remember { BringIntoViewRequester() }
    val sensorRequester = remember { BringIntoViewRequester() }
    val maintenanceRequester = remember { BringIntoViewRequester() }

    LaunchedEffect(state.curveSource, state.fanFilter) {
        selectedPointIndex = 0
    }
    LaunchedEffect(state.scenario) {
        delay(120)
        when (state.scenario) {
            FanScenario.AUTO, FanScenario.HELPER, FanScenario.DARK -> scroll.scrollTo(0)
            FanScenario.MANUAL -> manualRequester.bringIntoView()
            FanScenario.BATTERY -> curveRequester.bringIntoView()
            FanScenario.NIGHT, FanScenario.REDUCED -> nightRequester.bringIntoView()
            FanScenario.ALERTS -> alertRequester.bringIntoView()
            FanScenario.SENSORS -> sensorRequester.bringIntoView()
            FanScenario.MAINTENANCE -> maintenanceRequester.bringIntoView()
        }
    }
    LaunchedEffect(points.size) {
        selectedPointIndex = selectedPointIndex.coerceIn(0, maxPointIndex)
    }

    Column(
        modifier = Modifier
            .width(420.dp)
            .height(760.dp)
            .shadow(18.dp, RoundedCornerShape(24.dp))
            .clip(RoundedCornerShape(24.dp))
            .background(palette.surface)
            .border(1.dp, palette.divider.copy(alpha = 0.7f), RoundedCornerShape(24.dp)),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scroll)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(11.dp),
        ) {
            FanHeader(state, palette)
            DividerLine(palette)

            if (state.helperMissing) {
                HelperCallout(state, palette)
            }
            SafetyCallout(state, palette)

            EnableRow(state, palette)
            SegmentedRow(
                options = FanMode.entries,
                selected = state.mode,
                label = { it.label },
                enabled = state.enabled && !state.helperMissing,
                palette = palette,
                onSelect = { state.mode = it },
            )

            when (state.mode) {
                FanMode.AUTO -> Box(Modifier.bringIntoViewRequester(curveRequester)) {
                    AutomaticControls(
                        state = state,
                        palette = palette,
                        points = points,
                        selectedPointIndex = selectedPointIndex,
                        onSelectPoint = { selectedPointIndex = it },
                        onPointsChange = { state.updateCurve(it) },
                        onMovePoint = { index, point ->
                            selectedPointIndex = index
                            state.movePoint(index, point)
                        },
                    )
                }
                FanMode.MANUAL -> Box(Modifier.bringIntoViewRequester(manualRequester)) {
                    ManualControls(state, palette)
                }
            }

            FanReadings(state, palette)
            DividerLine(palette)
            Box(Modifier.bringIntoViewRequester(nightRequester)) { NightSection(state, palette) }
            Box(Modifier.bringIntoViewRequester(alertRequester)) { AlertSection(state, palette) }
            Box(Modifier.bringIntoViewRequester(sensorRequester)) { SensorSection(state, palette) }
            Box(Modifier.bringIntoViewRequester(maintenanceRequester)) { MaintenanceSection(state, palette) }

            state.actionMessage?.let { message ->
                InfoBanner(message, palette)
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (state.enabled) "Covio 退出或租约过期后恢复系统控制。" else "风扇控制已恢复系统模式。",
                    color = palette.textSecondary,
                    fontSize = 9.sp,
                    modifier = Modifier.weight(1f),
                )
                MiniAction("恢复系统控制", palette, danger = true) {
                    state.enabled = false
                    state.actionMessage = "已恢复系统控制"
                }
            }
        }
    }
}

@Composable
private fun FanHeader(state: FanPreviewState, palette: FanPalette) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("65.9 °C", color = palette.textPrimary, fontSize = 34.sp, fontWeight = FontWeight.SemiBold)
            Text(
                "控制温度 · ${state.selectedSensors.size} 个传感器取最大",
                color = palette.textSecondary,
                fontSize = 10.sp,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                StatusBadge(
                    text = if (state.curveSource == CurveSource.AC) "适配器曲线" else "电池曲线",
                    color = if (state.curveSource == CurveSource.AC) palette.textSecondary else palette.warningText,
                    background = if (state.curveSource == CurveSource.AC) palette.controlFill else palette.warningBackground,
                )
                if (state.nightEnabled) {
                    StatusBadge("夜间生效", palette.infoText, palette.infoBackground)
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(
                    Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(
                            when {
                                state.helperMissing -> palette.errorText
                                state.enabled -> palette.successFill
                                else -> palette.textSecondary
                            },
                        ),
                )
                Text(
                    text = when {
                        state.helperMissing -> "Helper 不可用"
                        state.enabled -> "Covio 已接管"
                        else -> "系统控制"
                    },
                    color = palette.textSecondary,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Text(
                text = if (state.mode == FanMode.AUTO) "自动曲线" else "手动转速",
                color = palette.textSecondary,
                fontSize = 9.sp,
            )
        }
    }
}

@Composable
private fun HelperCallout(state: FanPreviewState, palette: FanPalette) {
    Surface(
        color = palette.errorBackground,
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Helper 版本过旧", color = palette.errorText, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
                Text("读数保留，风扇写入暂停。重装后恢复控制。", color = palette.textSecondary, fontSize = 9.sp)
            }
            MiniAction("重装", palette) { state.actionMessage = "已请求重装 helper" }
        }
    }
}

@Composable
private fun SafetyCallout(state: FanPreviewState, palette: FanPalette) {
    Surface(
        color = palette.warningBackground.copy(alpha = 0.62f),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("写入风扇转速会改变硬件行为", color = palette.warningText, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
            Text("目标转速限制在硬件安全区间。连续 3 次写入失败后恢复系统控制。", color = palette.textSecondary, fontSize = 9.sp)
            if (state.actionMessage != null) {
                Text(state.actionMessage.orEmpty(), color = palette.successText, fontSize = 9.sp)
            }
        }
    }
}

@Composable
private fun EnableRow(state: FanPreviewState, palette: FanPalette) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("启用风扇控制", color = palette.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text("20 秒租约 · 正常退出会恢复系统控制", color = palette.textSecondary, fontSize = 9.sp)
        }
        Switch(
            checked = state.enabled,
            onCheckedChange = {
                state.enabled = it
                state.actionMessage = if (it) "已启用风扇控制" else "已恢复系统控制"
            },
            enabled = !state.helperMissing,
            colors = switchColors(palette),
        )
    }
}

@Composable
private fun AutomaticControls(
    state: FanPreviewState,
    palette: FanPalette,
    points: List<FanCurvePoint>,
    selectedPointIndex: Int,
    onSelectPoint: (Int) -> Unit,
    onPointsChange: (List<FanCurvePoint>) -> Unit,
    onMovePoint: (Int, FanCurvePoint) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        PresetChip("安静", palette) { state.applyPreset(80f, 100f) }
        PresetChip("均衡", palette) { state.applyPreset(70f, 95f) }
        PresetChip("强力", palette) { state.applyPreset(55f, 85f) }
        Spacer(Modifier.weight(1f))
        if (state.actionMessage != null) {
            Text("已应用", color = palette.successText, fontSize = 8.sp)
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("温控曲线", color = palette.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text("拖动控制点", color = palette.textSecondary, fontSize = 9.sp)
        }

        SegmentedRow(
            options = CurveSource.entries,
            selected = state.curveSource,
            label = { it.label },
            enabled = true,
            palette = palette,
            onSelect = { state.curveSource = it },
        )
        SegmentedRow(
            options = FanFilter.entries,
            selected = state.fanFilter,
            label = { it.label },
            enabled = true,
            palette = palette,
            onSelect = { state.fanFilter = it },
        )

        if (state.curveSource == CurveSource.BATTERY && !state.hasBatteryCurve()) {
            Surface(
                color = palette.warningBackground.copy(alpha = 0.62f),
                shape = RoundedCornerShape(9.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier.padding(9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("电池曲线未设置，当前沿用插电曲线。", color = palette.warningText, fontSize = 9.sp, modifier = Modifier.weight(1f))
                    MiniAction("复制插电曲线", palette) { state.copyBatteryFromAC() }
                }
            }
        }

        FanCurveChart(
            points = points,
            minimumRPM = state.selectedMinimumRPM(),
            maximumRPM = state.selectedMaximumRPM(),
            palette = palette,
            onSelectPoint = onSelectPoint,
            onMovePoint = onMovePoint,
            onCommit = { onPointsChange(it) },
        )

        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            points.indices.forEach { index ->
                val selected = index == selectedPointIndex
                Surface(
                    onClick = { onSelectPoint(index) },
                    color = if (selected) palette.accent else palette.controlFill,
                    contentColor = if (selected) Color.White else palette.textPrimary,
                    shape = RoundedCornerShape(999.dp),
                ) {
                    Text(
                        "${index + 1}",
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                        fontSize = 8.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            MiniAction("添加", palette, enabled = points.size < 6) {
                state.addPoint()
                onSelectPoint((state.displayCurve().size - 1).coerceAtLeast(0))
            }
            MiniAction("删除", palette, enabled = points.size > 2) {
                state.removePoint(selectedPointIndex)
                onSelectPoint((selectedPointIndex - 1).coerceAtLeast(0))
            }
        }

        if (points.isNotEmpty()) {
            CurvePointEditor(
                point = points[selectedPointIndex.coerceIn(points.indices)],
                index = selectedPointIndex.coerceIn(points.indices),
                minimumRPM = state.selectedMinimumRPM(),
                maximumRPM = state.selectedMaximumRPM(),
                palette = palette,
                onChange = { onChange ->
                    val updated = state.displayCurve().toMutableList()
                    val safeIndex = selectedPointIndex.coerceIn(updated.indices)
                    updated[safeIndex] = onChange
                    onPointsChange(updated.sortedBy { it.temperature })
                },
            )
        }

        if (state.curveSource == CurveSource.BATTERY) {
            MiniAction("清空当前电池曲线", palette) { state.clearBatteryCurve() }
        }
    }
}

@Composable
private fun CurvePointEditor(
    point: FanCurvePoint,
    index: Int,
    minimumRPM: Float,
    maximumRPM: Float,
    palette: FanPalette,
    onChange: (FanCurvePoint) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("控制点 ${index + 1}", color = palette.textSecondary, fontSize = 9.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.weight(1f))
            Text("${point.temperature.roundToInt()} °C", color = palette.textPrimary, fontSize = 9.sp)
            Text("  ${point.rpm.roundToInt()} RPM", color = palette.textSecondary, fontSize = 9.sp)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("温度", color = palette.textSecondary, fontSize = 8.sp, modifier = Modifier.width(30.dp))
            Slider(
                value = point.temperature,
                onValueChange = { onChange(point.copy(temperature = it.roundToInt().toFloat())) },
                valueRange = 40f..105f,
                colors = sliderColors(palette),
                modifier = Modifier.weight(1f),
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("转速", color = palette.textSecondary, fontSize = 8.sp, modifier = Modifier.width(30.dp))
            Slider(
                value = point.rpm.coerceIn(minimumRPM, maximumRPM),
                onValueChange = { onChange(point.copy(rpm = ((it / 50f).roundToInt() * 50).toFloat())) },
                valueRange = minimumRPM..maximumRPM,
                colors = sliderColors(palette),
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun FanCurveChart(
    points: List<FanCurvePoint>,
    minimumRPM: Float,
    maximumRPM: Float,
    palette: FanPalette,
    onSelectPoint: (Int) -> Unit,
    onMovePoint: (Int, FanCurvePoint) -> Unit,
    onCommit: (List<FanCurvePoint>) -> Unit,
) {
    val latestPoints by rememberUpdatedState(points)
    val latestMove by rememberUpdatedState(onMovePoint)
    val latestSelect by rememberUpdatedState(onSelectPoint)
    val latestCommit by rememberUpdatedState(onCommit)
    var draggingIndex by remember { mutableStateOf<Int?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(144.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(palette.controlFill)
                .border(1.dp, palette.divider.copy(alpha = 0.75f), RoundedCornerShape(10.dp)),
        ) {
            Canvas(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectDragGestures(
                            onDragStart = { start ->
                                val found = nearestPointIndex(
                                    start = start,
                                    size = size,
                                    points = latestPoints,
                                    rpmRange = minimumRPM..maximumRPM,
                                )
                                draggingIndex = found
                                found?.let(latestSelect)
                            },
                            onDragEnd = {
                                draggingIndex = null
                                latestCommit(latestPoints.sortedBy { it.temperature })
                            },
                            onDragCancel = { draggingIndex = null },
                            onDrag = { change, _ ->
                                val index = draggingIndex ?: return@detectDragGestures
                                if (index !in latestPoints.indices) return@detectDragGestures
                                change.consume()
                                val point = pointAt(
                                    offset = change.position,
                                    size = size,
                                    rpmRange = minimumRPM..maximumRPM,
                                )
                                latestMove(index, point)
                            },
                        )
                    },
            ) {
                val left = 12.dp.toPx()
                val right = size.width - 12.dp.toPx()
                val top = 10.dp.toPx()
                val bottom = size.height - 10.dp.toPx()
                val width = (right - left).coerceAtLeast(1f)
                val height = (bottom - top).coerceAtLeast(1f)

                for (temperature in 40..100 step 10) {
                    val x = left + (temperature - 40f) / 65f * width
                    drawLine(
                        color = palette.divider.copy(alpha = 0.38f),
                        start = Offset(x, top),
                        end = Offset(x, bottom),
                        strokeWidth = 1f,
                    )
                }
                for (fraction in listOf(0f, 0.5f, 1f)) {
                    val y = bottom - fraction * height
                    drawLine(
                        color = palette.divider.copy(alpha = 0.38f),
                        start = Offset(left, y),
                        end = Offset(right, y),
                        strokeWidth = 1f,
                    )
                }

                val currentX = left + (65.9f - 40f) / 65f * width
                drawLine(
                    color = palette.warningFill.copy(alpha = 0.72f),
                    start = Offset(currentX, top),
                    end = Offset(currentX, bottom),
                    strokeWidth = 1.2f,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 5f)),
                )

                val sorted = latestPoints.sortedBy { it.temperature }
                for (index in 1 until sorted.size) {
                    val from = sorted[index - 1]
                    val to = sorted[index]
                    drawLine(
                        color = palette.accent,
                        start = Offset(
                            x = left + (from.temperature - 40f) / 65f * width,
                            y = bottom - (from.rpm - minimumRPM) / (maximumRPM - minimumRPM).coerceAtLeast(1f) * height,
                        ),
                        end = Offset(
                            x = left + (to.temperature - 40f) / 65f * width,
                            y = bottom - (to.rpm - minimumRPM) / (maximumRPM - minimumRPM).coerceAtLeast(1f) * height,
                        ),
                        strokeWidth = 2.4f,
                        cap = StrokeCap.Round,
                    )
                }

                sorted.forEachIndexed { index, point ->
                    val center = Offset(
                        x = left + (point.temperature - 40f) / 65f * width,
                        y = bottom - (point.rpm - minimumRPM) / (maximumRPM - minimumRPM).coerceAtLeast(1f) * height,
                    )
                    drawCircle(
                        color = palette.controlFill,
                        radius = 7f,
                        center = center,
                    )
                    drawCircle(
                        color = if (draggingIndex == index) palette.warningFill else palette.accent,
                        radius = 6f,
                        center = center,
                        style = Stroke(width = 2.4f),
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Text("40 °C", color = palette.textSecondary, fontSize = 8.sp)
            Spacer(Modifier.weight(1f))
            Text("${minimumRPM.roundToInt()}–${maximumRPM.roundToInt()} RPM", color = palette.textSecondary, fontSize = 8.sp)
            Spacer(Modifier.weight(1f))
            Text("105 °C", color = palette.textSecondary, fontSize = 8.sp)
        }
    }
}

private fun nearestPointIndex(
    start: Offset,
    size: IntSize,
    points: List<FanCurvePoint>,
    rpmRange: ClosedFloatingPointRange<Float>,
): Int? {
    if (points.isEmpty() || size.width <= 0 || size.height <= 0) return null
    val left = 12f
    val right = (size.width - 12f).coerceAtLeast(left + 1f)
    val top = 10f
    val bottom = (size.height - 10f).coerceAtLeast(top + 1f)
    val width = right - left
    val height = bottom - top
    return points.indices.minByOrNull { index ->
        val point = points[index]
        val center = Offset(
            x = left + (point.temperature - 40f) / 65f * width,
            y = bottom - (point.rpm - rpmRange.start) / (rpmRange.endInclusive - rpmRange.start).coerceAtLeast(1f) * height,
        )
        hypot((center.x - start.x).toDouble(), (center.y - start.y).toDouble())
    }?.takeIf { index ->
        val point = points[index]
        val center = Offset(
            x = left + (point.temperature - 40f) / 65f * width,
            y = bottom - (point.rpm - rpmRange.start) / (rpmRange.endInclusive - rpmRange.start).coerceAtLeast(1f) * height,
        )
        hypot((center.x - start.x).toDouble(), (center.y - start.y).toDouble()) <= 28.0
    }
}

private fun pointAt(
    offset: Offset,
    size: IntSize,
    rpmRange: ClosedFloatingPointRange<Float>,
): FanCurvePoint {
    val left = 12f
    val right = (size.width - 12f).coerceAtLeast(left + 1f)
    val top = 10f
    val bottom = (size.height - 10f).coerceAtLeast(top + 1f)
    val width = right - left
    val height = bottom - top
    val temperature = (40f + ((offset.x - left) / width).coerceIn(0f, 1f) * 65f).roundToInt().toFloat()
    val rpm = (
        rpmRange.start +
            ((bottom - offset.y) / height).coerceIn(0f, 1f) * (rpmRange.endInclusive - rpmRange.start)
        ).roundToInt().toFloat()
    return FanCurvePoint(temperature, ((rpm / 50f).roundToInt() * 50).toFloat())
}

@Composable
private fun ManualControls(state: FanPreviewState, palette: FanPalette) {
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("手动转速", color = palette.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            MiniAction("全部全速", palette) {
                state.manualRPM[0] = 5800f
                state.manualRPM[1] = 5800f
                state.actionMessage = "全部风扇已设为全速"
            }
        }
        state.fans.forEach { fan ->
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("风扇 ${fan.index + 1}", color = palette.textPrimary, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                    Spacer(Modifier.weight(1f))
                    Text("${(state.manualRPM[fan.index] ?: fan.minimumRPM).roundToInt()} RPM", color = palette.textSecondary, fontSize = 9.sp)
                    Spacer(Modifier.width(6.dp))
                    MiniAction("全速", palette) {
                        state.manualRPM[fan.index] = fan.maximumRPM
                        state.actionMessage = "风扇 ${fan.index + 1} 已设为全速"
                    }
                }
                Slider(
                    value = (state.manualRPM[fan.index] ?: fan.minimumRPM).coerceIn(fan.minimumRPM, fan.maximumRPM),
                    onValueChange = { state.manualRPM[fan.index] = ((it / 50f).roundToInt() * 50).toFloat() },
                    valueRange = fan.minimumRPM..fan.maximumRPM,
                    colors = sliderColors(palette),
                )
            }
        }
        Text("手动目标受每个风扇的硬件最小和最大转速限制。", color = palette.textSecondary, fontSize = 9.sp)
    }
}

@Composable
private fun FanReadings(state: FanPreviewState, palette: FanPalette) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("风扇", color = palette.textPrimary, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text("实际 / 目标", color = palette.textSecondary, fontSize = 8.sp)
        }
        state.fans.forEach { fan ->
            val target = state.targetFor(fan).roundToInt()
            val actual = if (state.fanFault && fan.index == 1) 0 else (target + fan.actualOffset).coerceAtMost(fan.maximumRPM.roundToInt())
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (state.fanFault && fan.index == 1) palette.errorBackground else palette.controlFill)
                    .padding(horizontal = 9.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(if (state.fanFault && fan.index == 1) palette.errorText else palette.fanAccent))
                Spacer(Modifier.width(7.dp))
                Text("风扇 ${fan.index + 1}", color = palette.textPrimary, fontSize = 10.sp)
                Spacer(Modifier.weight(1f))
                Text(if (actual == 0) "0 RPM" else "$actual RPM", color = if (state.fanFault && fan.index == 1) palette.errorText else palette.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                Text("  目标 $target", color = palette.textSecondary, fontSize = 8.sp)
            }
        }
    }
}

@Composable
private fun NightSection(state: FanPreviewState, palette: FanPalette) {
    DisclosureSection(
        title = "定时夜间模式",
        subtitle = if (state.nightEnabled) "23:00–07:00 · ${state.nightPreset.label}" else "未启用",
        expanded = state.nightExpanded,
        palette = palette,
        onToggle = { state.nightExpanded = !state.nightExpanded },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("夜间使用预设", color = palette.textPrimary, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                Text("时间窗支持跨午夜。", color = palette.textSecondary, fontSize = 8.sp)
            }
            Switch(
                checked = state.nightEnabled,
                onCheckedChange = { state.nightEnabled = it },
                colors = switchColors(palette),
            )
        }
        TimeSlider("开始", state.nightStart, palette) { state.nightStart = it }
        TimeSlider("结束", state.nightEnd, palette) { state.nightEnd = it }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            NightPreset.entries.forEach { preset ->
                PresetChip(preset.label, palette, selected = state.nightPreset == preset) {
                    state.nightPreset = preset
                }
            }
        }
        StatusBadge(
            if (state.nightEnabled) "生效中：夜间预设接管曲线" else "未启用",
            if (state.nightEnabled) palette.infoText else palette.textSecondary,
            if (state.nightEnabled) palette.infoBackground else palette.controlFill,
        )
    }
}

@Composable
private fun TimeSlider(label: String, minutes: Int, palette: FanPalette, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, color = palette.textSecondary, fontSize = 9.sp, modifier = Modifier.width(28.dp))
        Slider(
            value = minutes.toFloat(),
            onValueChange = { onChange(((it / 30f).roundToInt() * 30).coerceIn(0, 24 * 60 - 30)) },
            valueRange = 0f..(24 * 60 - 30).toFloat(),
            colors = sliderColors(palette),
            modifier = Modifier.weight(1f),
        )
        Text(minuteText(minutes), color = palette.textPrimary, fontSize = 9.sp, modifier = Modifier.width(38.dp), textAlign = TextAlign.End)
    }
}

@Composable
private fun AlertSection(state: FanPreviewState, palette: FanPalette) {
    DisclosureSection(
        title = "通知",
        subtitle = if (state.highTempEnabled || state.fanFaultEnabled) "高温与风扇故障已启用" else "未启用",
        expanded = state.alertsExpanded,
        palette = palette,
        onToggle = { state.alertsExpanded = !state.alertsExpanded },
    ) {
        SettingSwitchRow(
            label = "高温通知",
            detail = "控制温度超过 ${state.alertThreshold.roundToInt()} °C",
            checked = state.highTempEnabled,
            palette = palette,
            onChange = { state.highTempEnabled = it },
        )
        if (state.highTempEnabled) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("阈值", color = palette.textSecondary, fontSize = 9.sp)
                Slider(
                    value = state.alertThreshold,
                    onValueChange = { state.alertThreshold = it.roundToInt().toFloat() },
                    valueRange = 60f..105f,
                    colors = sliderColors(palette),
                    modifier = Modifier.weight(1f),
                )
                Text("${state.alertThreshold.roundToInt()} °C", color = palette.textPrimary, fontSize = 9.sp)
            }
            StatusBadge(
                if (65.9f >= state.alertThreshold) "当前温度已触发高温状态" else "当前温度低于阈值",
                if (65.9f >= state.alertThreshold) palette.warningText else palette.successText,
                if (65.9f >= state.alertThreshold) palette.warningBackground else palette.successBackground,
            )
        }
        SettingSwitchRow(
            label = "风扇故障通知",
            detail = "目标大于 0 且转速为 0 时提醒",
            checked = state.fanFaultEnabled,
            palette = palette,
            onChange = { state.fanFaultEnabled = it },
        )
        if (state.fanFaultEnabled) {
            Surface(
                color = if (state.fanFault) palette.errorBackground else palette.successBackground,
                shape = RoundedCornerShape(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = if (state.fanFault) "风扇 2 实际转速为 0，已进入故障通知状态。" else "两个风扇转速正常。",
                    color = if (state.fanFault) palette.errorText else palette.successText,
                    fontSize = 9.sp,
                    modifier = Modifier.padding(horizontal = 9.dp, vertical = 6.dp),
                )
            }
        }
    }
}

@Composable
private fun SensorSection(state: FanPreviewState, palette: FanPalette) {
    DisclosureSection(
        title = "控制传感器",
        subtitle = "${state.selectedSensors.size} 个参与控制 · 取最大值",
        expanded = state.sensorsExpanded,
        palette = palette,
        onToggle = { state.sensorsExpanded = !state.sensorsExpanded },
    ) {
        OutlinedTextField(
            value = state.sensorQuery,
            onValueChange = { state.sensorQuery = it },
            label = { Text("搜索名称或键名", style = LocalTextStyle.current.copy(fontSize = 9.sp)) },
            singleLine = true,
            textStyle = LocalTextStyle.current.copy(fontSize = 9.sp),
            modifier = Modifier.fillMaxWidth(),
        )
        val filtered = state.sensors.filter {
            state.sensorQuery.isBlank() ||
                it.name.contains(state.sensorQuery, ignoreCase = true) ||
                it.key.contains(state.sensorQuery, ignoreCase = true)
        }
        if (filtered.isEmpty()) {
            Text("没有匹配的传感器", color = palette.textSecondary, fontSize = 9.sp)
        } else {
            filtered.take(10).forEach { sensor ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(7.dp))
                        .background(palette.controlFill)
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(
                        checked = state.selectedSensors.contains(sensor.key),
                        onCheckedChange = { checked -> state.toggleSensor(sensor.key, checked) },
                        colors = CheckboxDefaults.colors(
                            checkedColor = palette.accent,
                            uncheckedColor = palette.textSecondary,
                            checkmarkColor = Color.White,
                        ),
                    )
                    Text(sensor.name, color = palette.textPrimary, fontSize = 9.sp, modifier = Modifier.weight(1f))
                    Text(sensor.key, color = palette.textSecondary, fontSize = 8.sp)
                    Text("  ${sensor.temperature.roundToInt()} °C", color = palette.textSecondary, fontSize = 8.sp)
                }
            }
        }
        Text("完整名称库包含 64 个显式键名，未知键保留原始键名。", color = palette.textSecondary, fontSize = 8.sp)
    }
}

@Composable
private fun MaintenanceSection(state: FanPreviewState, palette: FanPalette) {
    DisclosureSection(
        title = "维护与导航",
        subtitle = "趋势、诊断、helper",
        expanded = state.maintenanceExpanded,
        palette = palette,
        onToggle = { state.maintenanceExpanded = !state.maintenanceExpanded },
    ) {
        SettingSwitchRow(
            label = "登录时启动",
            detail = "使用 Covio 已有设置",
            checked = state.launchAtLogin,
            palette = palette,
            onChange = { state.launchAtLogin = it },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MiniAction("趋势", palette) { state.actionMessage = "已打开近 15 分钟风扇趋势" }
            MiniAction("诊断", palette) { state.actionMessage = "诊断信息已准备导出" }
            MiniAction("修复 Helper", palette) { state.actionMessage = "已打开 helper 修复流程" }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (state.uninstallArmed) {
                Text("卸载 helper 会先恢复系统控制。", color = palette.errorText, fontSize = 8.sp, modifier = Modifier.weight(1f))
                MiniAction("确认卸载", palette, danger = true) {
                    state.uninstallArmed = false
                    state.actionMessage = "已恢复系统控制并请求卸载 helper"
                }
            } else {
                MiniAction("卸载 Helper", palette, danger = true) { state.uninstallArmed = true }
            }
        }
    }
}

@Composable
private fun DisclosureSection(
    title: String,
    subtitle: String,
    expanded: Boolean,
    palette: FanPalette,
    onToggle: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        color = palette.controlFill.copy(alpha = 0.72f),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            Surface(
                onClick = onToggle,
                color = Color.Transparent,
                contentColor = palette.textPrimary,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(title, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
                        Text(subtitle, color = palette.textSecondary, fontSize = 8.sp)
                    }
                    Text(if (expanded) "收起" else "展开", color = palette.accent, fontSize = 8.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            if (expanded) {
                Column(
                    modifier = Modifier.padding(horizontal = 10.dp).padding(bottom = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    content()
                }
            }
        }
    }
}

@Composable
private fun SettingSwitchRow(
    label: String,
    detail: String,
    checked: Boolean,
    palette: FanPalette,
    onChange: (Boolean) -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, color = palette.textPrimary, fontSize = 9.sp, fontWeight = FontWeight.Medium)
            Text(detail, color = palette.textSecondary, fontSize = 8.sp)
        }
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = switchColors(palette),
        )
    }
}

@Composable
private fun <T> SegmentedRow(
    options: List<T>,
    selected: T,
    label: (T) -> String,
    enabled: Boolean,
    palette: FanPalette,
    onSelect: (T) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(palette.controlFill)
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        options.forEach { option ->
            val isSelected = option == selected
            Surface(
                onClick = { onSelect(option) },
                enabled = enabled,
                shape = RoundedCornerShape(8.dp),
                color = if (isSelected) palette.accent else Color.Transparent,
                contentColor = if (isSelected) Color.White else palette.textPrimary,
                modifier = Modifier.weight(1f),
            ) {
                Text(
                    label(option),
                    modifier = Modifier.padding(vertical = 7.dp),
                    textAlign = TextAlign.Center,
                    fontSize = 9.sp,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                )
            }
        }
    }
}

@Composable
private fun PresetChip(
    label: String,
    palette: FanPalette,
    selected: Boolean = false,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(999.dp),
        color = if (selected) palette.accent else palette.controlFill,
        contentColor = if (selected) Color.White else palette.textPrimary,
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp),
            fontSize = 9.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun MiniAction(
    label: String,
    palette: FanPalette,
    enabled: Boolean = true,
    danger: Boolean = false,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(7.dp),
        color = when {
            !enabled -> palette.controlFill.copy(alpha = 0.4f)
            danger -> palette.errorBackground
            else -> palette.controlFill
        },
        contentColor = when {
            !enabled -> palette.textSecondary.copy(alpha = 0.45f)
            danger -> palette.errorText
            else -> palette.textPrimary
        },
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 4.dp),
            fontSize = 8.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun StatusBadge(text: String, color: Color, background: Color) {
    Surface(color = background, shape = RoundedCornerShape(999.dp)) {
        Text(
            text,
            color = color,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp),
            fontSize = 8.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun InfoBanner(text: String, palette: FanPalette) {
    Surface(color = palette.infoBackground, shape = RoundedCornerShape(9.dp), modifier = Modifier.fillMaxWidth()) {
        Text(text, color = palette.infoText, fontSize = 9.sp, modifier = Modifier.padding(9.dp))
    }
}

@Composable
private fun DividerLine(palette: FanPalette) {
    Box(Modifier.fillMaxWidth().height(1.dp).background(palette.divider.copy(alpha = 0.7f)))
}

@Composable
private fun sliderColors(palette: FanPalette) = SliderDefaults.colors(
    thumbColor = palette.accent,
    activeTrackColor = palette.accent,
    inactiveTrackColor = palette.divider,
)

@Composable
private fun switchColors(palette: FanPalette) = SwitchDefaults.colors(
    checkedThumbColor = Color.White,
    checkedTrackColor = palette.accent,
    uncheckedThumbColor = Color.White,
    uncheckedTrackColor = palette.divider,
)

private fun minuteText(value: Int): String {
    val wrapped = value.coerceIn(0, 24 * 60 - 1)
    return "${(wrapped / 60).toString().padStart(2, '0')}:${(wrapped % 60).toString().padStart(2, '0')}"
}

private data class FanCurvePoint(val temperature: Float, val rpm: Float)

private data class PreviewFan(
    val index: Int,
    val minimumRPM: Float,
    val maximumRPM: Float,
    val actualOffset: Int,
)

private enum class FanMode(val label: String) {
    AUTO("自动曲线"),
    MANUAL("手动转速"),
}

private enum class CurveSource(val label: String) {
    AC("插电曲线"),
    BATTERY("电池曲线"),
}

private enum class FanFilter(val label: String) {
    ALL("全部风扇"),
    FAN1("风扇 1"),
    FAN2("风扇 2"),
}

private enum class NightPreset(val label: String) {
    QUIET("安静"),
    BALANCED("均衡"),
    TURBO("强力"),
}

private enum class FanScenario(val label: String, val anchor: String) {
    AUTO("自动曲线", "auto"),
    MANUAL("手动与全速", "manual"),
    BATTERY("电池曲线", "battery"),
    NIGHT("夜间模式", "night"),
    ALERTS("高温与故障", "alerts"),
    SENSORS("传感器搜索", "sensors"),
    MAINTENANCE("维护入口", "maintenance"),
    HELPER("Helper 缺失", "helper"),
    DARK("深色外观", "dark"),
    REDUCED("减少动态", "reduced"),
}

private data class SensorPreview(val key: String, val name: String, val temperature: Float)

private data class FanPreviewStart(
    val scenario: FanScenario,
    val dark: Boolean,
    val mode: FanMode,
    val source: CurveSource,
    val nightEnabled: Boolean,
    val nightExpanded: Boolean,
    val alertsExpanded: Boolean,
    val sensorsExpanded: Boolean,
    val maintenanceExpanded: Boolean,
    val helperMissing: Boolean,
    val reducedMotion: Boolean,
    val highTempEnabled: Boolean,
    val fanFaultEnabled: Boolean,
    val fanFault: Boolean,
    val alertThreshold: Float,
) {
    companion object {
        fun fromHash(): FanPreviewStart = when (val anchor = DeepLink.anchor) {
            "", "auto" -> base(FanScenario.AUTO)
            "manual" -> base(FanScenario.MANUAL, mode = FanMode.MANUAL)
            "battery" -> base(FanScenario.BATTERY, source = CurveSource.BATTERY)
            "night" -> base(FanScenario.NIGHT, nightEnabled = true, nightExpanded = true)
            "alerts" -> base(
                FanScenario.ALERTS,
                alertsExpanded = true,
                highTempEnabled = true,
                fanFaultEnabled = true,
                fanFault = true,
                alertThreshold = 64f,
            )
            "sensors" -> base(FanScenario.SENSORS, sensorsExpanded = true)
            "maintenance" -> base(FanScenario.MAINTENANCE, maintenanceExpanded = true)
            "helper" -> base(FanScenario.HELPER, helperMissing = true)
            "dark" -> base(FanScenario.DARK, dark = true)
            "reduced" -> base(
                FanScenario.REDUCED,
                reducedMotion = true,
                nightExpanded = true,
            )
            else -> error("未知的锚点：$anchor")
        }

        private fun base(
            scenario: FanScenario,
            dark: Boolean = false,
            mode: FanMode = FanMode.AUTO,
            source: CurveSource = CurveSource.AC,
            nightEnabled: Boolean = false,
            nightExpanded: Boolean = false,
            alertsExpanded: Boolean = false,
            sensorsExpanded: Boolean = false,
            maintenanceExpanded: Boolean = false,
            helperMissing: Boolean = false,
            reducedMotion: Boolean = false,
            highTempEnabled: Boolean = false,
            fanFaultEnabled: Boolean = false,
            fanFault: Boolean = false,
            alertThreshold: Float = 90f,
        ) = FanPreviewStart(
            scenario = scenario,
            dark = dark,
            mode = mode,
            source = source,
            nightEnabled = nightEnabled,
            nightExpanded = nightExpanded,
            alertsExpanded = alertsExpanded,
            sensorsExpanded = sensorsExpanded,
            maintenanceExpanded = maintenanceExpanded,
            helperMissing = helperMissing,
            reducedMotion = reducedMotion,
            highTempEnabled = highTempEnabled,
            fanFaultEnabled = fanFaultEnabled,
            fanFault = fanFault,
            alertThreshold = alertThreshold,
        )
    }
}

private class FanPreviewState(start: FanPreviewStart) {
    var scenario by mutableStateOf(start.scenario)
    var dark by mutableStateOf(start.dark)
    var mode by mutableStateOf(start.mode)
    var curveSource by mutableStateOf(start.source)
    var fanFilter by mutableStateOf(FanFilter.ALL)
    var nightEnabled by mutableStateOf(start.nightEnabled)
    var nightExpanded by mutableStateOf(start.nightExpanded)
    var alertsExpanded by mutableStateOf(start.alertsExpanded)
    var sensorsExpanded by mutableStateOf(start.sensorsExpanded)
    var maintenanceExpanded by mutableStateOf(start.maintenanceExpanded)
    var helperMissing by mutableStateOf(start.helperMissing)
    var reducedMotion by mutableStateOf(start.reducedMotion)
    var highTempEnabled by mutableStateOf(start.highTempEnabled)
    var fanFaultEnabled by mutableStateOf(start.fanFaultEnabled)
    var fanFault by mutableStateOf(start.fanFault)
    var alertThreshold by mutableStateOf(start.alertThreshold)
    var enabled by mutableStateOf(!start.helperMissing)
    var actionMessage by mutableStateOf<String?>(null)
    var nightPreset by mutableStateOf(NightPreset.QUIET)
    var nightStart by mutableStateOf(23 * 60)
    var nightEnd by mutableStateOf(7 * 60)
    var launchAtLogin by mutableStateOf(true)
    var uninstallArmed by mutableStateOf(false)
    var sensorQuery by mutableStateOf("")

    val fans = listOf(
        PreviewFan(index = 0, minimumRPM = 1200f, maximumRPM = 5800f, actualOffset = 190),
        PreviewFan(index = 1, minimumRPM = 1200f, maximumRPM = 6200f, actualOffset = 240),
    )

    val manualRPM = mutableStateMapOf(0 to 2580f, 1 to 2710f)
    val acCurves = mutableStateMapOf(
        "0" to listOf(
            FanCurvePoint(45f, 1200f),
            FanCurvePoint(62f, 2200f),
            FanCurvePoint(78f, 3900f),
            FanCurvePoint(92f, 5800f),
        ),
        "1" to listOf(
            FanCurvePoint(45f, 1200f),
            FanCurvePoint(62f, 2400f),
            FanCurvePoint(78f, 4300f),
            FanCurvePoint(92f, 6200f),
        ),
    )
    val batteryCurves = mutableStateMapOf(
        "0" to listOf(
            FanCurvePoint(50f, 1200f),
            FanCurvePoint(70f, 2200f),
            FanCurvePoint(86f, 3900f),
            FanCurvePoint(100f, 5800f),
        ),
        "1" to listOf(
            FanCurvePoint(50f, 1200f),
            FanCurvePoint(70f, 2500f),
            FanCurvePoint(86f, 4300f),
            FanCurvePoint(100f, 6200f),
        ),
    )

    val selectedSensors = mutableStateListOf("TCMz", "TC0D", "TC0P", "TG0D", "TG0P")
    val sensors = listOf(
        SensorPreview("TCMz", "CPU 峰值", 65.9f),
        SensorPreview("TCMb", "CPU 平均", 63.2f),
        SensorPreview("TC0D", "CPU 核心", 61.8f),
        SensorPreview("TC0P", "CPU 邻近", 60.4f),
        SensorPreview("TG0D", "GPU 核心", 58.7f),
        SensorPreview("TG0P", "GPU 邻近", 57.2f),
        SensorPreview("TB0T", "电池 1", 34.1f),
        SensorPreview("TM0P", "内存", 49.3f),
        SensorPreview("TP0P", "供电", 52.8f),
        SensorPreview("TH0P", "硬盘", 43.9f),
        SensorPreview("TW0P", "无线网卡", 45.2f),
        SensorPreview("Ts0P", "掌托", 31.7f),
    )

    fun selectedMinimumRPM(): Float = when (fanFilter) {
        FanFilter.ALL -> fans.minOf { it.minimumRPM }
        FanFilter.FAN1 -> fans[0].minimumRPM
        FanFilter.FAN2 -> fans[1].minimumRPM
    }

    fun selectedMaximumRPM(): Float = when (fanFilter) {
        FanFilter.ALL -> fans.maxOf { it.maximumRPM }
        FanFilter.FAN1 -> fans[0].maximumRPM
        FanFilter.FAN2 -> fans[1].maximumRPM
    }

    fun displayCurve(): List<FanCurvePoint> {
        val key = when (fanFilter) {
            FanFilter.ALL, FanFilter.FAN1 -> "0"
            FanFilter.FAN2 -> "1"
        }
        return when (curveSource) {
            CurveSource.AC -> acCurves[key] ?: acCurves.getValue("0")
            CurveSource.BATTERY -> batteryCurves[key] ?: acCurves[key] ?: acCurves.getValue("0")
        }.sortedBy { it.temperature }
    }

    fun hasBatteryCurve(): Boolean {
        val keys = when (fanFilter) {
            FanFilter.ALL -> listOf("0", "1")
            FanFilter.FAN1 -> listOf("0")
            FanFilter.FAN2 -> listOf("1")
        }
        return keys.all { batteryCurves[it]?.size ?: 0 >= 2 }
    }

    fun updateCurve(points: List<FanCurvePoint>) {
        val normalized = normalizeCurve(points)
        val targets = when (fanFilter) {
            FanFilter.ALL -> listOf("0", "1")
            FanFilter.FAN1 -> listOf("0")
            FanFilter.FAN2 -> listOf("1")
        }
        val map = if (curveSource == CurveSource.AC) acCurves else batteryCurves
        targets.forEach { map[it] = normalized }
        actionMessage = "曲线已保存"
    }

    fun movePoint(index: Int, point: FanCurvePoint) {
        val updated = displayCurve().toMutableList()
        if (index !in updated.indices) return
        updated[index] = point.copy(
            temperature = point.temperature.coerceIn(40f, 105f),
            rpm = point.rpm.coerceIn(selectedMinimumRPM(), selectedMaximumRPM()),
        )
        updateCurve(updated)
    }

    fun addPoint() {
        val sorted = displayCurve().sortedBy { it.temperature }.toMutableList()
        if (sorted.size >= 6) return
        var bestIndex = 1
        var bestGap = -1f
        for (index in 1 until sorted.size) {
            val gap = sorted[index].temperature - sorted[index - 1].temperature
            if (gap > bestGap) {
                bestGap = gap
                bestIndex = index
            }
        }
        val before = sorted[bestIndex - 1]
        val after = sorted[bestIndex]
        sorted.add(
            bestIndex,
            FanCurvePoint(
                temperature = ((before.temperature + after.temperature) / 2f).roundToInt().toFloat(),
                rpm = ((before.rpm + after.rpm) / 2f / 50f).roundToInt() * 50f,
            ),
        )
        updateCurve(sorted)
    }

    fun removePoint(index: Int) {
        val points = displayCurve().sortedBy { it.temperature }.toMutableList()
        if (points.size <= 2 || index !in points.indices) return
        points.removeAt(index)
        updateCurve(points)
        actionMessage = "控制点已删除"
    }

    fun applyPreset(startCelsius: Float, fullCelsius: Float) {
        updateCurve(
            listOf(
                FanCurvePoint(startCelsius, selectedMinimumRPM()),
                FanCurvePoint(fullCelsius, selectedMaximumRPM()),
            ),
        )
        actionMessage = "已应用 ${startCelsius.roundToInt()}–${fullCelsius.roundToInt()} °C 预设"
    }

    fun copyBatteryFromAC() {
        batteryCurves.clear()
        acCurves.forEach { (key, points) -> batteryCurves[key] = points }
        actionMessage = "插电曲线已复制到电池曲线"
    }

    fun clearBatteryCurve() {
        val keys = when (fanFilter) {
            FanFilter.ALL -> listOf("0", "1")
            FanFilter.FAN1 -> listOf("0")
            FanFilter.FAN2 -> listOf("1")
        }
        keys.forEach(batteryCurves::remove)
        actionMessage = "电池曲线已清空，当前沿用插电曲线"
    }

    fun toggleSensor(key: String, checked: Boolean) {
        if (checked && !selectedSensors.contains(key)) {
            selectedSensors.add(key)
        } else if (!checked) {
            if (selectedSensors.size == 1) {
                actionMessage = "至少保留一个控制传感器"
            } else {
                selectedSensors.remove(key)
            }
        }
    }

    fun targetFor(fan: PreviewFan): Float {
        if (mode == FanMode.MANUAL) {
            return (manualRPM[fan.index] ?: fan.minimumRPM).coerceIn(fan.minimumRPM, fan.maximumRPM)
        }
        val key = fan.index.toString()
        val primary = if (curveSource == CurveSource.AC) acCurves[key] else batteryCurves[key]
        val points = primary ?: acCurves[key] ?: acCurves.getValue("0")
        return curveTarget(points, 65.9f).coerceIn(fan.minimumRPM, fan.maximumRPM)
    }

    fun applyScenario(scenario: FanScenario) {
        this.scenario = scenario
        dark = scenario == FanScenario.DARK
        mode = if (scenario == FanScenario.MANUAL) FanMode.MANUAL else FanMode.AUTO
        curveSource = if (scenario == FanScenario.BATTERY) CurveSource.BATTERY else CurveSource.AC
        helperMissing = scenario == FanScenario.HELPER
        enabled = !helperMissing
        nightEnabled = scenario == FanScenario.NIGHT || scenario == FanScenario.REDUCED
        nightExpanded = scenario == FanScenario.NIGHT || scenario == FanScenario.REDUCED
        alertsExpanded = scenario == FanScenario.ALERTS
        sensorsExpanded = scenario == FanScenario.SENSORS
        maintenanceExpanded = scenario == FanScenario.MAINTENANCE
        highTempEnabled = scenario == FanScenario.ALERTS
        fanFaultEnabled = scenario == FanScenario.ALERTS
        fanFault = scenario == FanScenario.ALERTS
        alertThreshold = if (scenario == FanScenario.ALERTS) 64f else 90f
        reducedMotion = scenario == FanScenario.REDUCED
        actionMessage = null
        uninstallArmed = false
    }

    private fun normalizeCurve(points: List<FanCurvePoint>): List<FanCurvePoint> {
        return points
            .map {
                it.copy(
                    temperature = it.temperature.coerceIn(40f, 105f).roundToInt().toFloat(),
                    rpm = ((it.rpm.coerceIn(selectedMinimumRPM(), selectedMaximumRPM()) / 50f).roundToInt() * 50f)
                        .coerceIn(selectedMinimumRPM(), selectedMaximumRPM()),
                )
            }
            .sortedBy { it.temperature }
            .fold(mutableListOf<FanCurvePoint>()) { result, point ->
                val previous = result.lastOrNull()
                if (previous == null || point.temperature > previous.temperature) {
                    result.add(point)
                }
                result
            }
    }
}

private fun curveTarget(points: List<FanCurvePoint>, temperature: Float): Float {
    val sorted = points.sortedBy { it.temperature }
    if (sorted.isEmpty()) return 0f
    if (temperature <= sorted.first().temperature) return sorted.first().rpm
    if (temperature >= sorted.last().temperature) return sorted.last().rpm
    for (index in 1 until sorted.size) {
        val left = sorted[index - 1]
        val right = sorted[index]
        if (temperature <= right.temperature) {
            val fraction = (temperature - left.temperature) / (right.temperature - left.temperature).coerceAtLeast(0.001f)
            return left.rpm + (right.rpm - left.rpm) * fraction
        }
    }
    return sorted.last().rpm
}

private data class FanPalette(
    val desktop: Color,
    val window: Color,
    val surface: Color,
    val controlFill: Color,
    val divider: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val accent: Color,
    val fanAccent: Color,
    val successFill: Color,
    val successText: Color,
    val successBackground: Color,
    val warningFill: Color,
    val warningText: Color,
    val warningBackground: Color,
    val errorText: Color,
    val errorBackground: Color,
    val infoText: Color,
    val infoBackground: Color,
) {
    companion object {
        fun forMode(dark: Boolean): FanPalette = if (dark) {
            FanPalette(
                desktop = Color(0xFF111113),
                window = Color(0xFF1C1C1E),
                surface = Color(0xFF242426),
                controlFill = Color(0xFF343436),
                divider = Color(0xFF48484A),
                textPrimary = Color(0xFFF5F5F7),
                textSecondary = Color(0xFFAEAEB2),
                accent = Color(0xFF0A84FF),
                fanAccent = Color(0xFF7D7AFF),
                successFill = Color(0xFF34C759),
                successText = Color(0xFF6EDB84),
                successBackground = Color(0xFF14351D),
                warningFill = Color(0xFFFF9F0A),
                warningText = Color(0xFFFFB340),
                warningBackground = Color(0xFF3A2A08),
                errorText = Color(0xFFFF6961),
                errorBackground = Color(0xFF3E151A),
                infoText = Color(0xFF84B8FF),
                infoBackground = Color(0xFF142644),
            )
        } else {
            FanPalette(
                desktop = Color(0xFFE9E9ED),
                window = Color(0xFFF5F5F7),
                surface = Color(0xFFFFFFFF),
                controlFill = Color(0xFFF4F4F7),
                divider = Color(0xFFD1D1D6),
                textPrimary = Color(0xFF1D1D1F),
                textSecondary = Color(0xFF6E6E73),
                accent = Color(0xFF0A84FF),
                fanAccent = Color(0xFF5856D6),
                successFill = Color(0xFF34C759),
                successText = Color(0xFF1E7A34),
                successBackground = Color(0xFFE5F8EA),
                warningFill = Color(0xFFFF9F0A),
                warningText = Color(0xFF8A4B00),
                warningBackground = Color(0xFFFFF2DC),
                errorText = Color(0xFFD70015),
                errorBackground = Color(0xFFFFF0F1),
                infoText = Color(0xFF245A9A),
                infoBackground = Color(0xFFEEF5FF),
            )
        }
    }
}
