# GitHub 合盖保持唤醒与内建屏亮度方案审计

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | GitHub 方案审计完成 |
| 日期 | `2026-10-21` |
| Issue | #191 |
| Feature | #148 |
| 关联任务 | #190 |

## 结论

GitHub 上存在可运行的“合盖保持唤醒，内建屏变暗”方案。
它们几乎都组合使用两个动作：

```text
pmset -a disablesleep 1
        +
DisplayServicesSetBrightness(displayID, 0.0)
```

`disablesleep` 保持系统运行。
`DisplayServicesSetBrightness` 把内建屏亮度设为最低值。
`DisplayServices` 是私有框架，不属于公开 macOS API。

公开 API 不能可靠完成第二项。
在 Apple Silicon 上，直接调用公开 IOKit 亮度接口返回 `kIOReturnUnsupported`。
因此 Covio 有两条路线：

1. 保持“合盖关屏”，只使用 helper 和公开电源路径。
2. 修改 ADR，允许 opt-in 的私有 DisplayServices 路径，实现“合盖最低亮度”。

当前默认路线是第 1 条。

## 仓库对比

| 仓库 | 许可证 | 活跃度 | 合盖保持 | 内建屏处理 | 结论 |
| --- | --- | --- | --- | --- | --- |
| `gyorgysh/keepresso` | GPL-3.0 | 活跃，117 stars | `pmset disablesleep` | `DisplayServices` 的 `displayOff`、`zeroBrightness`、`leaveAlone` 三态 | 最接近需求。GPL，不能直接复制进 MIT Covio。 |
| `krishhgg/Insomnia` | MIT | 活跃，1.6k stars | `pmset disablesleep` | `DisplayServices` 保存并设亮度，`IORegistry` 读合盖状态 | MIT，代码结构最值得参考。 |
| `innocarpe/dontsleep` | Apache-2.0 | 活跃，16 stars | `pmset disablesleep` | `DisplayServices` 关显示器和键盘背光 | 说明 `disablesleep` 会留下亮屏，需主动压暗。 |
| `richardlinq/lidawake` | Apache-2.0 | 活跃，20 stars | sudoers 允许的 3 条 `pmset` | `dispbright` 调用 `DisplayServicesSetBrightness(0)` | 直接验证 `displaysleepnow` 在 `SleepDisabled=1` 时不可靠。 |
| `dotcom07/clamshellctl` | BSD-2-Clause | 小型，0 stars | CLI 调 `pmset` | `DisplayServices`、`CoreDisplay`、IOKit 三级亮度回退 | 有亮度回退和恢复状态设计。 |
| `Eason09053360/InternalDisplayOff` | MIT | 小幅活跃，1 star | 不负责合盖保持 | `DisplayServices` 加 IOKit 回退，仅处理内建屏 | 屏幕控制参考，不是合盖方案。 |
| `nriley/brightness` | BSD-2-Clause | 维护型，667 stars | 不负责合盖保持 | Apple Silicon 使用 `DisplayServices`，旧系统使用 IOKit/CoreDisplay | 亮度 API 的经典参考；不是合盖工具。 |
| `mactools-app/MacTools` | GPL-3.0 | 活跃，1.3k stars | KeepAwake 插件 | DisplayBrightness 插件使用私有桥接并有软件回退 | 组件化参考，不是单一合盖实现。 |
| `vorssaint-utils` | GPL-3.0 | 活跃，28.5k stars | KeepAwake 服务 | BrightnessService 与显示器服务 | 大型工具箱，不能直接作为 Covio 代码来源。 |

统计数据来自 GitHub API，采集日期为 2026-10-21。
Star 数只表示社区关注度，不表示技术质量或安全性。

## 关键实现证据

### Keepresso

来源：

- `https://github.com/gyorgysh/keepresso`
- `Sources/KeepressoCore/DisplayPolicy.swift`
- `Sources/KeepressoCore/ClosedDisplay.swift`
- `Sources/Keepresso/BrightnessBackend.swift`

它把合盖显示行为显式定义成：

| 策略 | 行为 |
| --- | --- |
| `displayOff` | 合盖时请求显示器睡眠 |
| `zeroBrightness` | 合盖时保存亮度，然后设为 `0.0`，framebuffer 保持活动 |
| `leaveAlone` | 不改显示器状态 |

`zeroBrightness` 的注释明确写着：面板看起来关闭，但 framebuffer 仍可服务远程会话。
这比“可见最低亮度”更准确。

### Insomnia

来源：

- `https://github.com/krishhgg/Insomnia`
- `Sources/Insomnia/System/DisplayPower.swift`
- `Sources/Insomnia/Core/LidActions.swift`
- `Sources/Insomnia/System/LidObserver.swift`

它使用 `IORegistry` 的 `AppleClamshellState` 监听合盖。
合盖时保存显示器和键盘亮度，再调用 `DisplayServicesSetBrightness(0)`。
它把显示器和键盘亮度恢复信息写入日志，以便开盖或应用重启后恢复。
该仓库为 MIT，适合作为独立实现的许可证参考。

### DontSleep

来源：

- `https://github.com/innocarpe/dontsleep`
- `Sources/BuiltinPanel.swift`
- `Sources/ClamshellMode.swift`
- `Sources/Power.swift`

README 明确说明：只设置 `disablesleep` 会让合盖后的内建屏继续亮着。
DontSleep 在合盖后主动关闭内建屏和键盘背光。
它通过 `sudoers.d` 把权限限制到两条 `pmset` 命令。

### LidAwake

来源：

- `https://github.com/richardlinq/lidawake`
- `src/dispbright.c`
- `share/sudoers.in`
- `README.md`

它说明了关键行为差异：

- `pmset disablesleep 1` 阻止合盖睡眠。
- `pmset displaysleepnow` 在 `SleepDisabled=1` 时不可靠。
- 因此它用 `DisplayServicesSetBrightness(0)` 直接把内建屏压暗。
- 它同时锁定屏幕，避免关闭屏幕导致安全边界丢失。

### 亮度 CLI

`nriley/brightness` 在 Apple Silicon 上需要 DisplayServices。
它的 README 明确记录：macOS 10.12.4 后公开 IOKit 亮度行为不足，Apple Silicon 还需要额外私有接口。
这支持 Covio 的判断：亮度不是稳定的公开能力。

## 对 Covio 的建议

### 不建议直接复制

GPL-3.0 仓库的代码不能直接复制到 MIT 项目。
应只使用行为证据和公开可验证的接口事实。
MIT 仓库也需要保留许可证和版权声明。

### 如果允许私有 API

可以新增一个默认关闭的实验能力：

1. 只用 `DisplayServicesGetBrightness` 和 `DisplayServicesSetBrightness`。
2. 先读取原亮度。
3. 合盖后设为 `0.0`。
4. 开盖、会话结束、异常退出时恢复原亮度。
5. 写入前检查显示器和符号是否存在。
6. 失败时回退到“合盖关屏”，不伪造成功。
7. 将能力标记为 `experimental-private-api`。
8. 不把它放入公开正式发布默认值，除非 ADR 重新接受。

### 如果不允许私有 API

当前“合盖关屏”是唯一可承诺的路径。
“内建屏最低亮度”应保持不可用。
外接屏 clamshell 是另一项需求。

## 风险

1. DisplayServices 没有稳定公开头文件。
2. 私有符号可能随 macOS 更新消失或改变调用约定。
3. 最低亮度通常就是 `0.0`，视觉上等于黑屏；不能承诺可见画面。
4. 合盖后硬件会改变显示器电源状态，各机型行为不同。
5. 崩溃或 `SIGKILL` 可能留下亮度 0。
6. 缺少恢复日志会造成用户重启后屏幕仍很暗。
7. GPL 与 MIT 的许可证边界必须保持清楚。

## 相关证据

- `docs/research/lid-sleep-control/evidence.md` 的 `E-02`。
- Xcode 27 SDK `IOPMLib.h` 和 `IOGraphicsLib.h`。
- 本机 Apple M1 Max 的 IOKit 亮度探测。
- 上述仓库的 README、源码和许可证文件。
