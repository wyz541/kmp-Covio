# 结论、决策与限制

## 1. 结论摘要

保留当前全部特权功能时，root helper 是必要条件。
但是，当前把整个 `Covio` 应用二进制作为 root helper 不是全局最优。

全局目标架构是：

- 独立的最小特权 daemon。
- 使用 XPC Mach service。
- 使用 `SMAppService.daemon` 注册服务。
- 使用 Developer ID、hardened runtime 和 notarization 分发。
- app 与 helper 使用同一 release identity。

当前机器没有 Developer ID。
`SMAppService.daemon` 的使用条件暂时无法满足。
因此当前阶段不能继续把 `SMAppService` 当成已可落地的实现方案。

如果暂时不取得 Developer ID，只能选择受约束的 Legacy LaunchDaemon 路径。
该路径应至少做到独立最小 helper、稳定安装位置、XPC 代码签名校验和成对升级。

## 2. 主要决策因素

### 2.1 系统能力需要 root

`pmset` 写入需要 root（`E-07`）。
SMC 受保护写入返回 `kIOReturnNotPrivileged`（`E-08`）。
合盖控制已有真机实验证明不能用用户态断言替代（`E-06`）。

结论：完整功能集不能脱离特权服务。

### 2.2 当前 helper 的权限边界过大

`Covio --helper` 与 UI 使用同一个可执行文件（`E-09`）。
该二进制链接 SwiftUI、AppKit、Vision、AVFoundation、Metal 等用户态依赖（`E-10`）。
root helper 不需要这些依赖。

结论：当前二进制不满足最小权限原则。

### 2.3 当前 IPC 边界弱

helper 使用权限为 `0666` 的 Unix 域套接字（`E-11`）。
任意本机用户都可以建立连接，之后才做 UID 和部分签名检查。

`NSXPCListener` 可以在接受连接前校验代码签名 requirement（`E-14`）。

结论：XPC 比当前 socket 更适合作为特权边界。

### 2.4 Apple 已淘汰 `SMJobBless`

`SMJobBless` 在 macOS 13 被标记 deprecated，Apple 建议改用 `SMAppService`（`E-04`）。

结论：新架构不采用 `SMJobBless`。

### 2.5 `SMAppService` 需要签名与公证

SDK 头文件要求使用 `SMAppService` 的应用必须签名。
包含 LaunchDaemon 的应用必须 notarized（`E-01`）。

Apple 文档要求 daemon 的 plist 位于签名 app bundle，并使用 `BundleProgram`（`E-02`）。
更新 helper 或 plist 后必须重新注册（`E-01`）。

当前环境没有 Developer ID（`E-12`）。
既有探针用自签名和 ad-hoc 签名注册均失败（`E-13`）。

结论：`SMAppService` 是全局目标，但不是当前签名条件下的可行实现。

## 3. 决策表

| 决策 | 结果 | 原因 | 证据 |
| --- | --- | --- | --- |
| 是否保留特权服务 | 保留 | 全部功能需要系统级写入 | `E-06`、`E-07`、`E-08` |
| 是否继续让完整 app 以 root 运行 | 不再采用 | 攻击面和依赖过大 | `E-09`、`E-10` |
| helper 是否独立 | 是 | 最小权限和独立发布身份 | `E-10` |
| 目标 IPC | XPC Mach service | 连接前校验客户端签名 | `E-14` |
| 目标生命周期 | `SMAppService.daemon` | Apple 托管注册、批准和启动 | `E-01`、`E-02`、`E-03` |
| 是否使用 `SMJobBless` | 否 | macOS 13 已废弃 | `E-04` |
| 是否使用 `AuthorizationExecuteWithPrivileges` | 否 | macOS 10.7 已废弃，安全风险高 | `E-05` |
| 是否依赖 App Sandbox 下的 Authorization Services | 否 | Apple 明确不支持 | `E-16` |
| 无 Developer ID 时是否继续推进 `SMAppService` 实现 | 否 | 注册前提无法满足 | `E-01`、`E-12`、`E-13` |
| 无 Developer ID 时的备选 | 独立最小 helper + Legacy LaunchDaemon | 避免混合版本和过大权限 | 推论 |
| App Store 是否为当前目标 | 否 | 私有硬件写入和特权 daemon 不兼容 | 推论 |

## 4. 不采用的方案

### 4.1 完全不用 helper

该方案只能保留监控和用户态功能。
合盖、风扇控制和低档位充电必须删除。

未采用原因：当前产品范围要求保留这些功能。

### 4.2 每次操作弹管理员授权

该方案不能支持持续风扇控制和后台状态恢复。
频繁授权增加误操作和脚本注入风险。

未采用原因：可靠性、用户体验和安全性都不满足。

### 4.3 `setuid` 工具

该方案依赖文件权限位。
更新、签名和权限损坏后的恢复难以审计。

未采用原因：不满足最小权限和可靠性要求。

### 4.4 当前完整 app 作为 root helper

该方案能运行，但 root 进程包含大量非必要代码。
安装脚本、LaunchDaemon 和发布版本彼此分离。

未采用原因：不是全局最优。

### 4.5 `SMJobBless`

该方案被 Apple 明确替代。

未采用原因：API 已废弃。

## 5. 系统限制

1. 没有公开 API 可以无 root 修改合盖、SMC 风扇和低档位充电策略。
2. `SMAppService.daemon` 需要签名和公证。
3. daemon 注册后需要管理员批准。
4. helper 或 plist 更新后需要重新注册。
5. daemon 的 bundle 应位于 `/Applications`，便于登录前访问。

## 6. 产品限制

1. 正式采用目标架构前，必须持有 Developer ID 并建立 notarization 流程。
2. 如果暂不取得 Developer ID，只能采用受限路径，不能宣称已经达到全局最优。
3. App Store 与当前私有硬件写入范围不兼容。
4. 独立 helper 增加一个构建和测试目标。

## 7. 对既有决策的影响

ADR-0006 的结论建立在当前没有 Developer ID 的前提上。
该 ADR 关于“合盖必须提权”的结论仍然成立。
该 ADR 关于“保留手写 plist”的结论只适用于签名前提未改变的阶段。

取得 Developer ID 并完成 notarization 后，应新增 ADR。
新 ADR 应明确更新或 supersede ADR-0006 中关于 helper 形式的决定。

## 8. 未决项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Developer ID 与 notarization 是否作为产品发布前提 | pending | 产品与发布决策 |
| Apple Development 签名能否完成本地 `SMAppService` 试验 | pending | 配置有效 Team ID 后执行 |
| Developer ID 签名应用能否成功注册 daemon | pending | 验证案例 `V02` |
| app 更新后重新注册是否再次要求批准 | pending | 两版本连续升级案例 `V03` |
| XPC 在高频风扇状态查询下的延迟 | pending | 验证案例 `V04` |
| Legacy LaunchDaemon 迁移到 `SMAppService` 的停机窗口 | pending | 验证案例 `V06` |

## 9. 建议的下一步

先做架构决策，不直接拆实现任务。

决策应二选一：

1. 承诺 Developer ID 与 notarization，采用全局目标架构。
2. 暂不采用目标架构，只批准受限 Legacy 路径，并保留明确的迁移债务。

选择完成后，再创建 ADR 和实施 Feature。

后续架构记录见 [ADR-0018](../../adr/adr-0018-privileged-helper-release-identity.md)。

decision: pending
