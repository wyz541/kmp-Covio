# 调研

## 调研方法

1. 只读检查本机 macOS、SIP、IOPS 和 IOKit。
2. 只读调用 `PowerUISmartChargeClient`。
3. 只读编译 `smc` 探针并读取候选 SMC 键。
4. 阅读开源实现的写入路径和恢复路径。
5. 阅读 2026 年 macOS 27 相关 issue 和 PR。
6. 不执行 SMC 写入、PowerUI 写入或系统设置变更。

## 来源范围

| 类型 | 来源 |
| --- | --- |
| 本机 | macOS 27.0.1，MacBookPro18,2，arm64，SIP 开启 |
| 系统命令 | `pmset`、`ioreg`、`codesign`、`Objective-C runtime` |
| 开源实现 | `actuallymentor/battery`、旧版 AlDente、`smcFanControl`、Ampere |
| 社区证据 | `actuallymentor/battery` issue #474、#477、PR #479、PR #480 |
| 安全证据 | `actuallymentor/battery` issue #443 |

## 控制路径

| 路径 | 写入接口 | 权限 | macOS 27 状态 | 范围 |
| --- | --- | --- | --- | --- |
| 原生 MCL | `PowerUISmartChargeClient` | 无 root | 可用，本机支持 | `80` 到 `100` |
| root 原生偏好 | `com.apple.smartcharging.topoffprotection` | root | 技术上可写 | `1` 到 `100` |
| 独立 powerd 策略 | `com.apple.powerd.charging` 归档 | root helper | 实验性 | 自定义目标 |
| 旧 SMC | `CH0B`、`CH0C` | root | 键不存在 | 旧系统 |
| 新 SMC | `bfD0`、`bfE0`、`bfF0`、`CH0J` | Apple entitlement | 读取被拒绝 | 不适用于第三方 |
| 适配器控制 | `CH0I` 或 `CHIE` | root | `CH0I` 不存在 | 旧系统或特殊场景 |

## 信任边界

| 边界 | 可观察事实 | 结论 |
| --- | --- | --- |
| Covio 到 PowerUI | 私有 Objective-C 类和 XPC | 无公开 API |
| Covio 到 SMC | IOKit 用户客户端 | 新键受 entitlement 保护 |
| Covio 到 helper | Unix socket 和命令白名单 | 当前只允许 `pmset` |
| helper 到 root 文件 | root 所有路径 | 需要严格校验和恢复 |
| PowerUIAgent 到 `powerd` | 原生策略注册 | 系统拥有最终执行权 |
| 固件到电池 | 充电电流和旁路 | Covio 只能间接验证 |

## 原生能力矩阵

| 能力 | 本机结果 | 证据 |
| --- | --- | --- |
| `isMCLSupported` | `true` | Objective-C 只读调用 |
| `isMCLCurrentlyEnabled` | `true` | Objective-C 只读调用 |
| `getMCLLimitWithError` | `80` | Objective-C 只读调用 |
| `availableChargeLimitsWithError` | `80, 85, 90, 95, 100` | Objective-C 只读调用 |
| `BypassEngaged` | 已出现 | `PowerUISmartChargeClient.status` |
| `pmset -g battlimit` | `manualChargeLimit`，`chargeSocLimitSoc=80`，`drain=1`，`isEOC=1` | 本机命令 |
| `ExternalConnected` | `Yes` | `ioreg` |
| `IsCharging` | `No` | `ioreg` |
| `BatteryPower` | `0` | `ioreg` |
| `CH0B`、`CH0C`、`CH0I`、`CHWA`、`BCLM` | `no data` | 只读 `smc` 探针 |
| `bfD0`、`bfE0`、`bfF0`、`CH0J` | `kIOReturnNotPrivileged` | 只读 `smc` 探针 |
| `CHIE`、`CHIB` | 可读 | 只读 `smc` 探针 |

## 版本与硬件

| 环境 | MCL | 旧 SMC | 结论 |
| --- | --- | --- | --- |
| macOS 27.0.1，M1 Max | 支持 | 旧键消失 | 原生 MCL 可用 |
| macOS 27，M1 Pro | 社区报告可用 | 旧键消失 | PR #480 真机证据 |
| macOS 26.7 固件 | 部分机型可用 | 旧键消失 | 需要能力检测 |
| macOS 15.8，M2 Air | 社区报告不支持 | 旧键消失 | 无安全路径 |
| 旧 macOS，Apple Silicon | 不一定支持 | `CH0B`/`CH0C` 可用 | 需要 root helper |
| Intel MacBook | 未验证 | `BCLM` 旧路径有源码证据 | 不可宣称已支持 |
| 无电池 Mac | 不支持 | 不适用 | 隐藏功能 |

## 候选方案对比

| 方案 | 覆盖范围 | 成本 | 风险 | 成熟度 | 可维护性 |
| --- | --- | --- | --- | --- | --- |
| 原生 MCL | `80` 到 `100` | 低 | 私有框架变化 | 中，已有开源 evidence | 中 |
| root 原生偏好 | `1` 到 `100` | 高 | 私有文件、校准覆盖、权限 | 低，实验性 | 低 |
| root 独立 powerd 策略 | 自定义 | 很高 | 系统服务重载、恢复失败 | 低，实验性 | 低 |
| 旧 SMC 写入 | 旧系统 | 中 | 硬件写入、helper 安全 | 中，社区使用 | 低 |
| 仅调用系统设置 | `80` 到 `100` | 最低 | 无控制权 | 高 | 高 |

## 目标源码分析

Covio 当前 helper 只允许三条命令：
`version`、`setDisableSleep`、`setHibernateMode`。
helper 当前只执行 `pmset`。
helper 没有 SMC 或 PowerUI 调用。
因此，首期原生 MCL 路径不需要新增 helper 写入命令。

## 参考实现分析

### `actuallymentor/battery`

commit：`8288167d8bcfd396120a005ad3528a1e73904f2a`。

1. Apple Silicon 旧路径使用 `CH0B`、`CH0C` 和 `CH0I`。
2. 写入通过 `sudo`。
3. 安装脚本写入 `sudoers.d`。
4. 维护进程每 60 秒检查一次。
5. 正常维护只按单点阈值切换，没有 5% 回差。
6. 2026 年 issue 报告 macOS 26/27 失效。

### 旧版 AlDente

commit：`8b93da203592f4ad2e9f09fc9cfd2a77b0997de6`。

1. Apple Silicon 使用 `CH0B`。
2. Intel 模式使用 `BCLM`。
3. 写入通过特权 XPC helper。
4. helper 保存并恢复部分 SMC 键。
5. 当前版本已闭源，不能把旧源码当成 macOS 27 实现证据。

### `smcFanControl`

commit：`e1bd672bcd2d72eddff9b6da7b9cae38e35c4206`。

1. `AppleSMC` 用户客户端可读写 SMC。
2. 源码明确警告写入可能永久损坏设备。
3. 受保护写入会返回 `kIOReturnNotPrivileged`。

### Ampere

tag：`v0.0.65`，commit：`6a4fe6dae597f037ab9caa18b932f5cbd9f958b9`。

1. 旧固件使用 root `SMCWriter`。
2. 无旧 SMC 键时读取原生 MCL。
3. 低于原生范围时写入 root 偏好。
4. 需要常驻 root helper 和恢复设计。
5. README 声明支持 macOS 26 和 macOS 27。
6. 该路径是私有接口路径，不是公开 API。

## 反证

1. macOS 27 的原生 MCL 只列出 `80` 到 `100`。
2. 社区 PR 报告原生客户端低于 `80` 会崩溃。
3. 旧 SMC 键在 macOS 27 的本机不存在。
4. 新 SMC 键受 Apple entitlement 保护。
5. root 原生偏好会被 Apple 校准周期覆盖。
6. 独立 powerd 策略需要在 macOS 27 真机上重启服务。
7. 5% 回差不是原生 MCL 的公开参数。

## 已知缺口

1. 未在 Intel Mac 上运行本机探针。
2. 未在无电池 Mac 上运行本机探针。
3. 未执行任何写入验证。
4. 未验证重启、睡眠、唤醒和长期校准。
5. 未验证 macOS 26.0 到 26.6 的完整矩阵。
6. 未验证 Apple 私有 API 的 App Store 审核结果。
