# 推荐方案

## 1. 方案边界

本文推荐 `40%` 到 `100%` 的混合路径。
`80%` 到 `100%` 使用原生 MCL。
`40%` 到 `79%` 使用 root `CFPreferences` 与 Darwin 通知。
本文不批准写入 SMC。
本文不批准 root 策略重载。

## 2. 路径选择

| 条件 | 路径 |
| --- | --- |
| MCL 支持，目标不低于 `80%` | 原生 MCL |
| MCL 支持，目标低于 `80%` | root `CFPreferences` 与 Darwin 通知 |
| MCL 不支持，旧 SMC 键可用 | 单独评估 SMC |
| MCL 不支持，旧 SMC 键不可用 | 显示不支持 |
| 无电池 | 隐藏入口 |

## 3. 能力检测

只读步骤：

1. 加载 `PowerUI.framework`。
2. 取得 `PowerUISmartChargeClient`。
3. 调用 `isMCLSupported`。
4. 调用 `isMCLCurrentlyEnabled:error:`。
5. 调用 `getMCLLimitWithError:`。
6. 调用 `availableChargeLimitsWithError:`。
7. 读取 `pmset -g battlimit`。
8. 读取 IOPS 和电池功率。

检测失败时关闭功能。
检测失败时不保留旧的“已生效”状态。

## 4. 写入流程

写入前必须取得用户批准。

1. 保存原 MCL 开关和上限。
2. 写入 Covio 配置。
3. 目标不低于 `80%` 时调用 `enableMCL:error:` 与 `setMCLLimit:error:`。
4. 目标低于 `80%` 时先保持 MCL 开启，再写入 `enabled=false`、`MCLFeatureState=1` 与 `mclLimitValue`。
5. 目标低于 `80%` 时发送 `com.apple.smartcharging.defaultschanged` Darwin 通知。
6. 等待系统注册策略。
7. 读取 `PowerUI getMCLLimitWithError:` 与 `pmset -g battlimit`。
8. 校验目标值、电池充电状态和功率。
9. PowerUI 接受写入后，保持 `applying` 等待 powerd 确认。
10. 充电时 powerd 可能等待下一次电量 `1%` 步进。
11. `pmset` 与 PowerUI 目标一致后退出等待态。

如果任一步失败，执行恢复流程。

## 5. 恢复流程

1. 读取保存的原 MCL 开关。
2. 读取保存的原 MCL 上限。
3. 恢复原开关。
4. 恢复原上限。
5. 读取 `pmset -g battlimit`。
6. 校验恢复结果。
7. 恢复失败时保留恢复记录并提示用户。
8. 卸载 helper 前调用 `chargeLimitRestore`。
9. 充电状态文件仍存在时，卸载脚本拒绝删除 helper。

禁止删除用户原有系统充电上限。

## 6. 外部变更

用户可能从系统设置修改充电上限。
Covio 每次刷新只读检查原生 MCL。

| 检测结果 | 行为 |
| --- | --- |
| 值与 Covio 一致 | 显示生效 |
| 值不同 | 显示外部变更 |
| 原生开关关闭 | 显示系统策略 |
| 校准进行中 | 显示系统临时接管，不写入 |
| 校准结束且目标匹配临时值 | 恢复用户上限 |
| 校准结束且目标已变化 | 显示外部变更，不覆盖 |
| API 不可用 | 显示不支持 |

Covio 不在用户不知情时反复覆盖系统设置。
用户显式应用上限时，Covio 覆盖当前冲突一次。
后续自动刷新仍按外部变更进入冲突态。
helper 重启时，Covio 按已保存的用户意图恢复目标。
启动恢复不等同于运行期间的静默覆盖。

## 7. 状态显示

电源卡片显示：

1. 当前电量。
2. 设定上限。
3. 当前策略：Covio 或系统。
4. 状态：充电中、已暂停充电、旁路供电、不支持、恢复失败。
5. 旁路的证据值。
6. 不支持或失败原因。

旁路状态不能只依赖颜色。
旁路状态必须同时显示图标和文字。

## 8. 5% 回差

原生 MCL 不接受回差参数。
Covio 状态机实现固定的 `5%` 回差。
电量高于上限时，目标跟随当前电量，避免主动放电。
电量低于回差阈值时，目标回到用户上限。

固件是否严格按目标恢复充电仍需真机确认。
未完成机型矩阵前，不宣称所有设备满足 `5%` 回差。

## 9. 安全

1. 不向第三方发送电池数据。
2. 不记录序列号。
3. 对私有类做运行时形状检查。
4. 调用失败时 fail closed。
5. 不在未授权时执行写入。
6. 写入前保存原始状态。
7. 写入后回读验证。
8. 恢复失败时保留可重试记录。

## 10. 验收计划

1. 无写入的能力检测。
2. 原生 MCL 状态读取。
3. 原状态保存与恢复。
4. `20` 到 `100` 的关键档位。
5. 达到上限后停止充电。
6. `BatteryPower=0` 且 `BypassEngaged`。
7. 系统设置外部修改。
8. 睡眠和唤醒。
9. 重启。
10. 校准周期。
11. 无电池设备。
12. Intel 设备。
13. 卸载和 helper 缺失。
14. `bash scripts/test-all.sh` 通过。

详细矩阵见 [validation/README.md](validation/README.md)。
