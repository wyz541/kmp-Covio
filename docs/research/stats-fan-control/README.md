# Stats 风扇控制调研

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 已完成 |
| 日期 | `2026-10-24` |
| 对标仓库 | [`exelban/stats`](https://github.com/exelban/stats) |
| 固定提交 | `7d3f70dcd6a07177d0a529a1b907021eef740158` |
| 验证状态 | 仅源码调研；未执行风扇写入 |

## 前因

Covio 的自动曲线会持续写 `F%dTg`。
Stats 的自动模式把风扇交还 macOS。
两者对“自动”的定义不同。
问题定义见 [context.md](context.md)。

## 过程

本次调研读取 Stats 的风扇模型、Popover、SMC helper 和相关历史提交。
源码位置、观察和限制见 [evidence.md](evidence.md)。
控制路径和约束分析见 [investigation.md](investigation.md)。

## 结果

Stats 的自动模式写风扇模式 `0`。
Stats 的自动模式不运行温度曲线。
Stats 的手动模式写风扇模式 `1`。
Stats 的同步控制按转速百分比分发滑杆变化。
Stats 同步模式、最低、最高、全速和关闭操作。
结论和取舍见 [conclusion.md](conclusion.md)。

## 预期

Covio 需要保留系统自动、曲线和手动三个概念。
系统自动不持有风扇。
曲线和手动才持有风扇。
多风扇手动控制提供持久化同步开关。
实现映射见 [solution.md](solution.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题、范围、角色和约束 |
| [evidence.md](evidence.md) | 固定源码证据和限制 |
| [investigation.md](investigation.md) | Stats 控制路径和历史演变 |
| [conclusion.md](conclusion.md) | 结论、取舍和风险 |
| [solution.md](solution.md) | Covio 方案和验收标准 |
| [validation/README.md](validation/README.md) | 验证计划 |
