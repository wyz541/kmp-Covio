# 验证计划

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 部分通过 |
| 日期 | `2026-10-16` |
| 目标环境 | MacBookPro18,2，Apple M1 Max，macOS 27.0.1 |
| 问题类别 | 系统硬件遥测的能力边界 |
| 主方案 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 验证记录 | [Case 1](case-macos-hardware-probe.md) |

## 1. 案例索引

| 编号 | 案例 | 覆盖测试 | 结果文件 |
| --- | --- | --- | --- |
| Case 1 | macOS 本机硬件探针 | V01 至 V09 | [case-macos-hardware-probe.md](case-macos-hardware-probe.md) |
| Case 2 | Stats 风格监控页 | V10 | [case-stats-monitor-dashboard.md](case-stats-monitor-dashboard.md) |

## 2. 验证目标

确认 [investigation.md](../investigation.md) 第 5 节的每项结论在本机成立。
确认哪些结论只有源码证据，没有本机证据。

## 3. 范围内事项

1. 只读探针：`sysctl`、`ioreg`、`pmset`、`vm_stat`、`df`、`netstat`、`iostat`。
2. SDK 头文件清单。
3. IOReport 符号的可解析性。

## 4. 范围外事项

1. 需要 root 的命令。
2. 安装第三方工具。
3. 写操作，例如设置风扇转速。
4. 需要长时间运行的性能测量。
5. Intel 机型与台式机。

## 5. 当前事实

| 项目 | 值 |
| --- | --- |
| 机型 | MacBookPro18,2 |
| 芯片 | Apple M1 Max |
| 系统 | macOS 27.0.1 |
| 电池 | 交流电，电量 80% |
| 外接显示器 | 未接 |
| 蓝牙 HID 设备 | 未连接 |

## 6. 成功标准

1. 每项测试有命令与输出摘要。
2. 结论与输出一致。
3. 取不到数的项目写明原因。
4. 不执行需要 root 的步骤。

## 7. 前置条件

1. 系统处于正常使用状态，未合盖。
2. 探针全部只读。
3. 不安装任何工具。

## 8. 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| VR-01 | 探针改动系统状态 | 全部命令只读 |
| VR-02 | 输出含序列号等敏感信息 | 记录时只保留指标字段，不保留序列号 |
| VR-03 | 结论被当成跨机型保证 | 每条证据标注环境与限制 |

## 9. 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | CPU 核数、负载与运行时间 | 通过 | `case-macos-hardware-probe.md` |
| V02 | 内存、交换与压力 | 通过 | `case-macos-hardware-probe.md` |
| V03 | 磁盘容量与吞吐 | 通过 | `case-macos-hardware-probe.md` |
| V04 | 网络接口、计数与默认路由 | 通过 | `case-macos-hardware-probe.md` |
| V05 | 电池细节键 | 通过 | `case-macos-hardware-probe.md` |
| V06 | GPU 统计键 | 通过 | `case-macos-hardware-probe.md` |
| V07 | 合盖与电源状态 | 通过 | `case-macos-hardware-probe.md` |
| V08 | SMC 温度与风扇 | 阻塞 | `case-macos-hardware-probe.md` |
| V09 | IOReport 符号可解析性 | 通过 | `case-macos-hardware-probe.md` |
| V10 | Stats 风格监控页与真实读数 | 通过 | `case-stats-monitor-dashboard.md` |

V08 阻塞原因：本机没有 SMC 读取工具，安装第三方工具在范围外。

## 10. 证据要求

1. 每项测试记录命令、输出摘要与结论。
2. 失败项记录错误码与原因。
3. 阻塞项记录阻塞条件。
4. 输出里不写序列号。

## 11. 清理步骤

1. 探针不改系统状态，无需回滚。
2. 删除临时输出目录 `/tmp/covio-probe/`。
3. 确认没有后台进程残留。

## 12. 关联文档

- [主题索引](../README.md)
- [前因与问题边界](../context.md)
- [调研分析](../investigation.md)
- [结论与限制](../conclusion.md)
- [证据附录](../evidence.md)
- [本机硬件探针](case-macos-hardware-probe.md)
