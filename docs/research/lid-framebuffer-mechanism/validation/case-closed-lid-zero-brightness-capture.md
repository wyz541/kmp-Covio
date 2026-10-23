# Case 2：合盖黑屏捕获

## 状态

待执行。

## 目标

验证面板亮度为 `0.0` 时，系统仍在线并可被捕获。

## 前置

1. helper 已安装并通过版本校验。
2. 当前没有外接显示器。
3. 已经备份当前亮度。
4. 已启用实验性合盖黑屏。
5. 捕获工具已获得 Screen Recording 权限。
6. 不处理敏感窗口。

## 步骤

1. 记录开盖亮度。
2. 保存开盖截图基线。
3. 启动 15 分钟合盖会话。
4. 合上上盖。
5. 读取 `AppleClamshellState`。
6. 读取 `CGDisplayIsOnline`、`CGDisplayIsActive` 和 `CGDisplayIsAsleep`。
7. 读取内建屏亮度。
8. 用 ScreenCaptureKit 捕获主显示器。
9. 用 `screencapture` 捕获主显示器。
10. 用 Computer Use 执行截图。
11. 比较三张图。
12. 打开上盖。
13. 恢复亮度。
14. 结束会话。
15. 检查电源状态。

## 必须观察

| 项目 | 期望 |
| --- | --- |
| 系统 | awake |
| 合盖状态 | Yes |
| online | 1 |
| active | 1 |
| asleep | 0 |
| brightness | 0.0 |
| ScreenCaptureKit | 非空图像或明确错误 |
| screencapture | 非空图像或明确错误 |
| Computer Use | 非空图像或明确错误 |
| 开盖恢复 | 原亮度 |
| SleepDisabled | 0 |

## 失败判定

出现以下任一条件时失败：

1. 系统睡眠。
2. 内建屏 active 为 0。
3. 内建屏 asleep 为 1。
4. 捕获返回全黑图片。
5. 捕获没有错误信息。
6. 开盖后亮度不恢复。
7. `SleepDisabled` 残留为 1。

## 证据

保存以下内容：

1. 显示状态文本。
2. 亮度回读。
3. 捕获尺寸。
4. 捕获错误码。
5. 非黑像素统计。
6. 恢复记录状态。

不保存含隐私的截图到仓库。

## 清理

1. 打开上盖。
2. 结束会话。
3. 恢复原亮度。
4. 释放租约。
5. 确认 `SleepDisabled=0`。
6. 确认 `sleep_owner` 不存在。
7. 删除临时截图。
