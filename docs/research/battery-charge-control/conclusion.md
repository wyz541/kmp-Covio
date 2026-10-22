# 结论与限制

## 1. 结论

完整 `20%` 到 `100%` 范围不能使用同一条安全路径实现。

macOS 27 的可用方案分为两段：

| 范围 | 可行路径 | 权限 | 结论 |
| --- | --- | --- | --- |
| `80%` 到 `100%` | `PowerUISmartChargeClient` 和原生 MCL | 无 root | 本机通过 `85%` 验证 |
| `20%` 到 `79%` | root `defaults` 与 `notifyutil` | root helper | 本机通过 `70%` 验证 |
| 旧系统充电键可用 | `CH0B`、`CH0C` | root helper | 条件可做，需单独矩阵 |
| 无安全写入路径 | 无 | 无 | 不支持 |

原生 MCL 是私有接口。
它不是 Apple 公开文档 API。
因此，“条件可做”表示需要产品接受私有接口风险。

真机补充：

1. `PowerUISmartChargeClient.setMCLLimit(75)` 返回 `PowerUISmartChargingErrorDomain Code=4`。
2. root `defaults write` 写入 `mclLimitValue=70`，再执行 `notifyutil -p com.apple.smartcharging.defaultschanged` 后，`pmset` 显示 `70`。
3. `PowerUI enableMCL`、`disableMCL` 和 `setMCLLimit(85)` 成功后，`pmset` 显示 `85`。
4. 因此，`80` 到 `100` 使用原生客户端，`20` 到 `79` 使用直接偏好。

## 2. 旁路供电

本机观察到真实的系统旁路状态。

| 证据 | 观察 |
| --- | --- |
| `PowerUISmartChargeClient.status` | `BypassEngaged` |
| `pmset -g battlimit` | `chargeSocLimitDrain=1` |
| `pmset -g battlimit` | `chargeSocLimitIsEOC=1` |
| `ioreg` | `ExternalConnected=Yes` |
| `ioreg` | `IsCharging=No` |
| `ioreg` | `BatteryPower=0` |

因此，原生 MCL 可以把电池保持在 `80%`。
适配器继续供电。
电池电流为 `0`。
系统状态明确显示 `BypassEngaged`。

## 3. 5% 回差

Covio 状态机实现 `5%` 回差。
电量高于用户上限时，状态机把当前电量作为临时目标，不主动放电。
电量低于回差阈值时，状态机再写入用户上限。

原生 MCL 不提供回差参数。
固件是否立即恢复充电仍需真机验证。
因此，`5%` 回差目前属于条件通过。

## 4. 系统策略优先级

原生 MCL 是系统设置的一部分。
Covio 设置原生 MCL 会改写系统充电上限。
因此，产品需要明确以下行为：

| 场景 | 推荐行为 |
| --- | --- |
| 用户首次设置 | 保存原系统 MCL 状态和值 |
| 用户修改上限 | 更新 Covio 值并同步原生 MCL |
| 用户在系统设置中修改 | 读取到外部变更；不静默覆盖 |
| 用户恢复默认 | 恢复原系统 MCL 状态和值 |
| Apple 校准周期启动 | 显示系统临时接管，不误报错误 |
| Covio 退出 | 按产品设置保留或恢复 |

## 5. 决策表

| 决策 | 选择 | 原因 |
| --- | --- | --- |
| 首期是否支持 `20%` 到 `100%` | 条件支持 | 混合路径已在 macOS 27 Apple Silicon 验证 `70%` 与 `85%` |
| 首期是否使用原生 MCL | 条件采用 | 无 root，旁路可验证，私有接口 |
| 首期是否支持 `20%` 到 `79%` | 条件支持 | root 直接偏好已在 `70%` 验证 |
| 是否写旧 SMC 键 | macOS 27 不写 | 键不存在或 entitlement 阻止 |
| 是否写新 SMC 键 | 否 | 第三方无 entitlement |
| 是否写 root 原生偏好 | `20%` 到 `79%` 使用 | 真机 `70%` 已注册到 powerd；仍需扩展矩阵 |
| 是否把停止充电称为旁路 | 否 | 必须读取旁路证据 |
| 是否保留 5% 回差承诺 | 否 | 原生接口不提供该参数 |
| 是否保留用户原策略 | 是 | 避免破坏系统设置 |

## 6. 推荐

Feature #137 首期采用混合路径。

1. `80%` 到 `100%` 使用原生 MCL。
2. `20%` 到 `79%` 使用 root `defaults` 与 `notifyutil`。
3. helper 只接受签名客户端和合法档位。
4. 写入后必须回读 `PowerUI` 与 `pmset`。
5. 保存原策略，并允许重复恢复。
6. 高于用户上限时保持当前电量，不主动放电。
7. 能力不明确的设备隐藏入口。

完整机型矩阵、校准周期和重启恢复通过前，发布结论保持 `conditional-go`。

## 7. 未决项

| 项目 | 现状 | 下一步 |
| --- | --- | --- |
| `20%` 到 `79%` | 本机 `70%` 路径通过 | 补完整机型与系统矩阵 |
| Apple 校准周期 | 原生状态可观察到，写入覆盖未验证 | 真机周期测试 |
| 5% 回差 | Covio 状态机已实现 | 验证固件恢复充电的时机 |
| Intel MCL | 未验证 | 找 Intel Mac |
| 无电池设备 | 未真机验证 | 找台式机 |
| App Store 审核 | 未验证 | 发布策略评审 |
| macOS 版本矩阵 | 部分证据 | 补 macOS 26.x 和 27.x |
