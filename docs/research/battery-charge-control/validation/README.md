# 验证计划

## 目标

验证充电上限能力、旁路证据和恢复行为。
所有写入验证必须有独立批准。
每次写入前保存原状态。
每次写入后执行回读。

## 范围

1. 原生 MCL 能力检测。
2. `40%` 到 `79%` 的 root 偏好写入与 powerd 确认。
3. `80%` 到 `100%` 的写入与恢复。
4. 旁路状态证据。
5. 系统设置外部修改。
6. 睡眠、唤醒和重启。
7. Apple 校准周期。
8. Intel 和无电池设备。
9. 私有 API 变化。
10. 特权 helper 失败恢复。

## 矩阵

| 用例 | 环境 | 写入 | 状态 |
| --- | --- | --- | --- |
| V01 只读能力检测 | M1 Max，macOS 27.0.1 | 无 | 通过 |
| V02 读取原生上限 | M1 Max，macOS 27.0.1 | 无 | 通过 |
| V03 读取旁路证据 | M1 Max，macOS 27.0.1 | 无 | 通过 |
| V04 设置 `85%` | Apple Silicon，macOS 27 | MCL | 通过 |
| V05 设置 `100%` | Apple Silicon，macOS 27 | MCL | 待执行 |
| V06 恢复原系统值 `80%` | Apple Silicon，macOS 27 | MCL | 通过 |
| V07 系统设置外部修改 | Apple Silicon，macOS 27 | MCL | 待执行 |
| V08 睡眠与唤醒 | Apple Silicon，macOS 27 | MCL | 通过 |
| V09 重启恢复 | Apple Silicon，macOS 27 | MCL | 待执行 |
| V10 校准周期 | Apple Silicon，macOS 27 | MCL | 部分通过 |
| V11 设置 `70%` | Apple Silicon，macOS 27 | root 私有 | 部分通过 |
| V11b `40%`、`45%`、`50%`、`65%`、`75%` | Apple Silicon，macOS 27 | root 私有 | 待执行 |
| V12 Intel 原生 MCL | Intel MacBook | 无写入能力检测 | 待执行 |
| V13 Intel `BCLM` | Intel MacBook | SMC | 未批准 |
| V14 无电池设备 | Mac desktop | 无 | 待执行 |
| V15 helper 缺失 | Apple Silicon | 无 | 待执行 |
| V16 API 形状变化 | 模拟 | 无 | 待执行 |
| V17 卸载前恢复 | Apple Silicon | MCL | 部分通过 |
| V18 校准后恢复 | Apple Silicon | MCL | 部分通过 |

### 2026-10-22 状态说明

1. V04、V06 和 V08 的证据记录在 issue #162。
2. V10 和 V18 已有状态机测试。真实 Apple 校准周期尚未执行。
3. V11 的早期记录观察到 `70%` 注册；2026-10-22 复测仍待下一次电量 `1%` 步进确认。其他低档位尚未执行。
4. V17 已有恢复顺序和状态文件保护测试。真实卸载尚未执行。
5. `2026-10-22` 真机进入冲突态。显式重新应用仍保持 `80%` 目标。
6. 该问题已补测试：显式应用覆盖一次冲突，自动刷新继续保护外部修改。
7. 新 helper 已验证 `enabled=false`、`MCLFeatureState=1` 与 `mclLimitValue` 写入后的 powerd 回读。
8. PowerUI 写入后 powerd 可能等待下一次电量 `1%` 步进。
9. 状态必须保持 `applying`，不能按 `4` 秒判失败。

V11 真机顺序：

1. 设置 `70%`。
2. 拔掉电源，把电量降到 `65%` 或更低。
3. 接回电源，等待下一次电量 `1%` 步进。
4. 确认 `pmset chargeSocLimitSoc=70`。
5. 确认电量达到 `70%` 后停止充电。
6. 再拔掉电源，把电量降到 `65%`。
7. 接回电源，确认恢复充电。

电量在 `66%` 到 `69%` 且没有充电锁存时，状态机保持当前电量。该结果不计 V11 失败。

## 风险

| 风险 | 影响 | 控制 |
| --- | --- | --- |
| 私有 API 变化 | 功能失效 | 运行时检测、fail closed |
| SMC 错误写入 | 硬件风险 | 不写 SMC |
| root 偏好变化 | 低档位失效或被系统覆盖 | 保存原值、`PowerUI` 与 `pmset` 回读、失败关闭 |
| 恢复失败 | 系统策略残留 | 保存原值、回读、重试 |
| 校准覆盖 | 临时充到 100% | 显示系统接管，不误报 |
| 外部修改 | Covio 值被替换 | 读取并提示，不静默覆盖 |
| helper 安全 | 本地提权 | 不加入不必要的 root 写入 |

## 清理

1. 无写入的 V01 到 V03 不需要清理。
2. MCL 写入测试必须恢复原始开关。
3. MCL 写入测试必须恢复原始上限。
4. root 私有测试必须删除新增策略。
5. root 私有测试必须保留恢复日志。
6. 测试后重新读取 `pmset -g battlimit`。
7. 测试后确认 `ExternalConnected` 和 `IsCharging` 正常。

## 通过标准

1. 目标值与 `pmset -g battlimit` 一致。
2. 达到上限后 `IsCharging=false`。
3. 旁路用例同时满足 `BatteryPower=0`。
4. 恢复后原系统值一致。
5. 失败时功能显示不支持或错误。
6. 没有残留策略。
