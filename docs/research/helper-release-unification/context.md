# 问题、环境和成功标准

## 问题

本主题回答三个问题：

1. ADR-0020 的固定路径 helper 能否在真实 Mac 上安装。
2. app、helper、plist 和安装记录能否成对升级与回滚。
3. 不一致、缺失或写入失败时，Covio 是否进入只读安全模式。

## 环境

| 项目 | 值 |
| --- | --- |
| 机型 | `MacBookPro18,2` |
| 芯片 | Apple M1 Max |
| 内存 | 64 GB |
| 架构 | arm64 |
| 系统 | macOS 27.0.1，26A434 |
| Xcode | 27.1 |
| Developer ID | 未配置 |
| 测试签名 | ad-hoc |
| 分发渠道 | internal/local |

测试前旧安装：

- Covio `0.5.2` build 1。
- helper 协议 `8`。
- helper 使用 Unix socket。
- app 为 ad-hoc 签名。
- 旧 app 没有完整 `releaseId` 元数据。

## 范围

- 固定路径 helper。
- Legacy LaunchDaemon。
- XPC。
- 内部 PKG。
- 干净安装。
- 重复安装。
- N-1 升级。
- 状态恢复。
- 安全模式。
- 成对回滚。
- 中断恢复测试。

## 范围外

- Apple Developer Program。
- Developer ID。
- notarization。
- Gatekeeper 无警告启动。
- 公开最新版本。
- App Store。
- Windows 和 iOS。

## 成功标准

- 固定 helper 为 `root:wheel`。
- LaunchDaemon 只指向固定 helper。
- app、helper 和记录 `releaseId` 一致。
- 非 MATCH 状态禁止特权写入。
- 升级前恢复风扇和充电状态。
- helper 写入失败时恢复旧 app、helper、plist 和记录。
- 系统在测试后没有 `SleepDisabled`、充电状态或 helper 租约残留。
