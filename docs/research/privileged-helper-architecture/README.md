# 特权能力架构与 helper 选择

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 初稿，可评审 |
| 日期 | `2026-10-24` |
| 适用对象 | 产品、研发、测试和安全评审人员 |
| 当前环境 | MacBook Pro 18,2，Apple M1 Max，macOS 27.0.1（26A434），Xcode 27.1 |
| 当前结论 | 保留全部特权功能时，root helper 是必要条件。当前 `Covio` 整个应用二进制以 root 运行，不是全局最优。目标机制是独立的最小 XPC daemon 与 `SMAppService`，但采用目标机制需要 Developer ID 与 notarization。 |

## 前因

Covio 的睡眠、合盖、充电上限和风扇控制需要修改系统级状态。
当前实现把同一份 `Covio` 可执行文件以 root 运行，并通过可写 Unix 域套接字通信。
一次 app 覆盖安装曾留下旧 helper，导致 app 与 helper 版本不一致。

研究问题、问题分类、场景和成功标准见 [context.md](context.md)。

## 背景

合盖睡眠已由 [合盖睡眠控制与权限边界](../lid-sleep-control/README.md) 验证必须提权。
该研究还发现：当前机器没有 Developer ID，`SMAppService.daemon` 探针使用自签名与 ad-hoc 签名均注册失败。

本主题扩大范围。
本主题同时检查睡眠、充电和风扇控制，并重新比较 helper 的必要性、进程边界、IPC 和系统生命周期。

调研方法、方案矩阵与反证见 [investigation.md](investigation.md)。

## 过程

本主题读取 Apple SDK 头文件、Apple 官方文档和 Apple Service Management 示例。
本主题对照 Covio 当前实现和既有研究证据。
本主题检查当前 helper 的启动路径、socket 权限、二进制依赖和签名环境。
本主题不修改系统状态，不安装新 helper，不执行需要 root 的写入。

复现命令、环境事实、来源和证据链见 [evidence.md](evidence.md)。

## 结果

root helper 是保留全部特权功能的必要条件。
非 root 方案只能覆盖进程级睡眠断言，不能覆盖合盖、系统级 `pmset` 设置、SMC 风扇写入和低档位充电上限。

当前“整个应用以 root 运行”不是全局最优。
应用二进制包含 SwiftUI、AppKit、Vision、AVFoundation 等大量用户态依赖。
root 进程不需要这些依赖，扩大攻击面没有收益。

全局目标方案是独立的最小 XPC daemon。
正式分发时应通过 `SMAppService.daemon` 注册，并使用 Developer ID、hardened runtime 和 notarization。

当前环境没有 Developer ID。
`SMAppService.daemon` 不能作为当前 ad-hoc 构建的可用路径。
在没有签名前提时，只能采用受约束的 Legacy LaunchDaemon 路径，并先收紧进程边界、IPC 和发布身份。

完整结论、决策表和限制见 [conclusion.md](conclusion.md)。

## 预期

目标架构应满足以下条件：

1. root 进程只包含特权服务所需代码。
2. 用户态 app 与 root helper 使用强身份校验的 XPC。
3. helper 的生命周期由 macOS 管理。
4. app 与 helper 使用同一发布身份。
5. 升级、回滚和系统状态恢复可验证。

推荐架构、接口和失败模式见 [solution.md](solution.md)。
验证矩阵和当前阻塞项见 [validation/README.md](validation/README.md)。

## 实现预期的手段

第一步是作出架构决策。
决策必须回答是否投资 Developer ID 与 notarization。

如果投资签名前提，目标实现是：

1. 新建独立 `CovioHelper` target。
2. 使用 XPC Mach service，不再使用世界可写 Unix socket。
3. 使用 `SMAppService.daemon` 注册 daemon。
4. 使用同一 release identity 绑定 app、helper 和安装记录。
5. 使用签名 PKG 和可回滚升级流程交付。

如果不投资签名前提，则不能声称目标架构已落地。
替代路径只能是 Legacy LaunchDaemon 的受约束版本，并明确保留迁移债务。

实现顺序、回滚条件和产品化条件见 [solution.md](solution.md)。
证据和未决项见 [evidence.md](evidence.md)。
架构决策见 [ADR-0018](../../adr/adr-0018-privileged-helper-release-identity.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题定义、边界、状态矩阵和成功标准 |
| [investigation.md](investigation.md) | 证据、信任边界、方案矩阵和反证 |
| [conclusion.md](conclusion.md) | 结论、决策表、限制和未决项 |
| [solution.md](solution.md) | 目标架构、接口、流程、安全和实施计划 |
| [evidence.md](evidence.md) | 来源、命令、观察、推论和证据链 |
| [validation/README.md](validation/README.md) | 验证目标、矩阵、风险和清理要求 |

## 证据链阅读顺序

1. 阅读 [context.md](context.md)，确认问题和成功标准。
2. 阅读 [evidence.md](evidence.md) 的 `E-01` 到 `E-16`。
3. 阅读 [investigation.md](investigation.md)，检查方案矩阵。
4. 阅读 [conclusion.md](conclusion.md)，检查决策和限制。
5. 阅读 [solution.md](solution.md)，检查推荐架构是否存在未授权假设。
6. 阅读 [validation/README.md](validation/README.md)，确认未执行项。

## 更新规则

- 新证据改变结论时，更新 `evidence.md`、`conclusion.md` 和本索引。
- 验证状态变化时，更新 `validation/README.md` 和对应案例。
- 推荐架构变化时，更新 `solution.md`，并新增 ADR。
- 所有链接使用相对路径。
