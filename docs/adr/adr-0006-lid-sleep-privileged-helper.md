# ADR-0006：合盖睡眠保留特权 helper 与手写 plist

- Status：accepted
- Kind：architecture
- Date：2026-10-16
- Supersedes：none
- Superseded by：ADR-0018（仅 helper 形式）
- Implements：none
- 相关：#119

## 背景

Covio 的「合盖不睡」由一个特权 helper 实现。helper 是 root LaunchDaemon。
安装和卸载用 `osascript` 请求管理员权限。plist 手写进 `/Library/LaunchDaemons`。

这个形式被质疑过两次。

**第一次：能不能不提权。**

合盖判定在 `powerd`。它读全局电源设置，不读进程断言。
唯一的候选是 `caffeinate -s` 使用的 `PreventSystemSleep` 断言。
Apple 在 `IOPMLib.h` 里把它标为「not supported in any OS X releases」。
本机对照实验确认了这个判定：持有断言时合盖，系统仍然进入完全睡眠。

**第二次：能不能换成系统托管的 `SMAppService.daemon`。**

它把 plist 放进应用包，注册和注销由系统负责。形式上比手写 plist 干净。

两个约束决定了这个问题的答案：

1. `SMAppService.h` 要求含 LaunchDaemon 的应用必须公证。本机没有 Developer ID。
2. `pmset disablesleep` 是系统级键，需要 root。它没有每电源版本。

## 决策

1. 保留特权 helper。合盖睡眠只能由 root 控制。
2. 保留手写 plist 的形式。不换 `SMAppService.daemon`。
3. 插电与电池的区分由应用侧完成。`disablesleep` 没有每电源版本。
4. 安装与卸载继续用 `osascript` 提权。卸载脚本第一步清 `disablesleep`，顺序不改。

## 后果

### 正面

- 现有实现不改动。协议、鉴权和安装脚本都已经可用。
- Apple 明确保留手写 plist 这条路径，而且不需要 System Settings 批准。
- 管理员动作只发生在安装和卸载，各一次。

### 负面

- 用户要接受一个 root 守护进程。
- 安装和卸载各弹一次管理员授权框。
- 应用不运行时，`disablesleep` 保持上次写入值。

### 风险

- 卸载中断会让 `disablesleep` 留在 1，机器不再睡眠。缓解：卸载脚本先清标志，再删组件。
- `man pmset` 没有 `disablesleep` 条目。这个键没有官方文档。缓解：验证矩阵覆盖它的行为。
- Apple 没有写明手写 plist 路径的保留期限。缓解：这条路径被官方文档认可，短期内不会移除。

## 备选方案

### 备选 1：`PreventSystemSleep` 断言

用 `caffeinate -s` 的断言阻止系统睡眠。这条路径不需要 root。

未采纳的原因：Apple 写明这个断言在任何 macOS 版本里都不受支持。
本机实验确认：持有断言时合盖，系统仍然进入完全睡眠。

### 备选 2：换 `SMAppService.daemon`

plist 放进应用包的 `Contents/Library/LaunchDaemons/`。注册和注销由系统托管。

未采纳的原因：Apple 要求含 LaunchDaemon 的应用必须公证，本机没有 Developer ID。
注册探针用 `Covio Dev` 自签名证书和 ad-hoc 各试一次，两次都失败。
系统建了 BTM 条目，但标记为 `disallowed`，拒绝引导。

即使签名问题解决，这个方案也不减少提权动作：

| 环节 | 手写 plist | `SMAppService.daemon` |
| --- | --- | --- |
| 安装 | `osascript` 弹窗 | 注册，再到 System Settings 批准 |
| 卸载 | `osascript` 弹窗 | `unregister()` 一步 |
| 清 `disablesleep` | 卸载脚本第一步做 | `unregister()` 不做，仍需 root |
| 应用更新 | 没有额外动作 | 每次更新要重新注册 |

### 备选 3：删掉合盖功能

不做合盖不睡。

未采纳的原因：这是产品功能，不是实现细节。删除会让功能消失。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 电池合盖不睡的电量代价 | pending | 量化耗电 |
| `pmset -b disablesleep` 是否被接受 | pending | 需要 root，未执行 |
| 取得 Developer ID 后 `SMAppService` 是否可用 | pending | 重跑注册探针 |

## 参考

- [调研报告](../research/lid-sleep-control/README.md)
- [证据附录](../research/lid-sleep-control/evidence.md)
- issue #119
- [ADR-0005](adr-0005-local-code-signing.md)：本机签名配置
