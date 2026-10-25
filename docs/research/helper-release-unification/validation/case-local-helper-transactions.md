# Case 1：本机 helper 安装、升级和回滚

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 全部矩阵通过；真实崩溃发现并修复恢复缺陷 |
| 日期 | 2026-10-25 |
| 执行人 | agent |
| 复核人 | `wyz` |
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
releaseId: 0.5.2+4+8582c62c94a375e754b39b90c1e6fa95f12738f6
productVersion: 0.5.2
buildNumber: 4
channel: internal
helperProtocolVersion: 9
helperSHA256: a8a7ed3e548cb4dc96a0071535ac92b349541d9d0763dc1bb5356601a5fd7301
```

干净安装结果：`installed`。
`previousReleaseId` 为空。
重复安装结果：`installed`。
重复安装的 `previousReleaseId` 与当前 releaseId 相同。
最终状态：

- app、helper 和记录 releaseId 相同。
- 固定 helper 为 `root:wheel`。
- LaunchDaemon 使用固定 helper。
- XPC 握手为 MATCH。
- `SleepDisabled=0`。
- 没有充电、风扇或租约状态残留。

Draft：

```text
tag: v0.5.2-internal.4
draft: true
prerelease: true
latest: false
```

## 9. 真实边界场景

### 9.1 损坏 Mach-O

固定 helper 被截断为 4 KiB 零字节。
LaunchDaemon 无法启动有效 helper。
app 报告 `UNTRUSTED`。
恢复原 helper 后重新达到 MATCH。

### 9.2 无签名 helper

固定 helper 移除代码签名。
`codesign --verify --strict` 返回 `code object is not signed at all`。
app 报告 `UNTRUSTED`。
恢复原 helper 后重新达到 MATCH。

### 9.3 LaunchDaemon 服务策略拒绝

执行：

```sh
launchctl disable system/com.wyz.covio.helper
launchctl bootstrap system /Library/LaunchDaemons/com.wyz.covio.helper.plist
```

bootstrap 返回：

```text
Bootstrap failed: 5: Input/output error
```

app 进入安全模式。
重新 enable 并 bootstrap 后达到 MATCH。

### 9.4 合盖租约活动时升级

升级前：

```text
SleepDisabled=1
activeLeaseCount=1
sleep_owner=root:wheel
```

升级后：

```text
SleepDisabled=0
sleep_owner=absent
```

app、helper 和安装记录保持 MATCH。
最终 build 4 的重复安装也使用相同步骤通过。

### 9.5 真实安装进程崩溃

测试 PKG 在 `app-installed` 状态后向 `postinstall` 发送 SIGKILL。
`installer` 返回失败。
`current-transaction/state` 保持 `app-installed`。
执行：

```sh
/Library/Application Support/Covio/Installer/recover.sh
```

恢复结果：

```text
Rollback completed
status=MATCH
SleepDisabled=0
```

### 9.6 崩溃测试发现的恢复缺陷

首次真实崩溃测试发现 `recover.sh` 在加载事务环境前引用未定义的 `TRANSACTION_ID`。
修复后，恢复入口先使用安全占位值配置路径，再从事务环境加载真实 ID。

第二次测试发现两个问题：

- 退出探测匹配了其他工作树中的 Covio 进程。
- 未进入 `prepared` 状态的旧事务会永久阻塞下一次安装。

最终实现：

- 只匹配 `/Applications/Covio.app/Contents/MacOS/Covio`。
- 将未开始事务移动到 `history` 目录。
- `recover.sh` 可安全归档未开始事务。
- 归档后可以继续新的安装事务。

## 10. 全量验证

```sh
bash scripts/test-all.sh
```

结果：通过。

- Kotlin 共享层测试通过。
- macOS XCTest：866 个通过，3 个跳过。
- 发布身份、合同、事务和图集检查通过。

## 11. 限制

1. 测试使用 ad-hoc 签名，不证明发布者真实性。
2. 当前范围不包含 Apple Developer Program、Developer ID 或 notarization。
3. 当前范围不包含公开 Release、自动静默安装或 App Store。

## 12. 清理结果

- 充电上限已恢复。
- 风扇控制已恢复。
- 合盖租约已恢复。
- `SleepDisabled=0`。
- 最终 app、helper 和记录为同一 releaseId。
- 测试备份保留到合并和发布审阅完成。
