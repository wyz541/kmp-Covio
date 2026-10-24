# ADR-0018：用统一发布身份和 SMAppService 管理特权 helper

- Status：accepted
- Kind：architecture
- Date：2026-10-24
- Supersedes：ADR-0006 的 helper 形式部分
- Implements：#350
- 相关：[特权能力架构调研](../research/privileged-helper-architecture/README.md)、#351、#352

## 背景

Covio 的合盖、充电和风扇控制需要系统级写入。
[特权能力架构调研](../research/privileged-helper-architecture/conclusion.md) 已确认 root helper 是保留全部功能的必要条件。

当前 helper 复用完整 `Covio` 应用二进制。
LaunchDaemon 指向 `/Applications/Covio.app/Contents/MacOS/Covio`。
app 与 helper 通过权限为 `0666` 的 Unix 域套接字通信。

该实现有三个问题。

1. root 进程包含 SwiftUI、AppKit、Vision、AVFoundation 等非必要代码。
2. app 覆盖安装后，旧 helper 可能继续运行。
3. helper 安装、发布身份和运行身份没有形成一个发布事务。

Apple 从 macOS 13 起提供 `SMAppService`。
`SMAppService.daemon` 可以注册签名 app bundle 内的 LaunchDaemon。
包含 LaunchDaemon 的应用必须签名并 notarized。

Apple 已废弃 `SMJobBless` 和 `AuthorizationExecuteWithPrivileges`。

## 决策

1. 保留 root helper。合盖、SMC 风扇写入和低档位充电控制不删除。
2. 新建独立的 `CovioHelper` 二进制。root 进程不再复用完整 app 二进制。
3. helper 只链接特权服务所需的库和共享协议代码。
4. app 与 helper 使用 XPC Mach service 通信。
5. XPC listener 设置 connection code signing requirement。不满足要求的客户端在业务处理前被拒绝。
6. 使用 `SMAppService.daemon` 注册、注销和查询 helper。
7. 正式发布必须使用 Developer ID 签名、hardened runtime 和 notarization。
8. LaunchDaemon plist 位于 `Covio.app/Contents/Library/LaunchDaemons/`。
9. plist 使用 `BundleProgram` 指向 app bundle 内的 `CovioHelper`。
10. 自定义 LaunchDaemon 安装脚本只保留一次迁移能力，迁移完成后删除。
11. app、helper、发布清单和本机安装记录使用同一个 `releaseId`。
12. `releaseId` 由 `productVersion`、单调递增的 `buildNumber` 和完整 Git commit 生成。
13. 发布清单同时记录 `helperProtocolVersion`、`helperSHA256` 和发布渠道。
14. `helperProtocolVersion` 只在 XPC 协议不兼容时变化。`releaseId` 每次发布变化。
15. helper 握手返回完整发布身份。app 必须逐项比较，不只比较语义版本。
16. release identity 不一致、helper 缺失或 helper 摘要错误时，Covio 进入只读安全模式。
17. 只读安全模式禁止睡眠写入、充电上限写入、主动放电和风扇控制。
18. 只读安全模式只保留读取、状态解释和 helper 修复入口。
19. 发布流水线先创建 Draft Release。所有门槛通过后才能提升为 Published Release。
20. app 与 helper 采用成对升级和成对回滚。不得只替换其中一方。
21. 升级 helper 前恢复风扇控制、充电上限和活动租约。
22. 升级失败时恢复上一版 app、helper 和 root-owned 安装记录。
23. 内部测试版本使用独立 channel，并从正式更新检查中排除。
24. App Store 版本不在本 ADR 范围内。

## 后果

### 正面

- root 进程的代码和依赖范围明显缩小。
- XPC 在连接阶段校验客户端身份。
- macOS 管理 daemon 的注册和授权状态。
- app 与 helper 的版本绑定可审计。
- 不匹配时仍可打开只读界面并执行修复。
- 发布物、Git commit 和本机安装记录使用同一个 release identity。
- 升级失败可以成对回滚。

### 负面

- 必须取得 Developer ID 证书并建立 notarization 流水线。
- 首次注册 helper 需要用户在 System Settings 批准。
- helper 或 plist 更新后必须重新注册。
- 独立 helper target 增加构建和测试成本。
- XPC 协议需要新的版本化和兼容性测试。
- Legacy LaunchDaemon 需要一次迁移窗口。

### 风险

- 重新注册可能再次要求用户批准。缓解：保留旧 helper，直到新 helper 握手成功。
- 签名或公证失败导致 helper 不可用。缓解：发布流水线拒绝生成正式 Release。
- XPC requirement 生成错误。缓解：使用固定测试客户端和错误签名客户端做正反验证。
- 升级中断留下混合版本。缓解：使用 release identity、根状态记录和成对回滚。
- helper 崩溃留下系统写入状态。缓解：租约、退出恢复、stale-state 恢复和重启验证。
- 当前没有 Developer ID。缓解：在取得证书前只开发内部测试路径，不发布正式版本。

## 备选方案

### 备选 1：继续使用当前完整 app 作为 root helper

该方案改动最少。
该方案继续让 root 进程加载完整用户态应用。
该方案继续依赖手写 LaunchDaemon 和 Unix socket。
该方案无法可靠解决 app 与 helper 混合版本。

未采纳。

### 备选 2：继续使用 `SMJobBless`

`SMJobBless` 可以安装特权 helper。
Apple 从 macOS 13 起将其标记为 deprecated，并建议改用 `SMAppService`。

未采纳。

### 备选 3：完全移除 helper

删除 helper 会移除合盖、风扇和部分充电能力。
当前产品范围不接受该裁剪。

未采纳。

### 备选 4：Legacy LaunchDaemon 加独立 helper

该方案可以在没有 `SMAppService` 签名前提时运行。
该方案仍需维护 LaunchDaemon plist、`launchctl`、安装脚本和迁移代码。
该方案不能使用系统托管的授权和生命周期。

未作为目标方案。
该路径只允许作为 #355 完成前的迁移基线，不能标记为正式完成状态。

### 备选 5：每次操作请求管理员授权

该方案不能支持持续风扇控制、租约和后台状态恢复。
频繁管理员授权降低可用性并增加误操作风险。

未采纳。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| Developer ID 证书 | pending | 安装 Developer ID Application 与 Installer 证书 |
| notarization 凭据 | pending | 配置 `notarytool` keychain profile |
| 更新后是否再次要求批准 | pending | 两版本连续注册与升级验证 |
| XPC 高频状态查询性能 | pending | 执行 #358 的性能与稳定性矩阵 |
| Legacy LaunchDaemon 停机窗口 | pending | 执行 #357 的迁移与回滚验证 |

## 参考

- [#350 Feature](https://github.com/wyz541/kmp-Covio/issues/350)
- [#351 Research](https://github.com/wyz541/kmp-Covio/issues/351)
- [特权能力架构调研](../research/privileged-helper-architecture/README.md)
- [调研结论](../research/privileged-helper-architecture/conclusion.md)
- [推荐架构](../research/privileged-helper-architecture/solution.md)
- [ADR-0006](adr-0006-lid-sleep-privileged-helper.md)
- [ADR-0005](adr-0005-local-code-signing.md)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [NSXPCListener.setConnectionCodeSigningRequirement](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:))
