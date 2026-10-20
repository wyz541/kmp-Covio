package com.wyz.covio.preview.previews.power

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wyz.covio.preview.DeepLink

/**
 * `Monitor` 页签里的 Power 管理面。对应 #150。
 *
 * 打样只用假数据，不接 `kmpDomain`。
 * 文案和颜色逐条手抄自 `docs/covio-design-contract.json`。
 * 地址栏锚点见 [PowerPreviewStart]。
 */
@Composable
internal fun PowerManagementPreview() {
    val start = remember { PowerPreviewStart.fromHash() }
    var selectedTab by remember { mutableStateOf(start.tab) }
    var dark by remember { mutableStateOf(start.dark) }
    var active by remember { mutableStateOf(start.active) }
    var helperMissing by remember { mutableStateOf(start.helperMissing) }
    var conflict by remember { mutableStateOf(start.conflict) }
    var noBattery by remember { mutableStateOf(start.noBattery) }
    var onAdapter by remember { mutableStateOf(start.onAdapter) }
    var heatWarning by remember { mutableStateOf(start.heatWarning) }
    var emptyHistory by remember { mutableStateOf(start.emptyHistory) }
    var sessionMode by remember { mutableStateOf(start.sessionMode) }
    var duration by remember { mutableStateOf(start.duration) }
    var adapterRule by remember { mutableStateOf(true) }
    var batteryRule by remember { mutableStateOf(false) }
    var lidRule by remember { mutableStateOf(true) }
    var externalDisplayPause by remember { mutableStateOf(true) }
    var externalDisplay by remember { mutableStateOf(false) }
    var lowPowerMode by remember { mutableStateOf(false) }

    val palette = PowerPalette.forMode(dark)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.desktop),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 28.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 960.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(palette.canvas)
                    .border(1.dp, palette.divider, RoundedCornerShape(22.dp))
                    .padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                PowerPageHeader(
                    selectedTab = selectedTab,
                    onSelectTab = { selectedTab = it },
                    helperMissing = helperMissing,
                    palette = palette,
                )

                if (helperMissing) {
                    PowerAlert(
                        text = "使用合盖保持唤醒前请安装助手。",
                        accent = palette.warning,
                        background = palette.warningBg,
                        action = "安装助手",
                        palette = palette,
                    )
                }
                if (conflict) {
                    PowerAlert(
                        text = "其他应用修改了睡眠设置。Covio 不会清除该设置。",
                        accent = palette.error,
                        background = palette.errorBg,
                        action = "查看",
                        palette = palette,
                    )
                }
                if (heatWarning) {
                    PowerAlert(
                        text = "温度保护会释放全部保持唤醒。",
                        accent = palette.warning,
                        background = palette.warningBg,
                        action = null,
                        palette = palette,
                    )
                }

                when (selectedTab) {
                    PowerTab.OVERVIEW -> MonitorOverviewPreview(palette)
                    PowerTab.POWER -> PowerSurface(
                        palette = palette,
                        active = active,
                        sessionMode = sessionMode,
                        duration = duration,
                        helperMissing = helperMissing,
                        conflict = conflict,
                        noBattery = noBattery,
                        onAdapter = onAdapter,
                        heatWarning = heatWarning,
                        emptyHistory = emptyHistory,
                        adapterRule = adapterRule,
                        batteryRule = batteryRule,
                        lidRule = lidRule,
                        externalDisplayPause = externalDisplayPause,
                        externalDisplay = externalDisplay,
                        lowPowerMode = lowPowerMode,
                        onSessionMode = { sessionMode = it },
                        onDuration = { duration = it },
                        onToggleSession = {
                            if (active) {
                                active = false
                            } else if (!(sessionMode == SessionMode.LID && helperMissing)) {
                                active = true
                                conflict = false
                                heatWarning = false
                            }
                        },
                        onAdapterRule = { adapterRule = it },
                        onBatteryRule = { batteryRule = it },
                        onLidRule = { lidRule = it },
                        onExternalDisplayPause = { externalDisplayPause = it },
                        onExternalDisplay = { externalDisplay = it },
                        onLowPowerMode = { lowPowerMode = it },
                    )
                }
            }

            Spacer(Modifier.height(18.dp))
            Text(
                text = "预览锚点：#150-power · #150-dark · #150-battery · #150-helper · #150-conflict · #150-no-battery · #150-thermal · #150-empty · #150-overview",
                color = palette.textSecondary,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.widthIn(max = 960.dp).fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun PowerPageHeader(
    selectedTab: PowerTab,
    onSelectTab: (PowerTab) -> Unit,
    helperMissing: Boolean,
    palette: PowerPalette,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "监控",
                color = palette.textPrimary,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "电源管理",
                color = palette.textSecondary,
                fontSize = 11.sp,
            )
        }

        SegmentedControl(
            selected = selectedTab,
            options = listOf(PowerTab.OVERVIEW to "概览", PowerTab.POWER to "电源"),
            palette = palette,
            onSelect = onSelectTab,
        )

        StatusPill(
            text = if (helperMissing) "安全护栏不可用" else "安全护栏就绪",
            accent = if (helperMissing) palette.warning else palette.successText,
            background = if (helperMissing) palette.warningBg else palette.successBg,
        )
    }
}

@Composable
private fun PowerSurface(
    palette: PowerPalette,
    active: Boolean,
    sessionMode: SessionMode,
    duration: SessionDuration,
    helperMissing: Boolean,
    conflict: Boolean,
    noBattery: Boolean,
    onAdapter: Boolean,
    heatWarning: Boolean,
    emptyHistory: Boolean,
    adapterRule: Boolean,
    batteryRule: Boolean,
    lidRule: Boolean,
    externalDisplayPause: Boolean,
    externalDisplay: Boolean,
    lowPowerMode: Boolean,
    onSessionMode: (SessionMode) -> Unit,
    onDuration: (SessionDuration) -> Unit,
    onToggleSession: () -> Unit,
    onAdapterRule: (Boolean) -> Unit,
    onBatteryRule: (Boolean) -> Unit,
    onLidRule: (Boolean) -> Unit,
    onExternalDisplayPause: (Boolean) -> Unit,
    onExternalDisplay: (Boolean) -> Unit,
    onLowPowerMode: (Boolean) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PowerStatusCard(
            palette = palette,
            noBattery = noBattery,
            onAdapter = onAdapter,
            lowPowerMode = lowPowerMode,
            heatWarning = heatWarning,
            externalDisplay = externalDisplay,
            helperMissing = helperMissing,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SessionCard(
                palette = palette,
                active = active,
                onAdapter = onAdapter,
                mode = sessionMode,
                duration = duration,
                helperMissing = helperMissing,
                conflict = conflict,
                onMode = onSessionMode,
                onDuration = onDuration,
                onToggle = onToggleSession,
                modifier = Modifier.weight(1.25f),
            )
            RulesCard(
                palette = palette,
                noBattery = noBattery,
                adapterRule = adapterRule,
                batteryRule = batteryRule,
                lidRule = lidRule,
                externalDisplayPause = externalDisplayPause,
                onAdapterRule = onAdapterRule,
                onBatteryRule = onBatteryRule,
                onLidRule = onLidRule,
                onExternalDisplayPause = onExternalDisplayPause,
                modifier = Modifier.weight(0.75f),
            )
        }

        HistoryCard(
            palette = palette,
            empty = emptyHistory,
            heatWarning = heatWarning,
        )
    }
}

@Composable
private fun PowerStatusCard(
    palette: PowerPalette,
    noBattery: Boolean,
    onAdapter: Boolean,
    lowPowerMode: Boolean,
    heatWarning: Boolean,
    externalDisplay: Boolean,
    helperMissing: Boolean,
) {
    PowerCard(palette) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            BatteryDial(
                percent = if (noBattery) null else 84,
                accent = if (noBattery) palette.accent else palette.success,
                palette = palette,
            )

            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("当前供电", color = palette.textSecondary, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                Text(
                    text = when {
                        noBattery -> "桌面供电"
                        onAdapter -> "电源适配器 · 84%"
                        else -> "使用电池 · 84%"
                    },
                    color = palette.textPrimary,
                    fontSize = 19.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = when {
                        noBattery -> "电源适配器已连接"
                        onAdapter -> "适配器已连接 · 预计充满 32 分钟"
                        else -> "剩余 3 小时 42 分钟 · 适配器未连接"
                    },
                    color = palette.textSecondary,
                    fontSize = 11.sp,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatusPill(
                        text = if (noBattery || onAdapter) "电源适配器" else "使用电池",
                        accent = if (noBattery || onAdapter) palette.successText else palette.warningText,
                        background = if (noBattery || onAdapter) palette.successBg else palette.warningBg,
                    )
                    StatusPill(
                        text = if (helperMissing) "合盖保护不可用" else "合盖保护就绪",
                        accent = if (helperMissing) palette.warningText else palette.successText,
                        background = if (helperMissing) palette.warningBg else palette.successBg,
                    )
                }
            }

            Column(
                modifier = Modifier.width(246.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                MetricRow("低电量模式", if (lowPowerMode) "开启" else "关闭", palette)
                MetricRow(
                    "热状态",
                    if (heatWarning) "过热" else "正常",
                    palette,
                    accent = if (heatWarning) palette.warningText else palette.successText,
                )
                MetricRow(
                    "外接屏",
                    if (externalDisplay) "已连接" else "无",
                    palette,
                )
            }
        }
    }
}

@Composable
private fun SessionCard(
    palette: PowerPalette,
    active: Boolean,
    onAdapter: Boolean,
    mode: SessionMode,
    duration: SessionDuration,
    helperMissing: Boolean,
    conflict: Boolean,
    onMode: (SessionMode) -> Unit,
    onDuration: (SessionDuration) -> Unit,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    PowerCard(palette, modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("保持唤醒", color = palette.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            StatusPill(
                text = if (active) "运行中" else "关闭",
                accent = if (active) palette.successText else palette.textSecondary,
                background = if (active) palette.successBg else palette.controlFill,
            )
        }

        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SessionMode.entries.forEach { option ->
                SessionModeChip(
                    label = option.label,
                    selected = mode == option,
                    palette = palette,
                    onClick = { onMode(option) },
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Spacer(Modifier.height(10.dp))
        Text("时长", color = palette.textSecondary, fontSize = 10.sp, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(5.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SessionDuration.entries.forEach { option ->
                DurationChip(
                    label = option.label,
                    selected = duration == option,
                    palette = palette,
                    onClick = { onDuration(option) },
                )
            }
        }

        Spacer(Modifier.height(12.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(palette.controlFill)
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            when {
                active -> {
                    ReasonRow(
                        text = if (onAdapter) "已接通电源" else "使用电池规则",
                        color = if (onAdapter) palette.success else palette.warning,
                        palette = palette,
                    )
                    ReasonRow(
                        text = if (mode == SessionMode.LID) {
                            "安全条件通过时才保持合盖运行"
                        } else {
                            "只保持系统空闲唤醒"
                        },
                        color = palette.accent,
                        palette = palette,
                    )
                }
                else -> Text(
                    text = if (helperMissing && mode == SessionMode.LID) {
                        "合盖运行需要安装助手。"
                    } else {
                        "当前没有保持唤醒会话。"
                    },
                    color = if (helperMissing && mode == SessionMode.LID) palette.warningText else palette.textSecondary,
                    fontSize = 11.sp,
                )
            }
        }

        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = if (active) "剩余 45 分钟" else "随时可以开始",
                color = palette.textSecondary,
                fontSize = 10.sp,
            )
            Spacer(Modifier.weight(1f))
            PrimaryActionButton(
                label = if (active) "结束" else "开始",
                enabled = !(helperMissing && mode == SessionMode.LID),
                palette = palette,
                onClick = onToggle,
            )
        }
        if (conflict) {
            Spacer(Modifier.height(8.dp))
            Text("存在外部睡眠状态冲突。", color = palette.errorText, fontSize = 10.sp)
        }
    }
}

@Composable
private fun RulesCard(
    palette: PowerPalette,
    noBattery: Boolean,
    adapterRule: Boolean,
    batteryRule: Boolean,
    lidRule: Boolean,
    externalDisplayPause: Boolean,
    onAdapterRule: (Boolean) -> Unit,
    onBatteryRule: (Boolean) -> Unit,
    onLidRule: (Boolean) -> Unit,
    onExternalDisplayPause: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    PowerCard(palette, modifier) {
        Text("安全与自动规则", color = palette.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(10.dp))
        RuleToggleRow("接通电源时保持唤醒", adapterRule, palette, onAdapterRule)
        RuleToggleRow(
            label = if (noBattery) "使用电池时保持唤醒（不适用）" else "使用电池时保持唤醒",
            checked = batteryRule,
            palette = palette,
            onToggle = onBatteryRule,
            enabled = !noBattery,
        )
        RuleToggleRow("允许合盖保持唤醒", lidRule, palette, onLidRule)
        RuleToggleRow("有外接屏时暂停合盖保持唤醒", externalDisplayPause, palette, onExternalDisplayPause)

        Spacer(Modifier.height(10.dp))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(palette.controlFill)
                .padding(10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SafetyMetric("电池下限", if (noBattery) "—" else "15%", palette, Modifier.weight(1f))
            SafetyMetric("温度保护", "开启", palette, Modifier.weight(1f))
            SafetyMetric("合盖时长", "4 小时", palette, Modifier.weight(1f))
        }
    }
}

@Composable
private fun HistoryCard(
    palette: PowerPalette,
    empty: Boolean,
    heatWarning: Boolean,
) {
    PowerCard(palette) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("最近活动", color = palette.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text("最近 24 小时", color = palette.textSecondary, fontSize = 10.sp)
        }
        Spacer(Modifier.height(10.dp))
        if (empty) {
            Text("最近没有事件", color = palette.textSecondary, fontSize = 11.sp)
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                HistoryEvent("09:12", "Mac 已唤醒", palette.accent, palette, Modifier.weight(1f))
                HistoryEvent("08:58", "Mac 已睡眠", palette.textSecondary, palette, Modifier.weight(1f))
                HistoryEvent(
                    "08:42",
                    if (heatWarning) "温度保护已释放保持唤醒" else "合盖保持唤醒已开始",
                    if (heatWarning) palette.warning else palette.success,
                    palette,
                    Modifier.weight(1f),
                )
                HistoryEvent("08:41", "已接通电源", palette.success, palette, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MonitorOverviewPreview(palette: PowerPalette) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            MiniMetricCard("CPU", "34%", 0.34f, palette, Modifier.weight(1f))
            MiniMetricCard("内存", "61%", 0.61f, palette, Modifier.weight(1f))
            MiniMetricCard("磁盘", "42%", 0.42f, palette, Modifier.weight(1f))
            MiniMetricCard("网络", "2.8 MB/s", 0.28f, palette, Modifier.weight(1f))
        }
        PowerCard(palette) {
            Text(
                text = "现有实时指标保留在概览中。",
                color = palette.textSecondary,
                fontSize = 11.sp,
            )
        }
    }
}

@Composable
private fun MiniMetricCard(
    label: String,
    value: String,
    fraction: Float,
    palette: PowerPalette,
    modifier: Modifier,
) {
    PowerCard(palette, modifier) {
        Text(label, color = palette.textSecondary, fontSize = 10.sp, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(5.dp))
        Text(value, color = palette.textPrimary, fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(12.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(5.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(palette.divider),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(fraction)
                    .height(5.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(palette.accent),
            )
        }
    }
}

@Composable
private fun PowerCard(
    palette: PowerPalette,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(palette.surface)
            .border(1.dp, palette.divider, RoundedCornerShape(12.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(0.dp),
        content = content,
    )
}

@Composable
private fun PowerAlert(
    text: String,
    accent: Color,
    background: Color,
    action: String?,
    palette: PowerPalette,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(background)
            .border(1.dp, accent.copy(alpha = 0.28f), RoundedCornerShape(8.dp))
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(6.dp).clip(RoundedCornerShape(999.dp)).background(accent))
        Text(text, color = accent, fontSize = 11.sp, modifier = Modifier.weight(1f))
        if (action != null) {
            Text(action, color = accent, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun SegmentedControl(
    selected: PowerTab,
    options: List<Pair<PowerTab, String>>,
    palette: PowerPalette,
    onSelect: (PowerTab) -> Unit,
) {
    Row(
        modifier = Modifier
            .width(212.dp)
            .height(30.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(palette.controlFill)
            .border(1.dp, palette.divider, RoundedCornerShape(8.dp))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        options.forEach { (value, label) ->
            val isSelected = selected == value
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize()
                    .clip(RoundedCornerShape(6.dp))
                    .background(if (isSelected) palette.surface else Color.Transparent)
                    .clickable { onSelect(value) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    color = if (isSelected) palette.textPrimary else palette.textSecondary,
                    fontSize = 11.sp,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                )
            }
        }
    }
}

@Composable
private fun SessionModeChip(
    label: String,
    selected: Boolean,
    palette: PowerPalette,
    onClick: () -> Unit,
    modifier: Modifier,
) {
    Box(
        modifier = modifier
            .height(30.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(if (selected) palette.accent.copy(alpha = 0.14f) else palette.controlFill)
            .border(
                1.dp,
                if (selected) palette.accent.copy(alpha = 0.55f) else palette.divider,
                RoundedCornerShape(7.dp),
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (selected) palette.accent else palette.textSecondary,
            fontSize = 10.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

@Composable
private fun DurationChip(
    label: String,
    selected: Boolean,
    palette: PowerPalette,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .height(24.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) palette.accent else palette.controlFill)
            .border(1.dp, if (selected) palette.accent else palette.divider, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (selected) Color.White else palette.textSecondary,
            fontSize = 9.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

@Composable
private fun PrimaryActionButton(
    label: String,
    enabled: Boolean,
    palette: PowerPalette,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .height(28.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(if (enabled) palette.accent else palette.divider)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun RuleToggleRow(
    label: String,
    checked: Boolean,
    palette: PowerPalette,
    onToggle: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled) { onToggle(!checked) }
            .padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = label,
            color = palette.textPrimary,
            fontSize = 10.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        SmallToggle(checked = checked, palette = palette, onToggle = onToggle, enabled = enabled)
    }
}

@Composable
private fun SmallToggle(
    checked: Boolean,
    palette: PowerPalette,
    onToggle: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    Row(
        modifier = Modifier
            .width(32.dp)
            .height(18.dp)
            .clip(RoundedCornerShape(999.dp))
            .background(
                when {
                    !enabled -> palette.divider.copy(alpha = 0.5f)
                    checked -> palette.success
                    else -> palette.divider
                },
            )
            .clickable(enabled = enabled) { onToggle(!checked) }
            .padding(2.dp),
        horizontalArrangement = if (checked) Arrangement.End else Arrangement.Start,
    ) {
        Box(Modifier.size(14.dp).clip(RoundedCornerShape(999.dp)).background(Color.White))
    }
}

@Composable
private fun StatusPill(text: String, accent: Color, background: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(background)
            .padding(horizontal = 8.dp, vertical = 3.dp),
    ) {
        Text(text, color = accent, fontSize = 9.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun MetricRow(
    label: String,
    value: String,
    palette: PowerPalette,
    accent: Color = palette.textPrimary,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = palette.textSecondary, fontSize = 9.sp, modifier = Modifier.weight(1f))
        Text(value, color = accent, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ReasonRow(text: String, color: Color, palette: PowerPalette) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Box(Modifier.size(5.dp).clip(RoundedCornerShape(999.dp)).background(color))
        Text(text, color = palette.textSecondary, fontSize = 10.sp)
    }
}

@Composable
private fun SafetyMetric(
    label: String,
    value: String,
    palette: PowerPalette,
    modifier: Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(label, color = palette.textSecondary, fontSize = 8.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(value, color = palette.textPrimary, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun HistoryEvent(
    time: String,
    label: String,
    accent: Color,
    palette: PowerPalette,
    modifier: Modifier,
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(palette.controlFill)
            .padding(horizontal = 9.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Box(Modifier.padding(top = 4.dp).size(5.dp).clip(RoundedCornerShape(999.dp)).background(accent))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(time, color = palette.textSecondary, fontSize = 8.sp, fontWeight = FontWeight.Medium)
            Text(label, color = palette.textPrimary, fontSize = 9.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun BatteryDial(
    percent: Int?,
    accent: Color,
    palette: PowerPalette,
) {
    Box(modifier = Modifier.size(82.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 7.dp.toPx()
            drawCircle(color = palette.divider, style = Stroke(width = stroke))
            if (percent != null) {
                drawArc(
                    color = accent,
                    startAngle = -90f,
                    sweepAngle = 360f * percent / 100f,
                    useCenter = false,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
            } else {
                drawCircle(color = accent.copy(alpha = 0.16f), radius = size.minDimension / 2f - stroke)
                drawLine(
                    color = accent,
                    start = Offset(size.width * 0.36f, size.height * 0.50f),
                    end = Offset(size.width * 0.64f, size.height * 0.50f),
                    strokeWidth = stroke,
                    cap = StrokeCap.Round,
                )
            }
        }
        Text(
            text = percent?.let { "$it%" } ?: "AC",
            color = palette.textPrimary,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

private enum class PowerTab { OVERVIEW, POWER }

private enum class SessionMode(val label: String) {
    SYSTEM("仅系统"),
    DISPLAY("系统与屏幕"),
    LID("合盖运行"),
}

private enum class SessionDuration(val label: String) {
    FIFTEEN_MINUTES("15 分钟"),
    ONE_HOUR("1 小时"),
    TWO_HOURS("2 小时"),
    FOUR_HOURS("4 小时"),
    UNTIL_OFF("直到关闭"),
}

private data class PowerPreviewStart(
    val tab: PowerTab,
    val dark: Boolean,
    val active: Boolean,
    val helperMissing: Boolean,
    val conflict: Boolean,
    val noBattery: Boolean,
    val onAdapter: Boolean,
    val heatWarning: Boolean,
    val emptyHistory: Boolean,
    val sessionMode: SessionMode,
    val duration: SessionDuration,
) {
    companion object {
        fun fromHash(): PowerPreviewStart = when (val anchor = DeepLink.anchor) {
            "", "power", "active" -> base()
            "dark" -> base(dark = true)
            "battery" -> base(onAdapter = false)
            "helper" -> base(active = false, helperMissing = true)
            "conflict" -> base(active = false, conflict = true)
            "no-battery" -> base(active = false, noBattery = true, emptyHistory = true)
            "thermal" -> base(active = false, heatWarning = true)
            "empty" -> base(active = false, emptyHistory = true)
            "overview" -> base(tab = PowerTab.OVERVIEW)
            else -> error("未知的锚点：$anchor")
        }

        private fun base(
            tab: PowerTab = PowerTab.POWER,
            dark: Boolean = false,
            active: Boolean = true,
            helperMissing: Boolean = false,
            conflict: Boolean = false,
            noBattery: Boolean = false,
            onAdapter: Boolean = true,
            heatWarning: Boolean = false,
            emptyHistory: Boolean = false,
            sessionMode: SessionMode = SessionMode.LID,
            duration: SessionDuration = SessionDuration.ONE_HOUR,
        ) = PowerPreviewStart(
            tab = tab,
            dark = dark,
            active = active,
            helperMissing = helperMissing,
            conflict = conflict,
            noBattery = noBattery,
            onAdapter = onAdapter,
            heatWarning = heatWarning,
            emptyHistory = emptyHistory,
            sessionMode = sessionMode,
            duration = duration,
        )
    }
}

private data class PowerPalette(
    val desktop: Color,
    val canvas: Color,
    val surface: Color,
    val controlFill: Color,
    val divider: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val accent: Color,
    val success: Color,
    val successBg: Color,
    val successText: Color,
    val warning: Color,
    val warningBg: Color,
    val warningText: Color,
    val error: Color,
    val errorBg: Color,
    val errorText: Color,
) {
    companion object {
        fun forMode(dark: Boolean): PowerPalette = if (dark) {
            PowerPalette(
                desktop = Color(0xFF111113),
                canvas = Color(0xFF1C1C1E),
                surface = Color(0xFF2C2C2E),
                controlFill = Color(0xFF3A3A3C),
                divider = Color(0xFF48484A),
                textPrimary = Color(0xFFF5F5F7),
                textSecondary = Color(0xFFAEAEB2),
                accent = Color(0xFF0A84FF),
                success = Color(0xFF34C759),
                successBg = Color(0xFF14351D),
                successText = Color(0xFF6EDB84),
                warning = Color(0xFFFF9F0A),
                warningBg = Color(0xFF3A2A08),
                warningText = Color(0xFFFFB340),
                error = Color(0xFFD70015),
                errorBg = Color(0xFF3E151A),
                errorText = Color(0xFFFF6961),
            )
        } else {
            PowerPalette(
                desktop = Color(0xFFE5E5EA),
                canvas = Color(0xFFF2F2F7),
                surface = Color(0xFFFFFFFF),
                controlFill = Color(0xFFF7F7FA),
                divider = Color(0xFFD1D1D6),
                textPrimary = Color(0xFF1D1D1F),
                textSecondary = Color(0xFF6E6E73),
                accent = Color(0xFF007AFF),
                success = Color(0xFF34C759),
                successBg = Color(0xFFE5F8EA),
                successText = Color(0xFF1E7A34),
                warning = Color(0xFFFF9F0A),
                warningBg = Color(0xFFFFF2DC),
                warningText = Color(0xFF8A4B00),
                error = Color(0xFFD70015),
                errorBg = Color(0xFFFFF0F1),
                errorText = Color(0xFFD70015),
            )
        }
    }
}
