# ADR-0007：用持久化意图与租约统一电源 Engine

- Status：accepted
- Kind：architecture
- Date：2026-10-20
- Supersedes：none
- Implements：#148
- 相关：#145、#119、#135、#140

## 背景

Covio 已有电池、合盖、空闲睡眠和唤醒日志能力。
这些能力由 `Engine`、平台端口、特权 helper 和设置页共同承担。

当前实现存在四个结构问题：

1. 用户意图、系统状态和运行时动作混在同一个可变状态里。
2. 手动、定时和自动规则没有统一的租约模型。
3. helper 没有租约和所有权标记。
4. UI 无法稳定区分请求状态和真实系统状态。

调研结论见 #145。
合盖路径继续遵守 ADR-0006。
充电上限另由 #140 处理。

## 决策

1. `PowerConfig` 保存用户意图、阈值、规则和可选会话到期时间。
2. `PowerSnapshot` 保存一次求值所需的系统观察值。
3. 所有保持唤醒来源都创建运行时 `HoldLease`。
4. `HoldLease` 不跨进程持久化。
5. 电源策略由纯函数求值。纯函数不执行 I/O。
6. 决策优先级固定为：安全否决、显式关闭或暂停、活动租约、自动规则、允许睡眠。
7. 系统空闲保持唤醒使用 `PreventUserIdleSystemSleep`。
8. 屏幕保持唤醒使用 `PreventUserIdleDisplaySleep`。
9. 合盖保持唤醒使用 ADR-0006 保留的特权 helper。
10. helper 协议升级为租约模式。应用每 15 秒续租，租约 60 秒过期。
11. helper 保存所有权 marker。只清除 Covio 自己设置的 `SleepDisabled`。
12. 外部存在 `SleepDisabled` 且没有 Covio marker 时，Covio 显示冲突，不自动清除。
13. 安全否决高于用户强制模式。热危险和低电量必须释放全部租约。
14. 外接显示器在线时，不申请特权合盖保持唤醒。
15. 执行器完成动作后回读真实系统状态。
16. UI 显示真实状态，不显示请求状态。
17. 状态无法验证时，执行器释放保持唤醒并允许睡眠。
18. Power 管理面复用 `Monitor` 页签，不新增第七个页签。
19. 电源历史使用独立、有界、原子写入的本地文件。
20. 首版不接入内建屏亮度、外接屏 DDC、锁屏和屏保私有接口。

## 后果

### 正面

- 用户意图、系统状态和运行时动作有明确边界。
- 多个保持唤醒来源可以并存和独立结束。
- 策略可以脱离 macOS 运行单元测试。
- helper 崩溃恢复有明确上限。
- 外部工具的状态不会被误清。
- UI 可以解释当前保持唤醒的原因。
- 后续接入 agent、定时任务或系统任务时不需要重写 Engine。

### 负面

- 需要重构现有 `Engine`。
- 需要升级 helper 协议和安装版本。
- 需要新增多个状态快照和租约测试。
- 需要维护一份有界事件历史。
- 首版代码量和测试量都会增加。

### 风险

- helper 升级期间可能出现旧客户端和新服务端不匹配。缓解：保留版本校验，并拒绝不兼容请求。
- `disablesleep` 是持久系统状态。缓解：租约、所有权 marker、启动恢复和卸载清理共同保护。
- 应用被 `SIGKILL` 时无法执行正常退出。缓解：helper 租约到期后清除特权状态。
- 外部工具可能反复改写系统设置。缓解：回读实际值，限制纠错频率，并显示冲突。
- 部分热状态无法稳定注入。缓解：先覆盖可观察状态，损坏性条件进入真机验证矩阵。
- App Store 对现有 helper 的限制仍未确认。缓解：不把 App Store 交付作为本 ADR 的已满足条件。

## 备选方案

### 备选 1：保留当前分散策略

继续在 `Engine` 中使用多个布尔和条件分支。

未采纳的原因：手动、定时和自动规则无法组合。
状态所有权和故障恢复也无法可靠表达。

### 备选 2：启动 `caffeinate` 子进程

由子进程持有系统断言，并绑定 Covio 生命周期。

未采纳的原因：不能阻止合盖睡眠。
进程状态和断言原因也不如直接 IOKit 调用清楚。

### 备选 3：使用 sudoers 直接运行 `pmset`

应用直接执行固定 `sudo pmset` 规则。

未采纳的原因：ADR-0006 已决定保留独立 helper。
新增 sudoers 会增加第二套特权边界。

### 备选 4：保留 helper 但只做启动清理

应用退出和下次启动时清理 `SleepDisabled`。

未采纳的原因：应用崩溃后到下次启动之间，系统可能持续禁止睡眠。
这不能满足 fail-safe 目标。

### 备选 5：使用 `SMAppService.daemon`

把 helper 改成系统托管的 LaunchDaemon。

未采纳的原因：ADR-0006 已记录当前签名和公证条件不满足。
这个方案也不减少卸载时清除系统状态所需的权限。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| helper 协议 v2 的具体 JSON 字段 | pending | 在 #148 的 helper sub-issue 中定稿 |
| 安全护栏默认值 | pending | 产品评审后写入 `PowerConfig` |
| 低电量回差默认值 | pending | 真机耗电验证后确认 |
| 合盖时长默认上限 | pending | 热状态和真机验证后确认 |
| App Store 可行性 | pending | 取得 Developer ID 后单独验证 |
| Intel Mac 支持 | pending | 独立验证矩阵 |

## 参考

- [#145 电源 Engine 系统调研](https://github.com/wyz541/kmp-Covio/issues/145)
- [#119 非特权合盖限制调研](https://github.com/wyz541/kmp-Covio/issues/119)
- [#148 电源 Engine Feature](https://github.com/wyz541/kmp-Covio/issues/148)
- [ADR-0006：合盖睡眠保留特权 helper](adr-0006-lid-sleep-privileged-helper.md)
- Apple `IOPMLib.h`：电源断言类型和生命周期
- Apple `IOKitUser`：`IOPMSetSystemPowerSetting` 和偏好持久化
