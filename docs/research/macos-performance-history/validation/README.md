# 验证矩阵

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 通过，真实 10 天 soak 取消 |
| 日期 | 2026-10-22 |
| 执行人 | agent |
| 复核人 | 待填写 |

## 2. 案例索引

| 案例 | 主题 | 状态 | 文件 |
| --- | --- | --- | --- |
| Case 1 | macOS 历史数据覆盖 | 通过，有限制 | [case-macos-log-retention.md](case-macos-log-retention.md) |
| Case 2 | 监控读取成本 | 通过，有限制 | [case-sampler-cost.md](case-sampler-cost.md) |
| Case 3 | SQLite 容量与查询 | 通过 | [case-sqlite-capacity.md](case-sqlite-capacity.md) |
| Case 4 | 真实采样、HTML 导出与 soak | 通过，真实 10 天 soak 取消 | [case-macos-performance-history-soak.md](case-macos-performance-history-soak.md) |

## 3. 验证目标

1. 确认系统历史能覆盖什么。
2. 确认后台采样的必要性和成本。
3. 确认 14 天 SQLite 存储可行。
4. 确认首版可以不用 root、helper 和新增 TCC 权限。

## 4. 范围内事项

- macOS 27.0.1。
- Apple Silicon 笔记本。
- 公开接口。
- 只读探针。
- 合成 14 天样本。
- 1 小时真实后台采样。
- 10 天合成报告。
- HTML 和 SwiftUI 报告界面。

## 5. 范围外事项

- Intel Mac。
- 台式机。
- 独立 GPU。
- App Sandbox。
- 电池续航对照。
- agent 主动触发的系统睡眠和重启。

## 6. 当前事实

| 项目 | 值 |
| --- | --- |
| 机器 | `MacBookPro18,2` |
| 芯片 | `Apple M1 Max` |
| 内存 | 64 GiB |
| 系统 | macOS 27.0.1，26A434 |
| 连续运行 | 10 天 18 小时 |
| 用户权限 | 管理员 |
| 沙盒 | 未发现 app-sandbox entitlement |

## 7. 成功标准

1. 能证明统一日志至少覆盖 10 天的一部分。
2. 能证明连续性能指标需要应用采样。
3. 能正确处理 `powermetrics` 的 root 限制。
4. 30 秒采样摊薄后的读取器 CPU 低于 0.1%。
5. 14 天样本数据库低于 64 MiB。
6. 小时聚合查询不超过 1 秒。
7. 探针不读取用户内容，不留下临时文件。

## 8. 前置条件

1. 只读系统接口。
2. 不安装软件。
3. 不修改系统设置。
4. 不请求 root。
5. SQLite 测试只使用合成数据。

## 9. 风险

| 风险 | 控制 |
| --- | --- |
| 日志含隐私 | 只统计时间和条目数量，不保存正文 |
| `pmset` 输出很长 | 只观察起始时间，及时停止 |
| 循环读取抬高 CPU | 测量后立即停止 |
| 合成数据库占空间 | 测试后删除 |
| 采样成本受系统负载影响 | 记录为有限条件下的测量 |

## 10. 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | 统一日志、电源日志和诊断报告覆盖 | 已完成 | [Case 1](case-macos-log-retention.md) |
| V02 | 现有读取器单次与摊薄 CPU 成本 | 已完成 | [Case 2](case-sampler-cost.md) |
| V03 | 14 天 SQLite 容量与查询 | 已完成 | [Case 3](case-sqlite-capacity.md) |
| V04 | 1 小时真实后台采样 | 已完成 | [Case 4](case-macos-performance-history-soak.md) |
| V05 | 10 天合成报告与缺口表达 | 已完成 | [Case 4](case-macos-performance-history-soak.md) |
| V06 | 真实 10 天覆盖 | 未执行（用户取消） | [Case 4](case-macos-performance-history-soak.md) |
| V07 | Intel 与台式机矩阵 | 待执行 | 找到设备后补 |
| V08 | 低电量模式耗电 | 未执行 | 需要电池供电环境 |
| V09 | 睡眠、暗唤醒、完整唤醒和重启状态机 | 已完成 | [Case 4](case-macos-performance-history-soak.md) |
| V10 | HTML、浏览器和 SwiftUI 报告界面 | 已完成 | [Case 4](case-macos-performance-history-soak.md) |

## 11. 证据要求

1. 每个测试记录时间、命令、环境和结果。
2. 日志测试只记录时间和数量。
3. 成本测试记录迭代数、墙钟时间和 CPU 时间。
4. SQLite 测试记录行数、文件字节和查询时间。
5. 失败测试保留错误码和限制。

## 12. 清理步骤

1. 删除临时 SQLite 数据库与 WAL。
2. 删除临时 Swift 源文件和可执行文件。
3. 确认没有修改系统设置。
4. 确认没有保存原始隐私日志。
5. 确认临时目录为空。

合成报告和 1 小时结果已保存到 Covio 项目证据目录。
真实 10 天 soak 已停止并被用户取消。
部分 soak 运行目录已清理。
Scratch 内的临时截图和 Preview 副本已清理。

## 13. 关联文档

- [前因与问题边界](../context.md)
- [调研与方案矩阵](../investigation.md)
- [结论与限制](../conclusion.md)
- [推荐架构与实施计划](../solution.md)
- [证据](../evidence.md)
