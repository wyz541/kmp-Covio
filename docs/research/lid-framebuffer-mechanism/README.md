# 合盖黑屏与 framebuffer 显示链路

## 前因

Covio 的“实验性合盖黑屏”让内建面板亮度变为 `0.0`，同时希望显示链路继续存在。
该能力可能支持 Computer Use、ScreenCaptureKit 或远程桌面取得画面。
用户需要理解物理面板、framebuffer、WindowServer 和屏幕捕获之间的真实关系。

前因、问题定义和状态模型见 [context.md](context.md)。

## 背景

macOS 没有公开 API 叫“保持 framebuffer 活动”。
现代 macOS 使用 WindowServer、IOSurface、IOFramebuffer 和 display controller 组成图形路径。
面板亮度、显示电源状态和系统睡眠状态是三个不同层次。
背景和候选路径见 [context.md](context.md) 与 [investigation.md](investigation.md)。

## 过程

调研使用以下材料：

1. macOS 27 SDK 的 CoreGraphics、ScreenCaptureKit 和 IOKit 头文件。
2. DisplayServices 私有框架元数据和动态符号探针。
3. Covio 的真实实现与既有合盖矩阵。
4. Keepresso、Insomnia、DontSleep 和 LidAwake 的源码。

调研方法、控制路径和参考实现见 [investigation.md](investigation.md)。
原始观察和来源摘要见 [evidence.md](evidence.md)。

## 结果

主要结论如下：

1. `0.0` 亮度只改变面板可见亮度。
2. framebuffer 活动表示显示输出链路仍可提供合成帧。
3. 物理面板不可见，不代表捕获 API 一定拿不到图像。
4. Computer Use 可能读取合成结果，但它不直接读取面板。
5. 当前没有完成 Computer Use 合盖截图验收。

完整结论和限制见 [conclusion.md](conclusion.md)。
证据链和置信度见 [evidence.md](evidence.md)。

## 预期

Covio 应把该能力保持在实验路径。
成功条件包括：

1. 合盖后系统保持运行。
2. 内建屏保持 online、active、未 asleep。
3. 亮度稳定为 `0.0`。
4. 捕获工具能得到非空画面，或明确返回不可用。
5. 开盖、退出和崩溃恢复后亮度恢复。

推荐控制流程见 [solution.md](solution.md)。
验证矩阵见 [validation/README.md](validation/README.md)。

## 实现预期的手段

1. helper 持有合盖租约，执行 `pmset disablesleep 1`。
2. 不调用公开 `displaysleepnow`。
3. 通过私有 `DisplayServicesSetBrightness` 把面板设为 `0.0`。
4. 用 `CGDisplayIsOnline`、`CGDisplayIsActive` 和 `CGDisplayIsAsleep` 验证逻辑显示状态。
5. 用 ScreenCaptureKit 或 `screencapture` 验证捕获结果。
6. 失败时回退公开合盖关屏。

接口和不变量见 [solution.md](solution.md)。
执行步骤与清理要求见 [validation/README.md](validation/README.md)。
证据编号见 [evidence.md](evidence.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题、系统模型和状态矩阵 |
| [investigation.md](investigation.md) | SDK、控制路径、候选方案和参考实现 |
| [conclusion.md](conclusion.md) | 结论、限制和未决项 |
| [solution.md](solution.md) | 推荐控制流程和验收条件 |
| [evidence.md](evidence.md) | 来源、命令、观察和置信度 |
| [validation/README.md](validation/README.md) | 验证总表和清理要求 |
| [validation/case-open-display-capture.md](validation/case-open-display-capture.md) | 开盖基线捕获 |
| [validation/case-closed-lid-zero-brightness-capture.md](validation/case-closed-lid-zero-brightness-capture.md) | 合盖黑屏捕获计划 |

## 证据链阅读顺序

1. 阅读 [context.md](context.md) 的层模型和状态矩阵。
2. 阅读 [investigation.md](investigation.md) 的控制路径。
3. 用 [evidence.md](evidence.md) 核对每个事实。
4. 用 [conclusion.md](conclusion.md) 查看结论和限制。
5. 用 [validation/README.md](validation/README.md) 重跑验证。

## 更新规则

1. macOS 主版本变化时重跑显示状态和亮度探针。
2. 修改显示控制代码时更新目标 commit。
3. 完成 Computer Use 合盖截图后更新结论和验证案例。
4. 私有符号变化时更新证据和回退策略。
