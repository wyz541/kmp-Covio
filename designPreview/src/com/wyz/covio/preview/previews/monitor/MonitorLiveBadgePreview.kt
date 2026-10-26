package com.wyz.covio.preview.previews.monitor

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wyz.covio.preview.DeepLink

/**
 * Monitor 状态栏。对应 #405。
 *
 * 地址栏锚点：
 * - `#405-light`：亮色。
 * - `#405-dark`：深色。
 */
@Composable
internal fun MonitorLiveBadgePreview() {
    val dark = remember { DeepLink.anchor == "dark" }
    val palette = MonitorLiveBadgePalette.forMode(dark)

    Box(
        modifier = Modifier.fillMaxSize().background(palette.desktop),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 32.dp, vertical = 28.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(palette.canvas)
                .border(1.dp, palette.divider, RoundedCornerShape(18.dp))
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "Monitor 状态栏",
                    color = palette.textPrimary,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "状态栏保留原高度，内容暂时留空。普通指标卡保持无 Live 胶囊。",
                    color = palette.textSecondary,
                    fontSize = 12.sp,
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                PreviewColumn(
                    title = "当前",
                    note = "状态栏显示实时、采样周期、热状态和样本数。",
                    showStatusContent = true,
                    palette = palette,
                    modifier = Modifier.weight(1f),
                )
                PreviewColumn(
                    title = "建议",
                    note = "状态栏保留高度，内容为空。",
                    showStatusContent = false,
                    palette = palette,
                    modifier = Modifier.weight(1f),
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PreviewNote("状态栏高度不变", palette.successText, palette.successBg)
                PreviewNote("卡片标题不显示 Live", palette.accent, palette.accentBg)
            }
        }
    }
}

@Composable
private fun PreviewColumn(
    title: String,
    note: String,
    showStatusContent: Boolean,
    palette: MonitorLiveBadgePalette,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(palette.surface)
            .border(1.dp, palette.divider, RoundedCornerShape(12.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, color = palette.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Text(note, color = palette.textSecondary, fontSize = 10.sp)
        MonitorPreviewStatusRow(showContent = showStatusContent, palette = palette)
        MonitorCards(palette = palette)
    }
}

@Composable
private fun MonitorPreviewStatusRow(
    showContent: Boolean,
    palette: MonitorLiveBadgePalette,
) {
    if (!showContent) {
        Box(Modifier.fillMaxWidth().height(18.dp))
        return
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(6.dp).clip(RoundedCornerShape(999.dp)).background(palette.success))
        Text("实时", color = palette.textSecondary, fontSize = 10.sp, fontWeight = FontWeight.Medium)
        Text("·", color = palette.textSecondary, fontSize = 10.sp)
        Text("1 秒", color = palette.textSecondary, fontSize = 10.sp)
        Spacer(Modifier.weight(1f))
        Text("热状态 · 正常 · 24/60", color = palette.textSecondary, fontSize = 10.sp)
    }
}

@Composable
private fun MonitorCards(palette: MonitorLiveBadgePalette) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MonitorMiniCard("CPU", "56%", palette, Modifier.weight(1f))
            MonitorMiniCard("GPU", "28%", palette, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MonitorMiniCard("内存", "56%", palette, Modifier.weight(1f))
            MonitorMiniCard("磁盘", "67%", palette, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MonitorMiniCard("网络", "10.2 MB/s", palette, Modifier.weight(1f))
            MonitorMiniCard("电池", "84%", palette, Modifier.weight(1f))
        }
    }
}

@Composable
private fun MonitorMiniCard(
    title: String,
    value: String,
    palette: MonitorLiveBadgePalette,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(9.dp))
            .background(palette.card)
            .border(1.dp, palette.accent.copy(alpha = 0.24f), RoundedCornerShape(9.dp))
            .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = palette.textPrimary, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(value, color = palette.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        Text("最近 60 个采样点", color = palette.textSecondary, fontSize = 8.sp)
    }
}

@Composable
private fun PreviewNote(text: String, foreground: Color, background: Color) {
    Text(
        text = text,
        color = foreground,
        fontSize = 9.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(background)
            .padding(horizontal = 9.dp, vertical = 4.dp),
    )
}

private data class MonitorLiveBadgePalette(
    val desktop: Color,
    val canvas: Color,
    val surface: Color,
    val card: Color,
    val divider: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val accent: Color,
    val accentBg: Color,
    val success: Color,
    val successText: Color,
    val successBg: Color,
) {
    companion object {
        fun forMode(dark: Boolean): MonitorLiveBadgePalette = if (dark) {
            MonitorLiveBadgePalette(
                desktop = Color(0xFF111113),
                canvas = Color(0xFF1C1C1E),
                surface = Color(0xFF242426),
                card = Color(0xFF2C2C2E),
                divider = Color(0xFF48484A),
                textPrimary = Color(0xFFF5F5F7),
                textSecondary = Color(0xFFAEAEB2),
                accent = Color(0xFF0A84FF),
                accentBg = Color(0xFF102B4D),
                success = Color(0xFF34C759),
                successText = Color(0xFF6EDB84),
                successBg = Color(0xFF14351D),
            )
        } else {
            MonitorLiveBadgePalette(
                desktop = Color(0xFFE5E5EA),
                canvas = Color(0xFFF2F2F7),
                surface = Color(0xFFFFFFFF),
                card = Color(0xFFF8F8FA),
                divider = Color(0xFFD1D1D6),
                textPrimary = Color(0xFF1D1D1F),
                textSecondary = Color(0xFF6E6E73),
                accent = Color(0xFF007AFF),
                accentBg = Color(0xFFE8F2FF),
                success = Color(0xFF34C759),
                successText = Color(0xFF1E7A34),
                successBg = Color(0xFFE5F8EA),
            )
        }
    }
}
