# 证据

## E-01：自动模式写模式 0

来源：[`Modules/Sensors/popup.swift`](https://github.com/exelban/stats/blob/7d3f70dcd6a07177d0a529a1b907021eef740158/Modules/Sensors/popup.swift#L615-L621)

观察：`Automatic` 回调保存模式并调用 `setFanMode(id, mode: 0)`。
推论：Stats 的自动模式把风扇交还 SMC 和 macOS。
置信度：高。

## E-02：手动模式写模式 1

来源：[`SMC/smc.swift`](https://github.com/exelban/stats/blob/7d3f70dcd6a07177d0a529a1b907021eef740158/SMC/smc.swift#L46-L54)

观察：`FanMode.automatic` 为 `0`，`FanMode.forced` 为 `1`，`auto3` 为 `3`。
观察：`auto3` 和 `automatic` 都属于自动模式。
推论：模式 `3` 是 Apple Silicon 的系统控制值。
置信度：高。

## E-03：自动模式清除目标值

来源：[`SMC/smc.swift`](https://github.com/exelban/stats/blob/7d3f70dcd6a07177d0a529a1b907021eef740158/SMC/smc.swift#L357-L410)

观察：Apple Silicon 自动路径写模式 `0`。
观察：自动路径把 `F%dTg` 写为 `0`。
推论：系统自动模式不保留应用目标转速。
置信度：高。

## E-04：同步滑杆使用百分比

来源：[`Modules/Sensors/popup.swift`](https://github.com/exelban/stats/blob/7d3f70dcd6a07177d0a529a1b907021eef740158/Modules/Sensors/popup.swift#L782-L807)

观察：源风扇先计算相对 `Mn` 和 `Mx` 的百分比。
观察：目标风扇再用自己的范围计算 RPM。
推论：同步控制保持每台风扇的速度位置，不复制绝对 RPM。
置信度：高。

## E-05：同步模式操作

来源：[`Modules/Sensors/popup.swift`](https://github.com/exelban/stats/blob/7d3f70dcd6a07177d0a529a1b907021eef740158/Modules/Sensors/popup.swift#L1060-L1187)

观察：自动、手动、关闭和全速变化都会发送同步事件。
观察：同步事件的处理依赖 `Sensors_fansSync`。
观察：同步事件使用标记 `4`，避免回环。
推论：同步控制不只作用于滑杆，也作用于模式操作。
置信度：高。

## E-06：同步开关默认关闭

来源：[`Modules/Sensors/settings.swift`](https://github.com/exelban/stats/blob/7d3f70dcd6a07177d0a529a1b907021eef740158/Modules/Sensors/settings.swift#L45-L71)

观察：`Sensors_fansSync` 的默认值为 `false`。
推论：Stats 默认保留每台风扇独立控制。
置信度：高。

## E-07：百分比同步来自修复提交

来源：[`f176e494`](https://github.com/exelban/stats/commit/f176e494adfafc4296006c6a7c23f48920e42701)

观察：旧版同步复制绝对 RPM。
观察：修复后同步复制百分比。
推论：绝对 RPM 不能适配不同风扇范围。
置信度：高。

## E-08：同步关闭必须阻止全部同步写入

来源：[`99e0f142`](https://github.com/exelban/stats/commit/99e0f1427ede9c45b1255d905bc47438949e7b2f)

观察：历史缺陷导致同步开关关闭后仍同步。
观察：修复在同步接收端再次检查开关。
推论：同步检查必须同时存在于发送端和接收端逻辑之外。
置信度：高。
