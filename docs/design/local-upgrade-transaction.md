# 本机 app 与 helper 升级事务

## 状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 已实现；Developer ID 真机矩阵待 #358 |
| 日期 | `2026-10-25` |
| Issue | #357 |
| 上游决策 | ADR-0018 |

## 目标

PKG 把 app 与 helper 作为一个事务安装。
任一步失败时，安装器恢复上一版 app、helper 和 `installed-release.json`。

## 事务边界

`CovioHelper` 是 `Covio.app` 的内嵌可执行文件。
因此事务边界是整个 `Covio.app` bundle。
安装器使用 `renamex_np(RENAME_SWAP)` 原子交换 app bundle。
交换后，新 app 和新 helper 同时生效，不会留下混合版本。

## PKG 布局

PKG 不直接覆盖 `/Applications/Covio.app`。
PKG 先把新 bundle 和恢复工具写入 root-owned 暂存区：

```text
/Library/Application Support/Covio/Installer/
├── bin/CovioTransaction
├── staged/Covio.app
├── transaction.sh
└── recover.sh
```

`preinstall` 备份当前版本。
`postinstall` 验证暂存版本，执行原子交换，再注册新 helper。

## 提交条件

安装器在以下检查全部通过后才提交：

1. app、内嵌 manifest 和 helper 的 `releaseId`、版本、build、commit、协议和 channel 一致。
2. helper 文件的 SHA-256 与 manifest 一致。
3. app 和 helper 均为 arm64。
4. app 与 helper 的代码签名有效。
5. 正式渠道的 app 和 helper 使用 Developer ID Application 和 hardened runtime。
6. 正式渠道的 app 通过 notarization staple 和 Gatekeeper。
7. 新 build 不低于旧 build。不同 release 不允许复用同一 build。
8. 新 helper 注册成功，并与新 app 完成精确握手。
9. root-owned `installed-release.json` 写入成功。

## 前置恢复

安装器先要求 Covio 正常退出。
升级感知版本通过 `prepareInstallTransaction` helper 命令恢复：

- 风扇系统控制。
- 充电上限原始状态。
- 全部 Covio 合盖租约。
- Covio 持有的 `SleepDisabled`。

任一恢复动作失败时，安装器在交换 bundle 前停止。

## 状态

| 状态 | 含义 | 恢复动作 |
| --- | --- | --- |
| `prepared` | 旧版本已备份，新版本位于 PKG | 可回滚 |
| `prepared-new` | 干净安装，旧版本不存在 | 可删除新版本 |
| `swapping` | 正在交换 bundle | 下次运行恢复旧版本 |
| `app-installed` | 新 bundle 已到位 | 握手失败时恢复旧版本 |
| `committed` | 新版本已提交 | 手动恢复使用上一份备份 |
| `rolled-back` | 已恢复旧版本 | 无 |
| `rollback-failed` | 回滚未完成 | 运行恢复命令并保留现场 |

## 安装记录

`/Library/Application Support/Covio/installed-release.json` 由 root 所有。
安装成功时，该文件与新 app 的发布清单完全一致。

`/Library/Application Support/Covio/install-report.json` 写入：

- `source`。
- `transactionId`。
- `releaseId`。
- `previousReleaseId`。
- `result`。
- `rollbackReason`。
- `recordedAt`。

## 恢复命令

自动恢复未完成事务：

```sh
sudo "/Library/Application Support/Covio/Installer/recover.sh"
```

手动恢复上一份成功备份：

```sh
sudo "/Library/Application Support/Covio/Installer/recover.sh" --manual-rollback
```

恢复命令先停止 app，再原子恢复旧 bundle。
恢复后，命令重新注册旧 helper，并要求精确握手通过。

## 失败行为

| 失败 | 结果 |
| --- | --- |
| 前置签名或摘要校验失败 | app 不变，不交换 bundle |
| 状态恢复失败 | app 和 helper 不变，升级停止 |
| 降级或混合 release | app 不变，不交换 bundle |
| helper 首次握手失败 | 原子恢复旧 app 和 helper |
| 安装记录写入失败 | 原子恢复旧 app、helper 和旧记录 |
| 交换后进程中断 | 恢复命令根据事务状态回滚 |

## 验证边界

- 脚本测试使用真实 ad-hoc 签名和真实原子交换。
- 脚本测试覆盖成功、回滚、恢复失败、降级、摘要错误、签名错误、中断和干净安装。
- Developer ID、notarization、SMAppService 批准和跨版本真机升级由 #358 验证。
