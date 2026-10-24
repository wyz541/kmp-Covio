# 证据附录

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 可评审 |
| 日期 | `2026-10-24` |
| 问题类别 | 系统策略的可恢复自动化 |
| 主文 | [主题索引](README.md) |
| 验证目录 | [验证计划](validation/README.md) |

## 1. 问题类别和案例映射

本研究讨论专注配置的进入、运行和退出。
`Case 1` 记录只读能力探针。
`Case 2` 记录系统调整与恢复计划。
只读事实支持能力判断。
系统写入结论要等 `Case 2`。

## 2. 来源等级

| 等级 | 来源 | 用途 |
| --- | --- | --- |
| A | SDK 头文件、Apple 接口文档、本机工具帮助 | 权威接口边界 |
| B | Covio 固定 commit 的源码 | 实现边界 |
| C | Apple Mac Help | 产品能力说明 |
| D | 本机只读探针 | 当前环境事实 |
| E | 第三方资料 | 不用于关键决策 |

## 3. 环境事实

| 项目 | 值 | 证据 |
| --- | --- | --- |
| 系统 | macOS 27.0.1 | E-01 |
| 构建 | 26A434 | E-01 |
| Xcode | 27.1 | E-01 |
| SDK | MacOSX27.0 | E-01 |
| Covio | 0.5.0 | E-01、E-17 |
| 部署目标 | macOS 26.0 | E-01 |
| 目标 commit | `28d97d89ab192867df413e59115d19683062465a` | E-01 |

### 3.1 复现命令

```sh
sw_vers
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
shortcuts help
shortcuts help run
rg -n 'MACOSX_DEPLOYMENT_TARGET|MARKETING_VERSION' macosApp/Covio.xcodeproj/project.pbxproj
```

## 4. 证据索引

| 编号 | 主题 | 等级 | 置信度 |
| --- | --- | --- | --- |
| E-01 | 本机与目标版本 | D/B | 高 |
| E-02 | Focus 内置与自定义能力 | C | 中高 |
| E-03 | Focus 手动开关和时长 | C | 中高 |
| E-04 | Shortcuts 命令行 | A/C | 高 |
| E-05 | `Set Focus` 动作 | A | 高 |
| E-06 | SDK 无公开 Focus 写入 | A | 高 |
| E-07 | Focus 状态读取接口 | A | 高 |
| E-08 | Focus 状态本机探针 | D | 高，范围小 |
| E-09 | 应用启动接口 | A | 高 |
| E-10 | 隐藏和退出接口 | A | 高 |
| E-11 | 电源断言接口 | A/B | 高 |
| E-12 | 输出音量接口 | A | 高 |
| E-13 | Wi-Fi 开关接口 | A | 高 |
| E-14 | 蓝牙公开写入缺口 | A | 中高 |
| E-15 | 私有亮度路径 | B | 高，范围小 |
| E-16 | 壁纸接口 | A | 高 |
| E-17 | Covio 现有源码边界 | B | 高 |
| E-18 | 多来源唤醒租约 | B | 高 |
| E-19 | 当前 Shortcut 环境 | D | 高，范围小 |
| E-20 | Accessibility 权限边界 | A/B | 高 |

## 5. 证据详情

### E-01：本机与目标版本

来源等级：D、B。
环境：当前开发机与 `main` commit `28d97d8`。
命令或来源：`sw_vers`、`xcodebuild -version`、`xcrun --sdk macosx --show-sdk-version`、Xcode 工程配置。
关键输出：

```text
macOS 27.0.1
Build 26A434
Xcode 27.1
SDK 27.0
MARKETING_VERSION 0.5.0
MACOSX_DEPLOYMENT_TARGET 26.0
```

观察：当前 SDK 为 macOS 27。
观察：Covio 目标为 macOS 26 及以上。
推论：本机结论适用于 macOS 27。
限制：结论不自动适用于 macOS 26。
置信度：高。
关联：全部证据。

### E-02：Focus 内置与自定义能力

来源等级：C。
环境：macOS 27 Apple Mac Help。
命令或来源：[Set up a Focus on Mac](https://support.apple.com/guide/mac-help/set-up-a-focus-to-stay-on-task-mchl613dc43f/mac)。
关键输出：

```text
Add a provided Focus, such as Gaming or Work
Create a custom Focus, such as Study
You can create up to ten
Allow only certain notifications
Set up Focus Filters for Calendar, Mail, Messages, Safari
```

观察：系统支持内置 Focus 和自定义 Focus。
观察：系统支持通知允许列表和内容过滤器。
推论：Covio 不应重新实现通知过滤。
限制：页面描述用户界面能力，不提供第三方写入接口。
置信度：中高。
关联：解决方案 3.1 至 3.5。

### E-03：Focus 手动开关和时长

来源等级：C。
环境：macOS 27 Apple Mac Help。
命令或来源：[Turn a Focus on or off on Mac](https://support.apple.com/guide/mac-help/turn-a-focus-on-or-off-mchl999b7c1a/mac)。
关键输出：

```text
Open Control Center
Click the Focus
Choose a duration
Turn off the Focus by clicking it
```

观察：用户可从 Control Center 开关 Focus。
观察：Focus 支持按时长结束。
推论：Focus 的生命周期应由系统维护。
限制：页面不提供应用调用接口。
置信度：中高。
关联：解决方案 4.1、4.2。

### E-04：Shortcuts 命令行

来源等级：A、C。
环境：macOS 27，Shortcuts 10.0。
命令或来源：`shortcuts help`、`shortcuts help run`、[Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)。
关键输出：

```text
Subcommands: run, list, view, sign
shortcuts run <shortcut-name-or-identifier>
The shortcuts command exits 0 on success or 1 on error.
```

观察：命令行可以运行已有 Shortcut。
观察：命令行返回明确退出码。
推论：Covio 可把 Shortcut 作为系统编排入口。
限制：Covio 仍要处理超时和名称变化。
置信度：高。
关联：解决方案 1.3、2.6、4.1。

### E-05：`Set Focus` 动作

来源等级：A。
环境：Shortcuts 10.0 本机资源。
命令或来源：`plutil -convert xml1 ...WorkflowKit/.../Localizable.loctable`。
关键输出：

```text
Set Focus (Action Name)
Returns the currently active Focus.
Turn On
Turn Off
The time after which to turn off the Focus
```

观察：Shortcuts 存在 `Set Focus` 动作。
观察：动作支持开启、关闭和结束时间。
推论：用户可创建进入和退出 Focus 的 Shortcut。
限制：动作参数和 UI 仍由 Shortcuts 管理。
置信度：高。
关联：解决方案 1.1、5.2。

### E-06：SDK 无公开 Focus 写入

来源等级：A。
环境：MacOSX27.0 SDK。
命令或来源：`INFocusStatusCenter.h`、`INFocusStatus.h`、Intents 头文件检索。
关键输出：

```text
INFocusStatusCenter.defaultCenter
INFocusStatusCenter.focusStatus
INFocusStatusCenter.requestAuthorization
INFocusStatus.isFocused
```

观察：公开 Intents 头文件提供状态读取和授权。
观察：公开头文件未提供 Focus 开启、关闭或改名接口。
推论：Covio 不应依赖公开 Focus setter。
限制：头文件检索不能证明系统没有私有接口。
置信度：高。
关联：结论 2.1.1、6。

### E-07：Focus 状态读取接口

来源等级：A。
环境：Apple Developer 文档与 MacOSX27.0 SDK。
命令或来源：[INFocusStatusCenter](https://developer.apple.com/documentation/intents/infocusstatuscenter)、[requestAuthorization](https://developer.apple.com/documentation/intents/infocusstatuscenter/requestauthorization%28completionhandler:%29)。
关键输出：

```text
An object that maintains the user’s current focus status
Asks the system for access to the user’s focus status.
The first time you make this request, the system prompts the user
```

观察：Focus 状态读取需要用户授权。
观察：状态模型只公开 `isFocused`。
推论：状态接口不能提供 Focus 名称。
限制：状态权限被拒绝时不能依赖该接口。
置信度：高。
关联：解决方案 2.6、5.3。

### E-08：Focus 状态本机探针

来源等级：D。
环境：macOS 27.0.1，当前用户会话。
命令或来源：

```sh
xcrun swift -e 'import Intents; let c = INFocusStatusCenter.default; print("status=\(c.authorizationStatus.rawValue), focused=\(String(describing: c.focusStatus.isFocused))")'
```

关键输出：

```text
status=0, focused=Optional(false)
```

观察：授权状态为 `NotDetermined`。
观察：读取到 `false`。
推论：未授权时不能把 `false` 当成可靠的“没有 Focus”证据。
限制：结果只代表当前用户和当前会话。
置信度：高，范围小。
关联：验证 V04。

### E-09：应用启动接口

来源等级：A。
环境：MacOSX27.0 AppKit 头文件。
命令或来源：`NSWorkspace.h`。
关键输出：

```text
- (void)openApplicationAtURL:configuration:completionHandler:
- (BOOL)openURL:
```

观察：公开接口支持启动指定应用和打开 URL。
推论：Covio 可按 Bundle ID 查找并启动应用。
限制：应用可能不存在或拒绝启动。
置信度：高。
关联：解决方案 3.6、4.1。

### E-10：隐藏和退出接口

来源等级：A。
环境：MacOSX27.0 AppKit 头文件。
命令或来源：`NSRunningApplication.h`。
关键输出：

```text
- (BOOL)hide;
- (BOOL)unhide;
- (BOOL)terminate;
- (BOOL)forceTerminate;
```

观察：公开接口支持隐藏和取消隐藏。
观察：`terminate` 是正常退出请求。
观察：`forceTerminate` 是强制退出请求。
推论：默认应使用 `hide`。
推论：请求退出只能用 `terminate`。
限制：应用可以阻止退出或重新显示自己。
置信度：高。
关联：结论 2.1.2、解决方案 3.6。

### E-11：电源断言接口

来源等级：A、B。
环境：MacOSX27.0 IOKit 头文件与 Covio 源码。
命令或来源：`IOPMLib.h`、`MacSleepController.swift`、[IOPMAssertionCreateWithName](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname)。
关键输出：

```text
IOReturn IOPMAssertionCreateWithName(...)
kIOPMAssertionTypePreventUserIdleSystemSleep
kIOPMAssertionTypePreventUserIdleDisplaySleep
```

观察：公开接口支持阻止空闲系统和屏幕睡眠。
观察：Covio 已有 IOKit 实现。
推论：Focus 会话可复用保持唤醒能力。
限制：断言不阻止用户主动睡眠。
限制：现有 `MacSleepController` 只有一条断言。
置信度：高。
关联：解决方案 5.4、7。

### E-12：输出音量接口

来源等级：A。
环境：MacOSX27.0 CoreAudio 头文件。
命令或来源：`AudioHardware.h`。
关键输出：

```text
AudioObjectSetPropertyData
kAudioDevicePropertyVolumeScalar
kAudioDevicePropertyMute
```

观察：公开接口可修改输出音量和静音。
推论：技术上可做静音动作。
反证：全局静音会同时影响视频、游戏和音乐。
限制：无法只静音系统通知。
置信度：高。
关联：结论 5。

### E-13：Wi-Fi 开关接口

来源等级：A。
环境：MacOSX27.0 CoreWLAN 头文件。
命令或来源：`CWInterface.h`。
关键输出：

```text
- (BOOL)setPower:(BOOL)power error:(out NSError **)error;
```

观察：公开接口可开关 Wi-Fi。
推论：Focus 动作技术上可以断网。
反证：断网会中断同步、远程会话和云服务。
限制：该动作不适合作为通用专注默认项。
置信度：高。
关联：调查 11.1、结论 5。

### E-14：蓝牙公开写入缺口

来源等级：A。
环境：MacOSX27.0 IOBluetooth 头文件。
命令或来源：`IOBluetoothHostController.h`。
关键输出：

```text
@property(readonly) BluetoothHCIPowerState powerState;
```

观察：找到的控制器电源属性为只读。
观察：本次头文件检索未发现公开蓝牙开关方法。
推论：首版不自动开关蓝牙。
限制：未发现的接口不能证明全系统没有其他路径。
置信度：中高。
关联：结论 6、解决方案 3.2。

### E-15：私有亮度路径

来源等级：B。
环境：Covio `main` 与已有亮度研究。
命令或来源：`macosApp/src/Power/ClosedLidBrightnessBackend.swift`、[合盖黑屏研究](../lid-framebuffer-mechanism/REPORT.md)。
关键输出：

```text
DisplayServicesGetBrightness
DisplayServicesSetBrightness
verifiedMajorVersions = [27]
```

观察：Covio 已动态加载私有亮度符号。
观察：该实现按系统主版本门控。
观察：该实现只用于实验性合盖黑屏。
推论：专注模式不扩大私有接口使用范围。
限制：私有接口没有兼容承诺。
置信度：高，范围小。
关联：结论 5、6。

### E-16：壁纸接口

来源等级：A。
环境：MacOSX27.0 AppKit 头文件。
命令或来源：`NSWorkspace.h`。
关键输出：

```text
setDesktopImageURL:forScreen:options:error:
desktopImageURLForScreen:
```

观察：公开接口支持读取和设置每屏壁纸。
推论：壁纸可作为后期动作。
限制：多屏、动态壁纸和用户修改会增加恢复复杂度。
置信度：高。
关联：结论 8。

### E-17：Covio 现有源码边界

来源等级：B。
环境：commit `28d97d89ab192867df413e59115d19683062465a`。
命令或来源：Covio 源码。
关键输出：

```text
MacSleepController.swift
PowerRuntime.swift
HoldLeaseManager.kt
Ports.kt
AppPaths.swift
AppRuntime.swift
```

观察：Covio 已有电源、端口和数据目录抽象。
观察：当前没有专注配置运行时。
推论：新功能应接入现有运行时，不另建系统服务。
限制：源码分析不代表运行行为。
置信度：高。
关联：调查 9、解决方案 1.4。

### E-18：多来源唤醒租约

来源等级：B。
环境：Covio `main`。
命令或来源：`HoldLeaseManager.kt`、`PowerModels.kt`。
关键输出：

```text
HoldLeaseSource: MANUAL, TIMER, RULE, AGENT, TEST
HoldLeaseManager.upsert / cancel / tick
```

观察：租约管理器支持多个来源并存。
观察：当前没有 Focus 来源。
推论：应增加 `FOCUS` 来源，而不是覆盖单条断言。
限制：需要补充多来源测试。
置信度：高。
关联：解决方案 5.4、7。

### E-19：当前 Shortcut 环境

来源等级：D。
环境：当前用户会话。
命令或来源：`shortcuts list`。
关键输出：

```text
exit=0
stdout_line_count=0
```

观察：命令成功。
观察：当前用户没有可列出的 Shortcut。
推论：首次设置向导是必要能力。
限制：只代表当前用户。
置信度：高，范围小。
关联：验证 V03、V08。

### E-20：Accessibility 权限边界

来源等级：A、B。
环境：现有 macOS GUI 自动化研究。
命令或来源：[macOS 后台 GUI 自动化研究](../macos-background-gui-automation/investigation.md)。
关键输出：

```text
Accessibility 权限允许读取和控制系统 UI。
Accessibility 权限不能由后台进程绕过。
```

观察：系统 UI 自动化受用户授权控制。
推论：首版不依赖 Control Center 点击。
限制：现有研究的重点不是 Focus。
置信度：高。
关联：结论 5。

## 6. 逻辑证据链

```text
需求：五个专注配置可切换
  -> E-02、E-03：macOS Focus 支持场景和通知过滤
  -> E-04、E-05：Shortcuts 可运行 Set Focus 动作
  -> E-06、E-07：SDK 只公开状态读取
  -> E-09、E-10：应用动作有公开接口
  -> E-11、E-18：电源动作可接入多来源租约
  -> E-12、E-13、E-15、E-16：高风险或低价值动作不进首版
  -> 决策：Shortcuts 管 Focus，公开接口管应用和电源
```

## 7. 反证和限制

1. Wi-Fi 和音量存在公开写入接口。
2. 这些接口可用，不代表适合通用专注动作。
3. 私有亮度接口在本机可用。
4. 私有接口没有兼容承诺。
5. Focus 状态可读，但没有名称。
6. 授权未决定时，`false` 不能证明当前没有 Focus。
7. 当前用户没有 Shortcut。
8. 没有真实 Shortcut 时不能验证 Focus 流程。

## 8. 已知缺口

| 缺口 | 影响 | 下一步 |
| --- | --- | --- |
| 没有真实 Focus Shortcut | V08 未执行 | 创建临时测试 Shortcut |
| macOS 26 未运行 | 兼容性未定 | 增加真机 |
| 应用恢复未执行 | V09 未执行 | 用可丢弃文档测试 |
| 崩溃恢复未执行 | V10 未执行 | 注入进程退出 |
| 系统设置恢复冲突未执行 | 规则未实测 | 增加用户手动修改场景 |

## 9. 复核方法

1. 重跑 E-01 的版本命令。
2. 重跑 E-06 的头文件检索。
3. 重跑 E-08 的 Focus 状态探针。
4. 重跑 E-19 的 Shortcut 列表命令。
5. 按 [验证计划](validation/README.md) 执行写入测试。
6. 检查命令退出码和回读结果。

## 参考来源

1. [Set up a Focus on Mac](https://support.apple.com/guide/mac-help/set-up-a-focus-to-stay-on-task-mchl613dc43f/mac)
2. [Turn a Focus on or off on Mac](https://support.apple.com/guide/mac-help/turn-a-focus-on-or-off-mchl999b7c1a/mac)
3. [Manage Focus options on Mac](https://support.apple.com/guide/mac-help/manage-focus-options-on-mac-mchl74e8c77b/mac)
4. [Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)
5. [INFocusStatusCenter](https://developer.apple.com/documentation/intents/infocusstatuscenter)
6. [INFocusStatusCenter.requestAuthorization](https://developer.apple.com/documentation/intents/infocusstatuscenter/requestauthorization%28completionhandler:%29)
7. [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
8. [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication)
9. [IOPMAssertionCreateWithName](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname)
10. [合盖黑屏研究](../lid-framebuffer-mechanism/REPORT.md)

## 10. 关联文档

- [主题索引](README.md)
- [问题边界](context.md)
- [调研分析](investigation.md)
- [结论与限制](conclusion.md)
- [推荐方案](solution.md)
- [验证计划](validation/README.md)
- [Case 1](validation/case-readonly-focus-probe.md)
- [Case 2](validation/case-focus-profile-apply.md)
