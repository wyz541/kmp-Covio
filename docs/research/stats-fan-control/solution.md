# 方案

## 1. 模式模型

`MonitorFanMode` 包含 `automatic`、`curve` 和 `manual`。

| 模式 | UI 行为 | helper 行为 |
| --- | --- | --- |
| `automatic` | 恢复系统控制 | 不持有风扇 |
| `curve` | 显示曲线编辑器 | 持有风扇并写入曲线目标 |
| `manual` | 显示转速滑杆 | 持有风扇并写入手动目标 |

现有配置的 `enabled + automatic` 迁移为 `enabled + curve`。
关闭控制后保存为 `automatic`。

## 2. 曲线模式

全部风扇视图继续把同一曲线写入全部风扇。
单风扇视图只修改目标风扇。
曲线目标限制在每台风扇自己的范围。

## 3. 手动同步

新增持久化字段 `syncFans`，默认 `false`。
新增每风扇 `manualModes` 映射。
手动模式的风扇持有风扇并写入目标转速。
自动模式的风扇释放原模式。
手动滑杆等待 `300 ms` 后提交。
同步开启时，源风扇的 RPM 先换算为范围比例。
目标风扇再按自己的范围生成 RPM。
同步开启时，自动和手动模式变化也应用到全部风扇。
同步关闭时，滑杆只修改当前风扇。

## 4. Helper 安全

helper 收到 `automatic` 配置时直接恢复系统控制。
helper 只对 `curve` 和 `manual` 启动控制循环。
恢复动作写回原模式并清理租约。

## 5. 验收

- 自动模式不写目标转速。
- 曲线和手动模式保留硬件范围限制。
- 同步控制按百分比生成目标值。
- 每台风扇可以独立选择自动或手动。
- 连续滑杆变化只提交最后一个值。
- 同步配置可以持久化。
- 现有配置可以迁移。
- UI 亮色和深色截图齐全。

## 6. 实现映射

| 职责 | 文件 | 来源 |
| --- | --- | --- |
| SMC 设备读写 | `macosApp/src/Platform/SMC/SMCAccess.swift` | MacFanControl，MIT |
| 风扇模式、目标转速和 reset | `macosApp/src/Platform/SMC/StatsFanControl.swift` | Stats `7d3f70d`，MIT |
| 每风扇模式与同步设置 | `macosApp/src/Hub/Monitor/Fan/MonitorFanModels.swift` | Stats 行为，Covio 实现 |
| 睡眠保存与唤醒恢复 | `macosApp/src/Hub/Monitor/Fan/FanControlSleepPolicy.swift` | Stats 行为，Covio app |
| 曲线与租约 | `macosApp/src/Hub/Monitor/Fan/FanControlRuntime.swift` | Covio 扩展 |

`SMCAccess` 只负责与 AppleSMC 通信。
风扇控制语义由 Stats 移植层负责。
曲线和 helper 租约位于 Stats 核心之上，不改变自动、手动和 reset 语义。
