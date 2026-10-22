# Case 4：macOS 历史性能采样与报告导出

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | Case 4 |
| 状态 | 通过，真实 10 天 soak 取消 |
| 覆盖测试 | V04 至 V08 |
| 日期 | 2026-10-22 |
| 执行人 | agent |
| 复核人 | 待填写 |

## 2. 验证目标

1. 在真实 macOS 进程中运行后台采样器。
2. 测量应用自身平均 CPU。
3. 验证 10 天合成数据可以生成报告。
4. 验证 HTML 离线、自包含、可读。
5. 验证报告不包含禁止字段。
6. 记录真实 10 天 soak 的取消决定。

## 3. 预检记录

| 项目 | 值 |
| --- | --- |
| 机型 | `MacBookPro18,2` |
| 芯片 | `Apple M1 Max` |
| 内存 | 64 GiB |
| 系统 | macOS 27.0.1，26A434 |
| 电源 | 交流电 |
| 登录项 | 未安装 |
| 权限 | 不请求 root、helper 或新增 TCC 权限 |
| 隔离目录 | `workspace/active/covio-performance-history-soak-279` |

## 4. V04：1 小时后台采样

命令：

```sh
COVIO_MONITOR_HISTORY_SOAK_PATH=<workspace>/active/covio-performance-history-soak-279/one-hour \
COVIO_MONITOR_HISTORY_SOAK_SECONDS=3600 \
COVIO_MONITOR_HISTORY_LANGUAGE=zh-CN \
<Debug Covio executable>
```

状态：通过。

开始时间：`2026-10-22 18:40:54 +0800`。

结束时间：`2026-10-22 19:41:02 +0800`。

结果：

| 项目 | 值 |
| --- | ---: |
| 样本数 | 125 |
| 覆盖率 | 99.926% |
| 已记录时间 | 3,605.126 秒 |
| 未知缺口 | 2.659 秒 |
| 睡眠 | 0 秒 |
| 应用自身平均 CPU | 0.0736% |
| SQLite 总字节 | 2,212,448 bytes |
| Checkpoint 后主库 | 94,208 bytes |
| 最终 HTML | 11,591 bytes |

结论：1 小时后台采样达到 CPU 低于 0.1% 的目标。
覆盖率超过 99.9%。

## 5. V05：10 天合成报告

样本：

| 项目 | 值 |
| --- | ---: |
| 样本数 | 28,800 |
| 采样间隔 | 30 秒 |
| 时间桶 | 2,880 |
| 覆盖率 | 100.0% |
| 阈值时段 | 5 |
| SQLite 数据库 | 6,680,576 bytes |
| HTML | 601,578 bytes |

结论：10 天合成报告可以生成。
HTML 小于 5 MiB。
图表使用内联 SVG。
数据表完整。

状态：通过。

## 6. V06：HTML 自包含与隐私

命令：

```sh
rg -i 'https?://|<link|src=|@import' monitor-report.html
rg -i 'serial|hardware uuid|provisioning udid|bundlepath|ssid|bssid|password|token|secret|/Users/' monitor-report.html
```

结果：

1. 外部 URL、远程资源、脚本和样式导入均为 0。
2. 禁止字段为 0。
3. SQLite schema 没有序列号、SSID、BSSID、路径或进程字段。
4. 监控历史代码没有 `URLSession`、`NWConnection` 或网络框架调用。
5. HTML 有 6 个表、3 个内联 SVG 和 1 个数据表明细。

状态：通过。

## 7. V07：浏览器与报告界面

验证方式：

1. 在 Chrome 打开本地 HTML。
2. 检查标题、系统信息、覆盖摘要、峰值、异常时段和图表。
3. 打开真实的 SwiftUI 报告窗口。
4. 检查日期选择器、刷新、最近 10 天、清除历史和导出按钮。

结果：

1. 本地 HTML 在离线浏览器正常显示。
2. 中文标题和表头正常。
3. 温度显示 `℃`，功率显示 `W`，交换空间显示 `GB`。
4. SwiftUI 报告窗口显示覆盖状态、峰值、异常时段和未采满提示。
5. 日期选择器、按钮和滚动区出现在辅助功能树中。
6. 清除历史按钮会先要求确认。

状态：通过。

## 8. V08：真实 10 天 soak

状态：未执行（用户取消）。

| 项目 | 值 |
| --- | --- |
| 启动时间 | `2026-10-22 19:07:43 +0800` |
| 停止时间 | `2026-10-22 19:56:24 +0800` |
| 原定结束 | `2026-11-01 19:07:43 +0800` |
| 停止前样本 | 104 |
| tmux 会话 | `covio-history-soak-279` |
| 取消原因 | 用户不能接受 10 天等待 |
| 部分运行目录 | 已清理 |

决定：不声称真实 10 天连续运行已完成。
Feature #266 按 1 小时真实采样和 10 天合成报告验收。

## 9. 限制

1. 1 小时验证短于完整 10 天。
2. 真实 10 天连续运行被用户取消。
3. 当前电源为交流电，未执行电池续航对照。
4. 睡眠、暗唤醒、完整唤醒和重启由自动化状态机测试覆盖。
5. 真实物理睡眠和重启没有执行。
6. 10 天真实数据的兼容性仍是已接受风险。

## 10. 清理

1. 合成报告和 1 小时报告保存在项目证据目录。
2. 取消记录保存在项目证据目录。
3. 部分 soak 运行目录已删除。
4. `workspace/scratch` 中的临时产物已删除。
5. 不删除用户的现有历史数据库。

## 11. 证据

- `summary.json`
- `monitor-report.html`
- `Monitor/history.sqlite`
- 真实 SwiftUI 报告窗口已人工复核
- `soak-cancelled.md` 记录真实 10 天 soak 的取消原因和部分样本数
