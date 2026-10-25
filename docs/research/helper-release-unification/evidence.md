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


## E-10：最终 Release 干净安装

最终内部 Release：

```text
releaseId: 0.5.2+3+45d1beccc041346061286595c6c0693ec7cf2982
productVersion: 0.5.2
buildNumber: 3
channel: internal
helperProtocolVersion: 9
helperSHA256: 0f73158c02d5731bef68169c4368d7b8bf468f596c227b5d5cf265591d0fd519
```

制品 SHA-256：

```text
Covio-0.5.2.pkg      33d2a05abe5c82bf975eba2452505eb0c82c8d9e8a6201dfa10d36181139d62c
Covio-0.5.2.dmg      b9eb626d3f2516f10a16b278faf663af91913b09b80468490260759fce593404
Covio-0.5.2.app.zip  b4de59474e745872ff6bde8f512afd8ec63088ba15b317ab05a02f1ca7e039e8
```

安装结果：

```text
result=installed
previousReleaseId=""
```

最终验证：

- app、运行中的 helper 和安装记录 releaseId 相同。
- helper 位于固定 root-owned 路径。
- LaunchDaemon 声明 XPC Mach service。
- `scripts/verify-helper-cutover.sh verify` 通过。
- `SleepDisabled=0`。
- `state.json` 和 `runtime.json` 不存在。
