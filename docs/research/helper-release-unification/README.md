# CovioHelper 发布统一真机验证

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 真机矩阵完成主要场景；剩余边界见验证索引 |
| 日期 | `2026-10-25` |
| Issue | #358 |
| 上游决策 | [ADR-0020](../../adr/adr-0020-local-only-helper-distribution.md) |
| 当前分发 | internal/local |
| 签名身份 | ad-hoc；没有 Developer ID |

## 前因

app 与 helper 曾来自不同发布身份。
旧 helper 复用完整 app 二进制。
新固定路径 helper 需要独立升级和回滚。
普通用户不能获得 Developer ID 或 notarization。

本主题验证 ADR-0020 在真实 Mac 上是否可安装、可升级、可回滚。

## 背景

目标架构使用：

- 独立 `CovioHelper`。
- 固定 root-owned helper 路径。
- Legacy LaunchDaemon。
- XPC Mach service。
- root-owned 客户端签名 requirement。
- 完整 `releaseId` 和 helper SHA-256 握手。
- app、helper、plist 和安装记录的成对事务。

背景和边界见 [context.md](context.md)。

## 过程

本主题构建 ad-hoc internal PKG。
本主题先执行干净安装。
本主题再执行重复安装、N-1 升级、状态恢复和失败注入。
失败现场来自真实 `installer`、`launchd`、`codesign` 和事务日志。

真机过程发现并修复了五个发布阻断项。
失败原因、修复提交和证据见 [evidence.md](evidence.md)。

## 结果

以下场景在真实 Mac 上通过：

- 干净安装。
- 固定 helper 路径和 root 所有权。
- 同一内部包重复安装。
- build 3 到 build 4 的 N-1 升级。
- 充电上限活动时升级。
- 风扇最低转速活动时升级。
- helper 缺失时进入安全模式并拒绝写入。
- helper 发布身份不匹配时进入安全模式并拒绝写入。
- helper 写入失败时成对回滚 app、helper、plist 和记录。

完整矩阵见 [validation/README.md](validation/README.md)。
完整案例见 [validation/case-local-helper-transactions.md](validation/case-local-helper-transactions.md)。

## 预期

内部包应满足：

1. app、运行中的 helper 和安装记录使用同一 `releaseId`。
2. 非 MATCH 状态禁止特权写入。
3. 升级前恢复风扇、充电上限和租约。
4. 首次注册或握手失败时成对回滚。
5. 不需要 `SMAppService` 注册。
6. 不需要 Developer ID 或 notarization。

方案和发布流程见 [solution.md](solution.md)。
限制和未执行项见 [conclusion.md](conclusion.md)。

## 实现预期的手段

发布步骤：

1. app 与 helper 使用同一 release manifest 构建。
2. PKG 使用空 component plist，staged app 不能成为可重定位 bundle。
3. 安装器先恢复特权状态。
4. 安装器备份 app、helper、plist、helper 元数据和安装记录。
5. 安装器交换 app bundle。
6. 安装器写入固定 helper 和 LaunchDaemon plist。
7. 安装器执行完整身份握手。
8. 握手通过后写入 `installed-release.json`。
9. 任一步失败时恢复旧对象。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题、环境和成功标准 |
| [investigation.md](investigation.md) | 真机调查和五个失败根因 |
| [conclusion.md](conclusion.md) | 结论、限制和后续动作 |
| [solution.md](solution.md) | 发布和回滚方案 |
| [evidence.md](evidence.md) | 证据索引、命令和观察 |
| [validation/README.md](validation/README.md) | 真机矩阵和结果 |
| [validation/case-local-helper-transactions.md](validation/case-local-helper-transactions.md) | 完整执行记录 |
