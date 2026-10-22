# 案例：MacBookPro18,2 / macOS 27.0.1

## 结果

只读能力检测通过。
未执行任何写入。

## 环境

| 项 | 值 |
| --- | --- |
| 日期 | 2026-10-20 |
| 硬件 | MacBookPro18,2 |
| 架构 | arm64 |
| macOS | 27.0.1 |
| Build | 26A434 |
| SIP | enabled |

序列号未记录。

## 步骤

1. 读取 `sw_vers`、`uname -m` 和 `sysctl hw.model`。
2. 读取 `pmset -g batt`。
3. 读取 `ioreg` 的电池字段。
4. 读取 `pmset -g battlimit`。
5. 通过 Objective-C runtime 读取 `PowerUISmartChargeClient`。
6. 通过 JXA 读取同一客户端。
7. 编译 `smc` 只读探针。
8. 读取候选 SMC 键。

## 观察

| 项 | 结果 |
| --- | --- |
| MCL 支持 | `true` |
| MCL 启用 | `true` |
| MCL 上限 | `80` |
| 可用上限 | `80, 85, 90, 95, 100` |
| 旁路 | `BypassEngaged` |
| AC 接入 | `Yes` |
| 正在充电 | `No` |
| 电池功率 | `0` |
| `CH0B` | `no data` |
| `CH0C` | `no data` |
| `CH0J` | `kIOReturnNotPrivileged` |
| `bfD0` | `kIOReturnNotPrivileged` |

## 结论

本机有可用的原生 MCL。
本机有真实旁路证据。
本机不能用旧 SMC 路径。
本机不能用未授权的新 SMC 键。

## 未执行

1. 未调用 `enableMCL`。
2. 未调用 `setMCLLimit`。
3. 未写 SMC。
4. 未写 root 偏好。
5. 未重启 `powerd`。
6. 未验证睡眠和重启。

## 清理

本案例全部为只读命令。
无临时系统设置。
无清理项。
