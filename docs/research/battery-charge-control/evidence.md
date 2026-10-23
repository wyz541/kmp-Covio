# 证据

## 1. 环境

| 项 | 值 |
| --- | --- |
| 日期 | 2026-10-20 |
| 硬件 | MacBookPro18,2 |
| 架构 | arm64 |
| macOS | 27.0.1 |
| Build | 26A434 |
| SIP | enabled |

序列号和其他设备标识未记录。

## 2. 本机 IOPS 与 IO报告

| 字段 | 值 |
| --- | --- |
| `ExternalConnected` | `Yes` |
| `ExternalChargeCapable` | `Yes` |
| `IsCharging` | `No` |
| `FullyCharged` | `No` |
| `CurrentCapacity` | `79` |
| `BatteryPower` | `0` |
| `SystemPowerIn` | `0` |

来源：只读 `ioreg -l -w 0 -r -c AppleSmartBattery`。

## 3. `pmset` 策略

来源：只读 `pmset -g battlimit`。

```text
chargeSocLimitDrain = 1
chargeSocLimitIsEOC = 1
chargeSocLimitNoChargeToFull = 0
chargeSocLimitOwner = 442
chargeSocLimitReason = manualChargeLimit
chargeSocLimitSoc = 80
```

进程表显示 PID `442` 是 `/usr/libexec/PowerUIAgent`。

## 4. PowerUI 只读调用

客户端类：`PowerUISmartChargeClient`
来源：Objective-C runtime 只读调用。

| 方法 | 结果 |
| --- | --- |
| `isMCLSupported` | `true` |
| `isMCLCurrentlyEnabled:error:` | `1` |
| `getMCLLimitWithError:` | `80` |
| `availableChargeLimitsWithError:` | `80, 85, 90, 95, 100` |
| `currentSuggestedChargeLimitWithError:` | `0` |

`status` 返回值中的关键项：

```text
CurrentState = 0
Enabled = 0
Timeline: BypassEngaged
```

结论：本机在 `80%` 上限下出现系统级旁路状态。

限制：`status` 是私有字典结构。
字段名和含义没有 Apple 公开承诺。

## 5. JXA 只读调用

命令：`osascript -l JavaScript` 加载 `PowerUI.framework`。

```json
{"supported":true,"enabled":"1","limit":80,"error":null}
```

结论：同一读取路径不需要 root 或 SIP 关闭。

限制：这是私有接口。
该结果不证明写入接口长期稳定。

## 6. `PowerUIAgent` 权限

`codesign` 显示以下 entitlement：

```text
com.apple.private.iokit.soc-limit
com.apple.private.iokit.powersource-control
com.apple.private.iokit.powersource-write
com.apple.private.usernotifications.bundle-identifiers
```

结论：第三方进程不能获得 Apple 的新 SMC 充电控制 entitlement。

## 7. 只读 SMC 探针

来源：`smcFanControl` 的 `smc-command`。
探针只执行读取。
未执行 `-w`。

| 键 | 结果 |
| --- | --- |
| `CH0B` | `no data` |
| `CH0C` | `no data` |
| `CH0I` | `no data` |
| `CHWA` | `no data` |
| `BCLM` | `no data` |
| `CH0J` | `kIOReturnNotPrivileged` |
| `bfD0` | `kIOReturnNotPrivileged` |
| `bfE0` | `kIOReturnNotPrivileged` |
| `bfF0` | `kIOReturnNotPrivileged` |
| `CHIE` | `bytes 00` |
| `CHIB` | `ui8 0` |

结论：旧 SMC 充电键在本机不可用。
新键读取受 entitlement 保护。
本机无法使用安全的第三方 SMC 写入路径。

## 8. 开源实现

### `actuallymentor/battery`

- URL: `https://github.com/actuallymentor/battery`
- Commit: `8288167d8bcfd396120a005ad3528a1e73904f2a`
- 文件：`battery.sh`
- 观察：Apple Silicon 旧路径使用 `CH0B`、`CH0C`、`CH0I`。
- 观察：安装脚本创建 `sudoers.d` 规则。
- 观察：维护循环每 60 秒检查一次。
- 限制：仓库 HEAD 为 2023 年版本。

### 旧版 AlDente

- URL: `https://github.com/AppHouseKitchen/AlDente-Charge-Limiter`
- Commit: `8b93da203592f4ad2e9f09fc9cfd2a77b0997de6`
- 文件：`AlDente/Helper.swift`
- 观察：Apple Silicon 使用 `CH0B`。
- 观察：Intel 模式使用 `BCLM`。
- 观察：写入通过特权 XPC helper。
- 限制：README 说明源码已过时，当前版本闭源。

### `smcFanControl`

- URL: `https://github.com/hholtmann/smcFanControl`
- Commit: `e1bd672bcd2d72eddff9b6da7b9cae38e35c4206`
- 文件：`smc-command/smc.c`
- 观察：通过 `AppleSMC` 用户客户端读写。
- 观察：README 警告错误写入可能永久损坏设备。
- 观察：源码定义 `kIOReturnNotPrivileged`。

### Ampere

- URL: `https://github.com/az-code-lab/ampere`
- Tag: `v0.0.65`
- Commit: `6a4fe6dae597f037ab9caa18b932f5cbd9f958b9`
- 文件：`Sources/Shared/NativeChargeLimit.swift`
- 文件：`Sources/SMCWriter/main.swift`
- 观察：root helper 写入 `com.apple.smartcharging.topoffprotection`。
- 观察：写入 `MCLFeatureState` 和 `mclLimitValue`。
- 观察：删除 `checkpoint` 和 `currentState` 重置状态机。
- 观察：发送 `com.apple.smartcharging.defaultschanged`。
- 观察：低于 `80%` 依赖 root 私有路径。
- 限制：私有偏好可能被系统校准覆盖。

## 9. 社区问题与 PR

| 来源 | 观察 |
| --- | --- |
| `actuallymentor/battery#474` | `CH0B`/`CH0C`/`CH0I` 在 macOS 27 无数据；`PowerUISmartChargeClient` 可用 |
| `actuallymentor/battery#477` | macOS 27 SMC 失效；原生系统设置出现充电上限 |
| `actuallymentor/battery#443` | `sudoers` 配置存在提权风险 |
| `actuallymentor/battery#289` | 单点维护会造成频繁补电，用户需要回差 |
| `actuallymentor/battery#480` | 原生 MCL 只支持 `80` 到 `100`；低于 `80` 会让客户端崩溃 |
| `actuallymentor/battery#479` | root 原生偏好可能被校准覆盖；需要独立 powerd 策略 |
| `AppHouseKitchen/AlDente-Charge-Limiter` README | 当前产品支持 macOS 27，但源码闭源 |

## 10. 置信度

| 结论 | 置信度 | 原因 |
| --- | --- | --- |
| macOS 27 旧 SMC 键不可用 | 高 | 本机多个键只读验证 |
| 新 SMC 键受 entitlement 保护 | 高 | `kIOReturnNotPrivileged` 和 entitlement 列表 |
| 原生 MCL 支持 `80` 到 `100` | 高 | 本机读数和社区写入测试 |
| 原生 MCL 出现旁路 | 高 | `BypassEngaged`、`drain=1`、`BatteryPower=0` |
| `40%` 到 `79%` 需要等待 powerd | 中高 | root 偏好可写，执行时机依赖下一次电量步进 |
| 5% 回差无法由原生 API 配置 | 高 | 公开方法不含回差参数 |
| Intel 支持情况 | 低 | 只有旧源码证据 |
| 无电池设备支持情况 | 低 | 未做真机验证 |

## 11. 后续真机写入

2026-10-20 至 21 完成以下写入验证。

| 场景 | 观察 |
| --- | --- |
| 原生 `85%` | `PowerUI` 与 `pmset` 均显示 `85` |
| 原生恢复 `80%` | `PowerUI` 返回 `80`，MCL 保持启用 |
| root `70%`（早期记录） | `PowerUI`、`pmset` 与 helper 均显示 `70` |
| root `70%`（2026-10-22 复测） | 目标未稳定登记到 powerd；等待下一次电量 `1%` 步进复核 |
| 电量高于上限 | 目标保持当前电量，没有主动放电 |
| 睡眠与唤醒 | 多轮事件后 App 仍存活 |

详细步骤和结果见 issue #162。

## 12. 未执行

1. 未写 SMC 键。
2. 未修改 `com.apple.powerd.charging`。
3. 未重启 `powerd`。
4. 未验证真实系统重启。
5. 未验证真实 Apple 校准周期。
6. 未验证 macOS 26、Intel 和无电池设备上的 helper 卸载。
7. 未执行 Intel 和无电池测试。
