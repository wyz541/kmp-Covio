# Case 1：macOS 历史数据覆盖

## 1. 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | Case 1 |
| 状态 | 通过，有限制 |
| 覆盖测试 | V01 |
| 日期 | 2026-10-22 |
| 执行人 | agent |
| 复核人 | 待填写 |

## 2. 验证目标

确认以下几类系统历史在 10 天范围内的可用性：

1. 统一日志。
2. `pmset` 电源日志。
3. 旧 ASL 电源文件。
4. 诊断报告。
5. 热警告。

## 3. 预检记录

| 项目 | 值 |
| --- | --- |
| 机型 | `MacBookPro18,2` |
| 芯片 | `Apple M1 Max` |
| 系统 | macOS 27.0.1，26A434 |
| 连续运行 | 10 天 18 小时 |
| 电源 | 交流电，电池 80%，未充电 |
| 用户权限 | 管理员 |
| 当前热警告 | 无 |

本案例全部只读。
没有保存日志正文。
没有读取用户文件内容。

## 4. V01-1：统一日志 10 天覆盖

前置：无。

命令：

```sh
start="$(date -v-10d '+%Y-%m-%d %H:%M:%S')"
end="$(date -v-10d -v+1M '+%Y-%m-%d %H:%M:%S')"
log show --start "$start" --end "$end" --style compact --no-pager --info --debug \
  | awk '/^[0-9]{4}-/{n++; if(n==1) first=$0; last=$0} END{print n; print first; print last}'
```

预期结果：窗口内能返回至少一个条目。

实际结果：

```text
events=3
2026-10-12 14:32:35.616 I writeconfig...
2026-10-12 14:32:50.102 I writeconfig...
```

结论：统一日志至少覆盖 10 天前的一部分。
限制：只证明该窗口有日志，不证明所有事件都保存。

状态：通过。

## 5. V01-2：更早窗口探测

命令与 V01-1 相同，偏移为 11、12 和 15 天。

实际结果：

| 窗口 | 条目数 |
| --- | ---: |
| 11 天前 | 0 |
| 12 天前 | 0 |
| 15 天前 | 0 |

结论：日志库在 10 天附近发生了轮转的可能性较高。
限制：空窗口不是完整保留边界证明。

状态：通过，有限制。

## 6. V01-3：`pmset` 电源日志

命令：

```sh
pmset -g log
```

实际结果：在 `2026-10-22 14:31 +0800` 运行时，第一条带时间记录为 `2026-10-15 14:28:13 +0800`。
命令完整读取耗时较长，观察后中止。

结论：`pmset -g log` 直接视图在本机小于 10 天。
限制：这是调试接口，Apple 没有承诺固定保留天数。

状态：通过，有限制。

## 7. V01-4：旧 ASL 文件

命令：

```sh
ls -1 /var/log/powermanagement/*.asl
du -sh /var/log/powermanagement
```

实际结果：

```text
2026.10.08.asl
2026.10.22.asl
15 files
577M total
```

结论：物理文件覆盖 15 天。
限制：ASL 从 macOS 10.12 起废弃，首版不解析。

状态：通过，结论为不使用。

## 8. V01-5：诊断报告

命令：

```sh
find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports \
  -maxdepth 1 -type f -print0 2>/dev/null |
  xargs -0 stat -f '%m' |
  awk -v s="$(date -v-10d +%s)" '$1 >= s { n++ } END { print n }'
```

实际结果：128 个文件。

结论：诊断报告能补崩溃和故障事件数量。
限制：报告只使用计数和分类，不保存文件名或正文。

状态：通过。

## 9. V01-6：热警告

命令：

```sh
pmset -g therm
```

实际结果：

```text
Note: No thermal warning level has been recorded
Note: No performance warning level has been recorded
Note: No CPU power status has been recorded
```

结论：该输出是当前或已记录状态，不是完整时间线。
限制：热压力历史必须由 Covio 采样。

状态：通过。

## 10. 总体结论

macOS 历史可以补充事件。
macOS 历史不能提供连续 CPU、GPU、内存、磁盘、网络和电池时间线。
报告主要指标必须由 Covio 自己保存。

## 11. 清理

本案例没有创建文件。
没有修改系统设置。
没有保存原始日志。

## 12. 证据

- E-01
- E-02
- E-03
- E-04
- E-05
- E-06
- E-07
- E-18
- E-19
- E-23
