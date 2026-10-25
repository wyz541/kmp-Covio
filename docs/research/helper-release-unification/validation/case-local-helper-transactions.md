# Case 1：本机 helper 安装、升级和回滚

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 主要场景通过，三项边界部分覆盖 |
| 日期 | 2026-10-25 |
| 执行人 | agent |
| 复核人 | 待填写 |
| Issue | #358 |

## 2. 初始状态

| 项目 | 值 |
| --- | --- |
| 旧 app | Covio 0.5.2 build 1 |
| 旧 helper | 协议 8，Unix socket |
| Developer ID | 无 |
| 签名 | ad-hoc |
| 固定 helper | 不存在 |
| 旧记录 | 无 installed-release.json |

旧 app 和旧 helper 已备份。
旧状态中的 `state.json` 和 `runtime.json` 在预检时不存在。
`SleepDisabled` 为 `0`。

## 3. 成功流程

### 3.1 干净安装

真实 PKG 安装成功。
安装记录：

```json
{
  "result": "installed",
  "previousReleaseId": ""
}
```

安装后：

- 固定 helper 存在。
- helper 所有者为 `root:wheel`。
- LaunchDaemon 指向固定 helper。
- 记录 releaseId 与 app/helper 相同。
- XPC 握手为 MATCH。

### 3.2 重复安装

同一内部包再次安装成功。
`previousReleaseId` 与当前 releaseId 相同。
app、helper 和记录保持 MATCH。

### 3.3 N-1 升级

源版本：build 3。
目标版本：build 4。
升级成功。
`previousReleaseId` 为 build 3。
升级后 app、helper、plist 和记录全部为 build 4。
XPC 握手为 MATCH。

## 4. 安全模式

### 4.1 helper 身份不匹配

固定 helper 临时替换为 build 3。
LaunchDaemon 重启成功。
app 期望 build 4。

观察：

```text
opsStatus=OUTDATED
Privileged write rejected by the helper release handshake
```

充电状态文件没有产生。

### 4.2 helper 缺失

停止服务并移走固定 helper。

观察：

```text
opsStatus=MISSING
charge limit state.json: absent
charge limit runtime.json: absent
```

恢复 helper 后重新达到 MATCH。

## 5. 失败注入与回滚

### 5.1 helper 路径不可写

步骤：

1. 对固定 helper 目录设置 `uchg`。
2. 重新安装 build 4 PKG。
3. 安装器完成 app 交换后尝试安装 helper。
4. helper 写入失败。
5. 事务恢复旧 app 和旧 helper。
6. 清除 `uchg`。

安装日志：

```text
chmod 755 /Library/Application Support/Covio/bin: Operation not permitted
Rolling back transaction
Rollback completed
```

回滚后：

- app releaseId 为 build 4。
- helper releaseId 为 build 4。
- 记录 releaseId 为 build 4。
- XPC 状态为 MATCH。
- `SleepDisabled=0`。

### 5.2 回滚后再次升级

回滚后再次执行 build 4 升级。
升级成功。
随后活动充电上限和风扇测试也完成。

## 6. 状态恢复

### 6.1 充电上限

升级前：

```text
enabled=true,targetPercent=80,phase=applying
```

升级后：

```text
enabled=false,phase=off
```

### 6.2 风扇

升级前：

```text
active=true,mode=manual,leaseRemainingSeconds=20
```

升级后：

```text
active=false,mode=system
```

日志没有新增风扇租约过期事件。
说明升级事务在租约过期前恢复了系统控制。

## 7. 自动化补充

以下场景由事务脚本覆盖：

- 首次握手失败回滚。
- 中断恢复。
- 降级拒绝。
- helper SHA-256 不匹配。
- app 签名错误。
- `SMAppService` 迁移。
- 不可用 `TMPDIR`。

执行：

```sh
bash scripts/test-all.sh
```

结果：通过。

## 8. 最终 Release 安装

最终内部 Release：

```text
releaseId: 0.5.2+3+45d1beccc041346061286595c6c0693ec7cf2982
buildNumber: 3
channel: internal
```

执行干净安装。
安装结果：`installed`。
最终状态：

- app、helper 和记录 releaseId 相同。
- 固定 helper 为 `root:wheel`。
- LaunchDaemon 使用固定 helper。
- XPC 握手为 MATCH。
- `SleepDisabled=0`。
- 没有充电和租约状态残留。

## 9. 限制

1. 损坏 Mach-O 没有单独执行。
2. LaunchDaemon 被系统策略拒绝没有单独执行。
3. 真实安装进程崩溃没有执行。
4. 合盖租约活动状态没有单独执行。
5. 测试使用 ad-hoc 签名。
6. 最终 Release 制品仍需发布负责人审阅。

## 10. 清理结果

- 充电上限已恢复。
- 风扇控制已恢复。
- `SleepDisabled=0`。
- 固定 helper 恢复且 app/helper 为 MATCH。
- 测试备份保留到发布审阅结束。
