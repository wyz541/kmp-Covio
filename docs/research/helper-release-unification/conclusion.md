# 结论、限制和后续动作

## 结论

ADR-0020 的 internal/local helper 路径已在真实 Mac 上完成验收。
干净安装、重复安装和 N-1 升级均成功。
app、helper、plist 和安装记录能够保持一致。
所有非 MATCH 状态都进入只读安全模式。
失败事务能够成对回滚。
真实进程崩溃后，`recover.sh` 能够恢复旧发布身份。
活动风扇、充电上限和合盖租约在升级前被恢复。
真实 internal Draft 已创建，全部 internal Release 不提供 latest。

## 已验证

- 固定路径 helper。
- root 所有权和权限。
- XPC Mach service。
- 完整身份握手。
- 缺失 helper 安全模式。
- 身份不一致安全模式。
- 损坏 Mach-O 和无签名 helper 安全模式。
- LaunchDaemon 被服务策略拒绝后的安全模式。
- 同一包重复安装。
- build 3 到 build 4 升级。
- 充电上限活动时升级。
- 风扇控制活动时升级。
- 合盖租约活动时升级。
- 固定路径不可写时成对回滚。
- 真实安装进程在 app 交换后崩溃并恢复。
- 未开始事务归档后重试。
- 没有 `SMAppService` 注册要求。
- 没有 Developer ID 或 notarization 要求。
- 真实 Draft 与 latest 隔离。

## 真机发现并修复的问题

1. PKG 自动重定位 staged app。
2. 事务依赖不可用的 `TMPDIR`。
3. Legacy 安装调用无 entitlement 的 `SMAppService.unregister()`。
4. Debug 写入没有完整握手保护。
5. `recover.sh` 在加载事务环境前引用未定义变量。
6. 退出探测匹配了其他路径中的 Covio 进程。
7. 未开始事务会永久阻塞下一次安装。

## 限制

1. 测试使用 ad-hoc 签名，不证明发布者真实性。
2. 当前范围不包含 Apple Developer Program、Developer ID 或 notarization。
3. 当前范围不包含公开 Release、自动静默安装或 App Store。

## 最终 Release

最终内部 Release：

```text
releaseId: 0.5.2+4+8582c62c94a375e754b39b90c1e6fa95f12738f6
productVersion: 0.5.2
buildNumber: 4
channel: internal
helperProtocolVersion: 9
helperSHA256: a8a7ed3e548cb4dc96a0071535ac92b349541d9d0763dc1bb5356601a5fd7301
```

Draft：

```text
tag: v0.5.2-internal.4
state: draft
prerelease: true
latest: false
```

最终 PKG 已在本机完成干净安装和重复安装。
固定 helper、LaunchDaemon、安装记录和 XPC 握手均通过验证。

## 后续动作

1. 合并实现 PR。
2. 关闭 #358。
3. 在 Feature #350 中记录最终完成状态。
