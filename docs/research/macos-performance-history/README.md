# macOS 历史性能与硬件报告研究

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.2` |
| 状态 | 已实现，验收完成（真实 10 天 soak 取消） |
| 日期 | `2026-10-22` |
| 适用对象 | 产品、研发、测试和安全人员 |
| 当前验证环境 | MacBookPro18,2，Apple M1 Max，64 GiB，macOS 27.0.1 |
| 当前结论 | 连续性能历史必须由 Covio 自己采样。系统日志只能补事件。 |

本文回答一个问题：要生成过去 10 天的 macOS 性能和硬件报告，Covio 应保存哪些指标，采样和留存策略是什么？

## 前因

用户连续 10 天高强度使用 Mac。
用户没有关机，也没有断电。
用户要查看这段时间操作系统和硬件的运行情况。

现有实时监控只保存在内存。
现有电源历史最长只有 30 分钟和 24 小时。
因此不能直接生成 10 天报告。

前因、范围、状态矩阵和成功标准见 [context.md](context.md)。

## 背景

macOS 不提供统一的硬件遥测历史接口。
每项指标要走不同的公开接口。
部分事件能从统一日志和诊断报告补读。
连续 CPU、GPU、内存、磁盘、网络和电池时间线必须由应用自己采样。

实时数据源见 [hardware-monitoring-capability](../hardware-monitoring-capability/README.md)。
历史覆盖、采样成本和存储容量见 [investigation.md](investigation.md)。

## 过程

调研按四步进行。

1. 复用现有硬件监听研究。
2. 核对 Apple SDK 和系统手册。
3. 在本机执行只读历史覆盖与成本探针。
4. 分析现有 Covio 监控代码。

方法、来源矩阵、候选方案和源码分析见 [investigation.md](investigation.md)。

## 结果

结论：

1. 连续性能历史必须由 Covio 自己保存。
2. 接电源每 30 秒采样。
3. 使用电池每 60 秒采样。
4. 保留 14 天。
5. 使用 SQLite3。
6. 输出自包含 HTML。
7. 报告明确显示覆盖率、睡眠和缺口。
8. 首版不需要 root、helper 或新增 TCC 权限。

结论、决策表和限制见 [conclusion.md](conclusion.md)。
全部证据见 [evidence.md](evidence.md)。

当前实现与验证：

1. ADR-0015 已合并。
2. SQLite 历史存储已合并。
3. 后台采样器已合并。
4. 报告聚合已合并。
5. HTML 导出和报告界面已合并。
6. 1 小时真实采样覆盖率 99.926%，应用自身平均 CPU 0.0736%。
7. 10 天真实 soak 启动后，用户因等待时间过长决定取消。
8. Soak 于 2026-10-22 19:56:24 停止，已有 104 条部分样本。
9. 验收依据是 1 小时真实采样和 10 天合成报告。
10. 真实 10 天连续运行没有完成，不作为已满足的验证结论。

## 预期

首版在现有 Monitor 页增加报告入口。
采样器在应用运行期间持续记录。
报告读取 SQLite 并生成单文件 HTML。
报告不包含进程、路径、SSID、IP、MAC 或序列号。

推荐架构、存储契约和报告契约见 [solution.md](solution.md)。
验证矩阵见 [validation/README.md](validation/README.md)。

## 实现预期的手段

1. 先写 ADR-0015，固定存储、周期、保留和隐私边界。
2. 按 [solution.md](solution.md) 建立 SQLite 历史存储。
3. 实现后台采样、睡眠、唤醒和 boot session。
4. 实现 5 分钟时间桶、峰值和覆盖率。
5. 实现自包含 HTML 导出。
6. 按 [validation/README.md](validation/README.md) 执行真实设备验证。
7. 结果变化时回填 [evidence.md](evidence.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题定义、范围、系统模型和状态矩阵 |
| [investigation.md](investigation.md) | 数据源矩阵、候选方案、源码分析和缺口 |
| [conclusion.md](conclusion.md) | 结论、决策表、不采用方案和限制 |
| [solution.md](solution.md) | 推荐架构、接口、SQLite 契约和报告契约 |
| [evidence.md](evidence.md) | 来源等级、复现命令、证据和复核方法 |
| [validation/README.md](validation/README.md) | 验证目标、矩阵、风险和清理要求 |

## 证据链

```text
context.md 的问题定义
  -> investigation.md 的数据源矩阵
  -> evidence.md 的 E-01 至 E-24
  -> conclusion.md 的决策表
  -> solution.md 的存储与报告契约
  -> validation/README.md 的 V01 至 V08
```

## 更新规则

1. 真实采样结果写回 [validation/README.md](validation/README.md) 和案例文件。
2. 数据源变化时更新 [evidence.md](evidence.md)。
3. 决策变化时更新 [conclusion.md](conclusion.md) 和 ADR-0015。
4. 存储字段变化时更新 [solution.md](solution.md) 和迁移测试。
5. 报告字段变化时更新契约、测试和示例报告。
