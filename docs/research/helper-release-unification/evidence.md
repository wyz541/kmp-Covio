# 证据、命令和观察

## 环境证据

```sh
sw_vers
uname -m
system_profiler SPHardwareDataType
security find-identity -p codesigning
```

观察：

- macOS 27.0.1，26A434。
- arm64。
- MacBook Pro 18,2，Apple M1 Max，64 GB。
- 没有有效 Developer ID。
- 测试包使用 ad-hoc 签名。

## E-01：旧安装缺少统一身份

旧 app Info.plist 缺少：

- `CovioReleaseId`
- `CovioGitCommit`
- `CovioHelperProtocolVersion`
- `CovioInstallTransactionVersion`

旧 helper 协议为 `8`。
旧 helper 使用 Unix socket。
该安装用于保留恢复备份，不作为 N-1 升级源。

## E-02：PKG 自动重定位

命令：

```sh
pkgutil --expand-full Covio-0.5.2.pkg <dir>
plutil -p <dir>/Covio.pkg/PackageInfo
```

失败包包含：

```text
<bundle path="./Library/Application Support/Covio/Installer/staged/Covio.app" .../>
<relocate/>
```

修复包不包含 `<bundle path=...>`。

## E-03：TMPDIR 依赖

失败日志：

```text
Staged helper identity cannot be read
```

事务目录中的证据：

```text
helper-identity-NEW_HELPER.json
helper-identity-NEW_HELPER.stderr
```

修复后 helper 身份文件位于事务目录。
回归测试使用不存在的 `TMPDIR` 并通过。

## E-04：SMAppService entitlement

重复安装日志：

```text
Unregistering the dormant SMAppService helper
Cannot unregister CovioHelper: Requestor lacks required entitlement
```

移除该调用后，同一包重复安装通过。

## E-05：安全模式

缺失 helper：

```text
opsStatus=MISSING
Privileged write rejected by the helper release handshake: MISSING
```

身份不一致：

```text
opsStatus=OUTDATED
Privileged write rejected by the helper release handshake: UNTRUSTED
```

两种状态均没有产生充电状态文件。

## E-06：成对回滚

失败注入：

```sh
chflags uchg '/Library/Application Support/Covio/bin'
installer -pkg Covio-0.5.2-build4.pkg -target /
chflags nouchg '/Library/Application Support/Covio/bin'
```

安装日志：

```text
install: chmod 755 /Library/Application Support/Covio/bin: Operation not permitted
Rolling back transaction: new helper registration or exact handshake failed
Rollback completed at release 0.5.2+4+7416320420db02d38fd3ef744f1f46989cb28195
```

回滚后验证：

- app releaseId 为 build 4。
- helper releaseId 为 build 4。
- 安装记录 releaseId 为 build 4。
- XPC 状态为 MATCH。
- `SleepDisabled=0`。

## E-07：风扇活动升级

命令：

```sh
Covio --fan-control-configure-minimum
installer -pkg Covio-0.5.2-build4-fan.pkg -target /
```

配置结果：

```text
active=true,mode=manual,leaseRemainingSeconds=20
```

升级结果：成功。
升级后状态：

```text
active=false,mode=system
```

helper 日志没有新增 lease-expired 事件。

## E-08：充电上限活动升级

配置结果：

```text
enabled=true,targetPercent=80,phase=applying
```

升级结果：成功。
升级后状态：

```text
enabled=false,phase=off
```

`SleepDisabled=0`。

## E-09：自动化覆盖

```sh
bash scripts/test-all.sh
bash scripts/verify-helper-cutover.sh selftest
python3 -I scripts/test_release_pipeline.py
```

覆盖：

- 干净安装。
- 首次握手失败回滚。
- 中断恢复。
- 降级拒绝。
- helper SHA-256 错误。
- 签名错误。
- `SMAppService` 迁移。
- `TMPDIR` 不可用。
- 内部渠道不创建 latest。
- 恢复入口不依赖预先设置的 `TRANSACTION_ID`。
- 退出探测只匹配已安装 app 路径。
- 未开始事务归档后可重试。


## E-10：最终 Release 干净安装

最终内部 Release：

```text
releaseId: 0.5.2+4+8582c62c94a375e754b39b90c1e6fa95f12738f6
productVersion: 0.5.2
buildNumber: 4
channel: internal
helperProtocolVersion: 9
helperSHA256: a8a7ed3e548cb4dc96a0071535ac92b349541d9d0763dc1bb5356601a5fd7301
```

制品 SHA-256：

```text
Covio-0.5.2.pkg      2a8d836ec502c1efbf871df2f40194f079961714b4c757e6be6af8925f3bd5e5
Covio-0.5.2.dmg      b06487a8a4ad3ba5140d850f0fcfdf0ea37300e2fb488649b012ce29651c7fb6
Covio-0.5.2.app.zip  cec1f5da309c8bf2cc32e75143f21c1aea87845b078408a5596d946d68273eb5
```

干净安装结果：

```text
result=installed
previousReleaseId=""
```

重复安装结果：

```text
result=installed
previousReleaseId=0.5.2+4+8582c62c94a375e754b39b90c1e6fa95f12738f6
```

最终验证：

- app、运行中的 helper 和安装记录 releaseId 相同。
- helper 位于固定 root-owned 路径。
- LaunchDaemon 声明 XPC Mach service。
- `scripts/verify-helper-cutover.sh verify` 通过。
- `SleepDisabled=0`。
- 充电和租约状态文件不存在。

## E-11：损坏 Mach-O 和无签名 helper

损坏 Mach-O：

```text
sha256=cb26434dca6258b8d64a8a44ea50b34c556e45d1e90b523ef84d201f6d620dcd
status=UNTRUSTED
verify_exit=1
```

无签名 helper：

```text
code object is not signed at all
status=UNTRUSTED
verify_exit=1
```

恢复原 helper 后：

```text
status=MATCH
verify_exit=0
```

## E-12：LaunchDaemon 服务策略拒绝

命令：

```sh
launchctl disable system/com.wyz.covio.helper
launchctl bootstrap system /Library/LaunchDaemons/com.wyz.covio.helper.plist
```

观察：

```text
Bootstrap failed: 5: Input/output error
status=UNTRUSTED
verify_exit=1
```

重新 enable 和 bootstrap 后：

```text
status=MATCH
```

## E-13：合盖租约活动升级

升级前：

```text
SleepDisabled=1
activeLeaseCount=1
covioOwned=true
sleep_owner=root:wheel
```

升级后：

```text
SleepDisabled=0
sleep_owner=absent
status=MATCH
```

最终 build 4 重复执行相同步骤并通过。

## E-14：真实进程崩溃和恢复

测试 PKG 在 `app-installed` 状态后发送 SIGKILL：

```text
installer_exit=1
state=app-installed
Crash injection after app swap
```

执行恢复：

```sh
/Library/Application Support/Covio/Installer/recover.sh
```

结果：

```text
Rolling back transaction
Exact helper handshake matched for OLD
Rollback completed
status=MATCH
SleepDisabled=0
```

## E-15：崩溃测试发现的恢复缺陷

缺陷一：

```text
transaction.sh: TRANSACTION_ID: unbound variable
```

修复：
在加载事务环境前使用 `recovery` 作为安全占位事务 ID。

缺陷二：

```text
running app did not quit
```

原因：
`pgrep -x Covio` 匹配了其他工作树中的 Covio 进程。

修复：
改为精确匹配 `/Applications/Covio.app/Contents/MacOS/Covio`。

缺陷三：

```text
Unfinished transaction exists
```

原因：
失败发生在 `prepared` 状态写入前。
缺少 state 的事务永久阻塞下一次安装。

修复：
将未开始事务移动到 `history` 目录。
`recover.sh` 也支持归档这类事务。

## E-16：真实 Draft 和 latest 隔离

Draft：

```text
tag: v0.5.2-internal.4
isDraft: true
isPrerelease: true
targetCommitish: 8582c62c94a375e754b39b90c1e6fa95f12738f6
```

资产数量：8。
所有资产状态：uploaded。

所有 internal Release 已标记为 prerelease。
GitHub latest API 返回：

```text
HTTP 404 Not Found
```

结论：internal 渠道没有 latest。

## E-17：全量测试

```sh
bash scripts/test-all.sh
```

结果：通过。

```text
Kotlin 共享层：通过
macOS XCTest：866 passed，3 skipped，0 failures
```
