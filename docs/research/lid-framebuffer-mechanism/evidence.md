# 证据与观察

## 环境

| 项目 | 值 |
| --- | --- |
| 硬件 | MacBook Pro，Apple M1 Max |
| 系统 | macOS `27.0.1 (26A434)` |
| Xcode | `27.1 (27A9275)` |
| SDK | macOS 27.0 |
| 目标 commit | `b7065b2` |
| 显示 ID | `1` |
| 内建屏 | 是 |
| 开盖状态 | online `1`，active `1`，asleep `0` |

## 事实、推论和假设

### 事实

1. `CGDisplayIsActive` 返回真时，显示器已连接、awake 且可绘制。
2. `CGDisplayIsAsleep` 返回真时，显示器不可绘制。
3. `CGDisplayStream` 从 WindowServer 接收包含像素的 `IOSurfaceRef`。
4. ScreenCaptureKit 支持 display、window 和 application 捕获。
5. DisplayServices 动态符号在本机存在。
6. 开盖基线屏幕截图可生成 3456 x 2234 PNG。

### 推论

1. 面板亮度 0 时，合成帧仍可能被捕获。
2. Computer Use 可能通过系统捕获 API 获取桌面内容。
3. 只设置系统睡眠租约不足以保证面板黑屏。
4. 只设置 display sleep 可能破坏捕获路径。

### 假设

1. 特定 Computer Use 工具使用 ScreenCaptureKit、CGDisplayStream 或等价合成路径。
2. 合盖黑屏后 WindowServer 会继续生成所需帧。

## 证据表

| ID | 来源 | 观察 | 置信度 | 限制 |
| --- | --- | --- | --- | --- |
| E-01 | `CGDisplayConfiguration.h` | active、asleep、online 的定义不同 | 高 | 公开语义，不含内部实现 |
| E-02 | `CGDisplayStream.h` | WindowServer 生成帧并交付 IOSurface | 高 | API 已过时 |
| E-03 | `CGWindow.h` | 窗口列表可合成图像，WindowServer 不可用时失败 | 高 | 旧 API 已过时 |
| E-04 | `SCStream.h` | 捕获过滤器可选择显示器、窗口或应用 | 高 | 不保证 asleep 显示器的结果 |
| E-05 | `SCScreenshotManager.h` | 单帧捕获返回 CGImage 或 CMSampleBuffer | 高 | 需要权限 |
| E-06 | `IOGraphicsLib.h` | IOFramebuffer 和 IOAccelerator 是图形族对象 | 高 | 未暴露完整合成器实现 |
| E-07 | `IOPMLib.h` | 系统空闲断言不阻止合盖睡眠，显示断言不点亮已关闭显示 | 高 | 不是 `disablesleep` 文档 |
| E-08 | DisplayServices Info.plist | 私有框架版本 3.1，macOS 27 | 高 | 不提供 ABI 承诺 |
| E-09 | 本机动态探针 | `dlopen=ok`，Get/Set 符号都存在 | 高 | 只证明当前系统 |
| E-10 | 本机显示探针 | online=1，active=1，asleep=0，亮度=0.08575986 | 高 | 开盖状态 |
| E-11 | 本机 `screencapture` | 生成 3456 x 2234 PNG | 高 | 开盖状态 |
| E-12 | issue #203 真机矩阵 | 合盖黑屏时 online、active、未 asleep，亮度 6 次为 0.0 | 高 | 单机型、单系统 |
| E-13 | Keepresso 源码 | `zeroBrightness` 注释称 framebuffer 保持 live | 中 | 第三方实现，不是 Apple 文档 |
| E-14 | Insomnia 源码 | `disablesleep` 下合盖不会走系统睡眠，仍用 DisplayServices 压暗 | 中 | 第三方实现 |
| E-15 | DontSleep 源码 | 单独设置 `disablesleep` 会留下亮屏 | 中 | 第三方实现 |
| E-16 | LidAwake 源码 | `displaysleepnow` 在 `SleepDisabled=1` 时不可靠 | 中 | 第三方实现 |
| E-17 | Covio 源码 | 零亮度路径不调用 public display sleep | 高 | 目标 commit 可审阅 |
| E-18 | 合盖 Computer Use 截图 | 未执行 | 未知 | 关键缺口 |

## SDK 头文件哈希

| 文件 | SHA-256 |
| --- | --- |
| `CGDisplayConfiguration.h` | `24fc3b20cb4815835a632990a43ed28256997acc2cf8d4600159f8e8a4d7e27c` |
| `CGDisplayStream.h` | `a5bed36225760665b598196d783a8c64c6b7a641a375ed80ab6da6e9becda251` |
| `CGWindow.h` | `0f01073171b13d5a63a95763bac468efc00da89cb232292f2bcd95b1c0198aee` |
| `SCStream.h` | `11633abf2df86bd6c92345a9c4804a0746e18d4db39994ae29243671f332825b` |
| `SCScreenshotManager.h` | `f62995d35201d09753c852cdb83ce9880b9fae4ec34e1baef1d91fa1b47181e7` |
| `IOPMLib.h` | `9c6b97c780b655c93db5a2b7c787fda8a49e3289fea178cd2856c7802556945a` |
| `IOGraphicsLib.h` | `61d9fe45ff250c71e116851a5ab84f5b77b69cf353e35064edb8699d65d0b722` |

## 参考源码哈希

| 文件 | SHA-256 |
| --- | --- |
| Keepresso `DisplayPolicy.swift` | `9e94def665512723d3b2aaed0817622c991fe59bbde666a6dac53730d99d8ec3` |
| Keepresso `ClosedDisplay.swift` | `c15513ad306615436e62a5c2cc552823226f161c40df8028e869969c7600d4b3` |
| Keepresso `BrightnessBackend.swift` | `64bf4f370cb3d19b206a627b3d6692faee1d5915f669584afd248959c7cf2fad` |
| Insomnia `DisplayPower.swift` | `1c815bfe65c5fd0c221f7eef22e380a9f131bd031b254d1a83ade1f4db64e513` |
| Insomnia `LidActions.swift` | `0dff0f5a226578db6a38232e8870c713d46a98aa1d189aba24f506c8723e6db2` |
| Insomnia `LidObserver.swift` | `90c93b007d49dcfceb91af8758db9113ab970a08756734f7915d226a973d69c3` |
| DontSleep `BuiltinPanel.swift` | `ee072c8a6dfc59bcc89d975ec0a61f89aba74745d3ae8b7011e679eeacd953a2` |
| LidAwake `dispbright.c` | `e71aafb96db23dce7de7db3277d7f9da7a76312e6764d13072089814ced3fbeb` |

## 来源链接

- [CoreGraphics CGDisplayConfiguration](https://developer.apple.com/documentation/coregraphics)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [IOSurface](https://developer.apple.com/documentation/iosurface)
- [IOKit power management](https://developer.apple.com/documentation/iokit)
- [Keepresso](https://github.com/gyorgysh/keepresso)
- [Insomnia](https://github.com/krishhgg/Insomnia)
- [DontSleep](https://github.com/innocarpe/dontsleep)
- [LidAwake](https://github.com/richardlinq/lidawake)
- [Covio issue #203](https://github.com/wyz541/kmp-Covio/issues/203)
- [Covio issue #299](https://github.com/wyz541/kmp-Covio/issues/299)

## 缺口

1. 未运行合盖黑屏 ScreenCaptureKit 截图。
2. 未运行合盖黑屏 Computer Use。
3. 未验证 display sleep 的对照结果。
4. 未验证锁屏和 DRM。
5. 未验证其它机型。
