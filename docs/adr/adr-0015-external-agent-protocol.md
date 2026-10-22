# ADR-0015：外部 Agent 使用带认证的 loopback MCP 服务

- Status：accepted
- Kind：architecture
- Date：2026-10-22
- Supersedes：none
- Implements：#248
- 相关：[外部协议研究](../research/local-agent/external-protocol.md)、[#237](https://github.com/wyz541/kmp-Covio/issues/237)、[#249](https://github.com/wyz541/kmp-Covio/issues/249)

## 背景

Covio Agent 已有 typed tool registry。
registry 提供 allowlist、schema、风险、确认和审计。
外部本地 Agent 需要通用服务发现和调用接口。
现有 in-process 接口不能被外部进程调用。
XPC 和 Unix socket 缺少通用 Agent 客户端支持。
stdio 需要额外 CLI 和 App 间 IPC。
完整 OAuth 对本机单用户服务过重。

## 决策

1. 首版使用 MCP `2025-06-18` Streamable HTTP。
2. endpoint 只监听 `127.0.0.1` 的动态端口。
3. 每次启动生成随机 bearer token。
4. token 保存在 Keychain。
5. 校验 `Host`、`Origin`、协议版本和会话 ID。
6. POST 返回 JSON，GET 暂返回 405。
7. 外部客户端只能发现 `AgentToolCatalog` 中的工具。
8. 参数继续经过 registry 和 gateway 校验。
9. 外部副作用只生成 pending action。
10. 本机用户确认后执行一次。
11. pending action 绑定 MCP session。
12. DELETE、超时、App 退出时清理 pending action。
13. 审计记录 source、session、工具、风险、状态和耗时。
14. 不记录 token、请求头、文件正文或工具结果正文。
15. stdio、SSE、OAuth 2.1 和 App Intents 作为后续适配。

## 后果

### 正面

- 外部 Agent 可以使用标准工具发现协议。
- 主应用拥有服务和会话生命周期。
- 复用现有 allowlist、确认和审计。
- 不需要为每个客户端编写专用 socket 客户端。
- 不暴露公网接口。

### 负面

- 需要实现 HTTP transport、session 和认证。
- 首版 bearer token 不是完整 OAuth 2.1。
- 首版不支持 SSE 服务事件。
- 偏好 stdio 的客户端仍需后续 shim。

### 风险

- token 泄露。缓解：Keychain、随机 token、轮换和高权限文件保护。
- DNS rebinding。缓解：校验 Host 和 Origin，只绑定 loopback。
- 外部请求绕过副作用确认。缓解：外部风险策略提升，pending action 只由本机确认。
- pending action 残留。缓解：session DELETE、空闲超时和 App 退出清理。
- 审计泄露正文。缓解：只保存元数据，并沿用历史脱敏策略。

## 备选方案

### MCP stdio

stdio 无网络且 MCP 客户端支持广。
Covio 需要额外 CLI 和 App 间 IPC。
首版安装和进程生命周期复杂度更高。
因此作为后续适配。

### MCP over XPC 或 Unix socket

该方案权限边界强。
通用外部 Agent 不能直接使用。
因此只适合专用集成。

### App Intents 或 Shortcuts

该方案系统集成好。
该方案不是通用 Agent tool 协议。
因此作为补充入口。

### 完整 OAuth 2.1

该方案适合远程和多用户服务。
本机单用户首版不需要授权服务器和动态客户端注册。
因此在引入远程访问前再实现。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| stdio shim | 后续 | #249 完成后单独 issue |
| SSE 主动事件 | 后续 | 出现事件订阅需求 |
| OAuth 2.1 | 后续 | 增加非本机客户端前 |
| token 轮换 UI | #249 | 设置页交互验收 |

## 参考

- [外部协议研究](../research/local-agent/external-protocol.md)
- [MCP Transports](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
- [MCP Authorization](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization)
- [MCP Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [ADR-0009](adr-0009-local-agent-service-boundary.md)
