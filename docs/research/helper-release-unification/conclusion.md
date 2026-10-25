# 结论、限制和后续动作

## 结论

ADR-0020 的 internal/local helper 路径已在真实 Mac 上打通。
干净安装、重复安装和 N-1 升级均成功。
app、helper、plist 和安装记录能够保持一致。
helper 缺失和身份不一致时，特权写入被拒绝。
helper 安装失败时，事务恢复旧 app 和 helper 并重新达到 MATCH。
活动风扇和活动充电上限在升级前被恢复。

## 已验证

- 固定路径 helper。
- root 所有权和权限。
- XPC Mach service。
- 完整身份握手。
- 缺失 helper 安全模式。
- 身份不一致安全模式。
- 同一包重复安装。
- build 3 到 build 4 升级。
- 充电上限活动时升级。
- 风扇控制活动时升级。
- 固定路径不可写时成对回滚。
- 中断恢复自动化测试。
- 没有 `SMAppService` 注册要求。
- 没有 Developer ID 或 notarization 要求。

## 限制

1. 测试使用 ad-hoc 签名，不证明发布者真实性。
2. 损坏 Mach-O 和签名错误没有单独做实机案例。
3. LaunchDaemon 被系统策略拒绝没有单独做实机案例。
4. 安装过程中真实进程崩溃没有执行；恢复由事务测试覆盖。
5. 合盖租约活动状态没有单独做实机升级案例。
6. 内部 Draft 的“不创建 latest”由发布流水线测试覆盖，没有创建真实 Release。
7. 发布负责人尚未对最终 Release 制品完成审阅。

## 最终 Release

最终内部 Release：

```text
0.5.2+3+45d1beccc041346061286595c6c0693ec7cf2982
```

最终 PKG 已在本机干净安装。
固定 helper、LaunchDaemon、安装记录和 XPC 握手均通过验证。

## 后续动作

1. 发布负责人审阅证据。
2. 合并实现 PR。
3. 根据审阅结果关闭 #358 和 Feature #350。
