# 电源历史

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 已实现 |
| 日期 | `2026-10-20` |
| Issue | #155 |
| Feature | #148 |
| 上游决策 | ADR-0007 |

## 目标

电源历史回答三个问题。

1. 供电方式何时变化。
2. Mac 何时睡眠、DarkWake 和完整唤醒。
3. 保持唤醒何时开始，哪个安全护栏释放了租约。

历史不保存租约正文。
历史不保存 `pmset` 原始输出。
历史不放宽策略判断。

## 数据路径

| 层 | 实现 | 职责 |
| --- | --- | --- |
| 事件模型 | `PowerHistoryEvent` | 保存事件类型、时间和诊断字符串 |
| 保留策略 | `PowerHistoryPolicy` | 固定条数上限和保留天数 |
| 纯逻辑 | `PowerHistoryLogic` | 去重、按时间排序、裁剪、24 小时窗口 |
| 持久化 | `PowerHistoryStore` | 读取、追加、清空和原子写入 |
| 运行时 | `PowerRuntime` | 观察系统、策略和 helper 状态，然后追加事件 |
| 页面 | `PowerManagementView` | 显示最近 24 小时的真实事件 |

历史文件位于应用支持目录的 `Power/history.json`。

## 事件类型

| 类型 | 触发条件 | 来源 |
| --- | --- | --- |
| `ADAPTER_CONNECTED` | 供电来源从电池变为适配器 | IOPS |
| `ADAPTER_DISCONNECTED` | 供电来源从适配器变为电池 | IOPS |
| `SLEPT` | 系统将要睡眠 | `NSWorkspace.willSleepNotification` |
| `DARK_WAKE` | 唤醒日志新增 DarkWake | `pmset -g log` 与 `WakeLogReader` |
| `FULL_WAKE` | 唤醒日志新增完整唤醒 | `pmset -g log` 与 `WakeLogReader` |
| `HOLD_STARTED` | 自动规则或手动会话开始保持唤醒 | `PowerPolicy`、`PowerRuntime` |
| `GUARD_RELEASED` | 电池、热状态或低电量模式触发释放 | `PowerPolicy` |
| `EXTERNAL_CONFLICT` | 外部 `SleepDisabled` 不属于 Covio | helper 与 `pmset` 兜底 |
| `EXTERNAL_CONFLICT_CLEARED` | 外部 `SleepDisabled` 已解除 | helper 与 `pmset` 兜底 |

## 写入流程

```mermaid
flowchart LR
  A[系统观察与策略结果] --> B[PowerRuntime 生成事件]
  B --> C[PowerHistoryStore 读取并裁剪]
  C --> D[写 history.json.tmp]
  D --> E[atomicMove 到 history.json]
  E --> F[更新页面最近 24 小时]
  C -->|失败| G[保留旧文件]
  G --> H[策略继续执行]
```

## 有界策略

1. 最多保留 `200` 条事件。
2. 最多保留 `7` 天。
3. 页面只显示最近 `24` 小时。
4. 同一时刻先丢弃最旧事件。
5. 无效事件不进入结果。
6. 损坏文件按空历史读取。
7. 清空操作删除主文件和临时文件。

## 原子写入与故障隔离

1. 先创建父目录。
2. 写入同目录的 `history.json.tmp`。
3. 写入成功后执行 `atomicMove`。
4. 写入失败时保留旧文件。
5. `append` 返回 `null` 表示没有落盘。
6. `PowerRuntime` 不把失败事件加入内存列表。
7. 历史写入失败不改变租约和策略结果。

## 唤醒来源

`NSWorkspace.didWakeNotification` 只作为兜底。

完整唤醒优先来自 `WakeLogReader`。
2 秒内没有新的唤醒日志时，运行时记录一次 `FULL_WAKE` 兜底。
DarkWake 只来自唤醒日志解析。
DarkWake 感知关闭时不伪造 DarkWake 事件。

## 限制

1. `pmset` 输出不是公开稳定接口。
2. 唤醒日志读取失败时只能记录兜底完整唤醒。
3. 系统可能在历史写入前立即睡眠，最多丢失最后一条事件。
4. 文件损坏时无法恢复旧事件。
5. 没有管理员权限时不能验证 helper 写入路径。
6. 历史不是安全审计日志。
