package com.wyz.covio.preview

import androidx.compose.runtime.Composable
import com.wyz.covio.preview.previews.power.PowerManagementPreview
import com.wyz.covio.preview.previews.workbench.GlassWorkbenchPreview
import com.wyz.covio.preview.previews.workbench.WorkbenchPreview

/**
 * 一份打样。
 *
 * 一个改界面的 issue 对应一份打样。issue 正文里记打样的地址与截图。
 * 见 `docs/process/workflow.md` 的设计闸门。
 */
data class Preview(
    /** 首页上显示的名字。用界面自己的名字，不用 issue 的标题。 */
    val title: String,
    /** 这份打样覆盖什么。一行。评审人拿它对照 issue 的「表现预期」。 */
    val covers: String,
    /** 提出这份打样的 issue。 */
    val issue: Int,
    /** 画这一份打样。 */
    val content: @Composable () -> Unit,
)

/**
 * 全部打样。首页按这个顺序列出。
 *
 * 加一份打样就在这里加一条。
 *
 * **注意：** 只加画得完的。首页上点进去是空壳，就是死路，违反设计闸门的 R7。
 */
val previews: List<Preview> = listOf(
    Preview(
        title = "Monitor 电源管理",
        covers = "Monitor 内的概览 / 电源切换、状态、保持唤醒会话、安全规则和历史。",
        issue = 150,
        content = { PowerManagementPreview() },
    ),
    Preview(
        title = "挂帘工作台",
        covers = "S1 到 S8。菜单栏胶囊、玻璃面板、tab bar、bento 首页、编辑模式、工作区设置、错误恢复。",
        issue = 107,
        content = { WorkbenchPreview() },
    ),
    Preview(
        title = "玻璃板工作台",
        covers = "面板外壳照控制中心：两块独立玻璃板，中间露出桌面，板间没有投影。",
        issue = 118,
        content = { GlassWorkbenchPreview() },
    ),
)
