# 结论与限制

## 1. 结论摘要

“面板黑屏，framebuffer 保持活动”是可行的机制解释。
物理面板亮度 `0.0` 与 WindowServer 合成帧存在可以同时成立。
Computer Use 等工具可能通过 ScreenCaptureKit 或合成帧取得画面。
它们不直接读取物理面板。

当前证据支持机制链路。
当前证据没有证明任意 Computer Use 工具在合盖黑屏下都能截图。
因此产品文案应使用“可能”和“不保证”。

## 2. 主要原因

### 2.1 亮度位于显示输出之后

像素先由应用和 WindowServer 生成。
显示控制器读取帧缓冲。
面板亮度决定人眼看到多亮。

亮度为 `0.0` 时，像素仍可能存在。
用户看不到画面不证明合成结果不存在。

### 2.2 捕获读取合成结果

`CGDisplayStream` 的帧来自 WindowServer。
ScreenCaptureKit 按 display、window 或 application 选择内容。
捕获面不是物理面板。

只要逻辑显示器和捕获权限允许，捕获工具可能得到正常图像。
这条推论需要 ScreenCaptureKit 和 Computer Use 实测确认。

### 2.3 显示电源与系统电源不同

系统 awake 不代表显示器 active。
显示器 active 不代表面板可见。
显示器 online、active、asleep 是三个不同状态。

Covio 的零亮度路径避免公开 `displaysleepnow`。
它仍依赖 macOS 保持逻辑显示器 online 和 active。

### 2.4 私有 API 是主要风险

DisplayServices 没有公开头文件。
没有符号、调用约定或行为兼容承诺。
macOS 更新可能改变行为。

## 3. 证据链

| 结论 | 证据 |
| --- | --- |
| active 表示 connected、awake、drawable | `CGDisplayConfiguration.h` |
| asleep 表示不可绘制 | `CGDisplayConfiguration.h` |
| CGDisplayStream 从 WindowServer 接收 IOSurface | `CGDisplayStream.h` |
| ScreenCaptureKit 按 display 或 window 捕获 | `SCStream.h`、`SCScreenshotManager.h` |
| DisplayServices 可读可写亮度 | 本机 dlopen 和真机矩阵 |
| 零亮度时内建屏仍 online、active、未 asleep | issue #203 真机记录 |
| Computer Use 合盖黑屏捕获未验证 | 本报告验证矩阵 |

## 4. 决策表

| 决策 | 选择 | 原因 |
| --- | --- | --- |
| 是否保留零亮度模式 | 保留为实验能力 | 机制可行，但依赖私有 API |
| 是否默认开启 | 否 | macOS 更新和恢复风险 |
| 是否称最低亮度 | 否 | `0.0` 接近黑屏 |
| 是否称 framebuffer 一定可用 | 否 | 没有捕获实测 |
| 是否允许外接屏时写内建屏 | 否 | 显示组合和恢复风险 |
| 是否把窗口捕获作为唯一实现 | 否 | Computer Use 可能捕获整个显示 |
| 是否使用 gamma 黑屏 | 否 | 不满足硬件亮度语义 |

## 5. 对用户问题的直接回答

问题：

> Computer Use 等可以通过 framebuffer 拿到屏幕画面，但屏幕实际没点亮吗？

答案：

可以，但不是直接读取物理 framebuffer。
Computer Use 更可能通过 macOS 合成器和屏幕捕获 API 取得画面。
在合盖黑屏模式下，物理面板亮度为 `0.0`，逻辑显示器和合成帧可能仍在线。
因此捕获工具可能看到正常桌面，而用户看不到物理画面。

这个结论的置信度分开计算：

| 部分 | 置信度 |
| --- | --- |
| 面板亮度与合成帧不是同一层 | 高 |
| WindowServer 向捕获 API 提供 IOSurface | 高 |
| 合盖零亮度后逻辑显示器仍 active | 高，已有真机记录 |
| ScreenCaptureKit 在该状态能拿到非空画面 | 中，待验证 |
| 具体 Computer Use 工具能拿到画面 | 中，取决于实现和权限 |

## 6. 不采用方案

### 6.1 只设置 disablesleep

可能留下亮屏。
不能保证面板不可见。

### 6.2 只调用 displaysleepnow

显示 asleep 后不可绘制。
捕获可能返回空白。
不符合“framebuffer 保持活动”的目标。

### 6.3 Gamma 黑屏

不让面板亮度归零。
会改变颜色路径和截图结果。
不符合硬件亮度语义。

### 6.4 黑窗口覆盖

不改变显示电源和面板亮度。
捕获和交互语义不可靠。

## 7. 系统限制

1. macOS 可能在不同机型移除合盖内建屏 ID。
2. WindowServer 可能暂停无变化画面的帧更新。
3. 显示器 asleep 时捕获可能返回 `FrameBlank`。
4. 锁屏、安全输入和 DRM 可能阻止内容捕获。
5. DisplayServices 私有符号可能变化。

## 8. 产品限制

1. 该能力必须默认关闭。
2. UI 必须说明 `0.0` 不是可见最低亮度。
3. UI 必须说明 Computer Use 和远程截图不保证可用。
4. 失败时必须回退公开合盖关屏。
5. 外接屏存在时不得写内建屏。
6. 开盖、退出和崩溃恢复必须运行。

## 9. 未决项

| 项目 | 状态 | 下一步 |
| --- | --- | --- |
| ScreenCaptureKit 合盖黑屏截图 | 未执行 | 跑验证案例 |
| Computer Use 合盖黑屏截图 | 未执行 | 使用目标 Computer Use 工具 |
| 合盖关屏对照 | 未执行 | 比较空白和错误结果 |
| 锁屏与安全输入 | 未执行 | 分别验证 |
| DRM 内容 | 未执行 | 使用受控测试内容 |
| 外接屏组合 | 部分设计 | 真机验证 |
| macOS 26 | 未验证 | 独立测试 |
| Intel Mac | 不支持或未验证 | 独立测试 |
