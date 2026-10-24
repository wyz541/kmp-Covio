# 验证目标、矩阵与风险

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 部分阻塞 |
| 日期 | `2026-10-24` |
| 当前事实 | 没有 Developer ID；ad-hoc 与自签名注册探针已失败 |
| 目标验证 | Developer ID 与 notarized daemon 的注册、更新和恢复 |

## 案例索引

| 案例 | 场景 | 状态 | 结果 |
| --- | --- | --- | --- |
| [case-smappservice-signed-lifecycle.md](case-smappservice-signed-lifecycle.md) | 签名 daemon 注册与升级 | 阻塞 | 等待 Developer ID |

## 验证目标

1. 证明 notarized app 可以注册 `SMAppService.daemon`。
2. 证明 daemon 更新后可以重新注册。
3. 证明 XPC 代码签名 requirement 会拒绝未授权客户端。
4. 证明升级前能够恢复风扇、充电和租约状态。
5. 证明升级失败可以成对回滚 app 与 helper。
6. 证明 Legacy LaunchDaemon 可以安全迁移到目标 daemon。

## 范围内事项

- macOS 26 及后续。
- Developer ID 签名和 notarization。
- `SMAppService.daemon`。
- XPC Mach service。
- 独立最小 helper。
- Legacy LaunchDaemon 迁移。

## 范围外事项

- App Store 审核。
- Windows 与 iOS。
- 无 root 功能裁剪。
- 正式发布版本的业务策略配置。

## 当前事实

1. 本机没有有效 codesigning identity。
2. 既有自签名与 ad-hoc 探针均注册失败。
3. 当前 helper 使用 LaunchDaemon 与 Unix socket。
4. 当前 app 与 helper 为 `0.5.2`。

## 成功标准

- daemon 注册最终进入 `enabled`。
- daemon 启动后完成精确身份握手。
- 未签名或错误 Team ID 的客户端连接失败。
- 两个连续版本的 app/helper 更新后身份一致。
- 风扇、充电和租约状态在升级后恢复。
- 安装失败后 app、helper 和记录成对回滚。
- 清理后没有残留 daemon、plist 或测试状态。

## 前置条件

- Apple Developer Program 账号。
- Developer ID Application 证书。
- Developer ID Installer 证书。
- notarization 凭据。
- 专用测试 Mac。
- 可回滚的旧版 app 和 helper。

## 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 注册需要再次批准 | 用户升级中断 | 保留旧 daemon，直到新 daemon 可用 |
| helper 崩溃 | 风扇或充电状态残留 | 退出钩子、租约和 stale-state 恢复 |
| XPC 接口绕过 | 越权写入 | 连接签名 requirement 和固定命令矩阵 |
| 回滚不完整 | app 与 helper 混合版本 | 以 releaseId 为事务提交条件 |
| 系统设置残留 | 系统不睡或充电异常 | 预检备份、恢复脚本和人工复核 |

## 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | ad-hoc 签名注册 daemon | 已完成，失败 | [evidence.md](../evidence.md#e-13自签名与-ad-hoc-的注册探针失败) |
| V02 | Developer ID 公证 app 注册 daemon | 阻塞 | [case-smappservice-signed-lifecycle.md](case-smappservice-signed-lifecycle.md) |
| V03 | 两版本 helper 更新后重新注册 | 尚未执行 | 待创建 |
| V04 | XPC 拒绝未授权客户端 | 尚未执行 | 待创建 |
| V05 | 风扇、充电和租约状态升级恢复 | 尚未执行 | 待创建 |
| V06 | 升级失败与成对回滚 | 尚未执行 | 待创建 |
| V07 | Legacy LaunchDaemon 迁移 | 尚未执行 | 待创建 |

## 证据要求

- 记录 macOS build、硬件、app releaseId、helper releaseId。
- 记录签名 Team ID 和 notarization 结果。
- 记录 `SMAppService.status` 的每个状态迁移。
- 记录 XPC 拒绝连接的错误码。
- 记录升级前后风扇、充电和租约状态。
- 记录回滚后的 app、helper 和安装记录。
- 不记录用户密码、令牌或完整隐私日志。

## 清理步骤

1. 通过测试工具调用 `unregister()`。
2. 确认测试 daemon 不在运行。
3. 确认测试 plist 不在 `/Library/LaunchDaemons`。
4. 恢复测试前的系统电源设置。
5. 恢复旧版 app 和 helper。
6. 删除隔离测试目录。
7. 复核 `pmset -g assertions` 和 `pmset -g custom`。

## 关联文档

- [主题索引](../README.md)
- [推荐架构](../solution.md)
- [结论](../conclusion.md)
- [证据](../evidence.md)
