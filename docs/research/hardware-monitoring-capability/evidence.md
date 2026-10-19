# 证据附录

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 审计记录，可复核 |
| 日期 | `2026-10-16` |
| 主文 | [主题索引](README.md) |
| 验证目录 | [验证目录](validation/README.md) |
| 案例 | [本机硬件探针](validation/case-macos-hardware-probe.md) |

## 1. 问题类别和案例映射

问题类别是「系统硬件遥测的能力边界」。

| 案例 | 覆盖的问题 |
| --- | --- |
| [Case 1](validation/case-macos-hardware-probe.md) | macOS 上每项指标能否读到，来源是什么 |

## 2. 来源等级

| 等级 | 来源 | 用途 | 置信度 |
| --- | --- | --- | --- |
| A | 本机 macOS SDK 头文件 | 接口是否公开 | 高 |
| B | `exelban/stats` 源码与仓库实现 | 数据源与权限的实际用法 | 高 |
| C | Apple 官方文档 | 接口语义 | 中 |
| D | 本机只读探针 | 当前环境事实 | 高，范围小 |
| E | 社区讨论 | 线索 | 低 |

## 3. 环境事实

| 项目 | 值 | 命令 | 置信度 |
| --- | --- | --- | --- |
| 机型 | `MacBookPro18,2` | `sysctl -n hw.model` | 高 |
| 芯片 | `Apple M1 Max` | `sysctl -n machdep.cpu.brand_string` | 高 |
| 逻辑核数 | 10 | `sysctl -n hw.ncpu` | 高 |
| 物理核数 | 10 | `sysctl -n hw.physicalcpu` | 高 |
| 内存 | 68719476736 字节 | `sysctl -n hw.memsize` | 高 |
| 系统版本 | macOS 27.0.1，构建 26A434 | `sw_vers` | 高 |
| SDK 路径 | `MacOSX.sdk` | `xcrun --show-sdk-path` | 高 |
| 默认网络接口 | `en0` | `route -n get default` | 高 |
| 电源状态 | 交流电，电量 80%，未充电 | `pmset -g batt` | 高 |
| 内存压力等级 | 1 | `sysctl -n kern.memorystatus_vm_pressure_level` | 高 |

### 3.1 复现命令

```sh
sysctl -n hw.model machdep.cpu.brand_string hw.ncpu hw.physicalcpu hw.logicalcpu hw.memsize
sw_vers
xcrun --show-sdk-path
pmset -g ps
pmset -g batt
pmset -g therm
vm_stat
sysctl -n vm.swapusage kern.memorystatus_vm_pressure_level vm.loadavg
ioreg -r -c AppleSmartBattery -d 1
ioreg -rc IOAccelerator -d 1
ioreg -r -c IOPMrootDomain -d 1
df -h /
netstat -ib
```

## 4. 证据索引

| 编号 | 主题 | 来源 | 结论 | 置信度 |
| --- | --- | --- | --- | --- |
| E-01 | IOReport 不在 SDK | A | 私有接口 | 高 |
| E-02 | mach 头文件与 libproc 在 SDK | A | CPU 与内存可走公开调用 | 高 |
| E-03 | 公开框架存在 | A | 网络、蓝牙、磁盘、显示可用 | 高 |
| E-04 | SDK 无 SMC 头文件 | A | SMC 是私有接口 | 高 |
| E-05 | IOReport 本机不可解析 | D | 频率与功耗不能进第一版 | 高，范围小 |
| E-06 | HID 私有符号可解析 | D | HID 传感器可试 | 高，范围小 |
| E-07 | 电池键无 root 可读 | D | 电池分组可做 | 高 |
| E-08 | 机型与系统 | D | 环境基线 | 高 |
| E-09 | 无 CPU 频率 sysctl 键 | D | 频率只能走私有接口 | 高 |
| E-10 | 内存与交换可读 | D | 内存分组可做 | 高 |
| E-11 | 负载与运行时间可读 | D | CPU 分组补充项 | 高 |
| E-12 | 电源与热状态可读 | D | 电源分组可做 | 高 |
| E-13 | 磁盘容量与吞吐可读 | D | 磁盘分组可做 | 高 |
| E-14 | 网络接口与计数可读 | D | 网络分组可做 | 高 |
| E-15 | GPU 统计键存在，无温度与频率 | D | GPU 部分可做 | 高 |
| E-16 | 合盖状态可读 | D | 系统分组可做 | 高 |
| E-17 | 参考实现的数据源映射 | B | 数据源候选 | 中高 |
| E-18 | 参考实现的能力清单 | C | 模块范围 | 中 |
| E-19 | 仓库已有硬件读取实现 | B | 电池与合盖可复用 | 高 |

## 5. 证据详情

### E-01：IOReport 不在 SDK

来源等级：A
环境：macOS 27.0.1，MacOSX.sdk
命令或来源：`find "$(xcrun --show-sdk-path)" -maxdepth 6 -name "IOReport*"`

观察：无结果。
推论：IOReport 是私有接口，不能在公开 SDK 下链接。
限制：只代表本机 SDK 版本。
置信度：高
关联：E-05

### E-02：mach 头文件与 libproc 在 SDK

来源等级：A
命令或来源：`ls "$(xcrun --show-sdk-path)/usr/include/mach/"`、`ls "$(xcrun --show-sdk-path)/usr/include/" | grep libproc`

观察：`host_info.h`、`processor_info.h`、`task_info.h`、`vm_statistics.h`、`libproc.h` 都在。
推论：CPU 使用率、内存用量与每进程数据可走公开 C API。
限制：头文件存在不等于所有键在所有机型都有值。
置信度：高
关联：E-10、E-11

### E-03：公开框架存在

来源等级：A
命令或来源：`ls -d "$(xcrun --show-sdk-path)/System/Library/Frameworks/"*.framework`

观察：`CoreWLAN`、`IOBluetooth`、`IOKit`、`Metal`、`SystemConfiguration` 都在。
推论：网络、蓝牙、磁盘、显示可走公开框架。
限制：框架存在不等于权限已拿到。
置信度：高
关联：E-14

### E-04：SDK 无 SMC 头文件

来源等级：A
命令或来源：`ls "$(xcrun --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Headers/" | grep -i smc`

观察：无结果。
推论：SMC 只能走私有用户客户端。
限制：`AppleSMC` 是系统自带服务，服务本身可匹配。
置信度：高
关联：E-17

### E-05：IOReport 本机不可解析

来源等级：D
环境：macOS 27.0.1，Apple M1 Max
命令或来源：

```sh
ls -d /System/Library/PrivateFrameworks/IOReport.framework
grep -a -l "IOReportCopyChannelsInGroup" /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*
```

关键输出：

```text
ls: /System/Library/PrivateFrameworks/IOReport.framework: No such file or directory
dyld_shared_cache_arm64e.79.dyldlinkedit
```

观察：磁盘上没有 IOReport 框架。符号存在于 dyld 共享缓存的 linkedit 分片。
用 `dlopen` 按路径与按名字都失败。用 `dlsym(RTLD_DEFAULT, ...)` 也失败。
推论：本机上无法从普通进程取到 IOReport。
反证：符号仍在系统里，说明其他进程或特权路径可能仍可用。参考实现仍在维护。
限制：只代表本机与当前系统版本。不代表所有 macOS 27 机器。
置信度：高，范围小
关联：E-01、E-09

### E-06：HID 私有符号可解析

来源等级：D
命令或来源：Python `ctypes` 调 `dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate")`

观察：符号解析成功。
推论：HID 事件系统的私有接口在本机可用。
限制：只验证了符号解析，没有取数。
置信度：高，范围小
关联：E-17

### E-07：电池键无 root 可读

来源等级：D
命令或来源：`ioreg -r -c AppleSmartBattery -d 1`

关键输出：

```text
"CycleCount" = 82
"MaxCapacity" = 100
"CurrentCapacity" = 80
"Voltage" = 12235
"Amperage" = 0
"IsCharging" = No
"ExternalConnected" = Yes
"BatteryData" = {"FullChargeCapacity"=8360,"DesignCapacity"=8694,...}
```

观察：电池细节在普通用户下可读。
推论：电池分组不需要 root。
限制：键名在 Intel 机型上不同。本机未取温度键。
置信度：高
关联：E-19

### E-08：机型与系统

来源等级：D
命令或来源：`sysctl -n hw.model machdep.cpu.brand_string hw.ncpu hw.physicalcpu hw.logicalcpu hw.memsize`、`sw_vers`

关键输出：

```text
MacBookPro18,2
Apple M1 Max
10 / 10 / 10
68719476736
ProductVersion: 27.0.1  BuildVersion: 26A434
```

观察：逻辑核数等于物理核数，说明没有超线程。
推论：每核使用率的条数等于物理核数。
限制：Intel 机型不同。
置信度：高
关联：E-02

### E-09：无 CPU 频率 sysctl 键

来源等级：D
命令或来源：`sysctl -n hw.cpufrequency_max`

观察：退出码 0，无输出。
推论：Apple Silicon 不通过 sysctl 暴露 CPU 频率。
限制：Intel 机型有该键。
置信度：高
关联：E-05

### E-10：内存与交换可读

来源等级：D
命令或来源：`vm_stat`、`sysctl -n vm.swapusage kern.memorystatus_vm_pressure_level hw.memsize`

关键输出：

```text
page size of 16384 bytes
Pages free: 1112614
Pages active: 1382035
Pages inactive: 1365960
Pages wired down: 207929
total = 0.00M  used = 0.00M  free = 0.00M
1
```

观察：页统计、交换用量与压力等级都可读。
推论：内存分组不需要 root。压力等级 1 表示正常。
限制：本机交换区为 0，未验证非零时的读数。
置信度：高
关联：E-02

### E-11：负载与运行时间可读

来源等级：D
命令或来源：`sysctl -n vm.loadavg`、`uptime`

关键输出：

```text
{ 3.89 3.34 3.55 }
up 4 days, 17:37, 2 users, load averages: 3.89 3.34 3.55
```

观察：负载均值可读。运行时间可从 `uptime` 或 `kern.boottime` 得到。
推论：CPU 分组可加负载与运行时间。
限制：无。
置信度：高
关联：E-02

### E-12：电源与热状态可读

来源等级：D
命令或来源：`pmset -g ps`、`pmset -g batt`、`pmset -g therm`

关键输出：

```text
Now drawing from 'AC Power'
 -InternalBattery-0  80%; AC attached; not charging
Note: No thermal warning level has been recorded
```

观察：电源来源、电量与充电状态可读。热限当前无记录。
推论：电源分组不需要 root。热限只能表示「有没有被限制」。
限制：热限无记录不等于能取到温度。
置信度：高
关联：E-07

### E-13：磁盘容量与吞吐可读

来源等级：D
命令或来源：`df -h /`、`iostat -d -c 2`

关键输出：

```text
/dev/disk3s5s1  926Gi  13Gi  666Gi  2%  /
KB/t  tps  MB/s
34.71   48  1.64
```

观察：容量与吞吐都可读。
推论：磁盘分组不需要 root。进程内实现走 `statfs` 与 `IOBlockStorageDriver`。
限制：`iostat` 是命令行工具，进程内要换接口。
置信度：高
关联：E-03

### E-14：网络接口与计数可读

来源等级：D
命令或来源：`netstat -ib`、`ifconfig en0`、`route -n get default`

关键输出：

```text
lo0  16384 <Link#1>  5106260  0  7991763009  5106260  0  7991763009  0
en0: status: active
interface: en0
```

观察：接口计数与状态可读。默认接口是 `en0`。
推论：网络分组不需要 root。进程内实现走 `getifaddrs` 加 `sysctl NET_RT_IFLIST2`。
限制：Wi-Fi 名称未验证。
置信度：高
关联：E-03

### E-15：GPU 统计键存在，无温度与频率

来源等级：D
命令或来源：`ioreg -rc IOAccelerator -d 1`

关键输出：

```text
+-o AGXAcceleratorG13X
"PerformanceStatistics" = {"Device Utilization %"=0,"Renderer Utilization %"=0,
  "Tiler Utilization %"=0,"Alloc system memory"=2784903168,"In use system memory"=390529024,
  "TiledSceneBytes"=0,"recoveryCount"=0}
"AGCInfo" = {...}
"gpu-core-count" = 24
```

观察：使用率与显存键存在。没有温度、风扇和频率键。
推论：GPU 分组只做使用率与显存。温度在 Apple Silicon 上取不到。
限制：独显机型可能有更多键。
置信度：高
关联：E-17

### E-16：合盖状态可读

来源等级：D
命令或来源：`ioreg -r -c IOPMrootDomain -d 1`

关键输出：

```text
"AppleClamshellState" = No
```

观察：合盖状态可读。
推论：系统分组可加合盖状态。仓库已有实现，见 E-19。
限制：台式机返回 UNKNOWN。
置信度：高
关联：E-19

### E-17：参考实现的数据源映射

来源等级：B
环境：`exelban/stats`，`master` 的 `4ecf4f736056eb488c75aa2fa62e749abd87c4a4`，发布版 `v3.0.21`，MIT 许可

观察：模块到数据源的映射见 [investigation.md](investigation.md) 第 7 节。
读取 SMC 键不需要 root。只有写风扇转速走 XPC 特权 helper。
SMC 键按 SoC 变化。温度传感器键在每个新芯片上都要更新。
推论：温度与风扇可以用 SMC 实现，但要维护键表。
限制：参考实现不是本机事实。版本会变。
置信度：中高
关联：E-04、E-18

### E-18：参考实现的能力清单

来源等级：C
命令或来源：[exelban/stats README](https://github.com/exelban/stats)

观察：模块有十个：Battery、Bluetooth、CPU、Clock、Disk、GPU、Net、RAM、Remote、Sensors。
风扇控制处于遗留状态，不再维护。
Wi-Fi 名称需要位置服务，否则显示 Unknown。
推论：能力清单的边界与本研究的范围一致。
限制：README 不写接口。
置信度：中
关联：E-17

### E-19：仓库已有硬件读取实现

来源等级：B
命令或来源：`macosApp/src/Platform/MacLidSensor.swift`、`MacPowerSource.swift`、`MacSleepWatcher.swift`、`kmpDomain/src/com/wyz/covio/core/PmsetWakeLogParser.kt`

观察：合盖、电源、睡眠断言与唤醒原因已经有实现。
推论：电池与合盖可以直接复用，不重写。
限制：这些实现只覆盖睡眠控制场景，没有指标模型。
置信度：高
关联：E-16

## 6. 逻辑证据链

```text
研究问题：能监听哪些硬件信息，来源是什么
  -> 来源：E-02、E-03、E-07、E-10、E-13、E-14、E-15、E-16
  -> 观察：公开调用与公开框架覆盖 CPU、内存、磁盘、网络、电池、GPU 与合盖
  -> 推论：第一版不需要私有接口，也不需要 root
  -> 来源：E-01、E-04、E-05、E-09
  -> 观察：IOReport 不在 SDK，本机不可解析；SMC 无头文件；无 CPU 频率 sysctl 键
  -> 推论：频率、温度、风扇与整机功耗不能进第一版
  -> 决策：第一版做公开接口档，私有接口档留空
  -> 验证条件：V01 至 V09
  -> 回填位置：solution.md 第 1 节
```

## 7. 反证和限制

1. E-05 只说明本机取不到 IOReport，不说明所有机器取不到。
2. E-15 只有一台 Apple Silicon 机器的数据，独显机型未验证。
3. E-07 没有取到电池温度键，键名待确认。
4. E-12 的热限只能说明「没有被限制」，不能作为温度来源。
5. E-17 与 E-18 是第三方实现，不构成平台保证。
6. 采样开销没有测量。轮询周期来自参考实现的经验值。
7. 本机没有连接蓝牙设备，蓝牙分组的读数未验证。

## 8. 已知缺口

| 缺口 | 影响 | 下一步 |
| --- | --- | --- |
| IOReport 的可用路径 | 频率与功耗无结论 | 开 spike |
| SMC 读取的实际权限 | 温度与风扇无结论 | 案例 V08，需要先有 SMC 读取工具 |
| 环境光与亮度 | 显示分组不全 | 单独调研 |
| Intel 机型 | 兼容性不全 | 找 Intel 机器 |
| 蓝牙设备电量 | 配件分组不全 | 连接设备后验证 |
| 采样开销 | 续航影响未知 | 补一项测试 |
| Windows | 跨平台结论缺失 | 展开 investigation 第 9 节 |

## 9. 复核方法

1. 跑第 3.1 节的命令，核对环境事实。
2. 跑 `ls -d /System/Library/PrivateFrameworks/IOReport.framework`，核对 E-05。
3. 跑 `ioreg -rc IOAccelerator -d 1`，核对 E-15 的键列表。
4. 跑 `ioreg -r -c AppleSmartBattery -d 1`，核对 E-07 的键。
5. 打开参考实现的对应源码文件，核对 E-17 的映射。
6. 环境变化后重跑，并更新本文件与 [conclusion.md](conclusion.md)。

## 参考来源

- [exelban/stats](https://github.com/exelban/stats)
- [exelban/stats README](https://github.com/exelban/stats/blob/master/README.md)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)

## 10. 关联文档

- [主题索引](README.md)
- [前因与问题边界](context.md)
- [调研分析](investigation.md)
- [结论与限制](conclusion.md)
- [推荐架构](solution.md)
- [验证目录](validation/README.md)
- [本机硬件探针](validation/case-macos-hardware-probe.md)
