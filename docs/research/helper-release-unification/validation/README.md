# 真机矩阵与结果

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | `2026-10-25` |
| 系统 | macOS 27.0.1，26A434 |
| 机型 | `MacBookPro18,2`，Apple M1 Max、64 GB |
| 分发 | internal/local |
| 签名 | ad-hoc |
| 最终制品 | build 4 |
| 复核人 | `wyz` |

## 矩阵

| 编号 | 场景 | 状态 | 结果 |
| --- | --- | --- | --- |
| V01 | 干净安装，固定 helper 不存在 | 通过 | MATCH |
| V02 | 从 build 3 升级到 build 4 | 通过 | MATCH |
| V03 | app 为 build 4，运行中 helper 为 build 3 | 通过 | 安全模式，写入拒绝 |
| V04 | 语义版本相同但 releaseId 不同 | 通过 | V03 覆盖 |
| V05 | helper 缺失 | 通过 | MISSING，写入拒绝 |
| V06 | helper 损坏或签名错误 | 通过 | 损坏 Mach-O 和无签名 helper 得到 UNTRUSTED 或 MISSING，恢复后 MATCH |
| V07 | LaunchDaemon 加载被拒绝 | 通过 | `launchctl disable` 后 bootstrap 返回 5，app 进入安全模式 |
| V08 | app 已交换但 helper 注册失败 | 通过 | 成对回滚 |
| V09 | helper 或 plist 替换后 app 安装失败 | 通过 | 固定 helper 目录不可写注入 |
| V10 | 安装进程真实崩溃 | 通过 | `postinstall` 在 app 交换后收到 SIGKILL，`recover.sh` 成对回滚 |
| V11 | 风扇活动时升级 | 通过 | 升级前恢复系统控制 |
| V12 | 充电上限活动时升级 | 通过 | 升级前恢复原策略 |
| V13 | 回滚后再次升级 | 通过 | 回滚后两次升级成功 |
| V14 | 内部包重复安装 | 通过 | MATCH |
| V15 | 内部渠道不提供 latest | 通过 | 真实 Draft 为 draft 和 prerelease；全部 internal Release 为 prerelease；latest API 返回 404 |
| V16 | 最终 Release 干净安装 | 通过 | MATCH，`previousReleaseId` 为空 |
| V17 | 合盖租约活动时升级 | 通过 | `SleepDisabled=1`，owner 标记存在；升级后为 `0` 且标记缺失 |
| V18 | 未开始事务阻塞后重试 | 通过 | 未交换事务先归档，后续安装继续 |

## 验收检查

| 项目 | 状态 |
| --- | --- |
| 非匹配状态禁止特权写入 | 通过 |
| 正常模式不运行混合版本 | 通过 |
| 回滚后 app、helper、plist、记录一致 | 通过 |
| 风扇、充电和合盖租约状态恢复 | 通过 |
| 固定 helper 为 root-owned | 通过 |
| 不需要 SMAppService 注册 | 通过 |
| 不需要 Developer ID 或 notarization | 通过 |
| 证据和结果记录 | 通过 |
| 发布负责人审阅 | 通过 |

## 清理

- 不保留测试充电上限。
- 不保留测试风扇控制。
- 不保留测试合盖租约。
- `SleepDisabled` 为 `0`。
- 最终 app、运行中的 helper 和安装记录为同一 releaseId。
- 测试旧状态使用独立备份目录。
