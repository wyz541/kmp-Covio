// 本文件由 scripts/generate-contract-constants.py 生成。不要手改。
// 权威是 docs/covio-design-contract.json。
// 改合同后重跑脚本：python3 scripts/generate-contract-constants.py

import Foundation

/// 设计合同 `copy` 段的全部文案。
///
/// 键名就是合同里的键路径。`DesignContractTests` 逐条比对，
/// 所以这里的值不能手改。
enum ContractCopy {
    /// `copy/agent/action-cancelled`
    static let copyAgentActionCancelled = LocalizedCopy(key: "copy/agent/action-cancelled", en: "Local action cancelled.", zhHans: "本地操作已取消。")
    /// `copy/agent/action-completed`
    static let copyAgentActionCompleted = LocalizedCopy(key: "copy/agent/action-completed", en: "Local action completed.", zhHans: "本地操作已完成。")
    /// `copy/agent/action-failed`
    static let copyAgentActionFailed = LocalizedCopy(key: "copy/agent/action-failed", en: "Local action failed.", zhHans: "本地操作失败。")
    /// `copy/agent/cancel`
    static let copyAgentCancel = LocalizedCopy(key: "copy/agent/cancel", en: "Cancel", zhHans: "取消")
    /// `copy/agent/clear`
    static let copyAgentClear = LocalizedCopy(key: "copy/agent/clear", en: "New chat", zhHans: "新对话")
    /// `copy/agent/confirm`
    static let copyAgentConfirm = LocalizedCopy(key: "copy/agent/confirm", en: "Allow", zhHans: "允许")
    /// `copy/agent/confirm-body`
    static let copyAgentConfirmBody = LocalizedCopy(key: "copy/agent/confirm-body", en: "The agent will run this local service after your confirmation.", zhHans: "确认后 Agent 将执行此本地服务。")
    /// `copy/agent/confirm-title`
    static let copyAgentConfirmTitle = LocalizedCopy(key: "copy/agent/confirm-title", en: "Allow local action?", zhHans: "允许本地操作？")
    /// `copy/agent/copy-characters`
    static let copyAgentCopyCharacters = LocalizedCopy(key: "copy/agent/copy-characters", en: "Copy %d characters to the clipboard.", zhHans: "复制 %d 个字符到剪贴板。")
    /// `copy/agent/empty-body`
    static let copyAgentEmptyBody = LocalizedCopy(key: "copy/agent/empty-body", en: "It can check monitor, power, workspace, screenshots, and clipboard metadata. Side effects need confirmation.", zhHans: "可查询监控、电源、工作区、截图和剪贴板元数据。有副作用的操作需要确认。")
    /// `copy/agent/empty-response`
    static let copyAgentEmptyResponse = LocalizedCopy(key: "copy/agent/empty-response", en: "No response.", zhHans: "没有返回内容。")
    /// `copy/agent/empty-title`
    static let copyAgentEmptyTitle = LocalizedCopy(key: "copy/agent/empty-title", en: "Ask the local agent", zhHans: "询问本地 Agent")
    /// `copy/agent/error`
    static let copyAgentError = LocalizedCopy(key: "copy/agent/error", en: "The local agent could not complete this request.", zhHans: "本地 Agent 无法完成此请求。")
    /// `copy/agent/name`
    static let copyAgentName = LocalizedCopy(key: "copy/agent/name", en: "Covio Agent", zhHans: "Covio Agent")
    /// `copy/agent/offline`
    static let copyAgentOffline = LocalizedCopy(key: "copy/agent/offline", en: "Local only", zhHans: "仅本地")
    /// `copy/agent/placeholder`
    static let copyAgentPlaceholder = LocalizedCopy(key: "copy/agent/placeholder", en: "Ask about this Mac or your workspace", zhHans: "询问这台 Mac 或工作区")
    /// `copy/agent/send`
    static let copyAgentSend = LocalizedCopy(key: "copy/agent/send", en: "Send", zhHans: "发送")
    /// `copy/agent/stop`
    static let copyAgentStop = LocalizedCopy(key: "copy/agent/stop", en: "Stop", zhHans: "停止")
    /// `copy/agent/stopped`
    static let copyAgentStopped = LocalizedCopy(key: "copy/agent/stopped", en: "Stopped.", zhHans: "已停止。")
    /// `copy/agent/thinking`
    static let copyAgentThinking = LocalizedCopy(key: "copy/agent/thinking", en: "Using local services…", zhHans: "正在使用本地服务…")
    /// `copy/agent/you`
    static let copyAgentYou = LocalizedCopy(key: "copy/agent/you", en: "You", zhHans: "你")
    /// `copy/app/name`
    static let copyAppName = LocalizedCopy(key: "copy/app/name", en: "Covio", zhHans: "Covio")
    /// `copy/app/tagline`
    static let copyAppTagline = LocalizedCopy(key: "copy/app/tagline", en: "Keep your Mac awake when it matters.", zhHans: "在需要时保持 Mac 唤醒。")
    /// `copy/auto-naming/action/apply`
    static let copyAutoNamingActionApply = LocalizedCopy(key: "copy/auto-naming/action/apply", en: "Rename Selected", zhHans: "重命名所选")
    /// `copy/auto-naming/action/auto-name`
    static let copyAutoNamingActionAutoName = LocalizedCopy(key: "copy/auto-naming/action/auto-name", en: "Auto Name…", zhHans: "自动命名…")
    /// `copy/auto-naming/action/cancel`
    static let copyAutoNamingActionCancel = LocalizedCopy(key: "copy/auto-naming/action/cancel", en: "Cancel", zhHans: "取消")
    /// `copy/auto-naming/action/close`
    static let copyAutoNamingActionClose = LocalizedCopy(key: "copy/auto-naming/action/close", en: "Close", zhHans: "关闭")
    /// `copy/auto-naming/action/select`
    static let copyAutoNamingActionSelect = LocalizedCopy(key: "copy/auto-naming/action/select", en: "Include this file", zhHans: "选择这个文件")
    /// `copy/auto-naming/action/undo`
    static let copyAutoNamingActionUndo = LocalizedCopy(key: "copy/auto-naming/action/undo", en: "Undo Renames", zhHans: "撤销重命名")
    /// `copy/auto-naming/error/analysis`
    static let copyAutoNamingErrorAnalysis = LocalizedCopy(key: "copy/auto-naming/error/analysis", en: "Auto naming could not finish. No files were changed.", zhHans: "自动命名未完成。文件没有改动。")
    /// `copy/auto-naming/error/rename`
    static let copyAutoNamingErrorRename = LocalizedCopy(key: "copy/auto-naming/error/rename", en: "The rename run failed. No file was overwritten.", zhHans: "重命名失败。没有文件被覆盖。")
    /// `copy/auto-naming/error/undo`
    static let copyAutoNamingErrorUndo = LocalizedCopy(key: "copy/auto-naming/error/undo", en: "Undo could not finish. No file was overwritten.", zhHans: "撤销未完成。没有文件被覆盖。")
    /// `copy/auto-naming/label/evidence`
    static let copyAutoNamingLabelEvidence = LocalizedCopy(key: "copy/auto-naming/label/evidence", en: "Evidence", zhHans: "依据")
    /// `copy/auto-naming/label/original`
    static let copyAutoNamingLabelOriginal = LocalizedCopy(key: "copy/auto-naming/label/original", en: "Current name", zhHans: "当前名称")
    /// `copy/auto-naming/label/target`
    static let copyAutoNamingLabelTarget = LocalizedCopy(key: "copy/auto-naming/label/target", en: "Proposed name", zhHans: "建议名称")
    /// `copy/auto-naming/label/warnings`
    static let copyAutoNamingLabelWarnings = LocalizedCopy(key: "copy/auto-naming/label/warnings", en: "Warnings", zhHans: "警告")
    /// `copy/auto-naming/notice/applied`
    static let copyAutoNamingNoticeApplied = LocalizedCopy(key: "copy/auto-naming/notice/applied", en: "Selected files were renamed.", zhHans: "所选文件已重命名。")
    /// `copy/auto-naming/notice/cancelled`
    static let copyAutoNamingNoticeCancelled = LocalizedCopy(key: "copy/auto-naming/notice/cancelled", en: "Auto naming canceled.", zhHans: "已取消自动命名。")
    /// `copy/auto-naming/notice/no-files`
    static let copyAutoNamingNoticeNoFiles = LocalizedCopy(key: "copy/auto-naming/notice/no-files", en: "Choose at least one file.", zhHans: "请选择至少一个文件。")
    /// `copy/auto-naming/notice/no-results`
    static let copyAutoNamingNoticeNoResults = LocalizedCopy(key: "copy/auto-naming/notice/no-results", en: "No file could be analyzed.", zhHans: "没有可分析的文件。")
    /// `copy/auto-naming/notice/no-selection`
    static let copyAutoNamingNoticeNoSelection = LocalizedCopy(key: "copy/auto-naming/notice/no-selection", en: "Select at least one ready file.", zhHans: "请选择至少一个可重命名文件。")
    /// `copy/auto-naming/notice/partial-failure`
    static let copyAutoNamingNoticePartialFailure = LocalizedCopy(key: "copy/auto-naming/notice/partial-failure", en: "Some files were renamed. Review the failed items.", zhHans: "部分文件已重命名。请检查失败条目。")
    /// `copy/auto-naming/notice/partial-undo`
    static let copyAutoNamingNoticePartialUndo = LocalizedCopy(key: "copy/auto-naming/notice/partial-undo", en: "Some files were restored. Review the failed items.", zhHans: "部分文件已恢复。请检查失败条目。")
    /// `copy/auto-naming/notice/undone`
    static let copyAutoNamingNoticeUndone = LocalizedCopy(key: "copy/auto-naming/notice/undone", en: "The last rename run was undone.", zhHans: "已撤销上次重命名。")
    /// `copy/auto-naming/risk/conflict`
    static let copyAutoNamingRiskConflict = LocalizedCopy(key: "copy/auto-naming/risk/conflict", en: "Name conflict", zhHans: "名称冲突")
    /// `copy/auto-naming/risk/fallback`
    static let copyAutoNamingRiskFallback = LocalizedCopy(key: "copy/auto-naming/risk/fallback", en: "Fallback title", zhHans: "回退标题")
    /// `copy/auto-naming/risk/low-confidence`
    static let copyAutoNamingRiskLowConfidence = LocalizedCopy(key: "copy/auto-naming/risk/low-confidence", en: "Low confidence", zhHans: "低可信")
    /// `copy/auto-naming/risk/mixed`
    static let copyAutoNamingRiskMixed = LocalizedCopy(key: "copy/auto-naming/risk/mixed", en: "Mixed content", zhHans: "混合内容")
    /// `copy/auto-naming/risk/prompt-injection`
    static let copyAutoNamingRiskPromptInjection = LocalizedCopy(key: "copy/auto-naming/risk/prompt-injection", en: "Possible prompt injection", zhHans: "可能存在提示注入")
    /// `copy/auto-naming/risk/scanned`
    static let copyAutoNamingRiskScanned = LocalizedCopy(key: "copy/auto-naming/risk/scanned", en: "Scanned document", zhHans: "扫描件")
    /// `copy/auto-naming/risk/truncated`
    static let copyAutoNamingRiskTruncated = LocalizedCopy(key: "copy/auto-naming/risk/truncated", en: "Input truncated", zhHans: "输入已截断")
    /// `copy/auto-naming/status/blocked`
    static let copyAutoNamingStatusBlocked = LocalizedCopy(key: "copy/auto-naming/status/blocked", en: "Blocked", zhHans: "已阻止")
    /// `copy/auto-naming/status/failed`
    static let copyAutoNamingStatusFailed = LocalizedCopy(key: "copy/auto-naming/status/failed", en: "Failed", zhHans: "失败")
    /// `copy/auto-naming/status/ready`
    static let copyAutoNamingStatusReady = LocalizedCopy(key: "copy/auto-naming/status/ready", en: "Ready", zhHans: "可重命名")
    /// `copy/auto-naming/status/renamed`
    static let copyAutoNamingStatusRenamed = LocalizedCopy(key: "copy/auto-naming/status/renamed", en: "Renamed", zhHans: "已重命名")
    /// `copy/auto-naming/status/undone`
    static let copyAutoNamingStatusUndone = LocalizedCopy(key: "copy/auto-naming/status/undone", en: "Undone", zhHans: "已撤销")
    /// `copy/auto-naming/subtitle`
    static let copyAutoNamingSubtitle = LocalizedCopy(key: "copy/auto-naming/subtitle", en: "Files stay in their original folders. Review every proposed name before applying.", zhHans: "文件留在原目录。应用前请检查每个建议名称。")
    /// `copy/auto-naming/title`
    static let copyAutoNamingTitle = LocalizedCopy(key: "copy/auto-naming/title", en: "Review Auto Names", zhHans: "检查自动命名")
    /// `copy/battery/capacity-threshold`
    static let copyBatteryCapacityThreshold = LocalizedCopy(key: "copy/battery/capacity-threshold", en: "Capacity threshold", zhHans: "容量阈值")
    /// `copy/battery/enabled`
    static let copyBatteryEnabled = LocalizedCopy(key: "copy/battery/enabled", en: "Sleep at low battery", zhHans: "低电量时睡眠")
    /// `copy/battery/time-threshold`
    static let copyBatteryTimeThreshold = LocalizedCopy(key: "copy/battery/time-threshold", en: "Remaining time threshold", zhHans: "剩余时间阈值")
    /// `copy/battery/unit/minutes`
    static let copyBatteryUnitMinutes = LocalizedCopy(key: "copy/battery/unit/minutes", en: "minutes", zhHans: "分钟")
    /// `copy/battery/unit/percent`
    static let copyBatteryUnitPercent = LocalizedCopy(key: "copy/battery/unit/percent", en: "percent", zhHans: "百分比")
    /// `copy/clipboard/action/clear`
    static let copyClipboardActionClear = LocalizedCopy(key: "copy/clipboard/action/clear", en: "Clear All", zhHans: "全部清除")
    /// `copy/clipboard/action/open-settings`
    static let copyClipboardActionOpenSettings = LocalizedCopy(key: "copy/clipboard/action/open-settings", en: "Open System Settings", zhHans: "打开系统设置")
    /// `copy/clipboard/action/paste`
    static let copyClipboardActionPaste = LocalizedCopy(key: "copy/clipboard/action/paste", en: "Paste", zhHans: "粘贴")
    /// `copy/clipboard/action/pin`
    static let copyClipboardActionPin = LocalizedCopy(key: "copy/clipboard/action/pin", en: "Pin", zhHans: "置顶")
    /// `copy/clipboard/action/remove`
    static let copyClipboardActionRemove = LocalizedCopy(key: "copy/clipboard/action/remove", en: "Remove", zhHans: "删除")
    /// `copy/clipboard/action/unpin`
    static let copyClipboardActionUnpin = LocalizedCopy(key: "copy/clipboard/action/unpin", en: "Unpin", zhHans: "取消置顶")
    /// `copy/clipboard/action/workspace`
    static let copyClipboardActionWorkspace = LocalizedCopy(key: "copy/clipboard/action/workspace", en: "Save to Workspace", zhHans: "存入工作区")
    /// `copy/clipboard/empty`
    static let copyClipboardEmpty = LocalizedCopy(key: "copy/clipboard/empty", en: "Nothing copied yet", zhHans: "还没有复制内容")
    /// `copy/clipboard/error/accessibility`
    static let copyClipboardErrorAccessibility = LocalizedCopy(key: "copy/clipboard/error/accessibility", en: "Paste needs Accessibility permission.", zhHans: "粘贴回填需要辅助功能权限。")
    /// `copy/clipboard/error/hot-key`
    static let copyClipboardErrorHotKey = LocalizedCopy(key: "copy/clipboard/error/hot-key", en: "This shortcut is already taken.", zhHans: "这个快捷键已被占用。")
    /// `copy/clipboard/error/image`
    static let copyClipboardErrorImage = LocalizedCopy(key: "copy/clipboard/error/image", en: "Cannot save the image.", zhHans: "无法保存图片。")
    /// `copy/clipboard/error/paste`
    static let copyClipboardErrorPaste = LocalizedCopy(key: "copy/clipboard/error/paste", en: "Cannot paste into the front app.", zhHans: "无法粘贴到前台应用。")
    /// `copy/clipboard/settings/accessibility`
    static let copyClipboardSettingsAccessibility = LocalizedCopy(key: "copy/clipboard/settings/accessibility", en: "Accessibility permission", zhHans: "辅助功能权限")
    /// `copy/clipboard/settings/accessibility-fallback`
    static let copyClipboardSettingsAccessibilityFallback = LocalizedCopy(key: "copy/clipboard/settings/accessibility-fallback", en: "Copying still works. Without this permission Covio cannot press ⌘V for you.", zhHans: "复制仍然可用。没有这个权限时 Covio 不能替你按 ⌘V。")
    /// `copy/clipboard/settings/capture-hot-key`
    static let copyClipboardSettingsCaptureHotKey = LocalizedCopy(key: "copy/clipboard/settings/capture-hot-key", en: "Capture selection", zhHans: "抓取选中内容")
    /// `copy/clipboard/settings/enabled`
    static let copyClipboardSettingsEnabled = LocalizedCopy(key: "copy/clipboard/settings/enabled", en: "Record clipboard history", zhHans: "记录剪切板历史")
    /// `copy/clipboard/settings/granted`
    static let copyClipboardSettingsGranted = LocalizedCopy(key: "copy/clipboard/settings/granted", en: "Granted", zhHans: "已授权")
    /// `copy/clipboard/settings/hot-key-conflict`
    static let copyClipboardSettingsHotKeyConflict = LocalizedCopy(key: "copy/clipboard/settings/hot-key-conflict", en: "Registration failed. Another app owns this shortcut. Pick another one.", zhHans: "注册失败。这个快捷键被别的应用占用了，换一个。")
    /// `copy/clipboard/settings/hot-keys`
    static let copyClipboardSettingsHotKeys = LocalizedCopy(key: "copy/clipboard/settings/hot-keys", en: "Shortcuts", zhHans: "快捷键")
    /// `copy/clipboard/settings/not-granted`
    static let copyClipboardSettingsNotGranted = LocalizedCopy(key: "copy/clipboard/settings/not-granted", en: "Not granted", zhHans: "未授权")
    /// `copy/clipboard/settings/paste-stack-hot-key`
    static let copyClipboardSettingsPasteStackHotKey = LocalizedCopy(key: "copy/clipboard/settings/paste-stack-hot-key", en: "Paste next from stack", zhHans: "粘贴栈的下一条")
    /// `copy/clipboard/settings/request-permission`
    static let copyClipboardSettingsRequestPermission = LocalizedCopy(key: "copy/clipboard/settings/request-permission", en: "Request Permission", zhHans: "申请权限")
    /// `copy/clipboard/state/pause`
    static let copyClipboardStatePause = LocalizedCopy(key: "copy/clipboard/state/pause", en: "Pause", zhHans: "暂停记录")
    /// `copy/clipboard/state/paused`
    static let copyClipboardStatePaused = LocalizedCopy(key: "copy/clipboard/state/paused", en: "Recording paused", zhHans: "已暂停记录")
    /// `copy/clipboard/state/resume`
    static let copyClipboardStateResume = LocalizedCopy(key: "copy/clipboard/state/resume", en: "Resume", zhHans: "继续记录")
    /// `copy/clipboard/title`
    static let copyClipboardTitle = LocalizedCopy(key: "copy/clipboard/title", en: "Clipboard", zhHans: "剪切板")
    /// `copy/component/material/blur`
    static let copyComponentMaterialBlur = LocalizedCopy(key: "copy/component/material/blur", en: "Blur", zhHans: "模糊")
    /// `copy/component/material/medium`
    static let copyComponentMaterialMedium = LocalizedCopy(key: "copy/component/material/medium", en: "Medium", zhHans: "中")
    /// `copy/component/material/thick`
    static let copyComponentMaterialThick = LocalizedCopy(key: "copy/component/material/thick", en: "Thick", zhHans: "厚")
    /// `copy/component/material/thin`
    static let copyComponentMaterialThin = LocalizedCopy(key: "copy/component/material/thin", en: "Thin", zhHans: "薄")
    /// `copy/component/material/ultra-thick`
    static let copyComponentMaterialUltraThick = LocalizedCopy(key: "copy/component/material/ultra-thick", en: "Ultra Thick", zhHans: "超厚")
    /// `copy/component/material/ultra-thin`
    static let copyComponentMaterialUltraThin = LocalizedCopy(key: "copy/component/material/ultra-thin", en: "Ultra Thin", zhHans: "超薄")
    /// `copy/component/popover/bottom`
    static let copyComponentPopoverBottom = LocalizedCopy(key: "copy/component/popover/bottom", en: "Bottom", zhHans: "底部")
    /// `copy/component/popover/custom`
    static let copyComponentPopoverCustom = LocalizedCopy(key: "copy/component/popover/custom", en: "Custom", zhHans: "自定义")
    /// `copy/component/popover/form`
    static let copyComponentPopoverForm = LocalizedCopy(key: "copy/component/popover/form", en: "Form", zhHans: "表单")
    /// `copy/component/popover/menu`
    static let copyComponentPopoverMenu = LocalizedCopy(key: "copy/component/popover/menu", en: "Menu", zhHans: "菜单")
    /// `copy/component/popover/top`
    static let copyComponentPopoverTop = LocalizedCopy(key: "copy/component/popover/top", en: "Top", zhHans: "顶部")
    /// `copy/component/toolbar/compact`
    static let copyComponentToolbarCompact = LocalizedCopy(key: "copy/component/toolbar/compact", en: "Compact", zhHans: "紧凑")
    /// `copy/component/toolbar/default`
    static let copyComponentToolbarDefault = LocalizedCopy(key: "copy/component/toolbar/default", en: "Default", zhHans: "默认")
    /// `copy/component/window-shell/compact`
    static let copyComponentWindowShellCompact = LocalizedCopy(key: "copy/component/window-shell/compact", en: "Compact", zhHans: "紧凑")
    /// `copy/component/window-shell/sidebar`
    static let copyComponentWindowShellSidebar = LocalizedCopy(key: "copy/component/window-shell/sidebar", en: "Sidebar", zhHans: "侧边栏")
    /// `copy/component/window-shell/standard`
    static let copyComponentWindowShellStandard = LocalizedCopy(key: "copy/component/window-shell/standard", en: "Standard", zhHans: "标准")
    /// `copy/component/window-shell/toolbar`
    static let copyComponentWindowShellToolbar = LocalizedCopy(key: "copy/component/window-shell/toolbar", en: "Toolbar", zhHans: "工具栏")
    /// `copy/dialog/helper-install/body`
    static let copyDialogHelperInstallBody = LocalizedCopy(key: "copy/dialog/helper-install/body", en: "Covio needs the helper for sleep control.", zhHans: "Covio 需要助手来控制睡眠。")
    /// `copy/dialog/helper-install/title`
    static let copyDialogHelperInstallTitle = LocalizedCopy(key: "copy/dialog/helper-install/title", en: "Install helper", zhHans: "安装助手")
    /// `copy/dialog/helper-unavailable/body`
    static let copyDialogHelperUnavailableBody = LocalizedCopy(key: "copy/dialog/helper-unavailable/body", en: "Start the helper, then try again.", zhHans: "启动助手，然后重试。")
    /// `copy/dialog/helper-unavailable/title`
    static let copyDialogHelperUnavailableTitle = LocalizedCopy(key: "copy/dialog/helper-unavailable/title", en: "Helper unavailable", zhHans: "助手不可用")
    /// `copy/dialog/reset/body`
    static let copyDialogResetBody = LocalizedCopy(key: "copy/dialog/reset/body", en: "This action removes all local Covio settings.", zhHans: "此操作会删除全部本地 Covio 设置。")
    /// `copy/dialog/reset/title`
    static let copyDialogResetTitle = LocalizedCopy(key: "copy/dialog/reset/title", en: "Clear configuration?", zhHans: "清除配置？")
    /// `copy/dialog/update/body`
    static let copyDialogUpdateBody = LocalizedCopy(key: "copy/dialog/update/body", en: "A new Covio version is ready.", zhHans: "新的 Covio 版本已就绪。")
    /// `copy/dialog/update/title`
    static let copyDialogUpdateTitle = LocalizedCopy(key: "copy/dialog/update/title", en: "Update available", zhHans: "有可用更新")
    /// `copy/general/check-updates`
    static let copyGeneralCheckUpdates = LocalizedCopy(key: "copy/general/check-updates", en: "Check for updates", zhHans: "检查更新")
    /// `copy/general/clear-config`
    static let copyGeneralClearConfig = LocalizedCopy(key: "copy/general/clear-config", en: "Clear Configuration…", zhHans: "清除配置…")
    /// `copy/general/darkwake`
    static let copyGeneralDarkwake = LocalizedCopy(key: "copy/general/darkwake", en: "DarkWake awareness", zhHans: "DarkWake 感知")
    /// `copy/general/language`
    static let copyGeneralLanguage = LocalizedCopy(key: "copy/general/language", en: "Language", zhHans: "语言")
    /// `copy/general/language/chinese`
    static let copyGeneralLanguageChinese = LocalizedCopy(key: "copy/general/language/chinese", en: "Simplified Chinese", zhHans: "简体中文")
    /// `copy/general/language/english`
    static let copyGeneralLanguageEnglish = LocalizedCopy(key: "copy/general/language/english", en: "English", zhHans: "English")
    /// `copy/general/launch-at-login`
    static let copyGeneralLaunchAtLogin = LocalizedCopy(key: "copy/general/launch-at-login", en: "Launch at login", zhHans: "登录时启动")
    /// `copy/general/notifications`
    static let copyGeneralNotifications = LocalizedCopy(key: "copy/general/notifications", en: "Notifications", zhHans: "通知")
    /// `copy/general/sleep-mode`
    static let copyGeneralSleepMode = LocalizedCopy(key: "copy/general/sleep-mode", en: "Sleep mode", zhHans: "睡眠模式")
    /// `copy/general/sleep-mode/default`
    static let copyGeneralSleepModeDefault = LocalizedCopy(key: "copy/general/sleep-mode/default", en: "3 · Default", zhHans: "3 · 默认")
    /// `copy/general/sleep-mode/fastest`
    static let copyGeneralSleepModeFastest = LocalizedCopy(key: "copy/general/sleep-mode/fastest", en: "0 · Fastest", zhHans: "0 · 最快")
    /// `copy/general/sleep-mode/lowest-power`
    static let copyGeneralSleepModeLowestPower = LocalizedCopy(key: "copy/general/sleep-mode/lowest-power", en: "25 · Lowest power", zhHans: "25 · 最省电")
    /// `copy/hub/action/back`
    static let copyHubActionBack = LocalizedCopy(key: "copy/hub/action/back", en: "Back", zhHans: "返回")
    /// `copy/hub/action/done`
    static let copyHubActionDone = LocalizedCopy(key: "copy/hub/action/done", en: "Done", zhHans: "完成")
    /// `copy/hub/action/edit`
    static let copyHubActionEdit = LocalizedCopy(key: "copy/hub/action/edit", en: "Edit", zhHans: "编辑")
    /// `copy/hub/action/home`
    static let copyHubActionHome = LocalizedCopy(key: "copy/hub/action/home", en: "Home", zhHans: "首页")
    /// `copy/hub/action/settings`
    static let copyHubActionSettings = LocalizedCopy(key: "copy/hub/action/settings", en: "Settings", zhHans: "设置")
    /// `copy/hub/edit/banner`
    static let copyHubEditBanner = LocalizedCopy(key: "copy/hub/edit/banner", en: "Edit mode: drag tabs to reorder, drag cards to move, drag the corner to resize, click the cross to remove.", zhHans: "编辑模式：拖动页签排序，拖动卡片移动，拖右下角缩放，点叉删除。")
    /// `copy/hub/edit/reorder`
    static let copyHubEditReorder = LocalizedCopy(key: "copy/hub/edit/reorder", en: "Reorder", zhHans: "排序")
    /// `copy/hub/edit/widget-count`
    static let copyHubEditWidgetCount = LocalizedCopy(key: "copy/hub/edit/widget-count", en: "widgets", zhHans: "块组件")
    /// `copy/hub/edit/workspace-count`
    static let copyHubEditWorkspaceCount = LocalizedCopy(key: "copy/hub/edit/workspace-count", en: "workspaces", zhHans: "个工作区")
    /// `copy/hub/files/action/add`
    static let copyHubFilesActionAdd = LocalizedCopy(key: "copy/hub/files/action/add", en: "Add…", zhHans: "加入…")
    /// `copy/hub/files/action/cancel-transfer`
    static let copyHubFilesActionCancelTransfer = LocalizedCopy(key: "copy/hub/files/action/cancel-transfer", en: "Cancel Transfer", zhHans: "取消传输")
    /// `copy/hub/files/action/clear-filter`
    static let copyHubFilesActionClearFilter = LocalizedCopy(key: "copy/hub/files/action/clear-filter", en: "Clear Filter", zhHans: "清除筛选")
    /// `copy/hub/files/action/copy`
    static let copyHubFilesActionCopy = LocalizedCopy(key: "copy/hub/files/action/copy", en: "Copy", zhHans: "复制")
    /// `copy/hub/files/action/copy-text`
    static let copyHubFilesActionCopyText = LocalizedCopy(key: "copy/hub/files/action/copy-text", en: "Copy Text", zhHans: "复制正文")
    /// `copy/hub/files/action/download`
    static let copyHubFilesActionDownload = LocalizedCopy(key: "copy/hub/files/action/download", en: "Download", zhHans: "下载")
    /// `copy/hub/files/action/import`
    static let copyHubFilesActionImport = LocalizedCopy(key: "copy/hub/files/action/import", en: "Import Files…", zhHans: "放入文件…")
    /// `copy/hub/files/action/markup`
    static let copyHubFilesActionMarkup = LocalizedCopy(key: "copy/hub/files/action/markup", en: "Mark Up", zhHans: "标注")
    /// `copy/hub/files/action/more`
    static let copyHubFilesActionMore = LocalizedCopy(key: "copy/hub/files/action/more", en: "More", zhHans: "更多")
    /// `copy/hub/files/action/new-text`
    static let copyHubFilesActionNewText = LocalizedCopy(key: "copy/hub/files/action/new-text", en: "New Text…", zhHans: "新建文本…")
    /// `copy/hub/files/action/open`
    static let copyHubFilesActionOpen = LocalizedCopy(key: "copy/hub/files/action/open", en: "Open", zhHans: "打开")
    /// `copy/hub/files/action/pin`
    static let copyHubFilesActionPin = LocalizedCopy(key: "copy/hub/files/action/pin", en: "Pin", zhHans: "置顶")
    /// `copy/hub/files/action/remove`
    static let copyHubFilesActionRemove = LocalizedCopy(key: "copy/hub/files/action/remove", en: "Remove", zhHans: "删除")
    /// `copy/hub/files/action/retry`
    static let copyHubFilesActionRetry = LocalizedCopy(key: "copy/hub/files/action/retry", en: "Retry", zhHans: "重试")
    /// `copy/hub/files/action/reveal`
    static let copyHubFilesActionReveal = LocalizedCopy(key: "copy/hub/files/action/reveal", en: "Show in Finder", zhHans: "在访达中显示")
    /// `copy/hub/files/action/save-to-workspace`
    static let copyHubFilesActionSaveToWorkspace = LocalizedCopy(key: "copy/hub/files/action/save-to-workspace", en: "Save to Workspace", zhHans: "存入工作区")
    /// `copy/hub/files/action/sweep`
    static let copyHubFilesActionSweep = LocalizedCopy(key: "copy/hub/files/action/sweep", en: "Clean Up", zhHans: "清理过期")
    /// `copy/hub/files/action/unpin`
    static let copyHubFilesActionUnpin = LocalizedCopy(key: "copy/hub/files/action/unpin", en: "Unpin", zhHans: "取消置顶")
    /// `copy/hub/files/count/items`
    static let copyHubFilesCountItems = LocalizedCopy(key: "copy/hub/files/count/items", en: "items", zhHans: "项")
    /// `copy/hub/files/empty`
    static let copyHubFilesEmpty = LocalizedCopy(key: "copy/hub/files/empty", en: "The workspace is empty", zhHans: "工作区还是空的")
    /// `copy/hub/files/empty/hint`
    static let copyHubFilesEmptyHint = LocalizedCopy(key: "copy/hub/files/empty/hint", en: "Screenshots, files, and text stay in recent use.", zhHans: "截图、文件或文本会停在最近使用的位置。")
    /// `copy/hub/files/empty/title`
    static let copyHubFilesEmptyTitle = LocalizedCopy(key: "copy/hub/files/empty/title", en: "Drop the next item here", zhHans: "把下一件内容放进来")
    /// `copy/hub/files/error/import`
    static let copyHubFilesErrorImport = LocalizedCopy(key: "copy/hub/files/error/import", en: "Cannot read this file.", zhHans: "读不到这个文件。")
    /// `copy/hub/files/error/missing`
    static let copyHubFilesErrorMissing = LocalizedCopy(key: "copy/hub/files/error/missing", en: "This device no longer has the content.", zhHans: "本机已经没有这份内容。")
    /// `copy/hub/files/error/quota`
    static let copyHubFilesErrorQuota = LocalizedCopy(key: "copy/hub/files/error/quota", en: "The workspace is full. Remove an entry or raise the limit.", zhHans: "工作区已满。删除一些条目，或调高上限。")
    /// `copy/hub/files/error/save`
    static let copyHubFilesErrorSave = LocalizedCopy(key: "copy/hub/files/error/save", en: "Cannot write to the workspace.", zhHans: "写不进工作区。")
    /// `copy/hub/files/error/too-large`
    static let copyHubFilesErrorTooLarge = LocalizedCopy(key: "copy/hub/files/error/too-large", en: "This file is over the single entry limit.", zhHans: "这个文件超过单条目上限。")
    /// `copy/hub/files/filter/all`
    static let copyHubFilesFilterAll = LocalizedCopy(key: "copy/hub/files/filter/all", en: "All", zhHans: "全部")
    /// `copy/hub/files/filter/files`
    static let copyHubFilesFilterFiles = LocalizedCopy(key: "copy/hub/files/filter/files", en: "Files", zhHans: "文件")
    /// `copy/hub/files/filter/screenshots`
    static let copyHubFilesFilterScreenshots = LocalizedCopy(key: "copy/hub/files/filter/screenshots", en: "Screenshots", zhHans: "截图")
    /// `copy/hub/files/filter/text`
    static let copyHubFilesFilterText = LocalizedCopy(key: "copy/hub/files/filter/text", en: "Text", zhHans: "文本")
    /// `copy/hub/files/filter/transfers`
    static let copyHubFilesFilterTransfers = LocalizedCopy(key: "copy/hub/files/filter/transfers", en: "Transfers", zhHans: "传输")
    /// `copy/hub/files/hint`
    static let copyHubFilesHint = LocalizedCopy(key: "copy/hub/files/hint", en: "Drop files here, or use Import Files.", zhHans: "把文件拖到这里，或点「放入文件」。")
    /// `copy/hub/files/no-match/hint`
    static let copyHubFilesNoMatchHint = LocalizedCopy(key: "copy/hub/files/no-match/hint", en: "Try another keyword or clear the current filter.", zhHans: "换一个关键词，或清除当前筛选。")
    /// `copy/hub/files/no-match/title`
    static let copyHubFilesNoMatchTitle = LocalizedCopy(key: "copy/hub/files/no-match/title", en: "No matching files", zhHans: "没有匹配的文件")
    /// `copy/hub/files/notice/duplicate`
    static let copyHubFilesNoticeDuplicate = LocalizedCopy(key: "copy/hub/files/notice/duplicate", en: "The workspace already has this content.", zhHans: "工作区里已经有这份内容。")
    /// `copy/hub/files/notice/saved`
    static let copyHubFilesNoticeSaved = LocalizedCopy(key: "copy/hub/files/notice/saved", en: "Saved to the workspace.", zhHans: "已存入工作区。")
    /// `copy/hub/files/notice/swept`
    static let copyHubFilesNoticeSwept = LocalizedCopy(key: "copy/hub/files/notice/swept", en: "Removed expired entries.", zhHans: "已清理过期条目。")
    /// `copy/hub/files/state/fetching`
    static let copyHubFilesStateFetching = LocalizedCopy(key: "copy/hub/files/state/fetching", en: "Retrieving", zhHans: "正在取回")
    /// `copy/hub/files/state/local`
    static let copyHubFilesStateLocal = LocalizedCopy(key: "copy/hub/files/state/local", en: "Available on this Mac", zhHans: "本机可用")
    /// `copy/hub/files/state/on-other-device`
    static let copyHubFilesStateOnOtherDevice = LocalizedCopy(key: "copy/hub/files/state/on-other-device", en: "On another device", zhHans: "在另一台设备")
    /// `copy/hub/files/state/transfer-failed`
    static let copyHubFilesStateTransferFailed = LocalizedCopy(key: "copy/hub/files/state/transfer-failed", en: "Transfer failed", zhHans: "传输失败")
    /// `copy/hub/files/state/unavailable`
    static let copyHubFilesStateUnavailable = LocalizedCopy(key: "copy/hub/files/state/unavailable", en: "Content unavailable", zhHans: "内容不可用")
    /// `copy/hub/files/status/active`
    static let copyHubFilesStatusActive = LocalizedCopy(key: "copy/hub/files/status/active", en: "active", zhHans: "进行中")
    /// `copy/hub/files/usage`
    static let copyHubFilesUsage = LocalizedCopy(key: "copy/hub/files/usage", en: "In use", zhHans: "已占用")
    /// `copy/hub/home/empty-hint`
    static let copyHubHomeEmptyHint = LocalizedCopy(key: "copy/hub/home/empty-hint", en: "Turn on edit mode to add widgets.", zhHans: "进入编辑模式可以添加组件。")
    /// `copy/hub/home/empty-hint-editing`
    static let copyHubHomeEmptyHintEditing = LocalizedCopy(key: "copy/hub/home/empty-hint-editing", en: "Drag one in from the widget library.", zhHans: "从组件库里拖一块进来。")
    /// `copy/hub/home/empty-title`
    static let copyHubHomeEmptyTitle = LocalizedCopy(key: "copy/hub/home/empty-title", en: "No widgets yet", zhHans: "首页还没有组件")
    /// `copy/hub/log/export`
    static let copyHubLogExport = LocalizedCopy(key: "copy/hub/log/export", en: "Export Log…", zhHans: "导出日志…")
    /// `copy/hub/log/view`
    static let copyHubLogView = LocalizedCopy(key: "copy/hub/log/view", en: "View Log", zhHans: "查看日志")
    /// `copy/hub/placeholder-notice`
    static let copyHubPlaceholderNotice = LocalizedCopy(key: "copy/hub/placeholder-notice", en: "This tab is a placeholder. Content lands in a later phase.", zhHans: "本页签是占位。内容在后续阶段落地。")
    /// `copy/hub/tab/agent`
    static let copyHubTabAgent = LocalizedCopy(key: "copy/hub/tab/agent", en: "Agent", zhHans: "助手")
    /// `copy/hub/tab/agent/summary`
    static let copyHubTabAgentSummary = LocalizedCopy(key: "copy/hub/tab/agent/summary", en: "Chat with the offline local agent and its local services.", zhHans: "与离线本地 Agent 对话并使用本地服务。")
    /// `copy/hub/tab/board`
    static let copyHubTabBoard = LocalizedCopy(key: "copy/hub/tab/board", en: "Custom", zhHans: "自建")
    /// `copy/hub/tab/board/summary`
    static let copyHubTabBoardSummary = LocalizedCopy(key: "copy/hub/tab/board/summary", en: "A custom workspace with just the widget grid.", zhHans: "自建工作区，只有组件网格。")
    /// `copy/hub/tab/clipboard`
    static let copyHubTabClipboard = LocalizedCopy(key: "copy/hub/tab/clipboard", en: "Clipboard", zhHans: "剪贴板")
    /// `copy/hub/tab/clipboard/summary`
    static let copyHubTabClipboardSummary = LocalizedCopy(key: "copy/hub/tab/clipboard/summary", en: "Recent text, images, and files.", zhHans: "最近文本、图片和文件列表。")
    /// `copy/hub/tab/devices`
    static let copyHubTabDevices = LocalizedCopy(key: "copy/hub/tab/devices", en: "Monitor", zhHans: "监控")
    /// `copy/hub/tab/devices/summary`
    static let copyHubTabDevicesSummary = LocalizedCopy(key: "copy/hub/tab/devices/summary", en: "Live CPU, GPU, memory, disk, network, and power metrics.", zhHans: "CPU、GPU、内存、磁盘、网络和电源的实时指标。")
    /// `copy/hub/tab/files`
    static let copyHubTabFiles = LocalizedCopy(key: "copy/hub/tab/files", en: "Files", zhHans: "文件")
    /// `copy/hub/tab/files/summary`
    static let copyHubTabFilesSummary = LocalizedCopy(key: "copy/hub/tab/files/summary", en: "Temporary files, free space, and expiry.", zhHans: "临时文件、剩余空间和过期时间。")
    /// `copy/hub/tab/now`
    static let copyHubTabNow = LocalizedCopy(key: "copy/hub/tab/now", en: "Now", zhHans: "现在")
    /// `copy/hub/tab/now/summary`
    static let copyHubTabNowSummary = LocalizedCopy(key: "copy/hub/tab/now/summary", en: "Power, battery, lid, device links, and pending items.", zhHans: "电源、电池、合盖、设备连接和待处理项。")
    /// `copy/hub/tab/screenshots`
    static let copyHubTabScreenshots = LocalizedCopy(key: "copy/hub/tab/screenshots", en: "Screenshots", zhHans: "截图")
    /// `copy/hub/tab/screenshots/summary`
    static let copyHubTabScreenshotsSummary = LocalizedCopy(key: "copy/hub/tab/screenshots/summary", en: "Recent screenshots and the capture toolbar.", zhHans: "最近截图和截图工具栏。")
    /// `copy/hub/tab/settings`
    static let copyHubTabSettings = LocalizedCopy(key: "copy/hub/tab/settings", en: "Settings", zhHans: "设置")
    /// `copy/hub/tab/settings/summary`
    static let copyHubTabSettingsSummary = LocalizedCopy(key: "copy/hub/tab/settings/summary", en: "Permissions, language, notifications, privacy, and retention.", zhHans: "权限、语言、通知、隐私和保留策略。")
    /// `copy/hub/update/up-to-date`
    static let copyHubUpdateUpToDate = LocalizedCopy(key: "copy/hub/update/up-to-date", en: "Covio is up to date.", zhHans: "Covio 已是最新版本。")
    /// `copy/hub/widget/actions/title`
    static let copyHubWidgetActionsTitle = LocalizedCopy(key: "copy/hub/widget/actions/title", en: "Shortcuts", zhHans: "快捷操作")
    /// `copy/hub/widget/battery/title`
    static let copyHubWidgetBatteryTitle = LocalizedCopy(key: "copy/hub/widget/battery/title", en: "Battery", zhHans: "电量")
    /// `copy/hub/widget/clock/title`
    static let copyHubWidgetClockTitle = LocalizedCopy(key: "copy/hub/widget/clock/title", en: "Now", zhHans: "现在")
    /// `copy/hub/widget/devices/title`
    static let copyHubWidgetDevicesTitle = LocalizedCopy(key: "copy/hub/widget/devices/title", en: "Monitor", zhHans: "监控")
    /// `copy/hub/widget/remove`
    static let copyHubWidgetRemove = LocalizedCopy(key: "copy/hub/widget/remove", en: "Remove", zhHans: "删除")
    /// `copy/hub/widget/resize`
    static let copyHubWidgetResize = LocalizedCopy(key: "copy/hub/widget/resize", en: "Resize", zhHans: "缩放")
    /// `copy/hub/widget/shots/title`
    static let copyHubWidgetShotsTitle = LocalizedCopy(key: "copy/hub/widget/shots/title", en: "Recent Shots", zhHans: "最近截图")
    /// `copy/hub/widget/size/large`
    static let copyHubWidgetSizeLarge = LocalizedCopy(key: "copy/hub/widget/size/large", en: "Large", zhHans: "大")
    /// `copy/hub/widget/size/small`
    static let copyHubWidgetSizeSmall = LocalizedCopy(key: "copy/hub/widget/size/small", en: "Small", zhHans: "小")
    /// `copy/hub/widget/size/tall`
    static let copyHubWidgetSizeTall = LocalizedCopy(key: "copy/hub/widget/size/tall", en: "Tall", zhHans: "高")
    /// `copy/hub/widget/size/wide`
    static let copyHubWidgetSizeWide = LocalizedCopy(key: "copy/hub/widget/size/wide", en: "Wide", zhHans: "宽")
    /// `copy/hub/widget/transfer/title`
    static let copyHubWidgetTransferTitle = LocalizedCopy(key: "copy/hub/widget/transfer/title", en: "Transfers", zhHans: "传输")
    /// `copy/icon/concept/blue-grid`
    static let copyIconConceptBlueGrid = LocalizedCopy(key: "copy/icon/concept/blue-grid", en: "05 · BLUE GRID", zhHans: "05 · 蓝色网格")
    /// `copy/icon/concept/blue-koala`
    static let copyIconConceptBlueKoala = LocalizedCopy(key: "copy/icon/concept/blue-koala", en: "00 · BLUE KOALA", zhHans: "00 · 蓝色考拉")
    /// `copy/icon/concept/blue-orbit`
    static let copyIconConceptBlueOrbit = LocalizedCopy(key: "copy/icon/concept/blue-orbit", en: "01 · BLUE ORBIT", zhHans: "01 · 蓝色轨道")
    /// `copy/icon/concept/notch-core`
    static let copyIconConceptNotchCore = LocalizedCopy(key: "copy/icon/concept/notch-core", en: "02 · NOTCH CORE", zhHans: "02 · 刘海核心")
    /// `copy/icon/concept/status-pulse`
    static let copyIconConceptStatusPulse = LocalizedCopy(key: "copy/icon/concept/status-pulse", en: "04 · STATUS PULSE", zhHans: "04 · 状态脉冲")
    /// `copy/icon/concept/top-shelf`
    static let copyIconConceptTopShelf = LocalizedCopy(key: "copy/icon/concept/top-shelf", en: "03 · TOP SHELF", zhHans: "03 · 顶部挂架")
    /// `copy/idle/cancel-after`
    static let copyIdleCancelAfter = LocalizedCopy(key: "copy/idle/cancel-after", en: "Cancel after", zhHans: "在此时间后取消")
    /// `copy/idle/prevent-idle`
    static let copyIdlePreventIdle = LocalizedCopy(key: "copy/idle/prevent-idle", en: "Prevent idle sleep", zhHans: "阻止闲置睡眠")
    /// `copy/idle/remaining`
    static let copyIdleRemaining = LocalizedCopy(key: "copy/idle/remaining", en: "Remaining time", zhHans: "剩余时间")
    /// `copy/idle/while-charging`
    static let copyIdleWhileCharging = LocalizedCopy(key: "copy/idle/while-charging", en: "Prevent sleep while charging", zhHans: "充电时阻止睡眠")
    /// `copy/lid/battery-rules`
    static let copyLidBatteryRules = LocalizedCopy(key: "copy/lid/battery-rules", en: "Battery rules", zhHans: "电池规则")
    /// `copy/lid/instant-sleep`
    static let copyLidInstantSleep = LocalizedCopy(key: "copy/lid/instant-sleep", en: "Sleep immediately when the lid closes", zhHans: "合盖后立即睡眠")
    /// `copy/lid/power-rules`
    static let copyLidPowerRules = LocalizedCopy(key: "copy/lid/power-rules", en: "Power rules", zhHans: "接电源规则")
    /// `copy/lid/prevent-sleep`
    static let copyLidPreventSleep = LocalizedCopy(key: "copy/lid/prevent-sleep", en: "Prevent sleep after the lid closes", zhHans: "合盖后阻止睡眠")
    /// `copy/lid/warning`
    static let copyLidWarning = LocalizedCopy(key: "copy/lid/warning", en: "Warning: this option increases battery drain.", zhHans: "警告：此选项会增加电池耗电。")
    /// `copy/macos27-alignment/measurement`
    static let copyMacos27AlignmentMeasurement = LocalizedCopy(key: "copy/macos27-alignment/measurement", en: "Measurement Comparison", zhHans: "测量值对照")
    /// `copy/macos27-alignment/static-verified`
    static let copyMacos27AlignmentStaticVerified = LocalizedCopy(key: "copy/macos27-alignment/static-verified", en: "Static verified", zhHans: "静态已验证")
    /// `copy/mode/dark`
    static let copyModeDark = LocalizedCopy(key: "copy/mode/dark", en: "Dark", zhHans: "深色")
    /// `copy/mode/light`
    static let copyModeLight = LocalizedCopy(key: "copy/mode/light", en: "Light", zhHans: "浅色")
    /// `copy/monitor/battery/remaining`
    static let copyMonitorBatteryRemaining = LocalizedCopy(key: "copy/monitor/battery/remaining", en: "Remaining", zhHans: "剩余")
    /// `copy/monitor/battery/source`
    static let copyMonitorBatterySource = LocalizedCopy(key: "copy/monitor/battery/source", en: "Source", zhHans: "电源")
    /// `copy/monitor/battery/state`
    static let copyMonitorBatteryState = LocalizedCopy(key: "copy/monitor/battery/state", en: "State", zhHans: "状态")
    /// `copy/monitor/cores`
    static let copyMonitorCores = LocalizedCopy(key: "copy/monitor/cores", en: "Cores", zhHans: "核心")
    /// `copy/monitor/disk/free`
    static let copyMonitorDiskFree = LocalizedCopy(key: "copy/monitor/disk/free", en: "Free", zhHans: "可用")
    /// `copy/monitor/disk/read`
    static let copyMonitorDiskRead = LocalizedCopy(key: "copy/monitor/disk/read", en: "Read", zhHans: "读取")
    /// `copy/monitor/disk/used`
    static let copyMonitorDiskUsed = LocalizedCopy(key: "copy/monitor/disk/used", en: "Used", zhHans: "已用")
    /// `copy/monitor/disk/write`
    static let copyMonitorDiskWrite = LocalizedCopy(key: "copy/monitor/disk/write", en: "Write", zhHans: "写入")
    /// `copy/monitor/gpu/device`
    static let copyMonitorGpuDevice = LocalizedCopy(key: "copy/monitor/gpu/device", en: "Device", zhHans: "设备")
    /// `copy/monitor/gpu/memory`
    static let copyMonitorGpuMemory = LocalizedCopy(key: "copy/monitor/gpu/memory", en: "Memory in use", zhHans: "已用显存")
    /// `copy/monitor/history`
    static let copyMonitorHistory = LocalizedCopy(key: "copy/monitor/history", en: "60 samples", zhHans: "60 个采样")
    /// `copy/monitor/live`
    static let copyMonitorLive = LocalizedCopy(key: "copy/monitor/live", en: "Live", zhHans: "实时")
    /// `copy/monitor/load1`
    static let copyMonitorLoad1 = LocalizedCopy(key: "copy/monitor/load1", en: "Load 1m", zhHans: "1 分钟负载")
    /// `copy/monitor/memory-pressure/critical`
    static let copyMonitorMemoryPressureCritical = LocalizedCopy(key: "copy/monitor/memory-pressure/critical", en: "Critical", zhHans: "紧急")
    /// `copy/monitor/memory-pressure/normal`
    static let copyMonitorMemoryPressureNormal = LocalizedCopy(key: "copy/monitor/memory-pressure/normal", en: "Normal", zhHans: "正常")
    /// `copy/monitor/memory-pressure/warning`
    static let copyMonitorMemoryPressureWarning = LocalizedCopy(key: "copy/monitor/memory-pressure/warning", en: "Warning", zhHans: "警告")
    /// `copy/monitor/memory/pressure`
    static let copyMonitorMemoryPressure = LocalizedCopy(key: "copy/monitor/memory/pressure", en: "Pressure", zhHans: "压力")
    /// `copy/monitor/memory/swap`
    static let copyMonitorMemorySwap = LocalizedCopy(key: "copy/monitor/memory/swap", en: "Swap", zhHans: "交换")
    /// `copy/monitor/memory/total`
    static let copyMonitorMemoryTotal = LocalizedCopy(key: "copy/monitor/memory/total", en: "Total", zhHans: "总量")
    /// `copy/monitor/memory/used`
    static let copyMonitorMemoryUsed = LocalizedCopy(key: "copy/monitor/memory/used", en: "Used", zhHans: "已用")
    /// `copy/monitor/network/download`
    static let copyMonitorNetworkDownload = LocalizedCopy(key: "copy/monitor/network/download", en: "Download", zhHans: "下行")
    /// `copy/monitor/network/interface`
    static let copyMonitorNetworkInterface = LocalizedCopy(key: "copy/monitor/network/interface", en: "Interface", zhHans: "接口")
    /// `copy/monitor/network/upload`
    static let copyMonitorNetworkUpload = LocalizedCopy(key: "copy/monitor/network/upload", en: "Upload", zhHans: "上行")
    /// `copy/monitor/per-core`
    static let copyMonitorPerCore = LocalizedCopy(key: "copy/monitor/per-core", en: "Per core", zhHans: "每核")
    /// `copy/monitor/power/average/draw`
    static let copyMonitorPowerAverageDraw = LocalizedCopy(key: "copy/monitor/power/average/draw", en: "Average power", zhHans: "平均功耗")
    /// `copy/monitor/power/charge-limit/apply`
    static let copyMonitorPowerChargeLimitApply = LocalizedCopy(key: "copy/monitor/power/charge-limit/apply", en: "Apply limit", zhHans: "应用上限")
    /// `copy/monitor/power/charge-limit/applying`
    static let copyMonitorPowerChargeLimitApplying = LocalizedCopy(key: "copy/monitor/power/charge-limit/applying", en: "Applying charge limit", zhHans: "正在应用充电上限")
    /// `copy/monitor/power/charge-limit/current-charge`
    static let copyMonitorPowerChargeLimitCurrentCharge = LocalizedCopy(key: "copy/monitor/power/charge-limit/current-charge", en: "Current charge", zhHans: "当前电量")
    /// `copy/monitor/power/charge-limit/current-target`
    static let copyMonitorPowerChargeLimitCurrentTarget = LocalizedCopy(key: "copy/monitor/power/charge-limit/current-target", en: "Current target", zhHans: "当前目标")
    /// `copy/monitor/power/charge-limit/enable`
    static let copyMonitorPowerChargeLimitEnable = LocalizedCopy(key: "copy/monitor/power/charge-limit/enable", en: "Enable limit", zhHans: "启用上限")
    /// `copy/monitor/power/charge-limit/failed`
    static let copyMonitorPowerChargeLimitFailed = LocalizedCopy(key: "copy/monitor/power/charge-limit/failed", en: "Charge limit did not apply", zhHans: "充电上限未生效")
    /// `copy/monitor/power/charge-limit/helper-required`
    static let copyMonitorPowerChargeLimitHelperRequired = LocalizedCopy(key: "copy/monitor/power/charge-limit/helper-required", en: "Install or repair the helper", zhHans: "请安装或修复 helper")
    /// `copy/monitor/power/charge-limit/restore`
    static let copyMonitorPowerChargeLimitRestore = LocalizedCopy(key: "copy/monitor/power/charge-limit/restore", en: "Restore system default", zhHans: "恢复系统默认")
    /// `copy/monitor/power/charge-limit/resume-at`
    static let copyMonitorPowerChargeLimitResumeAt = LocalizedCopy(key: "copy/monitor/power/charge-limit/resume-at", en: "Resume charging at", zhHans: "恢复充电阈值")
    /// `copy/monitor/power/charge-limit/state/above-limit`
    static let copyMonitorPowerChargeLimitStateAboveLimit = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/above-limit", en: "Above limit", zhHans: "高于上限")
    /// `copy/monitor/power/charge-limit/state/bypass`
    static let copyMonitorPowerChargeLimitStateBypass = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/bypass", en: "Bypass power", zhHans: "旁路供电")
    /// `copy/monitor/power/charge-limit/state/calibration`
    static let copyMonitorPowerChargeLimitStateCalibration = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/calibration", en: "Calibration in progress", zhHans: "校准中")
    /// `copy/monitor/power/charge-limit/state/conflict`
    static let copyMonitorPowerChargeLimitStateConflict = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/conflict", en: "System policy conflict", zhHans: "系统策略冲突")
    /// `copy/monitor/power/charge-limit/state/error`
    static let copyMonitorPowerChargeLimitStateError = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/error", en: "Charge limit error", zhHans: "充电上限错误")
    /// `copy/monitor/power/charge-limit/state/holding`
    static let copyMonitorPowerChargeLimitStateHolding = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/holding", en: "Charging paused", zhHans: "已暂停充电")
    /// `copy/monitor/power/charge-limit/state/protection`
    static let copyMonitorPowerChargeLimitStateProtection = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/protection", en: "System protection", zhHans: "系统保护中")
    /// `copy/monitor/power/charge-limit/state/sailing`
    static let copyMonitorPowerChargeLimitStateSailing = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/sailing", en: "Holding current level", zhHans: "保持当前电量")
    /// `copy/monitor/power/charge-limit/state/system`
    static let copyMonitorPowerChargeLimitStateSystem = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/system", en: "macOS controls the charge limit", zhHans: "macOS 控制充电上限")
    /// `copy/monitor/power/charge-limit/state/unplugged`
    static let copyMonitorPowerChargeLimitStateUnplugged = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/unplugged", en: "Connect the power adapter", zhHans: "请接通电源适配器")
    /// `copy/monitor/power/charge-limit/title`
    static let copyMonitorPowerChargeLimitTitle = LocalizedCopy(key: "copy/monitor/power/charge-limit/title", en: "Charge limit", zhHans: "充电上限")
    /// `copy/monitor/power/charge-limit/unsupported`
    static let copyMonitorPowerChargeLimitUnsupported = LocalizedCopy(key: "copy/monitor/power/charge-limit/unsupported", en: "Charge limit is unavailable", zhHans: "当前设备不支持充电上限")
    /// `copy/monitor/power/charge/health`
    static let copyMonitorPowerChargeHealth = LocalizedCopy(key: "copy/monitor/power/charge/health", en: "Battery health", zhHans: "电池健康度")
    /// `copy/monitor/power/charge/power`
    static let copyMonitorPowerChargePower = LocalizedCopy(key: "copy/monitor/power/charge/power", en: "Charging power", zhHans: "充电功率")
    /// `copy/monitor/power/charge/time-to-full`
    static let copyMonitorPowerChargeTimeToFull = LocalizedCopy(key: "copy/monitor/power/charge/time-to-full", en: "Time to full", zhHans: "预计充满")
    /// `copy/monitor/power/charge/title`
    static let copyMonitorPowerChargeTitle = LocalizedCopy(key: "copy/monitor/power/charge/title", en: "Charging information", zhHans: "充电信息")
    /// `copy/monitor/power/critical-battery`
    static let copyMonitorPowerCriticalBattery = LocalizedCopy(key: "copy/monitor/power/critical-battery", en: "Battery critical", zhHans: "电量极低")
    /// `copy/monitor/power/details/close`
    static let copyMonitorPowerDetailsClose = LocalizedCopy(key: "copy/monitor/power/details/close", en: "Close power details", zhHans: "关闭电源详情")
    /// `copy/monitor/power/details/collapse`
    static let copyMonitorPowerDetailsCollapse = LocalizedCopy(key: "copy/monitor/power/details/collapse", en: "Hide details", zhHans: "收起详情")
    /// `copy/monitor/power/details/expand`
    static let copyMonitorPowerDetailsExpand = LocalizedCopy(key: "copy/monitor/power/details/expand", en: "Show details", zhHans: "展开详情")
    /// `copy/monitor/power/details/title`
    static let copyMonitorPowerDetailsTitle = LocalizedCopy(key: "copy/monitor/power/details/title", en: "Power details", zhHans: "电源详情")
    /// `copy/monitor/power/draw`
    static let copyMonitorPowerDraw = LocalizedCopy(key: "copy/monitor/power/draw", en: "Power draw", zhHans: "功耗")
    /// `copy/monitor/power/estimate/basis`
    static let copyMonitorPowerEstimateBasis = LocalizedCopy(key: "copy/monitor/power/estimate/basis", en: "Based on recent average power", zhHans: "按近期平均功耗估算")
    /// `copy/monitor/power/events/connected`
    static let copyMonitorPowerEventsConnected = LocalizedCopy(key: "copy/monitor/power/events/connected", en: "Adapter connected", zhHans: "已接通电源")
    /// `copy/monitor/power/events/disconnected`
    static let copyMonitorPowerEventsDisconnected = LocalizedCopy(key: "copy/monitor/power/events/disconnected", en: "Adapter disconnected", zhHans: "已断开电源")
    /// `copy/monitor/power/events/fully-charged`
    static let copyMonitorPowerEventsFullyCharged = LocalizedCopy(key: "copy/monitor/power/events/fully-charged", en: "Fully charged", zhHans: "已充满")
    /// `copy/monitor/power/events/title`
    static let copyMonitorPowerEventsTitle = LocalizedCopy(key: "copy/monitor/power/events/title", en: "Power events · 24 h", zhHans: "供电事件 · 近 24 小时")
    /// `copy/monitor/power/high-temperature`
    static let copyMonitorPowerHighTemperature = LocalizedCopy(key: "copy/monitor/power/high-temperature", en: "Battery hot", zhHans: "电池温度高")
    /// `copy/monitor/power/history/accumulating`
    static let copyMonitorPowerHistoryAccumulating = LocalizedCopy(key: "copy/monitor/power/history/accumulating", en: "Collecting data", zhHans: "数据积累中")
    /// `copy/monitor/power/history/title`
    static let copyMonitorPowerHistoryTitle = LocalizedCopy(key: "copy/monitor/power/history/title", en: "Power and temperature · 30 min", zhHans: "功耗与温度 · 近 30 分钟")
    /// `copy/monitor/power/low-battery`
    static let copyMonitorPowerLowBattery = LocalizedCopy(key: "copy/monitor/power/low-battery", en: "Low battery", zhHans: "电量低")
    /// `copy/monitor/power/no-battery`
    static let copyMonitorPowerNoBattery = LocalizedCopy(key: "copy/monitor/power/no-battery", en: "No battery", zhHans: "无电池设备")
    /// `copy/monitor/power/no-data`
    static let copyMonitorPowerNoData = LocalizedCopy(key: "copy/monitor/power/no-data", en: "No data", zhHans: "暂无数据")
    /// `copy/monitor/power/read-failed`
    static let copyMonitorPowerReadFailed = LocalizedCopy(key: "copy/monitor/power/read-failed", en: "Some readings unavailable", zhHans: "部分读数不可用")
    /// `copy/monitor/power/remaining`
    static let copyMonitorPowerRemaining = LocalizedCopy(key: "copy/monitor/power/remaining", en: "Estimated time", zhHans: "预计可使用")
    /// `copy/monitor/power/state/battery`
    static let copyMonitorPowerStateBattery = LocalizedCopy(key: "copy/monitor/power/state/battery", en: "On battery", zhHans: "电池供电")
    /// `copy/monitor/power/state/connected`
    static let copyMonitorPowerStateConnected = LocalizedCopy(key: "copy/monitor/power/state/connected", en: "Power connected", zhHans: "已接通电源")
    /// `copy/monitor/power/temperature`
    static let copyMonitorPowerTemperature = LocalizedCopy(key: "copy/monitor/power/temperature", en: "Temperature", zhHans: "温度")
    /// `copy/monitor/power/top-apps`
    static let copyMonitorPowerTopApps = LocalizedCopy(key: "copy/monitor/power/top-apps", en: "Top energy · 1 hour", zhHans: "耗电 Top3 · 近 1 小时")
    /// `copy/monitor/power/trend/title`
    static let copyMonitorPowerTrendTitle = LocalizedCopy(key: "copy/monitor/power/trend/title", en: "Recent trend", zhHans: "近期趋势")
    /// `copy/monitor/power/trend/window`
    static let copyMonitorPowerTrendWindow = LocalizedCopy(key: "copy/monitor/power/trend/window", en: "Last 1 min", zhHans: "近 1 分钟")
    /// `copy/monitor/sampling/fast`
    static let copyMonitorSamplingFast = LocalizedCopy(key: "copy/monitor/sampling/fast", en: "1s", zhHans: "1 秒")
    /// `copy/monitor/sampling/slow`
    static let copyMonitorSamplingSlow = LocalizedCopy(key: "copy/monitor/sampling/slow", en: "5s", zhHans: "5 秒")
    /// `copy/monitor/state/ac-power`
    static let copyMonitorStateAcPower = LocalizedCopy(key: "copy/monitor/state/ac-power", en: "Power adapter", zhHans: "电源适配器")
    /// `copy/monitor/state/charged`
    static let copyMonitorStateCharged = LocalizedCopy(key: "copy/monitor/state/charged", en: "Charged", zhHans: "已充满")
    /// `copy/monitor/state/charging`
    static let copyMonitorStateCharging = LocalizedCopy(key: "copy/monitor/state/charging", en: "Charging", zhHans: "充电中")
    /// `copy/monitor/state/on-battery`
    static let copyMonitorStateOnBattery = LocalizedCopy(key: "copy/monitor/state/on-battery", en: "On battery", zhHans: "使用电池")
    /// `copy/monitor/state/unknown`
    static let copyMonitorStateUnknown = LocalizedCopy(key: "copy/monitor/state/unknown", en: "Unknown", zhHans: "未知")
    /// `copy/monitor/thermal`
    static let copyMonitorThermal = LocalizedCopy(key: "copy/monitor/thermal", en: "Thermal", zhHans: "热状态")
    /// `copy/monitor/thermal/critical`
    static let copyMonitorThermalCritical = LocalizedCopy(key: "copy/monitor/thermal/critical", en: "Critical", zhHans: "过热")
    /// `copy/monitor/thermal/fair`
    static let copyMonitorThermalFair = LocalizedCopy(key: "copy/monitor/thermal/fair", en: "Fair", zhHans: "较热")
    /// `copy/monitor/thermal/nominal`
    static let copyMonitorThermalNominal = LocalizedCopy(key: "copy/monitor/thermal/nominal", en: "Normal", zhHans: "正常")
    /// `copy/monitor/thermal/serious`
    static let copyMonitorThermalSerious = LocalizedCopy(key: "copy/monitor/thermal/serious", en: "Serious", zhHans: "过热")
    /// `copy/monitor/title/battery`
    static let copyMonitorTitleBattery = LocalizedCopy(key: "copy/monitor/title/battery", en: "Power", zhHans: "电源")
    /// `copy/monitor/title/cpu`
    static let copyMonitorTitleCpu = LocalizedCopy(key: "copy/monitor/title/cpu", en: "CPU", zhHans: "CPU")
    /// `copy/monitor/title/disk`
    static let copyMonitorTitleDisk = LocalizedCopy(key: "copy/monitor/title/disk", en: "Disk", zhHans: "磁盘")
    /// `copy/monitor/title/gpu`
    static let copyMonitorTitleGpu = LocalizedCopy(key: "copy/monitor/title/gpu", en: "GPU", zhHans: "GPU")
    /// `copy/monitor/title/memory`
    static let copyMonitorTitleMemory = LocalizedCopy(key: "copy/monitor/title/memory", en: "Memory", zhHans: "内存")
    /// `copy/monitor/title/network`
    static let copyMonitorTitleNetwork = LocalizedCopy(key: "copy/monitor/title/network", en: "Network", zhHans: "网络")
    /// `copy/monitor/unavailable`
    static let copyMonitorUnavailable = LocalizedCopy(key: "copy/monitor/unavailable", en: "Unavailable", zhHans: "不可用")
    /// `copy/monitor/uptime`
    static let copyMonitorUptime = LocalizedCopy(key: "copy/monitor/uptime", en: "Uptime", zhHans: "运行时间")
    /// `copy/monitor/usage`
    static let copyMonitorUsage = LocalizedCopy(key: "copy/monitor/usage", en: "Usage", zhHans: "使用率")
    /// `copy/nav/battery`
    static let copyNavBattery = LocalizedCopy(key: "copy/nav/battery", en: "Battery", zhHans: "电池")
    /// `copy/nav/general`
    static let copyNavGeneral = LocalizedCopy(key: "copy/nav/general", en: "General", zhHans: "通用")
    /// `copy/nav/idle`
    static let copyNavIdle = LocalizedCopy(key: "copy/nav/idle", en: "Idle", zhHans: "闲置")
    /// `copy/nav/lid`
    static let copyNavLid = LocalizedCopy(key: "copy/nav/lid", en: "Lid", zhHans: "合盖")
    /// `copy/nav/overview`
    static let copyNavOverview = LocalizedCopy(key: "copy/nav/overview", en: "Overview", zhHans: "概览")
    /// `copy/nav/quit`
    static let copyNavQuit = LocalizedCopy(key: "copy/nav/quit", en: "Quit Covio", zhHans: "退出 Covio")
    /// `copy/nav/rail-label`
    static let copyNavRailLabel = LocalizedCopy(key: "copy/nav/rail-label", en: "Hub tab bar", zhHans: "Hub 页签栏")
    /// `copy/nav/search-empty`
    static let copyNavSearchEmpty = LocalizedCopy(key: "copy/nav/search-empty", en: "No matching settings", zhHans: "没有匹配的设置")
    /// `copy/nav/search-placeholder`
    static let copyNavSearchPlaceholder = LocalizedCopy(key: "copy/nav/search-placeholder", en: "Search workspaces and settings", zhHans: "搜索工作区与设置")
    /// `copy/nav/search-results`
    static let copyNavSearchResults = LocalizedCopy(key: "copy/nav/search-results", en: "Search results", zhHans: "搜索结果")
    /// `copy/nav/status-paused`
    static let copyNavStatusPaused = LocalizedCopy(key: "copy/nav/status-paused", en: "Paused", zhHans: "已暂停")
    /// `copy/nav/status-running`
    static let copyNavStatusRunning = LocalizedCopy(key: "copy/nav/status-running", en: "Running", zhHans: "运行中")
    /// `copy/nav/top-shelf`
    static let copyNavTopShelf = LocalizedCopy(key: "copy/nav/top-shelf", en: "Top Shelf", zhHans: "顶部挂帘")
    /// `copy/notch-hub/layout/collapsed-presence`
    static let copyNotchHubLayoutCollapsedPresence = LocalizedCopy(key: "copy/notch-hub/layout/collapsed-presence", en: "A · Collapsed Presence", zhHans: "A · 收起存在感")
    /// `copy/notch-hub/layout/drag-target`
    static let copyNotchHubLayoutDragTarget = LocalizedCopy(key: "copy/notch-hub/layout/drag-target", en: "C · Drag Target", zhHans: "C · 拖放目标")
    /// `copy/notch-hub/layout/expanded-output`
    static let copyNotchHubLayoutExpandedOutput = LocalizedCopy(key: "copy/notch-hub/layout/expanded-output", en: "B · Expanded Output", zhHans: "B · 展开输出")
    /// `copy/notch-hub/state/active`
    static let copyNotchHubStateActive = LocalizedCopy(key: "copy/notch-hub/state/active", en: "Active", zhHans: "活动")
    /// `copy/notch-hub/state/collapsed`
    static let copyNotchHubStateCollapsed = LocalizedCopy(key: "copy/notch-hub/state/collapsed", en: "Collapsed", zhHans: "收起")
    /// `copy/notch-hub/state/drag-target`
    static let copyNotchHubStateDragTarget = LocalizedCopy(key: "copy/notch-hub/state/drag-target", en: "Drag Target", zhHans: "拖放目标")
    /// `copy/notch-hub/state/error`
    static let copyNotchHubStateError = LocalizedCopy(key: "copy/notch-hub/state/error", en: "Error", zhHans: "错误")
    /// `copy/notch-hub/state/exit`
    static let copyNotchHubStateExit = LocalizedCopy(key: "copy/notch-hub/state/exit", en: "Exit", zhHans: "退出")
    /// `copy/notch-hub/state/expanded`
    static let copyNotchHubStateExpanded = LocalizedCopy(key: "copy/notch-hub/state/expanded", en: "Expanded Output", zhHans: "展开输出")
    /// `copy/notch-hub/state/hidden`
    static let copyNotchHubStateHidden = LocalizedCopy(key: "copy/notch-hub/state/hidden", en: "Hidden", zhHans: "隐藏")
    /// `copy/notch-hub/state/hover`
    static let copyNotchHubStateHover = LocalizedCopy(key: "copy/notch-hub/state/hover", en: "Hover", zhHans: "悬停")
    /// `copy/notch-hub/state/open`
    static let copyNotchHubStateOpen = LocalizedCopy(key: "copy/notch-hub/state/open", en: "Open", zhHans: "打开")
    /// `copy/notch-hub/state/processing`
    static let copyNotchHubStateProcessing = LocalizedCopy(key: "copy/notch-hub/state/processing", en: "Processing", zhHans: "处理中")
    /// `copy/notch-hub/state/ready`
    static let copyNotchHubStateReady = LocalizedCopy(key: "copy/notch-hub/state/ready", en: "Ready", zhHans: "就绪")
    /// `copy/overview/action/display-off`
    static let copyOverviewActionDisplayOff = LocalizedCopy(key: "copy/overview/action/display-off", en: "Turn Display Off", zhHans: "关闭显示器")
    /// `copy/overview/action/sleep-now`
    static let copyOverviewActionSleepNow = LocalizedCopy(key: "copy/overview/action/sleep-now", en: "Sleep Now", zhHans: "立即睡眠")
    /// `copy/overview/helper/install`
    static let copyOverviewHelperInstall = LocalizedCopy(key: "copy/overview/helper/install", en: "Install helper", zhHans: "安装助手")
    /// `copy/overview/helper/installed`
    static let copyOverviewHelperInstalled = LocalizedCopy(key: "copy/overview/helper/installed", en: "Helper installed", zhHans: "助手已安装")
    /// `copy/overview/helper/missing`
    static let copyOverviewHelperMissing = LocalizedCopy(key: "copy/overview/helper/missing", en: "Helper not installed", zhHans: "助手未安装")
    /// `copy/overview/helper/version`
    static let copyOverviewHelperVersion = LocalizedCopy(key: "copy/overview/helper/version", en: "Version", zhHans: "版本")
    /// `copy/overview/rules/master`
    static let copyOverviewRulesMaster = LocalizedCopy(key: "copy/overview/rules/master", en: "Sleep protection", zhHans: "睡眠保护")
    /// `copy/page/battery/state/disabled`
    static let copyPageBatteryStateDisabled = LocalizedCopy(key: "copy/page/battery/state/disabled", en: "04 · Battery - Disabled", zhHans: "04 · Battery - 不可用")
    /// `copy/page/battery/state/empty`
    static let copyPageBatteryStateEmpty = LocalizedCopy(key: "copy/page/battery/state/empty", en: "04 · Battery - Empty", zhHans: "04 · Battery - 无项目")
    /// `copy/page/battery/state/error`
    static let copyPageBatteryStateError = LocalizedCopy(key: "copy/page/battery/state/error", en: "04 · Battery - Error", zhHans: "04 · Battery - 操作失败")
    /// `copy/page/battery/state/loading`
    static let copyPageBatteryStateLoading = LocalizedCopy(key: "copy/page/battery/state/loading", en: "04 · Battery - Loading", zhHans: "04 · Battery - 正在加载")
    /// `copy/page/battery/state/normal`
    static let copyPageBatteryStateNormal = LocalizedCopy(key: "copy/page/battery/state/normal", en: "04 · Battery - Normal", zhHans: "04 · Battery - 就绪")
    /// `copy/page/battery/state/success`
    static let copyPageBatteryStateSuccess = LocalizedCopy(key: "copy/page/battery/state/success", en: "04 · Battery - Success", zhHans: "04 · Battery - 已完成")
    /// `copy/page/battery/state/warning`
    static let copyPageBatteryStateWarning = LocalizedCopy(key: "copy/page/battery/state/warning", en: "04 · Battery - Warning", zhHans: "04 · Battery - 需要检查")
    /// `copy/page/battery/summary`
    static let copyPageBatterySummary = LocalizedCopy(key: "copy/page/battery/summary", en: "Sleep when battery power reaches a threshold.", zhHans: "电池电量达到阈值时睡眠。")
    /// `copy/page/battery/title`
    static let copyPageBatteryTitle = LocalizedCopy(key: "copy/page/battery/title", en: "Battery", zhHans: "电池")
    /// `copy/page/general/state/disabled`
    static let copyPageGeneralStateDisabled = LocalizedCopy(key: "copy/page/general/state/disabled", en: "08 · General - Disabled", zhHans: "08 · General - 不可用")
    /// `copy/page/general/state/empty`
    static let copyPageGeneralStateEmpty = LocalizedCopy(key: "copy/page/general/state/empty", en: "08 · General - Empty", zhHans: "08 · General - 无项目")
    /// `copy/page/general/state/error`
    static let copyPageGeneralStateError = LocalizedCopy(key: "copy/page/general/state/error", en: "08 · General - Error", zhHans: "08 · General - 操作失败")
    /// `copy/page/general/state/loading`
    static let copyPageGeneralStateLoading = LocalizedCopy(key: "copy/page/general/state/loading", en: "08 · General - Loading", zhHans: "08 · General - 正在加载")
    /// `copy/page/general/state/normal`
    static let copyPageGeneralStateNormal = LocalizedCopy(key: "copy/page/general/state/normal", en: "08 · General - Normal", zhHans: "08 · General - 就绪")
    /// `copy/page/general/state/success`
    static let copyPageGeneralStateSuccess = LocalizedCopy(key: "copy/page/general/state/success", en: "08 · General - Success", zhHans: "08 · General - 已完成")
    /// `copy/page/general/state/warning`
    static let copyPageGeneralStateWarning = LocalizedCopy(key: "copy/page/general/state/warning", en: "08 · General - Warning", zhHans: "08 · General - 需要检查")
    /// `copy/page/general/summary`
    static let copyPageGeneralSummary = LocalizedCopy(key: "copy/page/general/summary", en: "Control startup, updates, language, and power mode.", zhHans: "控制启动、更新、语言和电源模式。")
    /// `copy/page/general/title`
    static let copyPageGeneralTitle = LocalizedCopy(key: "copy/page/general/title", en: "General", zhHans: "通用")
    /// `copy/page/idle/state/disabled`
    static let copyPageIdleStateDisabled = LocalizedCopy(key: "copy/page/idle/state/disabled", en: "06 · Idle - Disabled", zhHans: "06 · Idle - 不可用")
    /// `copy/page/idle/state/empty`
    static let copyPageIdleStateEmpty = LocalizedCopy(key: "copy/page/idle/state/empty", en: "06 · Idle - Empty", zhHans: "06 · Idle - 无项目")
    /// `copy/page/idle/state/error`
    static let copyPageIdleStateError = LocalizedCopy(key: "copy/page/idle/state/error", en: "06 · Idle - Error", zhHans: "06 · Idle - 操作失败")
    /// `copy/page/idle/state/loading`
    static let copyPageIdleStateLoading = LocalizedCopy(key: "copy/page/idle/state/loading", en: "06 · Idle - Loading", zhHans: "06 · Idle - 正在加载")
    /// `copy/page/idle/state/normal`
    static let copyPageIdleStateNormal = LocalizedCopy(key: "copy/page/idle/state/normal", en: "06 · Idle - Normal", zhHans: "06 · Idle - 就绪")
    /// `copy/page/idle/state/success`
    static let copyPageIdleStateSuccess = LocalizedCopy(key: "copy/page/idle/state/success", en: "06 · Idle - Success", zhHans: "06 · Idle - 已完成")
    /// `copy/page/idle/state/warning`
    static let copyPageIdleStateWarning = LocalizedCopy(key: "copy/page/idle/state/warning", en: "06 · Idle - Warning", zhHans: "06 · Idle - 需要检查")
    /// `copy/page/idle/summary`
    static let copyPageIdleSummary = LocalizedCopy(key: "copy/page/idle/summary", en: "Control sleep behavior while the Mac is idle.", zhHans: "控制 Mac 闲置时的睡眠行为。")
    /// `copy/page/idle/title`
    static let copyPageIdleTitle = LocalizedCopy(key: "copy/page/idle/title", en: "Idle", zhHans: "闲置")
    /// `copy/page/lid/state/disabled`
    static let copyPageLidStateDisabled = LocalizedCopy(key: "copy/page/lid/state/disabled", en: "05 · Lid - Disabled", zhHans: "05 · Lid - 不可用")
    /// `copy/page/lid/state/empty`
    static let copyPageLidStateEmpty = LocalizedCopy(key: "copy/page/lid/state/empty", en: "05 · Lid - Empty", zhHans: "05 · Lid - 无项目")
    /// `copy/page/lid/state/error`
    static let copyPageLidStateError = LocalizedCopy(key: "copy/page/lid/state/error", en: "05 · Lid - Error", zhHans: "05 · Lid - 操作失败")
    /// `copy/page/lid/state/loading`
    static let copyPageLidStateLoading = LocalizedCopy(key: "copy/page/lid/state/loading", en: "05 · Lid - Loading", zhHans: "05 · Lid - 正在加载")
    /// `copy/page/lid/state/normal`
    static let copyPageLidStateNormal = LocalizedCopy(key: "copy/page/lid/state/normal", en: "05 · Lid - Normal", zhHans: "05 · Lid - 就绪")
    /// `copy/page/lid/state/success`
    static let copyPageLidStateSuccess = LocalizedCopy(key: "copy/page/lid/state/success", en: "05 · Lid - Success", zhHans: "05 · Lid - 已完成")
    /// `copy/page/lid/state/warning`
    static let copyPageLidStateWarning = LocalizedCopy(key: "copy/page/lid/state/warning", en: "05 · Lid - Warning", zhHans: "05 · Lid - 需要检查")
    /// `copy/page/lid/summary`
    static let copyPageLidSummary = LocalizedCopy(key: "copy/page/lid/summary", en: "Control sleep behavior when the lid closes.", zhHans: "控制合盖后的睡眠行为。")
    /// `copy/page/lid/title`
    static let copyPageLidTitle = LocalizedCopy(key: "copy/page/lid/title", en: "Lid", zhHans: "合盖")
    /// `copy/page/overview/state/disabled`
    static let copyPageOverviewStateDisabled = LocalizedCopy(key: "copy/page/overview/state/disabled", en: "03 · Overview - Disabled", zhHans: "03 · Overview - 不可用")
    /// `copy/page/overview/state/empty`
    static let copyPageOverviewStateEmpty = LocalizedCopy(key: "copy/page/overview/state/empty", en: "03 · Overview - Empty", zhHans: "03 · Overview - 无项目")
    /// `copy/page/overview/state/error`
    static let copyPageOverviewStateError = LocalizedCopy(key: "copy/page/overview/state/error", en: "03 · Overview - Error", zhHans: "03 · Overview - 操作失败")
    /// `copy/page/overview/state/loading`
    static let copyPageOverviewStateLoading = LocalizedCopy(key: "copy/page/overview/state/loading", en: "03 · Overview - Loading", zhHans: "03 · Overview - 正在加载")
    /// `copy/page/overview/state/normal`
    static let copyPageOverviewStateNormal = LocalizedCopy(key: "copy/page/overview/state/normal", en: "03 · Overview - Normal", zhHans: "03 · Overview - 就绪")
    /// `copy/page/overview/state/success`
    static let copyPageOverviewStateSuccess = LocalizedCopy(key: "copy/page/overview/state/success", en: "03 · Overview - Success", zhHans: "03 · Overview - 已完成")
    /// `copy/page/overview/state/warning`
    static let copyPageOverviewStateWarning = LocalizedCopy(key: "copy/page/overview/state/warning", en: "03 · Overview - Warning", zhHans: "03 · Overview - 需要检查")
    /// `copy/page/overview/summary`
    static let copyPageOverviewSummary = LocalizedCopy(key: "copy/page/overview/summary", en: "Manage sleep rules and helper status.", zhHans: "管理睡眠规则和助手状态。")
    /// `copy/page/overview/title`
    static let copyPageOverviewTitle = LocalizedCopy(key: "copy/page/overview/title", en: "Overview", zhHans: "概览")
    /// `copy/page/top-shelf-settings/state/disabled`
    static let copyPageTopShelfSettingsStateDisabled = LocalizedCopy(key: "copy/page/top-shelf-settings/state/disabled", en: "07 · Top Shelf Settings - Disabled", zhHans: "07 · Top Shelf Settings - 不可用")
    /// `copy/page/top-shelf-settings/state/empty`
    static let copyPageTopShelfSettingsStateEmpty = LocalizedCopy(key: "copy/page/top-shelf-settings/state/empty", en: "07 · Top Shelf Settings - Empty", zhHans: "07 · Top Shelf Settings - 无项目")
    /// `copy/page/top-shelf-settings/state/error`
    static let copyPageTopShelfSettingsStateError = LocalizedCopy(key: "copy/page/top-shelf-settings/state/error", en: "07 · Top Shelf Settings - Error", zhHans: "07 · Top Shelf Settings - 操作失败")
    /// `copy/page/top-shelf-settings/state/loading`
    static let copyPageTopShelfSettingsStateLoading = LocalizedCopy(key: "copy/page/top-shelf-settings/state/loading", en: "07 · Top Shelf Settings - Loading", zhHans: "07 · Top Shelf Settings - 正在加载")
    /// `copy/page/top-shelf-settings/state/normal`
    static let copyPageTopShelfSettingsStateNormal = LocalizedCopy(key: "copy/page/top-shelf-settings/state/normal", en: "07 · Top Shelf Settings - Normal", zhHans: "07 · Top Shelf Settings - 就绪")
    /// `copy/page/top-shelf-settings/state/success`
    static let copyPageTopShelfSettingsStateSuccess = LocalizedCopy(key: "copy/page/top-shelf-settings/state/success", en: "07 · Top Shelf Settings - Success", zhHans: "07 · Top Shelf Settings - 已完成")
    /// `copy/page/top-shelf-settings/state/warning`
    static let copyPageTopShelfSettingsStateWarning = LocalizedCopy(key: "copy/page/top-shelf-settings/state/warning", en: "07 · Top Shelf Settings - Warning", zhHans: "07 · Top Shelf Settings - 需要检查")
    /// `copy/page/top-shelf-settings/summary`
    static let copyPageTopShelfSettingsSummary = LocalizedCopy(key: "copy/page/top-shelf-settings/summary", en: "Control screenshot takeover and the top shelf.", zhHans: "控制截图接管和顶部挂帘。")
    /// `copy/page/top-shelf-settings/title`
    static let copyPageTopShelfSettingsTitle = LocalizedCopy(key: "copy/page/top-shelf-settings/title", en: "Top Shelf", zhHans: "顶部挂帘")
    /// `copy/state/cancel`
    static let copyStateCancel = LocalizedCopy(key: "copy/state/cancel", en: "Cancel", zhHans: "取消")
    /// `copy/state/component/toolbar/default/disabled`
    static let copyStateComponentToolbarDefaultDisabled = LocalizedCopy(key: "copy/state/component/toolbar/default/disabled", en: "Disabled", zhHans: "禁用")
    /// `copy/state/component/toolbar/default/focused`
    static let copyStateComponentToolbarDefaultFocused = LocalizedCopy(key: "copy/state/component/toolbar/default/focused", en: "Focused", zhHans: "聚焦")
    /// `copy/state/component/toolbar/default/hover`
    static let copyStateComponentToolbarDefaultHover = LocalizedCopy(key: "copy/state/component/toolbar/default/hover", en: "Hover", zhHans: "悬停")
    /// `copy/state/component/toolbar/default/pressed`
    static let copyStateComponentToolbarDefaultPressed = LocalizedCopy(key: "copy/state/component/toolbar/default/pressed", en: "Pressed", zhHans: "按下")
    /// `copy/state/disabled`
    static let copyStateDisabled = LocalizedCopy(key: "copy/state/disabled", en: "Unavailable", zhHans: "不可用")
    /// `copy/state/empty`
    static let copyStateEmpty = LocalizedCopy(key: "copy/state/empty", en: "No items", zhHans: "无项目")
    /// `copy/state/error`
    static let copyStateError = LocalizedCopy(key: "copy/state/error", en: "Action failed", zhHans: "操作失败")
    /// `copy/state/loading`
    static let copyStateLoading = LocalizedCopy(key: "copy/state/loading", en: "Loading", zhHans: "正在加载")
    /// `copy/state/normal`
    static let copyStateNormal = LocalizedCopy(key: "copy/state/normal", en: "Ready", zhHans: "就绪")
    /// `copy/state/retry`
    static let copyStateRetry = LocalizedCopy(key: "copy/state/retry", en: "Retry", zhHans: "重试")
    /// `copy/state/success`
    static let copyStateSuccess = LocalizedCopy(key: "copy/state/success", en: "Completed", zhHans: "已完成")
    /// `copy/state/warning`
    static let copyStateWarning = LocalizedCopy(key: "copy/state/warning", en: "Review required", zhHans: "需要检查")
    /// `copy/status-item/charging`
    static let copyStatusItemCharging = LocalizedCopy(key: "copy/status-item/charging", en: "Battery is charging.", zhHans: "电池正在充电。")
    /// `copy/status-item/default`
    static let copyStatusItemDefault = LocalizedCopy(key: "copy/status-item/default", en: "Covio is available.", zhHans: "Covio 可用。")
    /// `copy/status-item/disabled`
    static let copyStatusItemDisabled = LocalizedCopy(key: "copy/status-item/disabled", en: "Covio is paused.", zhHans: "Covio 已暂停。")
    /// `copy/status-item/helper-error`
    static let copyStatusItemHelperError = LocalizedCopy(key: "copy/status-item/helper-error", en: "The helper needs attention.", zhHans: "Helper 需要处理。")
    /// `copy/status-item/idle-prevented`
    static let copyStatusItemIdlePrevented = LocalizedCopy(key: "copy/status-item/idle-prevented", en: "Idle sleep is prevented.", zhHans: "已阻止空闲休眠。")
    /// `copy/status-item/lid-prevented`
    static let copyStatusItemLidPrevented = LocalizedCopy(key: "copy/status-item/lid-prevented", en: "Lid sleep is prevented.", zhHans: "已阻止合盖休眠。")
    /// `copy/status-item/low-battery`
    static let copyStatusItemLowBattery = LocalizedCopy(key: "copy/status-item/low-battery", en: "Battery is low.", zhHans: "电池电量低。")
    /// `copy/toast/error`
    static let copyToastError = LocalizedCopy(key: "copy/toast/error", en: "The operation failed. Try again.", zhHans: "操作失败。请重试。")
    /// `copy/toast/success`
    static let copyToastSuccess = LocalizedCopy(key: "copy/toast/success", en: "Operation completed.", zhHans: "操作已完成。")
    /// `copy/toast/warning`
    static let copyToastWarning = LocalizedCopy(key: "copy/toast/warning", en: "Review the result before you continue.", zhHans: "继续前检查结果。")
    /// `copy/top-shelf/action/clear-all`
    static let copyTopShelfActionClearAll = LocalizedCopy(key: "copy/top-shelf/action/clear-all", en: "Clear", zhHans: "清空")
    /// `copy/top-shelf/action/copy`
    static let copyTopShelfActionCopy = LocalizedCopy(key: "copy/top-shelf/action/copy", en: "Copy", zhHans: "复制")
    /// `copy/top-shelf/action/hide-toolbar`
    static let copyTopShelfActionHideToolbar = LocalizedCopy(key: "copy/top-shelf/action/hide-toolbar", en: "Hide Toolbar", zhHans: "隐藏工具栏")
    /// `copy/top-shelf/action/markup`
    static let copyTopShelfActionMarkup = LocalizedCopy(key: "copy/top-shelf/action/markup", en: "Markup", zhHans: "标记")
    /// `copy/top-shelf/action/open-folder`
    static let copyTopShelfActionOpenFolder = LocalizedCopy(key: "copy/top-shelf/action/open-folder", en: "Open Folder", zhHans: "打开目录")
    /// `copy/top-shelf/action/preview`
    static let copyTopShelfActionPreview = LocalizedCopy(key: "copy/top-shelf/action/preview", en: "Preview", zhHans: "预览")
    /// `copy/top-shelf/action/remove`
    static let copyTopShelfActionRemove = LocalizedCopy(key: "copy/top-shelf/action/remove", en: "Remove", zhHans: "移除")
    /// `copy/top-shelf/action/remove-from-shelf`
    static let copyTopShelfActionRemoveFromShelf = LocalizedCopy(key: "copy/top-shelf/action/remove-from-shelf", en: "Remove from Shelf", zhHans: "从工具栏移除")
    /// `copy/top-shelf/action/show-toolbar`
    static let copyTopShelfActionShowToolbar = LocalizedCopy(key: "copy/top-shelf/action/show-toolbar", en: "Show Toolbar", zhHans: "显示工具栏")
    /// `copy/top-shelf/action/workspace`
    static let copyTopShelfActionWorkspace = LocalizedCopy(key: "copy/top-shelf/action/workspace", en: "Save to Workspace", zhHans: "存入工作区")
    /// `copy/top-shelf/clear`
    static let copyTopShelfClear = LocalizedCopy(key: "copy/top-shelf/clear", en: "Clear Shelf", zhHans: "清空挂帘")
    /// `copy/top-shelf/empty`
    static let copyTopShelfEmpty = LocalizedCopy(key: "copy/top-shelf/empty", en: "No screenshots match your filters.", zhHans: "没有截图符合筛选条件。")
    /// `copy/top-shelf/enabled`
    static let copyTopShelfEnabled = LocalizedCopy(key: "copy/top-shelf/enabled", en: "Top Shelf", zhHans: "顶部挂帘")
    /// `copy/top-shelf/error/copy`
    static let copyTopShelfErrorCopy = LocalizedCopy(key: "copy/top-shelf/error/copy", en: "Cannot copy the screenshot.", zhHans: "无法复制截图。")
    /// `copy/top-shelf/error/directory`
    static let copyTopShelfErrorDirectory = LocalizedCopy(key: "copy/top-shelf/error/directory", en: "Cannot open the screenshot folder.", zhHans: "无法打开截图目录。")
    /// `copy/top-shelf/error/markup`
    static let copyTopShelfErrorMarkup = LocalizedCopy(key: "copy/top-shelf/error/markup", en: "Cannot open Markup.", zhHans: "无法打开标记工具。")
    /// `copy/top-shelf/error/move`
    static let copyTopShelfErrorMove = LocalizedCopy(key: "copy/top-shelf/error/move", en: "The file operation failed.", zhHans: "文件操作失败。")
    /// `copy/top-shelf/error/open`
    static let copyTopShelfErrorOpen = LocalizedCopy(key: "copy/top-shelf/error/open", en: "Cannot open the screenshot.", zhHans: "无法打开截图。")
    /// `copy/top-shelf/error/restore`
    static let copyTopShelfErrorRestore = LocalizedCopy(key: "copy/top-shelf/error/restore", en: "System screenshot settings were not restored.", zhHans: "系统截图设置未能恢复。")
    /// `copy/top-shelf/error/takeover`
    static let copyTopShelfErrorTakeover = LocalizedCopy(key: "copy/top-shelf/error/takeover", en: "Screenshot takeover failed.", zhHans: "截图接管失败。")
    /// `copy/top-shelf/none`
    static let copyTopShelfNone = LocalizedCopy(key: "copy/top-shelf/none", en: "No screenshots", zhHans: "没有截图")
    /// `copy/top-shelf/open-folder`
    static let copyTopShelfOpenFolder = LocalizedCopy(key: "copy/top-shelf/open-folder", en: "Open Screenshot Folder", zhHans: "打开截图文件夹")
    /// `copy/top-shelf/pending-notice`
    static let copyTopShelfPendingNotice = LocalizedCopy(key: "copy/top-shelf/pending-notice", en: "These switches save the setting now. The shelf itself arrives in a later phase.", zhHans: "这些开关现在只保存设置。挂帘本体在后续阶段接上。")
    /// `copy/top-shelf/show`
    static let copyTopShelfShow = LocalizedCopy(key: "copy/top-shelf/show", en: "Show Shelf", zhHans: "显示挂帘")
    /// `copy/top-shelf/sounds`
    static let copyTopShelfSounds = LocalizedCopy(key: "copy/top-shelf/sounds", en: "Screenshot sounds", zhHans: "截图声音")
    /// `copy/top-shelf/state/cancel`
    static let copyTopShelfStateCancel = LocalizedCopy(key: "copy/top-shelf/state/cancel", en: "CANCEL", zhHans: "取消拖拽")
    /// `copy/top-shelf/state/drag-to-app`
    static let copyTopShelfStateDragToApp = LocalizedCopy(key: "copy/top-shelf/state/drag-to-app", en: "DRAG TO APP", zhHans: "拖到应用")
    /// `copy/top-shelf/state/drag-to-folder`
    static let copyTopShelfStateDragToFolder = LocalizedCopy(key: "copy/top-shelf/state/drag-to-folder", en: "DRAG TO FOLDER", zhHans: "拖到文件夹")
    /// `copy/top-shelf/state/drag-to-trash`
    static let copyTopShelfStateDragToTrash = LocalizedCopy(key: "copy/top-shelf/state/drag-to-trash", en: "DRAG TO TRASH", zhHans: "拖到废纸篓")
    /// `copy/top-shelf/state/hover`
    static let copyTopShelfStateHover = LocalizedCopy(key: "copy/top-shelf/state/hover", en: "HOVER", zhHans: "悬停")
    /// `copy/top-shelf/state/right-click-menu`
    static let copyTopShelfStateRightClickMenu = LocalizedCopy(key: "copy/top-shelf/state/right-click-menu", en: "RIGHT-CLICK MENU", zhHans: "右键菜单")
    /// `copy/top-shelf/status`
    static let copyTopShelfStatus = LocalizedCopy(key: "copy/top-shelf/status", en: "Shelf status", zhHans: "挂帘状态")
    /// `copy/top-shelf/take-over`
    static let copyTopShelfTakeOver = LocalizedCopy(key: "copy/top-shelf/take-over", en: "Take over screenshots", zhHans: "接管截图")
    /// `copy/top-shelf/title`
    static let copyTopShelfTitle = LocalizedCopy(key: "copy/top-shelf/title", en: "Top Shelf", zhHans: "顶部工具栏")
    /// `copy/tray/action/display-off`
    static let copyTrayActionDisplayOff = LocalizedCopy(key: "copy/tray/action/display-off", en: "Turn Display Off", zhHans: "关闭显示器")
    /// `copy/tray/action/quit`
    static let copyTrayActionQuit = LocalizedCopy(key: "copy/tray/action/quit", en: "Quit Covio", zhHans: "退出 Covio")
    /// `copy/tray/action/settings`
    static let copyTrayActionSettings = LocalizedCopy(key: "copy/tray/action/settings", en: "Settings…", zhHans: "设置…")
    /// `copy/tray/action/show-shelf`
    static let copyTrayActionShowShelf = LocalizedCopy(key: "copy/tray/action/show-shelf", en: "Show Shelf", zhHans: "显示挂帘")
    /// `copy/tray/action/sleep-now`
    static let copyTrayActionSleepNow = LocalizedCopy(key: "copy/tray/action/sleep-now", en: "Sleep Now", zhHans: "立即睡眠")
    /// `copy/tray/tooltip/battery`
    static let copyTrayTooltipBattery = LocalizedCopy(key: "copy/tray/tooltip/battery", en: "On battery", zhHans: "使用电池")
    /// `copy/tray/tooltip/charging`
    static let copyTrayTooltipCharging = LocalizedCopy(key: "copy/tray/tooltip/charging", en: "Charging", zhHans: "正在充电")
    /// `copy/tray/tooltip/helper-error`
    static let copyTrayTooltipHelperError = LocalizedCopy(key: "copy/tray/tooltip/helper-error", en: "Helper error", zhHans: "助手错误")
    /// `copy/tray/tooltip/idle-prevented`
    static let copyTrayTooltipIdlePrevented = LocalizedCopy(key: "copy/tray/tooltip/idle-prevented", en: "Idle sleep prevented", zhHans: "已阻止闲置睡眠")
    /// `copy/tray/tooltip/lid-prevented`
    static let copyTrayTooltipLidPrevented = LocalizedCopy(key: "copy/tray/tooltip/lid-prevented", en: "Lid sleep prevented", zhHans: "已阻止合盖睡眠")
    /// `copy/tray/tooltip/low-battery`
    static let copyTrayTooltipLowBattery = LocalizedCopy(key: "copy/tray/tooltip/low-battery", en: "Low battery", zhHans: "电量低")
    /// `copy/tray/tooltip/normal`
    static let copyTrayTooltipNormal = LocalizedCopy(key: "copy/tray/tooltip/normal", en: "Covio status", zhHans: "Covio 状态")

    /// 全部条目。供测试遍历。
    static let all: [LocalizedCopy] = [
        copyAgentActionCancelled,
        copyAgentActionCompleted,
        copyAgentActionFailed,
        copyAgentCancel,
        copyAgentClear,
        copyAgentConfirm,
        copyAgentConfirmBody,
        copyAgentConfirmTitle,
        copyAgentCopyCharacters,
        copyAgentEmptyBody,
        copyAgentEmptyResponse,
        copyAgentEmptyTitle,
        copyAgentError,
        copyAgentName,
        copyAgentOffline,
        copyAgentPlaceholder,
        copyAgentSend,
        copyAgentStop,
        copyAgentStopped,
        copyAgentThinking,
        copyAgentYou,
        copyAppName,
        copyAppTagline,
        copyAutoNamingActionApply,
        copyAutoNamingActionAutoName,
        copyAutoNamingActionCancel,
        copyAutoNamingActionClose,
        copyAutoNamingActionSelect,
        copyAutoNamingActionUndo,
        copyAutoNamingErrorAnalysis,
        copyAutoNamingErrorRename,
        copyAutoNamingErrorUndo,
        copyAutoNamingLabelEvidence,
        copyAutoNamingLabelOriginal,
        copyAutoNamingLabelTarget,
        copyAutoNamingLabelWarnings,
        copyAutoNamingNoticeApplied,
        copyAutoNamingNoticeCancelled,
        copyAutoNamingNoticeNoFiles,
        copyAutoNamingNoticeNoResults,
        copyAutoNamingNoticeNoSelection,
        copyAutoNamingNoticePartialFailure,
        copyAutoNamingNoticePartialUndo,
        copyAutoNamingNoticeUndone,
        copyAutoNamingRiskConflict,
        copyAutoNamingRiskFallback,
        copyAutoNamingRiskLowConfidence,
        copyAutoNamingRiskMixed,
        copyAutoNamingRiskPromptInjection,
        copyAutoNamingRiskScanned,
        copyAutoNamingRiskTruncated,
        copyAutoNamingStatusBlocked,
        copyAutoNamingStatusFailed,
        copyAutoNamingStatusReady,
        copyAutoNamingStatusRenamed,
        copyAutoNamingStatusUndone,
        copyAutoNamingSubtitle,
        copyAutoNamingTitle,
        copyBatteryCapacityThreshold,
        copyBatteryEnabled,
        copyBatteryTimeThreshold,
        copyBatteryUnitMinutes,
        copyBatteryUnitPercent,
        copyClipboardActionClear,
        copyClipboardActionOpenSettings,
        copyClipboardActionPaste,
        copyClipboardActionPin,
        copyClipboardActionRemove,
        copyClipboardActionUnpin,
        copyClipboardActionWorkspace,
        copyClipboardEmpty,
        copyClipboardErrorAccessibility,
        copyClipboardErrorHotKey,
        copyClipboardErrorImage,
        copyClipboardErrorPaste,
        copyClipboardSettingsAccessibility,
        copyClipboardSettingsAccessibilityFallback,
        copyClipboardSettingsCaptureHotKey,
        copyClipboardSettingsEnabled,
        copyClipboardSettingsGranted,
        copyClipboardSettingsHotKeyConflict,
        copyClipboardSettingsHotKeys,
        copyClipboardSettingsNotGranted,
        copyClipboardSettingsPasteStackHotKey,
        copyClipboardSettingsRequestPermission,
        copyClipboardStatePause,
        copyClipboardStatePaused,
        copyClipboardStateResume,
        copyClipboardTitle,
        copyComponentMaterialBlur,
        copyComponentMaterialMedium,
        copyComponentMaterialThick,
        copyComponentMaterialThin,
        copyComponentMaterialUltraThick,
        copyComponentMaterialUltraThin,
        copyComponentPopoverBottom,
        copyComponentPopoverCustom,
        copyComponentPopoverForm,
        copyComponentPopoverMenu,
        copyComponentPopoverTop,
        copyComponentToolbarCompact,
        copyComponentToolbarDefault,
        copyComponentWindowShellCompact,
        copyComponentWindowShellSidebar,
        copyComponentWindowShellStandard,
        copyComponentWindowShellToolbar,
        copyDialogHelperInstallBody,
        copyDialogHelperInstallTitle,
        copyDialogHelperUnavailableBody,
        copyDialogHelperUnavailableTitle,
        copyDialogResetBody,
        copyDialogResetTitle,
        copyDialogUpdateBody,
        copyDialogUpdateTitle,
        copyGeneralCheckUpdates,
        copyGeneralClearConfig,
        copyGeneralDarkwake,
        copyGeneralLanguage,
        copyGeneralLanguageChinese,
        copyGeneralLanguageEnglish,
        copyGeneralLaunchAtLogin,
        copyGeneralNotifications,
        copyGeneralSleepMode,
        copyGeneralSleepModeDefault,
        copyGeneralSleepModeFastest,
        copyGeneralSleepModeLowestPower,
        copyHubActionBack,
        copyHubActionDone,
        copyHubActionEdit,
        copyHubActionHome,
        copyHubActionSettings,
        copyHubEditBanner,
        copyHubEditReorder,
        copyHubEditWidgetCount,
        copyHubEditWorkspaceCount,
        copyHubFilesActionAdd,
        copyHubFilesActionCancelTransfer,
        copyHubFilesActionClearFilter,
        copyHubFilesActionCopy,
        copyHubFilesActionCopyText,
        copyHubFilesActionDownload,
        copyHubFilesActionImport,
        copyHubFilesActionMarkup,
        copyHubFilesActionMore,
        copyHubFilesActionNewText,
        copyHubFilesActionOpen,
        copyHubFilesActionPin,
        copyHubFilesActionRemove,
        copyHubFilesActionRetry,
        copyHubFilesActionReveal,
        copyHubFilesActionSaveToWorkspace,
        copyHubFilesActionSweep,
        copyHubFilesActionUnpin,
        copyHubFilesCountItems,
        copyHubFilesEmpty,
        copyHubFilesEmptyHint,
        copyHubFilesEmptyTitle,
        copyHubFilesErrorImport,
        copyHubFilesErrorMissing,
        copyHubFilesErrorQuota,
        copyHubFilesErrorSave,
        copyHubFilesErrorTooLarge,
        copyHubFilesFilterAll,
        copyHubFilesFilterFiles,
        copyHubFilesFilterScreenshots,
        copyHubFilesFilterText,
        copyHubFilesFilterTransfers,
        copyHubFilesHint,
        copyHubFilesNoMatchHint,
        copyHubFilesNoMatchTitle,
        copyHubFilesNoticeDuplicate,
        copyHubFilesNoticeSaved,
        copyHubFilesNoticeSwept,
        copyHubFilesStateFetching,
        copyHubFilesStateLocal,
        copyHubFilesStateOnOtherDevice,
        copyHubFilesStateTransferFailed,
        copyHubFilesStateUnavailable,
        copyHubFilesStatusActive,
        copyHubFilesUsage,
        copyHubHomeEmptyHint,
        copyHubHomeEmptyHintEditing,
        copyHubHomeEmptyTitle,
        copyHubLogExport,
        copyHubLogView,
        copyHubPlaceholderNotice,
        copyHubTabAgent,
        copyHubTabAgentSummary,
        copyHubTabBoard,
        copyHubTabBoardSummary,
        copyHubTabClipboard,
        copyHubTabClipboardSummary,
        copyHubTabDevices,
        copyHubTabDevicesSummary,
        copyHubTabFiles,
        copyHubTabFilesSummary,
        copyHubTabNow,
        copyHubTabNowSummary,
        copyHubTabScreenshots,
        copyHubTabScreenshotsSummary,
        copyHubTabSettings,
        copyHubTabSettingsSummary,
        copyHubUpdateUpToDate,
        copyHubWidgetActionsTitle,
        copyHubWidgetBatteryTitle,
        copyHubWidgetClockTitle,
        copyHubWidgetDevicesTitle,
        copyHubWidgetRemove,
        copyHubWidgetResize,
        copyHubWidgetShotsTitle,
        copyHubWidgetSizeLarge,
        copyHubWidgetSizeSmall,
        copyHubWidgetSizeTall,
        copyHubWidgetSizeWide,
        copyHubWidgetTransferTitle,
        copyIconConceptBlueGrid,
        copyIconConceptBlueKoala,
        copyIconConceptBlueOrbit,
        copyIconConceptNotchCore,
        copyIconConceptStatusPulse,
        copyIconConceptTopShelf,
        copyIdleCancelAfter,
        copyIdlePreventIdle,
        copyIdleRemaining,
        copyIdleWhileCharging,
        copyLidBatteryRules,
        copyLidInstantSleep,
        copyLidPowerRules,
        copyLidPreventSleep,
        copyLidWarning,
        copyMacos27AlignmentMeasurement,
        copyMacos27AlignmentStaticVerified,
        copyModeDark,
        copyModeLight,
        copyMonitorBatteryRemaining,
        copyMonitorBatterySource,
        copyMonitorBatteryState,
        copyMonitorCores,
        copyMonitorDiskFree,
        copyMonitorDiskRead,
        copyMonitorDiskUsed,
        copyMonitorDiskWrite,
        copyMonitorGpuDevice,
        copyMonitorGpuMemory,
        copyMonitorHistory,
        copyMonitorLive,
        copyMonitorLoad1,
        copyMonitorMemoryPressureCritical,
        copyMonitorMemoryPressureNormal,
        copyMonitorMemoryPressureWarning,
        copyMonitorMemoryPressure,
        copyMonitorMemorySwap,
        copyMonitorMemoryTotal,
        copyMonitorMemoryUsed,
        copyMonitorNetworkDownload,
        copyMonitorNetworkInterface,
        copyMonitorNetworkUpload,
        copyMonitorPerCore,
        copyMonitorPowerAverageDraw,
        copyMonitorPowerChargeLimitApply,
        copyMonitorPowerChargeLimitApplying,
        copyMonitorPowerChargeLimitCurrentCharge,
        copyMonitorPowerChargeLimitCurrentTarget,
        copyMonitorPowerChargeLimitEnable,
        copyMonitorPowerChargeLimitFailed,
        copyMonitorPowerChargeLimitHelperRequired,
        copyMonitorPowerChargeLimitRestore,
        copyMonitorPowerChargeLimitResumeAt,
        copyMonitorPowerChargeLimitStateAboveLimit,
        copyMonitorPowerChargeLimitStateBypass,
        copyMonitorPowerChargeLimitStateCalibration,
        copyMonitorPowerChargeLimitStateConflict,
        copyMonitorPowerChargeLimitStateError,
        copyMonitorPowerChargeLimitStateHolding,
        copyMonitorPowerChargeLimitStateProtection,
        copyMonitorPowerChargeLimitStateSailing,
        copyMonitorPowerChargeLimitStateSystem,
        copyMonitorPowerChargeLimitStateUnplugged,
        copyMonitorPowerChargeLimitTitle,
        copyMonitorPowerChargeLimitUnsupported,
        copyMonitorPowerChargeHealth,
        copyMonitorPowerChargePower,
        copyMonitorPowerChargeTimeToFull,
        copyMonitorPowerChargeTitle,
        copyMonitorPowerCriticalBattery,
        copyMonitorPowerDetailsClose,
        copyMonitorPowerDetailsCollapse,
        copyMonitorPowerDetailsExpand,
        copyMonitorPowerDetailsTitle,
        copyMonitorPowerDraw,
        copyMonitorPowerEstimateBasis,
        copyMonitorPowerEventsConnected,
        copyMonitorPowerEventsDisconnected,
        copyMonitorPowerEventsFullyCharged,
        copyMonitorPowerEventsTitle,
        copyMonitorPowerHighTemperature,
        copyMonitorPowerHistoryAccumulating,
        copyMonitorPowerHistoryTitle,
        copyMonitorPowerLowBattery,
        copyMonitorPowerNoBattery,
        copyMonitorPowerNoData,
        copyMonitorPowerReadFailed,
        copyMonitorPowerRemaining,
        copyMonitorPowerStateBattery,
        copyMonitorPowerStateConnected,
        copyMonitorPowerTemperature,
        copyMonitorPowerTopApps,
        copyMonitorPowerTrendTitle,
        copyMonitorPowerTrendWindow,
        copyMonitorSamplingFast,
        copyMonitorSamplingSlow,
        copyMonitorStateAcPower,
        copyMonitorStateCharged,
        copyMonitorStateCharging,
        copyMonitorStateOnBattery,
        copyMonitorStateUnknown,
        copyMonitorThermal,
        copyMonitorThermalCritical,
        copyMonitorThermalFair,
        copyMonitorThermalNominal,
        copyMonitorThermalSerious,
        copyMonitorTitleBattery,
        copyMonitorTitleCpu,
        copyMonitorTitleDisk,
        copyMonitorTitleGpu,
        copyMonitorTitleMemory,
        copyMonitorTitleNetwork,
        copyMonitorUnavailable,
        copyMonitorUptime,
        copyMonitorUsage,
        copyNavBattery,
        copyNavGeneral,
        copyNavIdle,
        copyNavLid,
        copyNavOverview,
        copyNavQuit,
        copyNavRailLabel,
        copyNavSearchEmpty,
        copyNavSearchPlaceholder,
        copyNavSearchResults,
        copyNavStatusPaused,
        copyNavStatusRunning,
        copyNavTopShelf,
        copyNotchHubLayoutCollapsedPresence,
        copyNotchHubLayoutDragTarget,
        copyNotchHubLayoutExpandedOutput,
        copyNotchHubStateActive,
        copyNotchHubStateCollapsed,
        copyNotchHubStateDragTarget,
        copyNotchHubStateError,
        copyNotchHubStateExit,
        copyNotchHubStateExpanded,
        copyNotchHubStateHidden,
        copyNotchHubStateHover,
        copyNotchHubStateOpen,
        copyNotchHubStateProcessing,
        copyNotchHubStateReady,
        copyOverviewActionDisplayOff,
        copyOverviewActionSleepNow,
        copyOverviewHelperInstall,
        copyOverviewHelperInstalled,
        copyOverviewHelperMissing,
        copyOverviewHelperVersion,
        copyOverviewRulesMaster,
        copyPageBatteryStateDisabled,
        copyPageBatteryStateEmpty,
        copyPageBatteryStateError,
        copyPageBatteryStateLoading,
        copyPageBatteryStateNormal,
        copyPageBatteryStateSuccess,
        copyPageBatteryStateWarning,
        copyPageBatterySummary,
        copyPageBatteryTitle,
        copyPageGeneralStateDisabled,
        copyPageGeneralStateEmpty,
        copyPageGeneralStateError,
        copyPageGeneralStateLoading,
        copyPageGeneralStateNormal,
        copyPageGeneralStateSuccess,
        copyPageGeneralStateWarning,
        copyPageGeneralSummary,
        copyPageGeneralTitle,
        copyPageIdleStateDisabled,
        copyPageIdleStateEmpty,
        copyPageIdleStateError,
        copyPageIdleStateLoading,
        copyPageIdleStateNormal,
        copyPageIdleStateSuccess,
        copyPageIdleStateWarning,
        copyPageIdleSummary,
        copyPageIdleTitle,
        copyPageLidStateDisabled,
        copyPageLidStateEmpty,
        copyPageLidStateError,
        copyPageLidStateLoading,
        copyPageLidStateNormal,
        copyPageLidStateSuccess,
        copyPageLidStateWarning,
        copyPageLidSummary,
        copyPageLidTitle,
        copyPageOverviewStateDisabled,
        copyPageOverviewStateEmpty,
        copyPageOverviewStateError,
        copyPageOverviewStateLoading,
        copyPageOverviewStateNormal,
        copyPageOverviewStateSuccess,
        copyPageOverviewStateWarning,
        copyPageOverviewSummary,
        copyPageOverviewTitle,
        copyPageTopShelfSettingsStateDisabled,
        copyPageTopShelfSettingsStateEmpty,
        copyPageTopShelfSettingsStateError,
        copyPageTopShelfSettingsStateLoading,
        copyPageTopShelfSettingsStateNormal,
        copyPageTopShelfSettingsStateSuccess,
        copyPageTopShelfSettingsStateWarning,
        copyPageTopShelfSettingsSummary,
        copyPageTopShelfSettingsTitle,
        copyStateCancel,
        copyStateComponentToolbarDefaultDisabled,
        copyStateComponentToolbarDefaultFocused,
        copyStateComponentToolbarDefaultHover,
        copyStateComponentToolbarDefaultPressed,
        copyStateDisabled,
        copyStateEmpty,
        copyStateError,
        copyStateLoading,
        copyStateNormal,
        copyStateRetry,
        copyStateSuccess,
        copyStateWarning,
        copyStatusItemCharging,
        copyStatusItemDefault,
        copyStatusItemDisabled,
        copyStatusItemHelperError,
        copyStatusItemIdlePrevented,
        copyStatusItemLidPrevented,
        copyStatusItemLowBattery,
        copyToastError,
        copyToastSuccess,
        copyToastWarning,
        copyTopShelfActionClearAll,
        copyTopShelfActionCopy,
        copyTopShelfActionHideToolbar,
        copyTopShelfActionMarkup,
        copyTopShelfActionOpenFolder,
        copyTopShelfActionPreview,
        copyTopShelfActionRemove,
        copyTopShelfActionRemoveFromShelf,
        copyTopShelfActionShowToolbar,
        copyTopShelfActionWorkspace,
        copyTopShelfClear,
        copyTopShelfEmpty,
        copyTopShelfEnabled,
        copyTopShelfErrorCopy,
        copyTopShelfErrorDirectory,
        copyTopShelfErrorMarkup,
        copyTopShelfErrorMove,
        copyTopShelfErrorOpen,
        copyTopShelfErrorRestore,
        copyTopShelfErrorTakeover,
        copyTopShelfNone,
        copyTopShelfOpenFolder,
        copyTopShelfPendingNotice,
        copyTopShelfShow,
        copyTopShelfSounds,
        copyTopShelfStateCancel,
        copyTopShelfStateDragToApp,
        copyTopShelfStateDragToFolder,
        copyTopShelfStateDragToTrash,
        copyTopShelfStateHover,
        copyTopShelfStateRightClickMenu,
        copyTopShelfStatus,
        copyTopShelfTakeOver,
        copyTopShelfTitle,
        copyTrayActionDisplayOff,
        copyTrayActionQuit,
        copyTrayActionSettings,
        copyTrayActionShowShelf,
        copyTrayActionSleepNow,
        copyTrayTooltipBattery,
        copyTrayTooltipCharging,
        copyTrayTooltipHelperError,
        copyTrayTooltipIdlePrevented,
        copyTrayTooltipLidPrevented,
        copyTrayTooltipLowBattery,
        copyTrayTooltipNormal,
    ]
}
