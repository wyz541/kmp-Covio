# 触控板多指手势入口验证目录

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 尚未执行 |
| 日期 | `2026-10-13` |
| 目标环境 | MacBook Pro 18,2，Apple M1 Max，macOS 27.0.1（26A434） |
| 问题类别 | 系统保留手势的再获取 |
| 主方案 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 验证记录 | [Case 1](case-macos-trackpad-gesture.md)、[Case 2](case-macos-two-finger-entry.md) |

## 1. 案例索引

| 编号 | 案例 | 状态 | 记录 |
| --- | --- | --- | --- |
| Case 1 | 内建触控板四指下滑采集与标定 | 尚未执行 | [case-macos-trackpad-gesture.md](case-macos-trackpad-gesture.md) |
| Case 2 | 双指下滑工作台入口验证 | 通过 | [case-macos-two-finger-entry.md](case-macos-two-finger-entry.md) |

## 2. 目标

补齐四个本机实验无法回答的问题。

1. 私有路径能否收到四指接触帧。
2. 四指下滑的识别阈值取多少。
3. 私有路径是否需要输入监控权限。
4. 私有路径失效时降级是否正常。
5. 双指下滑能否与普通滚动可靠区分。

## 3. 范围

### 3.1 范围内

- 内建触控板的接触帧采集。
- 四指下滑、三指下滑、两指滚动的区分。
- 双指下滑、双指滚动、上滑和横滑的区分。
- 未授权进程下的私有路径行为。
- 符号缺失时的降级行为。
- 外接触控板的枚举。

### 3.2 范围外

- 挂帘外壳的动效与层级。
- 触发层的协议定义。
- Windows 与 iOS。
- 手势的无障碍替代入口。

## 4. 当前事实

`bash scripts/probe-trackpad-gesture.sh symbols` 显示 17 个符号全部存在。
`bash scripts/probe-trackpad-gesture.sh devices` 显示 1 个内建设备。
`bash scripts/probe-trackpad-gesture.sh accessors` 显示 4 个访问器崩溃。
`bash scripts/probe-trackpad-gesture.sh listen 1` 显示启动成功，帧数为 0。
详见 [evidence.md](../evidence.md)。

## 5. 成功标准

1. `V01` 能收到手指数为 4 的帧。
2. `V02` 四指下滑连续 10 次全部识别，两指滚动与三指滑动零误触发。
3. `V03` 记录四指下滑时系统是否同时触发调度中心。
4. `V04` 符号缺失时应用正常启动，其余入口可用。
5. `V05` 在未授予输入监控权限的进程里，私有路径的行为被记录。
6. `V06` 外接触控板被枚举，并且能注册回调。
7. `V07` 双指下滑初测记录方向和位移。
8. `V08` 双指下滑连续 10 次全部识别。
9. `V09` 普通双指滚动、上滑和横滑零误触发。
10. `V10` 外接触控板不在双指入口验收范围。

## 6. 前置条件

1. 一台带内建触控板的 Apple Silicon Mac。
2. macOS 版本与第 2 节一致，或者记录实际版本。
3. Xcode 已安装，`clang` 可用。
4. 一台外接触控板，用于 `V06`。
5. `V05` 需要一个未授予输入监控权限的进程。用新用户账户或者重置 TCC 后测试。

**警告：** 执行 `V05` 前备份 TCC 数据库。
重置输入监控权限会影响其他应用。
重置后需要重新授权其他应用。

## 7. 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| `VR-01` | 启动触控板设备后未停止 | 探针脚本在退出和信号处理里都调用 `MTDeviceStop` |
| `VR-02` | 采集期间触控板行为异常 | 探针只读接触数据，不注入事件。异常时注销回调。 |
| `VR-03` | 重置 TCC 影响其他应用 | 用新用户账户，不动主账户 |
| `VR-04` | 误触发导致挂帘频繁弹出 | 标定阶段只在探针里跑，不接入应用 |

## 8. 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | 内建触控板四指帧采集 | 待执行 | `case-macos-trackpad-gesture.md` |
| V02 | 识别阈值标定与误触发 | 待执行 | `case-macos-trackpad-gesture.md` |
| V03 | 系统手势并发行为 | 待执行 | `case-macos-trackpad-gesture.md` |
| V04 | 私有符号缺失时的降级 | 待执行 | `case-macos-trackpad-gesture.md` |
| V05 | 未授权进程下的私有路径 | 待执行 | `case-macos-trackpad-gesture.md` |
| V06 | 外接触控板枚举 | 待执行 | `case-macos-trackpad-gesture.md` |
| V07 | 双指下滑方向与位移初测 | 通过 | `case-macos-two-finger-entry.md` |
| V08 | 双指下滑连续 10 次识别 | 通过，应用层 `10/10` | `case-macos-two-finger-entry.md` |
| V09 | 双指滚动、上滑与横滑误触发 | 通过，滚动 `0/10`，上滑与横滑各 `0/1` | `case-macos-two-finger-entry.md` |
| V10 | 外接触控板双指下滑 | 不在范围 | `case-macos-two-finger-entry.md` |

## 9. 证据要求

1. 每个测试记录开始时间、结束时间和命令。
2. `V01` 记录帧数、手指数分布和采样率。
3. `V02` 记录识别次数与误触发次数。
4. `V03` 记录是否同时触发调度中心。
5. `V04` 记录降级后哪些入口可用。
6. `V05` 记录进程的权限状态和私有路径的结果。
7. 不记录设备序列号。
8. 不记录完整的触控轨迹原始日志。只记录统计量。

## 10. 清理步骤

1. 确认探针进程已退出。用 `pgrep -fl probe` 检查。
2. 确认触控板已停止。重跑 `bash scripts/probe-trackpad-gesture.sh devices`，核对“运行中=0”。
3. `V05` 结束后恢复 TCC 权限。
4. `V06` 结束后断开外接触控板。
5. 删除 `V05` 使用的临时用户账户。

## 11. 关联文档

- [主题索引](../README.md)
- [证据附录](../evidence.md)
