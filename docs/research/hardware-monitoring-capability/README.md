# 硬件信息监听能力研究

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.1` |
| 状态 | 第一版已落地 |
| 日期 | `2026-10-19` |
| 适用对象 | Covio 产品、研发、测试和安全人员 |
| 当前验证环境 | MacBookPro18,2，Apple M1 Max，macOS 27.0.1 |
| 当前结论 | macOS 多数指标可无 root 读取。CPU 频率与整机功耗的来源待验证。 |
| 验证状态 | 第一版自动测试与真机截图通过，见 [验证计划](validation/README.md) |

本文回答一个问题：Covio 在工作台的监控页上能读到哪些硬件信息，每项信息的来源是什么。

本文覆盖 macOS 与 Windows。macOS 写到接口级。Windows 只列骨架，不展开。

## 前因

工作台的「设备」页替换成「监控」页。页面要显示硬件指标。
指标清单和数据源必须先定，页面才知道读什么。
前因、边界和成功标准见 [context.md](context.md)。
本机环境事实见 [evidence.md](evidence.md)。

## 背景

操作系统不提供统一的硬件遥测接口。
每类指标走不同的路径：Mach 调用、sysctl、IOKit 服务、系统框架和私有接口。
不同路径的权限要求不同。私有接口还有上架限制。
调研方法与来源见 [investigation.md](investigation.md)。
参考实现的源码分析见 [investigation.md](investigation.md) 第 7 节。
环境事实见 [evidence.md](evidence.md)。

## 过程

调研分三步。

1. 读 macOS SDK，确认哪些接口是公开的。
2. 读参考实现 `exelban/stats` 的源码，得到模块到接口的映射。
3. 在本机跑只读探针，核对每项指标能不能读到。

方法与来源范围见 [investigation.md](investigation.md)。
命令与输出见 [evidence.md](evidence.md)。
执行记录见 [案例](validation/case-macos-hardware-probe.md)。

## 结果

macOS 的能力分三档。

| 档 | 内容 | 权限 |
| --- | --- | --- |
| 直接可读 | CPU 使用率、内存、磁盘容量与吞吐、网络吞吐、电池、合盖、热状态 | 无 |
| 需要授权 | Wi-Fi 名称与 BSSID、蓝牙设备电量 | 位置服务或蓝牙授权 |
| 需要私有接口或未验证 | CPU 频率、整机功耗、温度传感器、风扇转速 | 未定 |

结论、决策表和未决项见 [conclusion.md](conclusion.md)。
每项结论的证据见 [evidence.md](evidence.md)。

## 预期

监控页按指标分组显示。数据源分四层，逐层降级。
第一版只做「直接可读」档。其余档留接口，不实现。
推荐分层、接口契约和实施计划见 [solution.md](solution.md)。
验收标准和测试矩阵见 [validation/README.md](validation/README.md)。

## 第一版实现

- 指标模型与历史窗口：`macosApp/src/Hub/Monitor/MonitorSnapshot.swift`
- 公开接口读取器：`macosApp/src/Hub/Monitor/MacMonitorReader.swift`
- Stats 风格页面：`macosApp/src/Hub/Monitor/MonitorTabView.swift`
- 单元测试：`macosApp/test/MonitorMetricsTests.swift`
- 页面只在可见时采样。接电源时每秒采样，使用电池时每 5 秒采样。
- 第一版使用 Swift 侧读取器，不新增 KMP 端口。跨平台需求出现时再抽取共享模型。

## 实现预期的手段

1. 按 [solution.md](solution.md) 定义指标模型与端口。
2. 按 [validation/README.md](validation/README.md) 的测试矩阵逐项验证。
3. 用 [案例](validation/case-macos-hardware-probe.md) 记录实机结果。
4. 结论变化时回填 [conclusion.md](conclusion.md) 与 [evidence.md](evidence.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题类别、研究问题、范围、系统模型、状态矩阵和成功标准 |
| [investigation.md](investigation.md) | 调研方法、领域模型、能力矩阵、权限模型、参考实现和缺口 |
| [conclusion.md](conclusion.md) | 结论摘要、决策因素、决策表、不采用方案和未决项 |
| [solution.md](solution.md) | 推荐分层、指标模型、接口契约、刷新策略和实施计划 |
| [evidence.md](evidence.md) | 来源等级、环境事实、证据详情和复核方法 |
| [validation/README.md](validation/README.md) | 验证目标、范围、测试矩阵和清理要求 |
| [validation/case-macos-hardware-probe.md](validation/case-macos-hardware-probe.md) | 本机只读探针的执行记录 |

## 证据链

按以下顺序阅读。

```text
context.md 的问题定义
  -> investigation.md 第 5 节的能力矩阵
  -> evidence.md 的 E-01 至 E-19
  -> conclusion.md 的决策表
  -> solution.md 的分层与契约
  -> validation/README.md 的 V01 至 V09
```

## 更新规则

1. 实机结果回填到案例文件，并更新 [validation/README.md](validation/README.md) 的状态。
2. 结论变化时更新 [conclusion.md](conclusion.md)。
3. 证据变化时更新 [evidence.md](evidence.md)。
4. Windows 部分展开时，在 [investigation.md](investigation.md) 第 9 节补内容。
5. 监控页落地后，把实施结果写回 [solution.md](solution.md)。
