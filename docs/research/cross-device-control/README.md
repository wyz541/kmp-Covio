# Windows 与 macOS 跨设备控制研究

> 结论：条件可行。局域网使用 mDNS 加手动地址。公网首选用户自管的 Tailscale/WireGuard 覆盖网络。设备控制使用独立的配对、mTLS 和 JSON-RPC 通道。自建中继推迟到后续版本。

| 项目 | 内容 |
| --- | --- |
| 状态 | 初稿，可评审 |
| 日期 | 2026-10-24 |
| 负责人 | @wyz541 |
| Issue | #319 |
| 范围 | 发现、配对、连接、能力和安全边界 |
| 范围外 | Windows 宿主构建；各控制能力的本机实现 |

## 前因

用户要求 Windows Covio 发现 macOS Covio，查看设备状态，并在授权后读取数据或执行受控操作。

候选操作包括充电上限、屏幕亮度、睡眠和风扇转速。macOS 端只有睡眠能力当前可用。充电上限、亮度和风扇控制仍需各自的本机实现。

## 背景

现有 [跨设备内容读取能力研究](../cross-device-content-access/README.md) 已调查 mDNS、TLS、配对和 Windows 权限。该研究面向内容传输，不覆盖远程控制授权。

现有 [跨设备共享暂存工作区研究](../shared-transfer-workspace/README.md) 明确不建立云端内容存储。本次研究把公网路径限定为网络接入，不把控制数据存入服务器。

## 过程

调研分五步。

1. 比较局域网发现路径。
2. 比较公网连接路径。
3. 定义设备身份、配对和撤销。
4. 定义控制能力与安全边界。
5. 制定验证矩阵和实施顺序。

详细过程见 [investigation.md](investigation.md)。来源与观察见 [evidence.md](evidence.md)。

## 结果

方案采用三层。

| 层 | 选择 |
| --- | --- |
| 局域网发现 | mDNS 为主，手动地址兜底 |
| 公网接入 | 用户自管 Tailscale/WireGuard |
| 应用安全 | 独立配对、mTLS、能力授权和审计 |

Windows 只发起连接。macOS 监听并执行本机能力。这个方向避免要求 Windows 标准用户开放入站端口。

SSDP 不采用。它面向 UPnP，暴露面更大，且不能解决公网接入。

自建中继不进入首版。它需要服务器、信任链、隐私说明和运维。协议保留中继适配点，后续版本可加入。

结论与限制见 [conclusion.md](conclusion.md)。

## 预期

首个版本应满足以下条件。

1. Windows 在局域网发现已配对的 macOS 设备。
2. 手动输入地址可以连接设备。
3. 用户可以完成一次性配对。
4. 后续连接使用双向认证。
5. 用户可以按能力授权和撤销。
6. Windows 能看到在线状态和设备基本信息。
7. 只读状态先上线。
8. 写操作逐项上线。
9. Tailscale 下可以连接远端 macOS。
10. 未授权、离线和不支持状态都有明确结果。

方案见 [solution.md](solution.md)。验收见 [validation/README.md](validation/README.md)。

## 实现预期的手段

1. 新增 KMP 跨设备协议模块。
2. 在 macOS 宿主运行 TLS 服务。
3. 在 Windows 宿主运行 TLS 客户端。
4. 增加 mDNS 发布与浏览适配器。
5. 增加手动端点和 Tailscale 名称输入。
6. 增加配对 URI、设备证书和能力授权。
7. 先交付只读设备状态。
8. 逐项接入睡眠、亮度、充电上限和风扇控制。
9. 在 Windows 与 macOS 真机执行端到端验收。

## 子文档

| 文件 | 职责 |
| --- | --- |
| [context.md](context.md) | 问题、模型、场景和成功标准 |
| [investigation.md](investigation.md) | 发现、公网、协议和安全比较 |
| [conclusion.md](conclusion.md) | 结论、决策表、限制和未决项 |
| [solution.md](solution.md) | 协议、配对、授权、能力和实施计划 |
| [evidence.md](evidence.md) | 来源、观察、推论和置信度 |
| [validation/README.md](validation/README.md) | 端到端测试矩阵和风险 |
| [validation/case-windows-macos-control.md](validation/case-windows-macos-control.md) | Windows 与 macOS 验证记录 |

## 证据链阅读顺序

1. 先读 [context.md](context.md) 的问题与边界。
2. 再读 [evidence.md](evidence.md) 的 `E-CD01` 到 `E-CD10`。
3. 用 [investigation.md](investigation.md) 核对方案比较。
4. 用 [conclusion.md](conclusion.md) 核对选择与限制。
5. 用 [solution.md](solution.md) 制定协议和 Feature 子任务。
6. 最后按 [validation/README.md](validation/README.md) 执行真机验证。

## 更新规则

1. 新实验写入 [evidence.md](evidence.md)。
2. 真机结果写入 [validation/case-windows-macos-control.md](validation/case-windows-macos-control.md)。
3. 能力状态变化时同步更新本文件、[conclusion.md](conclusion.md) 和相关 Issue。
4. 协议版本变化时必须补迁移与兼容说明。
