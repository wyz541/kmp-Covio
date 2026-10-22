# 推荐架构、接口与实施计划

> 本文件承载推荐方案、存储契约、报告契约、安全边界、失败模式和验收计划。

## 1. 推荐架构

### 1.1 分层

| 层 | 组件 | 职责 |
| --- | --- | --- |
| 采集 | `MonitorHistorySampler` | 后台定时读取，处理睡眠和事件 |
| 读取 | `MacMonitorReader.readHistory()` | 复用公开接口，跳过进程扫描 |
| 存储 | `MonitorHistoryStore` | SQLite 事务、查询、保留与完整性 |
| 聚合 | `MonitorReportBuilder` | 按时间桶聚合，计算峰值和覆盖 |
| 导出 | `MonitorReportExporter` | 生成自包含 HTML |
| 界面 | `MonitorReportView` | 选择范围、显示覆盖、删除与导出 |

### 1.2 数据流

```text
30/60 秒计时器
  -> readHistory()
  -> MonitorHistorySample
  -> SQLite samples
  -> 事件监听
  -> SQLite events 与 gaps
  -> 选择范围
  -> 原始范围查询
  -> 5 分钟时间桶
  -> 自包含 HTML
  -> 保存面板
```

### 1.3 生命周期

1. `AppRuntime.start()` 启动 `MonitorHistorySampler`。
2. 采样器不依赖监控页是否可见。
3. 应用收到睡眠通知时结束当前段。
4. 应用收到唤醒通知时立即补样本。
5. 应用启动时读取 `kern.boottime`，建立或复用 boot session。
6. 应用启动时比较最后样本与当前时间，补记未知缺口。
7. 应用退出时尽力关闭当前段，不写伪造样本。

## 2. 组件职责

### 2.1 `MacMonitorReader.readHistory()`

`readHistory()` 与现有 `read()` 共用读取函数。
它必须跳过下列昂贵或敏感数据。

1. 进程扫描。
2. top app 能耗排名。
3. 应用名称和 bundle path。
4. 文件系统路径。
5. 网络接口名称。

返回的样本只包含报告需要的系统指标。

### 2.2 `MonitorHistorySampler`

职责：

1. 选择 30 秒或 60 秒周期。
2. 串行读取样本。
3. 检测供电和热状态变化。
4. 在变化时立即补样本。
5. 处理睡眠、唤醒和时钟变化。
6. 批量写入 SQLite。
7. 每日执行一次保留清理。
8. 写入失败时保留有界内存队列。

非职责：

1. 不计算报告内容。
2. 不打开网络。
3. 不访问用户文件。
4. 不请求 root。
5. 不保持系统唤醒。

### 2.3 `MonitorHistoryStore`

职责：

1. 创建和迁移数据库。
2. 校验数据库完整性。
3. 写入样本、事件、系统段和缺口。
4. 按范围查询。
5. 执行 14 天和 64 MiB 保留策略。
6. 删除全部历史。

数据库位置由 `AppPaths` 提供：

```text
Application Support/com.wyz.covio/Monitor/history.sqlite
```

不要在仓库文档中写本机展开后的绝对路径。

### 2.4 `MonitorReportBuilder`

职责：

1. 检查请求范围。
2. 读取样本和事件。
3. 生成 5 分钟图表时间桶。
4. 从原始样本计算峰值。
5. 区分睡眠区间和采集缺口。
6. 计算覆盖率。
7. 生成不可得指标清单。
8. 生成报告事实，不生成故障结论。

### 2.5 `MonitorReportExporter`

职责：

1. 生成单文件 HTML。
2. 内联 CSS 和 SVG。
3. 不引用 CDN、远程字体或远程图片。
4. 用系统保存面板写入用户选择的位置。
5. 文件名包含开始和结束日期。

建议文件名：

```text
Covio-Report-YYYYMMDD-HHMM-YYYYMMDD-HHMM.html
```

## 3. 存储契约

### 3.1 SQLite 设置

| 设置 | 值 |
| --- | --- |
| `journal_mode` | `WAL` |
| `synchronous` | `NORMAL` |
| `busy_timeout` | 1000 ms |
| `wal_autocheckpoint` | 1000 pages |
| 页面大小 | 4096 bytes |
| 外键 | 开启 |
| 写入 | 单次采样一个事务，批量样本一个事务 |

### 3.2 表 `samples`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK | 自增 |
| `sampled_at_ms` | INTEGER | UTC 毫秒 |
| `monotonic_ns` | INTEGER | 连续时间，用于识别时钟跳变 |
| `boot_id` | TEXT | boot session |
| `power_source` | TEXT | `ac`、`battery`、`unknown` |
| `thermal_state` | TEXT | `nominal`、`fair`、`serious`、`critical` |
| `cpu_usage` | REAL | 0 到 1 |
| `cpu_load_1` | REAL | 1 分钟负载 |
| `cpu_core_count` | INTEGER | 核数 |
| `gpu_usage` | REAL | 0 到 1 |
| `gpu_memory_bytes` | REAL | 已用显存 |
| `memory_used_bytes` | REAL | 已用内存 |
| `memory_total_bytes` | REAL | 总内存 |
| `memory_pressure` | TEXT | `normal`、`warning`、`critical` |
| `swap_used_bytes` | REAL | 交换空间 |
| `disk_read_bps` | REAL | 读速率 |
| `disk_write_bps` | REAL | 写速率 |
| `disk_used_bytes` | REAL | 已用容量 |
| `disk_free_bytes` | REAL | 可用容量 |
| `network_rx_bps` | REAL | 接收速率 |
| `network_tx_bps` | REAL | 发送速率 |
| `battery_percent` | REAL | 0 到 100 |
| `battery_temp_c` | REAL | 摄氏度 |
| `battery_health_pct` | REAL | 0 到 100 |
| `system_power_w` | REAL | 系统功率，接口可用时 |
| `battery_power_w` | REAL | 电池功率，接口可用时 |
| `display_state` | TEXT | `on`、`off`、`unknown` |
| `lid_state` | TEXT | `open`、`closed`、`unknown` |
| `sample_kind` | TEXT | `periodic`、`event`、`wake` |
| `quality` | TEXT | `complete`、`partial` |

索引：

1. `sampled_at_ms`。
2. `(boot_id, sampled_at_ms)`。

### 3.3 表 `events`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK | 自增 |
| `occurred_at_ms` | INTEGER | UTC 毫秒 |
| `boot_id` | TEXT | boot session |
| `kind` | TEXT | 固定枚举 |
| `detail_code` | TEXT | 固定错误码或原因码 |
| `source` | TEXT | `covio`、`oslog`、`diagnostic_report` |
| `confidence` | TEXT | `observed`、`best_effort` |

事件枚举：

```text
sleep
dark_wake
full_wake
adapter_connected
adapter_disconnected
thermal_fair
thermal_serious
thermal_critical
boot
shutdown_or_crash
app_crash_summary
```

### 3.4 表 `gaps`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK | 自增 |
| `started_at_ms` | INTEGER | 缺口开始 |
| `ended_at_ms` | INTEGER | 缺口结束，未结束为 NULL |
| `boot_id` | TEXT | boot session |
| `reason` | TEXT | `sleep`、`app_stopped`、`reboot`、`clock_change`、`write_failed`、`unknown` |

### 3.5 表 `system_epochs`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `boot_id` | TEXT PK | boot session |
| `started_at_ms` | INTEGER | 启动时间 |
| `os_version` | TEXT | 系统版本 |
| `os_build` | TEXT | 系统构建 |
| `model` | TEXT | 机型标识 |
| `chip` | TEXT | 芯片名称 |
| `memory_bytes` | INTEGER | 内存容量 |
| `disk_total_bytes` | INTEGER | 磁盘总容量 |
| `ssd_model` | TEXT | SSD 型号，可选 |

不保存序列号、硬件 UUID、电池序列号和 MAC 地址。

### 3.6 表 `metadata`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `key` | TEXT PK | `schema_version` 等 |
| `value` | TEXT | 文本值 |

## 4. 采样契约

### 4.1 周期

| 条件 | 周期 |
| --- | --- |
| 接电源 | 30 秒 |
| 使用电池 | 60 秒 |
| 供电变化 | 立即补样本 |
| 热状态变化 | 立即补样本 |
| 完整唤醒 | 立即补样本 |
| 睡眠中 | 不采样 |

### 4.2 时钟和分段

每次样本同时记录：

1. 墙钟 `sampled_at_ms`。
2. 连续时间 `monotonic_ns`。
3. `boot_id`。

如果墙钟变化超过预期周期的 2 倍，记为时钟事件。
如果 `boot_id` 变化，旧段结束，新段开始。
如果两次样本间隔超过 2.5 个预期周期且不是睡眠，记为未知缺口。

### 4.3 保留

1. 每次启动执行一次清理。
2. 每日执行一次清理。
3. 导出前执行一次轻量清理。
4. 删除早于 14 天的样本和事件。
5. 如果数据库超过 64 MiB，从最旧样本开始删除。
6. WAL 超过 16 MiB 时执行 checkpoint。
7. 用户点击“清除历史”时删除全部样本、事件、缺口和系统段。

## 5. 报告契约

### 5.1 输入

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| `start` | Date | 不含 |
| `end` | Date | 含 |
| `maximumDays` | Int | 1 到 14 |
| `bucketSeconds` | Int | 默认 300 |
| `language` | enum | 中文或英文 |

请求范围超过 14 天时拒绝。
开始时间晚于结束时间时拒绝。
没有样本时返回空报告，不生成假时间线。

### 5.2 输出结构

| 区块 | 内容 |
| --- | --- |
| 报告标题 | 时间范围与生成时间 |
| 系统信息 | macOS 版本、机型、芯片、内存、磁盘 |
| 覆盖摘要 | 请求时长、已知睡眠、采集时长、未知缺口 |
| 关键峰值 | CPU、GPU、内存压力、磁盘、网络、电池温度、功率 |
| 时间线 | 5 分钟时间桶的趋势图 |
| 事件时间线 | 睡眠、唤醒、供电、热状态、重启、崩溃摘要 |
| 不可得指标 | 温度、风扇、频率等 |
| 方法说明 | 采样周期、来源、阈值和限制 |

### 5.3 峰值口径

| 指标 | 口径 |
| --- | --- |
| CPU 峰值 | 原始样本的最大 `cpu_usage` |
| GPU 峰值 | 原始样本的最大 `gpu_usage` |
| CPU 持续高负载 | 连续 5 分钟均值大于 80% |
| GPU 持续高负载 | 连续 5 分钟均值大于 80% |
| 内存压力 | warning 或 critical 的持续时间 |
| 磁盘低空间 | 可用空间低于总容量 10% |
| 电池高温 | `battery_temp_c` 大于 45 ℃ |
| 热压力 | fair、serious 或 critical 的持续区间 |

阈值是报告事实规则，不是故障诊断。

### 5.4 HTML 要求

1. 单文件。
2. 内联 CSS。
3. 内联 SVG 图表。
4. 不执行远程请求。
5. 转义所有文本。
6. 支持浅色和深色系统主题。
7. 支持打印。
8. 图表同时提供数据表。
9. 不可得数据写“不可得”，不显示 0。
10. 10 天报告目标小于 5 MiB。

## 6. 界面契约

### 6.1 报告入口

报告入口放在现有 Monitor 页。
不新增顶层页签。

界面元素：

1. 时间范围选择。
2. 数据覆盖摘要。
3. 采样状态与最近样本时间。
4. 导出按钮。
5. 清除历史按钮。
6. 不可得指标说明。

### 6.2 空状态

没有足够样本时显示：

1. 已有样本范围。
2. 缺少的原因。
3. 从现在开始记录需要等待多久。
4. 可以补读的系统事件。

禁止显示“过去 10 天正常”。

## 7. 错误码

| 错误码 | 触发条件 | 可重试 | 处理 |
| --- | --- | --- | --- |
| `history.range_invalid` | 开始时间不合法 | 否 | 提示修改范围 |
| `history.range_too_old` | 超出 14 天 | 否 | 限制到 14 天 |
| `history.empty` | 范围内无样本 | 否 | 显示空状态 |
| `history.open_failed` | 数据库打不开 | 是 | 提示检查磁盘 |
| `history.corrupt` | 完整性检查失败 | 否 | 保留旧文件并新建 |
| `history.write_failed` | 写入失败 | 是 | 重试并使用有界缓冲 |
| `history.prune_failed` | 清理失败 | 是 | 下次启动重试 |
| `report.build_failed` | 聚合失败 | 是 | 保留数据库并显示错误 |
| `report.write_failed` | HTML 写入失败 | 是 | 让用户重选位置 |
| `history.delete_failed` | 删除失败 | 是 | 保留状态并提示 |

## 8. 安全设计

1. 只读系统指标。
2. 不采集用户内容。
3. 不采集窗口标题。
4. 不采集完整进程参数。
5. 不采集 SSID、BSSID、IP 和 MAC。
6. 不采集序列号与硬件 UUID。
7. 日志文本不进入报告。
8. HTML 所有动态文本都要转义。
9. 报告只写用户选择的文件。
10. 报告生成不访问网络。
11. 数据库文件权限限制为当前用户。
12. 用户能查看占用并清除历史。

## 9. 合规设计

1. 使用公开 API。
2. 不使用 `powermetrics`。
3. 不安装特权 helper。
4. 不新增 TCC 权限。
5. 日志读取失败时降级，不阻塞核心报告。
6. 每个数据块显示来源与覆盖限制。
7. 不把相关性写成因果结论。

## 10. 可靠性设计

1. SQLite 事务保证样本成组写入。
2. WAL 降低写入阻塞。
3. 数据库损坏时保留旧文件。
4. 连续时间与墙钟同时记录。
5. 睡眠和重启产生明确分段。
6. 写入队列有上限，超过上限丢弃最旧样本并记录缺口。
7. 采样器不保留系统唤醒。
8. 任务取消后不继续写数据库。
9. 导出先写临时文件，再原子替换目标。
10. 清理与导出互斥，避免读到半清理状态。

## 11. 失败模式

| 失败 | 表现 | 处理 |
| --- | --- | --- |
| 应用退出 | 无样本 | 下次启动补未知缺口 |
| 系统睡眠 | 无样本 | 记录睡眠区间 |
| 重启 | boot session 变化 | 分段显示 |
| 时钟回退 | 时间重叠 | 使用连续时间标记 |
| 磁盘满 | 写数据库失败 | 停止落盘并显示错误 |
| 数据库损坏 | 打开失败 | 保留旧文件并新建 |
| 日志不可读 | 事件补读失败 | 核心报告继续 |
| 日志格式变化 | predicate 无结果 | 标记事件不可得 |
| 指标消失 | 字段为空 | 显示不可得 |
| HTML 写失败 | 没有输出文件 | 显示目标错误 |

## 12. 验收标准

1. 30 秒和 60 秒后台采样可运行。
2. 接电源、电池和状态事件都有样本。
3. 睡眠不产生假样本。
4. 唤醒后立即补样本。
5. 重启后出现新 boot session。
6. 14 天以外的数据会被删除。
7. 数据库超过 64 MiB 时会从最旧数据开始删除。
8. 10 天合成数据可以生成报告。
9. 报告显示覆盖率和未知缺口。
10. 报告区分睡眠区间和采集缺口。
11. 不可得指标显示为空，不显示 0。
12. 报告不包含进程、路径、SSID、IP、MAC 和序列号。
13. 报告生成无网络请求。
14. 导出文件可以在离线浏览器打开。
15. 报告数据表可读，图表有文本替代。
16. 后台采样器自身平均 CPU 低于 0.1%。
17. `bash scripts/test-all.sh` 通过。
18. 真机运行至少 1 小时，并在后续 10 天长时验收中保持预期覆盖。

## 13. 实施计划

| 阶段 | 交付 | 依赖 |
| --- | --- | --- |
| 1 | ADR-0015 记录存储、周期、保留和隐私边界 | 本研究 |
| 2 | SQLite 历史存储和迁移 | 阶段 1 |
| 3 | 后台采样器、睡眠与 boot session | 阶段 2 |
| 4 | 报告聚合、覆盖率和峰值 | 阶段 2、3 |
| 5 | 自包含 HTML 导出和报告界面 | 阶段 4 |
| 6 | 系统事件补读和崩溃摘要 | 阶段 3 |
| 7 | 真机长时与机型矩阵验收 | 阶段 3 到 6 |

每个阶段一条分支，一个 PR。
阶段 2 到 6 的单个交付应控制在 1 到 3 个工作日。

## 14. 回滚条件

出现下列任一情况时回滚后台采样。

1. 采样器自身平均 CPU 持续超过 0.1%。
2. 正常使用下电池续航下降超过 2%。
3. 数据库增长超过容量上限。
4. 数据写入导致主线程卡顿。
5. 睡眠或唤醒后出现重复样本风暴。
6. 报告泄露禁止字段。
7. 报告生成发出网络请求。
8. 数据库损坏后无法保留旧文件。

回滚后保留手动导出入口，停止后台采样。
已有数据库保留，等待修复或用户删除。

## 15. 产品化条件

1. 10 天报告的核心数据来自真实采样。
2. 覆盖率和缺口对用户清楚。
3. 14 天容量在真机稳定。
4. 睡眠、重启和时钟变化通过验证。
5. Intel 与 Apple Silicon 的差异已知。
6. 台式机没有电池时报告仍可生成。
7. 不新增 root、helper 或 TCC 权限。
8. 导出 HTML 通过离线、打印和无障碍检查。
