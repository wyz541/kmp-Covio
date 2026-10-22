# Case 2：监控读取成本

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | Case 2 |
| 状态 | 通过，有限制 |
| 覆盖测试 | V02 |
| 日期 | 2026-10-22 |
| 执行人 | agent |
| 复核人 | 待填写 |

## 2. 验证目标

测量现有 `MacMonitorReader` 一次完整读取的 CPU 成本。
用测量结果判断 30 秒和 60 秒后台周期是否可行。

## 3. 前置条件

1. 当前构建为 Release 优化。
2. 使用当前 `MonitorSnapshot`、`MonitorPower` 和 `MacMonitorReader`。
3. 探针在临时目录编译。
4. 读取器只调用公开接口。
5. 预先读取一次，建立 CPU、磁盘和网络计数器基线。

## 4. 测试方法

测试循环：

1. 创建 `MacMonitorReader`。
2. 先读取一次。
3. 开始记录 `getrusage`。
4. 连续读取 20 次。
5. 统计墙钟时间与进程 CPU 时间。
6. 删除临时源文件和可执行文件。

核心代码：

```swift
let reader = MacMonitorReader()
_ = reader.read()
var before = rusage()
getrusage(RUSAGE_SELF, &before)
let wallStart = Date()
for _ in 0..<20 { _ = reader.read() }
let wallSeconds = Date().timeIntervalSince(wallStart)
var after = rusage()
getrusage(RUSAGE_SELF, &after)
```

## 5. 实际结果

```text
iterations=20
wall_seconds=0.545940
cpu_seconds=0.313694
cpu_ms_per_sample=15.685
cpu_percent_during_loop=57.459
```

## 6. 结果解释

57.459% 是连续无间隔循环的占用。
它不是后台采样在正常使用时的占用。

按周期摊薄：

| 周期 | 读取器平均 CPU 占用 |
| --- | ---: |
| 30 秒 | 0.052% |
| 60 秒 | 0.026% |

后台历史采样应跳过下列工作：

1. 进程列表扫描。
2. top app 能耗排名。
3. 应用名称和 bundle path 解析。

因此真实读取成本应更低。

## 7. 结论

30 秒和 60 秒后台周期具备可行性。
不能直接把实时页的 1 秒周期用于后台 10 天采样。

状态：通过，有限制。

## 8. 限制

1. 只测读取器，没有测数据库写入。
2. 没有测计时器唤醒开销。
3. 没有测电池续航。
4. 没有隔离系统负载变化。
5. 没有测低电量模式。

这些限制进入真实后台采样的后续验证。

## 9. 清理

临时 Swift 文件和可执行文件已删除。
没有修改工程文件。
没有修改系统设置。

## 10. 证据

- E-09
- E-10
- E-13
