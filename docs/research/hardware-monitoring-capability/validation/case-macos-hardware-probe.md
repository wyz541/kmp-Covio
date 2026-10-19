# Case 1：macOS 本机硬件探针

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | Case 1 |
| 状态 | 部分通过 |
| 覆盖测试 | V01 至 V09 |
| 日期 | `2026-10-16` |
| 执行人 | agent |
| 复核人 | 待填写 |

探针全部只读。V08 未执行，原因见该节。

## 1. 验证目标

确认 [investigation.md](../investigation.md) 第 5 节的每项结论在本机成立。
确认哪些结论只有源码证据。

## 2. 预检记录

| 项目 | 值 |
| --- | --- |
| 机型 | `MacBookPro18,2` |
| 芯片 | `Apple M1 Max` |
| 系统 | macOS 27.0.1，构建 26A434 |
| 电源 | 交流电，电量 80%，未充电 |
| 合盖 | 否 |
| 蓝牙 HID 设备 | 未连接 |

## 3. 测试前采集

| 项目 | 值 | 命令 |
| --- | --- | --- |
| 负载均值 | 3.89 / 3.34 / 3.55 | `sysctl -n vm.loadavg` |
| 运行时间 | 4 天 17 小时 37 分 | `uptime` |
| 内存压力等级 | 1 | `sysctl -n kern.memorystatus_vm_pressure_level` |
| 交换区 | 0 | `sysctl -n vm.swapusage` |

## 4. V01：CPU 核数、负载与运行时间

前置：无。

命令：

```sh
sysctl -n hw.model machdep.cpu.brand_string hw.ncpu hw.physicalcpu hw.logicalcpu hw.memsize
sysctl -n vm.loadavg
uptime
sysctl -n hw.cpufrequency_max
```

预期结果：核数、负载与运行时间可读。频率键可能不存在。

实际结果：

```text
MacBookPro18,2
Apple M1 Max
10 / 10 / 10 / 68719476736
{ 3.89 3.34 3.55 }
14:01  up 4 days, 17:37, 2 users, load averages: 3.89 3.34 3.55
hw.cpufrequency_max: 退出码 0，无输出
```

结论：核数、负载与运行时间可读。逻辑核数等于物理核数，没有超线程。
`hw.cpufrequency_max` 无输出，与 E-09 一致。

错误码：无。

状态：通过。

## 5. V02：内存、交换与压力

前置：无。

命令：

```sh
vm_stat
sysctl -n vm.swapusage kern.memorystatus_vm_pressure_level hw.memsize
```

预期结果：页统计、交换用量与压力等级可读。

实际结果：

```text
page size of 16384 bytes
Pages free: 1112614
Pages active: 1382035
Pages inactive: 1365960
Pages speculative: 25640
Pages wired down: 207929
Pages purgeable: 39500
total = 0.00M  used = 0.00M  free = 0.00M  (encrypted)
1
```

结论：全部可读。交换区为 0，未验证非零时的读数。

错误码：无。

状态：通过。

## 6. V03：磁盘容量与吞吐

前置：无。

命令：

```sh
df -h /
df -h /System/Volumes/Data
iostat -d -c 2
```

预期结果：容量与吞吐可读。

实际结果：

```text
/dev/disk3s5s1   926Gi   13Gi   666Gi     2%   /
/dev/disk3s1     926Gi  228Gi   666Gi    26%   /System/Volumes/Data
KB/t  tps  MB/s
34.71   48  1.64
```

结论：容量与吞吐可读。`iostat` 是命令行工具，进程内实现要换 `statfs` 与 IOKit 统计。

错误码：无。

状态：通过。

## 7. V04：网络接口、计数与默认路由

前置：无。

命令：

```sh
netstat -ib
ifconfig en0
route -n get default
```

预期结果：接口计数与默认接口可读。

实际结果：

```text
lo0  16384 <Link#1>  5106260  0  7991763009  5106260  0  7991763009  0
en0: status: active
interface: en0
```

结论：接口计数与状态可读，默认接口是 `en0`。
Wi-Fi 名称与信号强度未测，需要应用进程。

错误码：无。

状态：通过。

## 8. V05：电池细节键

前置：无。

命令：

```sh
ioreg -r -c AppleSmartBattery -d 1
```

预期结果：循环次数、容量、电压与充电状态可读，不需要 root。

实际结果：

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

结论：电池细节可读，不需要 root。
顶层没有 `Temperature` 键。温度键名待确认。

错误码：无。

状态：通过。

## 9. V06：GPU 统计键

前置：无。

命令：

```sh
ioreg -rc IOAccelerator -d 1
```

预期结果：使用率与显存键存在。温度与频率键可能不存在。

实际结果：

```text
+-o AGXAcceleratorG13X
"PerformanceStatistics" = {"Device Utilization %"=0,"Renderer Utilization %"=0,
  "Tiler Utilization %"=0,"Alloc system memory"=2784903168,
  "In use system memory"=390529024,"TiledSceneBytes"=0,"recoveryCount"=0,
  "lastRecoveryTime"=0,"SplitSceneCount"=0,"Allocated PB Size"=56229888}
"AGCInfo" = {...}
"gpu-core-count" = 24
```

结论：使用率与显存键存在。
没有 `Temperature(C)`、`Fan Speed(%)`、`Core Clock(MHz)` 键。
Apple Silicon 上取不到 GPU 温度与频率。

错误码：无。

状态：通过。

## 10. V07：合盖与电源状态

前置：无。

命令：

```sh
ioreg -r -c IOPMrootDomain -d 1
pmset -g ps
pmset -g batt
pmset -g therm
```

预期结果：合盖状态、电源来源与热限可读。

实际结果：

```text
"AppleClamshellState" = No
Now drawing from 'AC Power'
 -InternalBattery-0  80%; AC attached; not charging
Note: No thermal warning level has been recorded
Note: No performance warning level has been recorded
```

结论：合盖与电源状态可读。
热限当前无记录，只能说明系统没有被限制，不能作为温度来源。

错误码：无。

状态：通过。

## 11. V08：SMC 温度与风扇

前置：一个能调用 `AppleSMC` 用户客户端的工具。

命令模板：

```sh
# 本机没有 SMC 读取工具。安装第三方工具在范围外。
# 需要自建探针程序，见 investigation.md 第 7 节的 SMC 访问方式。
```

预期结果：能读到温度与风扇转速，且不需要 root。

实际结果：未执行。

错误码：`probe_tool_missing`

结论：本机没有 SMC 读取工具。安装第三方工具在范围外。
SMC 读取是否真的无需 root 只有源码证据，见 E-17。

状态：阻塞。

## 12. V09：IOReport 符号可解析性

前置：无。

命令：

```sh
ls -d /System/Library/PrivateFrameworks/IOReport.framework
grep -a -l "IOReportCopyChannelsInGroup" \
  /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e*
```

对照命令，用来确认搜索方法有效：

```sh
grep -a -l "IOHIDEventSystemClientCreate" \
  /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e.0*
```

预期结果：确认 IOReport 在本机是否可用。

实际结果：

```text
ls: /System/Library/PrivateFrameworks/IOReport.framework: No such file or directory
dyld_shared_cache_arm64e.79.dyldlinkedit
对照：dyld_shared_cache_arm64e.01
```

再用 `dlopen` 与 `dlsym` 复核：

```text
dlopen("/System/Library/PrivateFrameworks/IOReport.framework/IOReport") -> FAILED
dlopen("IOReport") -> FAILED
dlsym(RTLD_DEFAULT, "IOReportCopyChannelsInGroup") -> NOT FOUND
dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate") -> resolved
```

结论：磁盘上没有 IOReport 框架。符号存在于 dyld 共享缓存。
本机从普通进程无法解析。对照符号可解析，说明方法有效。
CPU 频率与整机功耗不能进第一版。

错误码：`symbol_unresolved`

状态：通过。验证目标是确认可用性，结论为不可用。

## 13. 结果汇总

| 测试 | 状态 | 通过项 | 失败项 |
| --- | --- | --- | --- |
| V01 | 通过 | 核数、负载、运行时间 | 频率键不存在，符合预期 |
| V02 | 通过 | 内存、交换、压力 | 无 |
| V03 | 通过 | 容量、吞吐 | 无 |
| V04 | 通过 | 接口、计数、默认路由 | Wi-Fi 名称未测 |
| V05 | 通过 | 循环、容量、电压、充电 | 顶层无温度键 |
| V06 | 通过 | 使用率、显存、核心数 | 无温度与频率键 |
| V07 | 通过 | 合盖、电源、热限 | 热限无记录 |
| V08 | 阻塞 | 无 | 缺 SMC 读取工具 |
| V09 | 通过 | 可用性结论明确 | IOReport 不可用 |

## 14. 清理记录

| 项目 | 值 |
| --- | --- |
| 系统状态改动 | 无 |
| 临时目录 | `/tmp/covio-probe/` |
| 删除的文件 | `cpu-mem.txt`、`gpu.txt`、`net.txt`、`power-disk.txt`、`sensors.txt` |
| 保留的文件 | 目录里还有其他会话的文件，未删除 |
| 后台进程 | 无 |
| 安装的软件 | 无 |

## 15. 更新规则

1. 换机型或换系统版本后重跑，并更新本文件的日期与结果。
2. V08 有工具后补执行，并更新 [validation/README.md](README.md) 的状态。
3. 结果变化时更新 [evidence.md](../evidence.md) 与 [conclusion.md](../conclusion.md)。

## 16. 关联文档

- [主题索引](../README.md)
- [前因与问题边界](../context.md)
- [调研分析](../investigation.md)
- [结论与限制](../conclusion.md)
- [证据附录](../evidence.md)
- [验证计划](README.md)
