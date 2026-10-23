# 调研与系统控制路径

## 1. 调研方法

### 1.1 SDK 头文件

使用 macOS 27 SDK 核对这些公开语义：

| 头文件 | 用途 |
| --- | --- |
| `CoreGraphics/CGDisplayConfiguration.h` | online、active、asleep |
| `CoreGraphics/CGDisplayStream.h` | WindowServer 到 IOSurface 的帧交付 |
| `CoreGraphics/CGWindow.h` | 窗口合成和屏幕捕获函数 |
| `ScreenCaptureKit/SCStream.h` | display、window、application 捕获过滤器 |
| `ScreenCaptureKit/SCScreenshotManager.h` | 捕获单帧图片 |
| `IOKit/graphics/IOGraphicsLib.h` | IOFramebuffer、IOAccelerator 和显示参数 |
| `IOKit/pwr_mgt/IOPMLib.h` | 系统与显示电源断言 |

### 1.2 本机探针

本机执行以下只读检查：

1. 读取 `CGDisplayIsOnline`、`CGDisplayIsActive` 和 `CGDisplayIsAsleep`。
2. 读取显示模式、像素尺寸和刷新率。
3. 动态加载 `DisplayServices`。
4. 读取内建屏亮度。
5. 使用 `screencapture` 取得开盖基线图。

### 1.3 Covio 源码

目标 commit：`b7065b2`。

关键实现：

1. `macosApp/src/Power/ClosedLidZeroBrightnessController.swift`
2. `macosApp/src/Power/ClosedLidBrightnessBackend.swift`
3. `macosApp/src/Power/PowerRuntime.swift`
4. `kmpDomain/src/com/wyz/covio/core/Engine.kt`
5. `macosApp/src/Platform/HelperLeaseCoordinator.swift`

### 1.4 参考实现

审计了以下仓库：

1. `gyorgysh/keepresso`
2. `krishhgg/Insomnia`
3. `innocarpe/dontsleep`
4. `richardlinq/lidawake`

## 2. 领域模型

### 2.1 渲染层

应用通过 AppKit、SwiftUI 或 Metal 提交绘制命令。

### 2.2 WindowServer

WindowServer 负责窗口合成。
`CGDisplayStream.h` 明确写明：
帧由 WindowServer 为一个显示器生成。
回调收到包含像素数据的 `IOSurfaceRef`。

### 2.3 帧缓冲

现代 macOS 更接近“多 IOSurface 队列”，不是单一传统固定 framebuffer。
因此“framebuffer 保持活动”应理解为：
WindowServer 和显示输出仍有有效的共享帧资源。

### 2.4 显示输出

`IOGraphicsLib.h` 说明用户态可以通过 IOFramebuffer 和 IOAccelerator 接口访问图形族对象。
这些对象描述模式、像素格式、显示参数和显示硬件。

### 2.5 面板亮度

`DisplayServicesSetBrightness(displayID, 0.0)` 只证明亮度值被接受。
公开头文件没有说明它作用于背光、面板控制器还是其它亮度层。
本机证据只能确认可见亮度和回读值变化。

### 2.6 捕获层

`CGDisplayStream` 从 WindowServer 接收合成帧。
ScreenCaptureKit 通过 display、window 或 application 过滤器选择内容。
`SCScreenshotManager` 捕获单帧。
捕获路径读取的是合成结果，不是物理面板的亮度。

## 3. 约束模型

1. `0.0` 不是可见最低亮度。
2. 显示 online 不等于显示 active。
3. 显示 active 不等于捕获权限已授予。
4. 系统 awake 不等于 WindowServer 一定生成新帧。
5. 捕获成功不等于锁屏、DRM 或安全输入内容可见。
6. 私有 DisplayServices 符号没有兼容承诺。
7. 外接显示器和内建屏必须分开处理。

## 4. 控制路径

### 4.1 保持系统运行

```text
Covio
  -> helper lease
  -> pmset -a disablesleep 1
  -> system sleep blocked
```

事实：现有真机验证中 `SleepDisabled=1`，启动时间不变。
限制：`pmset disablesleep` 没有出现在 `man pmset` 的公开设置列表。

### 4.2 保持显示器 online 和 active

```text
Covio zero-brightness mode
  -> disable public displaysleepnow path
  -> keep helper lease
  -> display remains online, active, not asleep
```

这是本机观察到的状态。
它不是公开 API 保证。
不同 macOS、机型和电源状态仍需验证。

### 4.3 让面板不可见

```text
built-in display ID
  -> DisplayServicesGetBrightness
  -> DisplayServicesSetBrightness(0.0)
  -> readback 0.0
```

亮度位于显示输出之后。
亮度写入不必然改变 framebuffer 内容。
因此“面板黑”和“帧仍存在”可以同时成立。

### 4.4 捕获合成结果

```text
ScreenCaptureKit or CGDisplayStream
  -> WindowServer
  -> IOSurface frame
  -> CGImage or CMSampleBuffer
```

Computer Use 的具体实现没有公开。
它可能使用上述路径之一。
它也可能只捕获单个窗口或使用辅助功能树。
因此不能对任意 Computer Use 工具作统一保证。

## 5. 信任边界

| 边界 | 风险 | 控制 |
| --- | --- | --- |
| App 到 helper | 普通进程请求系统级设置 | Unix socket、UID 和签名检查 |
| 私有 DisplayServices | macOS 更新移除符号 | 动态加载、版本白名单、回读、回退 |
| App 到 WindowServer | 当前用户会话失效 | 检查 GUI 会话和捕获错误 |
| 捕获 API | TCC、锁屏、DRM | 权限检查、错误显示、不绕过安全边界 |
| 内建屏与外接屏 | 错把外接屏状态用于内建屏 | 按 `CGDirectDisplayID` 分开读取 |

## 6. 原生能力矩阵

| 能力 | API | 公开性 | 本机结果 | 限制 |
| --- | --- | --- | --- | --- |
| 查询 online | `CGDisplayIsOnline` | 公开 | 开盖 `1` | 只表示连接 |
| 查询 active | `CGDisplayIsActive` | 公开 | 开盖 `1` | 只表示 awake 和可绘制 |
| 查询 asleep | `CGDisplayIsAsleep` | 公开 | 开盖 `0` | 不证明捕获权限 |
| 读取帧 | `CGDisplayStream` | 公开但已过时 | 未在合盖黑屏重跑 | macOS 15 起旧 API 过时 |
| 捕获显示 | ScreenCaptureKit | 公开 | 开盖基线用 `screencapture` 通过 | 合盖黑屏未验证 |
| 设置亮度 | DisplayServices | 私有 | 写入 `0.0` 和恢复通过 | 无兼容承诺 |
| 禁止合盖睡眠 | `pmset disablesleep` | 未文档化 | 通过 | 需要 root |
| 空闲系统断言 | IOPMAssertion | 公开 | 未阻止合盖 | 头文件明确说明合盖仍可睡眠 |
| 空闲显示断言 | IOPMAssertion | 公开 | 不点亮已关闭显示 | 不能单独实现本需求 |

## 7. 候选方案对比

| 方案 | 成本 | 风险 | 成熟度 | 可维护性 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 只保持系统 awake | 低 | 面板仍亮或由系统关闭 | 高 | 高 | 不足 |
| 合盖后 display sleep | 低 | 不可绘制，捕获可能失败 | 高 | 高 | 公开回退 |
| 亮度设 `0.0` | 中 | 私有 API、恢复风险 | 多仓库实践 | 中 | 当前实验路径 |
| gamma 黑屏 | 中 | 不改变硬件亮度，破坏颜色路径 | 中 | 低 | 拒绝 |
| 黑窗口覆盖 | 低 | 不改变显示电源，交互和捕获语义错误 | 高 | 低 | 拒绝 |
| 虚拟显示器 | 高 | 架构和权限成本大 | 中 | 中 | 后续独立研究 |

## 8. 目标产品源码分析

### 8.1 合盖租约

`HelperLeaseCoordinator` 维护多个 lease。
lease 到期或释放后，helper 清除 Covio 拥有的 `SleepDisabled`。
外接屏存在时拒绝合盖 lease。

### 8.2 显示路径选择

`PowerRuntime.applyClosedLidZeroBrightness` 在私有路径可用时关闭公开 `powerLidDisplayOff`。
因此普通合盖关屏请求不会发送。
该逻辑只适用于无外接屏和内建屏可定位的场景。

### 8.3 亮度状态机

`ClosedLidZeroBrightnessController` 做以下动作：

1. 检查 macOS 版本和 Apple Silicon。
2. 动态加载 DisplayServices。
3. 先写恢复记录。
4. 合盖后写 `0.0`。
5. 立即回读。
6. 开盖、结束、退出或启动恢复。
7. 失败时回退公开关屏。

### 8.4 现有验证

issue #203 的真机记录：

1. 合盖状态为 Yes。
2. helper 租约持续续租。
3. `SleepDisabled=1`。
4. 内建屏 online、active、未 asleep。
5. 连续 6 次亮度采样为 `0.0`。
6. 开盖和结束恢复通过。
7. `SIGKILL` 后下次启动恢复通过。

## 9. 参考实现分析

### Keepresso

Keepresso 把策略分为 `displayOff`、`zeroBrightness` 和 `leaveAlone`。
源码注释明确写明：
`zeroBrightness` 时面板看起来关闭，但 framebuffer 仍可服务远程会话。
本报告的快照 SHA-256 见 [evidence.md](evidence.md)。

### Insomnia

Insomnia 说明在 `pmset disablesleep 1` 下，合盖不会走系统睡眠路径。
因此面板和键盘背光仍需单独处理。
它使用 `DisplayServicesSetBrightness(0)`。

### DontSleep

DontSleep 同样说明只设置 `disablesleep` 会留下亮屏。
它用 DisplayServices 关闭内建屏。

### LidAwake

LidAwake 记录 `pmset displaysleepnow` 在 `SleepDisabled=1` 时不可靠。
因此它改用 DisplayServices 设置亮度。

## 10. 反证和限制

1. 面板黑屏不等于 framebuffer 一定有效。
2. 显示器 online 不等于 WindowServer 一定生成新帧。
3. 显示器 active 不等于捕获权限已授予。
4. Computer Use 可能使用窗口捕获、辅助功能或其它后端。
5. 锁屏和安全输入可能阻止捕获。
6. DRM 内容可能返回黑帧。
7. `DisplayServices` 没有稳定公开语义。
8. 合盖后 macOS 可能在不同机型上移除内建屏 ID。

## 11. 已知缺口

1. 没有在合盖黑屏状态运行 ScreenCaptureKit 截图。
2. 没有在合盖黑屏状态运行 Computer Use。
3. 没有比较合盖关屏与合盖黑屏的捕获结果。
4. 没有验证锁屏、DRM 和外接屏组合。
5. 没有验证 macOS 26、Intel 和其它 Apple Silicon 机型。
