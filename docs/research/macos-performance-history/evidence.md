# 证据、复现与限制

> 本文件承载来源等级、环境事实、复现命令、证据索引、逻辑链和复核方法。

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 初稿，可评审 |
| 日期 | 2026-10-22 |
| 研究问题 | 过去 10 天的 macOS 性能和硬件报告需要哪些历史数据与采集策略 |
| 执行人 | agent |
| 敏感数据处理 | 不记录用户名、序列号、硬件 UUID、SSID、IP、MAC、文件路径和完整日志正文 |

## 2. 来源等级

| 等级 | 定义 | 示例 |
| --- | --- | --- |
| A | Apple SDK、Apple 手册或官方接口契约 | `OSLog` 头文件、`pmset(1)`、`asl(3)` |
| B | 本机只读实验 | 日志覆盖、采样成本、SQLite 容量 |
| C | 目标产品源码 | `MacMonitorReader.swift`、`MonitorSnapshot.swift` |
| D | 其他源码或二手资料 | 参考实现和外部文章 |

本结论主要使用 A、B、C 级证据。

## 3. 环境事实

| 项目 | 值 | 来源 |
| --- | --- | --- |
| 机型 | `MacBookPro18,2` | `sysctl -n hw.model` |
| 芯片 | `Apple M1 Max` | `sysctl -n machdep.cpu.brand_string` |
| CPU 核数 | 10 个物理核，10 个逻辑核 | `sysctl -n hw.physicalcpu hw.logicalcpu` |
| 内存 | 64 GiB | `sysctl -n hw.memsize` |
| 系统 | macOS 27.0.1，构建 26A434 | `sw_vers` |
| 运行时间 | 10 天 18 小时 3 分 | `uptime` |
| 当前电源 | 交流电，电池 80%，未充电 | `pmset -g ps` |
| 当前热警告 | 没有已记录警告 | `pmset -g therm` |
| 当前用户账户 | 管理员账户 | 当前用户组成员检查 |
| 当前应用沙盒 | 未发现 app-sandbox entitlement | 签名与工程检查 |

## 4. 证据索引

| 编号 | 事实 | 等级 | 置信度 |
| --- | --- | --- | --- |
| E-01 | 当前机器覆盖用户描述的 10 天连续运行场景 | B | 高 |
| E-02 | 统一日志在 10 天前窗口内仍有条目 | B | 高 |
| E-03 | 11 天及更早的时间窗口没有返回条目 | B | 中 |
| E-04 | 统一日志会按时间和空间轮转 | A | 高 |
| E-05 | `pmset -g log` 在本机只显示约 7 天 | B | 中 |
| E-06 | 旧电源 ASL 文件在本机覆盖 15 天，但 API 已废弃 | A、B | 高 |
| E-07 | 10 天内存在 128 个诊断报告文件 | B | 高 |
| E-08 | `powermetrics` 要求 root | B | 高 |
| E-09 | 现有读取器覆盖报告所需的主要公开指标 | C | 高 |
| E-10 | 现有监控只在页面可见时采样 | C | 高 |
| E-11 | 现有内存历史只有 60 个点 | C | 高 |
| E-12 | 现有电源历史最长 30 分钟和 24 小时 | C | 高 |
| E-13 | 一次完整监控读取约消耗 15.685 ms CPU | B | 中 |
| E-14 | 14 天、30 秒样本的 SQLite 数据库为 6.36 MiB | B | 高 |
| E-15 | 40,320 条样本的小时聚合查询约 0.02 秒 | B | 高 |
| E-16 | 当前分发形态没有 app-sandbox entitlement | C、B | 中 |
| E-17 | 应用已有登录项能力 | C | 高 |
| E-18 | 热警告接口只提供当前或已记录状态 | A、B | 高 |
| E-19 | `OSLogStore` 要求管理员账户 | A | 高 |
| E-20 | 系统版本、机型和硬件容量可从公开接口取得 | C、B | 高 |
| E-21 | CPU 温度、GPU 温度、风扇和频率缺少稳定公开读取路径 | A、D | 高 |
| E-22 | 当前 boot session 已经运行超过 10 天 | B | 高 |
| E-23 | `pmset -g stats` 只有计数，没有事件时间线 | A、B | 高 |
| E-24 | CPU、GPU、内存、磁盘和网络没有可直接读取的连续系统历史 | C、A | 高 |

## 5. 证据详情

### E-01：当前机器符合 10 天连续运行场景

来源：本机只读命令。

命令：

```sh
sw_vers
sysctl -n hw.model machdep.cpu.brand_string hw.physicalcpu hw.logicalcpu hw.memsize
uptime
sysctl -n kern.boottime
```

观察：

```text
macOS 27.0.1 (26A434)
MacBookPro18,2
Apple M1 Max
10 physical cores, 10 logical cores
64 GiB memory
up 10 days, 18:03
```

推论：本机可以作为用户描述场景的当前案例。
限制：只覆盖 Apple Silicon 笔记本。
置信度：高。

### E-02：统一日志在 10 天前仍有条目

来源：本机 `log show` 只读查询。

命令模板：

```sh
start="$(date -v-10d '+%Y-%m-%d %H:%M:%S')"
end="$(date -v-10d -v+1M '+%Y-%m-%d %H:%M:%S')"
log show --start "$start" --end "$end" --style compact --no-pager --info --debug
```

观察：一个一分钟窗口返回 3 个条目。
最早条目时间为 `2026-10-12 14:32:35 +0800`。

推论：本机统一日志至少能覆盖 10 天范围的一部分。
限制：时间窗口有内容，不等于每一类指标都有日志。
置信度：高。

### E-03：11 天及更早窗口没有返回条目

来源：本机 `log show` 只读查询。

命令模板与 E-02 相同，偏移改为 11、12 和 15 天。

观察：

| 窗口 | 条目数 |
| --- | ---: |
| 11 天前 | 0 |
| 12 天前 | 0 |
| 15 天前 | 0 |

推论：当前日志库很可能在约 10 天附近发生了轮转。
限制：一个一分钟空窗口不能单独证明整个时间范围没有数据。
置信度：中。

### E-04：统一日志会按时间和空间轮转

来源：macOS SDK `OSLog.framework` 的 `Entry.h`。

命令：

```sh
SDK="$(xcrun --show-sdk-path)"
sed -n '1,120p' "$SDK/System/Library/Frameworks/OSLog.framework/Headers/Entry.h"
```

原文要点：日志保存在内存环和持久存储中。
轮转按空间、时间和存储类别处理。
长期类别可以标记 1、3、7、14、30 天提示，但不等于硬保证。

推论：不能把单机 10 天观察写成平台契约。
限制：Apple 没有给出固定保留天数。
置信度：高。

### E-05：`pmset -g log` 在本机只显示约 7 天

来源：`pmset(1)` 与本机只读输出。

命令：

```sh
pmset -g log
```

观察：在 `2026-10-22 14:31 +0800` 运行时，第一条带时间记录为 `2026-10-15 14:28:13 +0800`。
命令读取完整输出耗时较长，观察后中止了后续输出。

推论：`pmset -g log` 的直接视图中，本机可用范围小于 10 天。
限制：输出格式和保留范围不是公开稳定契约。
置信度：中。

### E-06：旧 ASL 电源文件覆盖 15 天，但 API 已废弃

来源：本机文件元数据与 Apple `asl(3)` 手册。

命令：

```sh
ls -1 /var/log/powermanagement/*.asl
du -sh /var/log/powermanagement
```

观察：文件从 `2026.10.08.asl` 到 `2026.10.22.asl`，共 15 个日文件，总大小约 577 MiB。
SDK 头文件把 ASL 标为从 macOS 10.12 起废弃，并说明由 `os_log` 替代。

推论：不能用旧 ASL 文件作为首版稳定历史来源。
限制：文件存在不等于可以安全、长期地依赖。
置信度：高。

### E-07：10 天内存在 128 个诊断报告文件

来源：本机诊断报告目录元数据。

命令：

```sh
find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports \
  -maxdepth 1 -type f -print0 2>/dev/null |
  xargs -0 stat -f '%m' |
  awk -v s="$(date -v-10d +%s)" '$1 >= s { n++ } END { print n }'
```

观察：10 天内共有 128 个 `.ips` 或 `.diag` 文件。

推论：诊断文件可以补充崩溃和故障事件数量。
限制：文件名和正文可能包含隐私，报告只使用计数和分类。
置信度：高。

### E-08：`powermetrics` 要求 root

来源：本机命令。

```sh
powermetrics -n 1 -i 1000 -s cpu_power,gpu_power,thermal
```

观察：

```text
powermetrics must be invoked as the superuser
```

推论：`powermetrics` 不满足首版无 root 边界。
限制：它仍可作为后续高级功能。
置信度：高。

### E-09：现有读取器覆盖报告所需的主要公开指标

来源：目标产品源码 `macosApp/src/Hub/Monitor/MacMonitorReader.swift`。

函数和接口：

| 指标 | 接口 |
| --- | --- |
| CPU 总使用率 | `host_statistics` |
| 每核使用率 | `host_processor_info` |
| 内存 | `host_statistics64`、`sysctl` |
| GPU | `IOAccelerator` |
| 磁盘 | `statfs`、`IOBlockStorageDriver` |
| 网络 | `getifaddrs` |
| 电池 | `IOKit.ps`、`AppleSmartBattery` |
| 热状态 | `ProcessInfo.thermalState` |

推论：首版不需要新增数据源类别。
限制：现有读取器包含额外进程扫描，历史模式需要裁剪。
置信度：高。

### E-10：现有监控只在页面可见时采样

来源：`macosApp/src/Hub/Monitor/MonitorTabView.swift`。

观察：`runSamples()` 和 `runPowerSamples()` 由视图的 `.task` 启动。
源码注释明确说页面切换后任务被取消。

推论：现有实现不能提供后台 10 天历史。
限制：没有测量页面快速切换的执行时序。
置信度：高。

### E-11：现有内存历史只有 60 个点

来源：`macosApp/src/Hub/Monitor/MonitorSnapshot.swift`。

观察：`MonitorHistory` 默认容量为 60。
它保存 CPU、GPU、内存、磁盘、网络和电池数组，但不持久化。

推论：现有历史只服务页面折线图。
限制：没有单独的时间戳数组。
置信度：高。

### E-12：现有电源历史最长 30 分钟和 24 小时

来源：

1. `macosApp/src/Hub/Monitor/MonitorPower.swift`
2. `kmpDomain/src/com/wyz/covio/core/PowerHistory.kt`

观察：

1. 分钟功耗历史窗口为 30 分钟。
2. 内存事件窗口为 24 小时。
3. 持久化电源事件最长 7 天，最多 200 条。

推论：现有事件层可以作为起点，但不能直接提供 10 天性能报告。
限制：测试没有覆盖真实 7 天事件积累。
置信度：高。

### E-13：一次完整监控读取约消耗 15.685 ms CPU

来源：本机编译只读探针。

方法：编译现有 `MacMonitorReader`、快照和电源模型。
预先读取一次。
连续读取 20 次。
用 `getrusage` 统计进程 CPU 时间。

观察：

```text
iterations=20
wall_seconds=0.545940
cpu_seconds=0.313694
cpu_ms_per_sample=15.685
cpu_percent_during_loop=57.459
```

解释：57.459% 是连续无间隔循环的平均占用，不是后台采样占用。
按 30 秒周期摊薄为 0.052%；按 60 秒周期摊薄为 0.026%。

推论：后台采样周期可以明显低于实时页 1 秒节奏。
限制：没有测数据库写入、后台计时器和电池续航。
置信度：中。

### E-14：14 天、30 秒样本的 SQLite 数据库为 6.36 MiB

来源：本机 SQLite 合成数据测试。

方法：建立严格表，字段覆盖报告指标。
插入 40,320 条模拟样本。
执行 WAL checkpoint。

观察：

```text
rows=40320
db_bytes=6664192
db_mib=6.36
pages=1627
page_size=4096
```

推论：64 MiB 容量上限足够首版 14 天数据。
限制：真实数据包含空值和事件，容量会小幅变化。
置信度：高。

### E-15：40,320 条样本的小时聚合查询约 0.02 秒

来源：E-14 的同一数据库。

命令：

```sh
time sqlite3 history.sqlite \
  "SELECT strftime('%Y-%m-%d %H', sampled_at, 'unixepoch'),
          avg(cpu_usage), max(cpu_usage), count(*)
   FROM metric_samples
   GROUP BY 1;"
```

观察：`real 0.02`、`user 0.01`、`sys 0.00`。

推论：报告生成可以按需聚合，不需要维护另一套预聚合数据库。
限制：测试是合成数据，硬件与磁盘缓存状态未隔离。
置信度：高。

### E-16：当前分发形态没有 app-sandbox entitlement

来源：工程签名配置和源码检查。

观察：

1. 工程目录没有 app-sandbox entitlement。
2. 当前签名配置为 ad-hoc 或本机开发签名。
3. 当前用户属于管理员组。

推论：当前形态下 `OSLogStore` 和诊断报告读取没有已知沙盒阻断。
限制：分发策略改变后必须重新验证。
置信度：中。

### E-17：应用已有登录项能力

来源：`macosApp/src/Platform/MacLoginItem.swift`。

观察：应用可以写用户的 LaunchAgent plist，并通过 `launchctl` 注册或停用。
`LSUIElement` 已开启。

推论：后台持续采样可以复用现有登录项，不需要新特权组件。
限制：用户关闭登录项后，应用退出期间不会采样。
置信度：高。

### E-18：热警告接口只提供当前或已记录状态

来源：`pmset(1)` 与本机 `pmset -g therm`。

观察：

```text
Note: No thermal warning level has been recorded
Note: No performance warning level has been recorded
Note: No CPU power status has been recorded
```

`pmset -g thermlog` 是持续日志，不是历史查询。

推论：热压力时间线必须由 Covio 采样。
限制：`ProcessInfo.thermalState` 只有四档。
置信度：高。

### E-19：`OSLogStore` 要求管理员账户

来源：macOS SDK `OSLog.framework/Headers/Store.h`。

原文要点：访问本地统一日志需要系统许可，调用者必须由管理员账户运行。

观察：本机是管理员账户，`OSLogStore.local()` 成功。
限制：没有在标准用户账户下验证失败路径。

推论：事件补读只能作为可选能力，不能阻塞核心报告。
置信度：高。

### E-20：系统版本、机型和硬件容量可从公开接口取得

来源：`ProcessInfo`、`sysctl`、`system_profiler` 与目标源码。

观察：

1. `sw_vers` 返回版本和构建。
2. `sysctl` 返回机型、芯片、核数和内存。
3. `system_profiler SPStorageDataType` 返回容量、文件系统、SSD 型号和挂载点。

推论：系统段元数据可以保存到 `system_epochs`。
限制：`system_profiler` 要启动子进程，只适合低频调用。
置信度：高。

### E-21：CPU 温度、GPU 温度、风扇和频率缺少稳定公开读取路径

来源：现有硬件监听研究和 Apple SDK 检查。

观察：

1. 公开 CPU 与 GPU 使用率接口可用。
2. CPU 温度、风扇和频率依赖 SMC 或私有接口。
3. Apple Silicon GPU 加速器当前没有稳定温度键。
4. `powermetrics` 可提供更多传感器，但要求 root。

推论：报告不能承诺这些指标。
限制：未来 macOS 可能增加公开接口。
置信度：高。

### E-22：当前 boot session 已经运行超过 10 天

来源：本机只读命令。

```sh
sysctl -n kern.boottime
uptime
```

观察：当前 boot time 为 `2026-10-11 20:24:08 +0800`。
运行时间为 `10 days, 18:03`。

推论：本次研究直接覆盖用户描述的“10 天不断电”场景。
限制：只覆盖 Apple Silicon 笔记本。
置信度：高。

### E-23：`pmset -g stats` 只有计数，没有事件时间线

来源：`pmset(1)` 与本机输出。

观察：

```text
Sleep Count:28904
Dark Wake Count:28898
User Wake Count:322
```

推论：这些计数可以用于摘要，但不能定位某个时间发生了什么。
限制：计数含义由电源管理内部实现决定，未作为稳定契约。
置信度：高。

### E-24：CPU、GPU、内存、磁盘和网络没有可直接读取的连续系统历史

来源：目标源码与 Apple 接口检查。

观察：

1. 现有读取器每个指标只返回当前值或累计计数器。
2. macOS SDK 没有提供这些指标的连续历史查询 API。
3. 统一日志能提供系统事件，但不是这些指标的规律时间序列。

推论：核心报告时间线必须由 Covio 自己采样。
限制：可能存在未公开的系统遥测存储，但不在公开接口和当前权限范围内。
置信度：高。

## 6. 逻辑证据链

```text
E-01 当前环境符合 10 天运行场景
  -> E-22 boot session 覆盖 10 天
  -> E-02 统一日志能补少量事件
  -> E-03 和 E-04 显示日志范围不稳定

E-09 当前读取器能读主要指标
  -> E-10 只在页面可见时采样
  -> E-11 和 E-12 历史容量不足
  -> E-24 系统没有连续指标历史
  -> 必须新增后台采样和持久化

E-13 单次读取成本
  -> 30 秒与 60 秒周期可接受

E-14 和 E-15 SQLite 容量与查询
  -> 14 天持久化可行

E-08 / E-21 温度与功耗边界
  -> 首版不承诺这些指标
```

## 7. 反证和限制

1. E-02 只证明统一日志有一个 10 天前的窗口，不证明每个事件都有日志。
2. E-03 的空窗口不是全局保留边界证明。
3. E-05 的 `pmset` 范围来自调试输出，不是 Apple 的稳定契约。
4. E-06 的旧 ASL 文件存在，不代表应在新产品中解析。
5. E-13 只测读取器，不是完整后台进程成本。
6. E-14 和 E-15 使用合成数据，不是 10 天真实采样。
7. 当前机器没有 Intel 和台式机对照。
8. 当前机器没有独立 GPU。
9. 当前分发不启用 App Sandbox。

## 8. 已知缺口

| 缺口 | 影响 | 后续方法 |
| --- | --- | --- |
| 10 天真实后台采样 | 不能证明长期稳定性 | 实现后做长时验收 |
| 电池续航影响 | 不能证明后台采样没有续航回归 | 30 分钟与 1 小时对照测试 |
| Intel 与台式机 | 设备能力矩阵不完整 | 增加机型验证 |
| App Sandbox | 日志补读可能失败 | 分发决策后复测 |
| 低电量模式 | 唤醒与采样成本未知 | 真机电池模式测试 |
| 统一日志 predicate 稳定性 | 事件补读可能随版本变化 | 固定版本矩阵和降级测试 |

## 9. 复核方法

1. 重跑 E-01、E-02、E-07、E-08、E-13、E-14。
2. 确认环境版本和机型没有变化。
3. 确认日志命令只读。
4. 确认 SQLite 探针使用临时文件并删除。
5. 确认没有记录隐私字段。
6. 用真实采样数据库重跑报告聚合和覆盖测试。

## 10. 参考来源

1. Apple `OSLog.framework` 的 `Store.h` 和 `Entry.h`。
2. Apple `asl(3)` 手册。
3. Apple `pmset(1)` 手册。
4. `macosApp/src/Hub/Monitor/MacMonitorReader.swift`。
5. `macosApp/src/Hub/Monitor/MonitorSnapshot.swift`。
6. `macosApp/src/Hub/Monitor/MonitorPower.swift`。
7. `kmpDomain/src/com/wyz/covio/core/PowerHistory.kt`。
8. `docs/research/hardware-monitoring-capability/`。
9. `docs/research/macos-background-gui-automation/`。

## 11. 关联文档

- [前因与问题边界](context.md)
- [调研与方案矩阵](investigation.md)
- [结论与限制](conclusion.md)
- [推荐架构与实施计划](solution.md)
- [验证矩阵](validation/README.md)
