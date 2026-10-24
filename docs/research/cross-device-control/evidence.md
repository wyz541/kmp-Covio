# 证据附录

## 1. 证据等级

| 等级 | 含义 |
| --- | --- |
| A | 官方规范、官方文档或可重复实验 |
| B | 公开产品实现或间接证据 |
| C | 推论或待验证假设 |

## 2. 证据清单

| ID | 主题 | 等级 | 摘要 |
| --- | --- | --- | --- |
| E-CD01 | mDNS | A | 本地链路无中心名称查询 |
| E-CD02 | DNS-SD | A | 服务类型和实例发现 |
| E-CD03 | TLS 1.3 | A | 认证加密传输标准 |
| E-CD04 | WebSocket | A | 双向消息协议 |
| E-CD05 | JSON-RPC | A | 请求、响应和错误结构 |
| E-CD06 | Tailscale 数据面 | A | WireGuard、NAT 穿透和覆盖网络 |
| E-CD07 | Tailscale 控制 | A | MagicDNS 和 ACL |
| E-CD08 | Windows 防火墙 | A | 普通用户不能创建入站允许规则 |
| E-CD09 | Ktor 目标与编译 | A | `jvm` 与 `macosArm64` 编译通过 |
| E-CD10 | 本机能力状态 | A | 睡眠已有；充电与风扇在建；亮度缺失 |

## 3. 详细记录

### E-CD01：mDNS

来源等级：A

来源：RFC 6762。

关键输出：

```text
Multicast DNS provides DNS-like operations on the local link.
It works without a conventional DNS server.
It requires little or no administration.
```

观察：mDNS 适合局域网发现。

限制：mDNS 依赖本地链路组播。路由器和企业网络可以阻断。

置信度：高。

### E-CD02：DNS-SD

来源等级：A

来源：RFC 6763。

关键输出：

```text
DNS-Based Service Discovery uses service types and instance names.
Service information can be represented with SRV, TXT and PTR records.
```

观察：Covio 可以使用独立服务类型发布设备。

限制：TXT 记录不应包含秘密。

置信度：高。

### E-CD03：TLS 1.3

来源等级：A

来源：RFC 8446。

关键输出：

```text
TLS 1.3 provides authenticated encryption.
The handshake authenticates peers when configured with certificates.
```

观察：TLS 1.3 可以作为控制通道的加密层。

限制：证书生命周期和系统信任库仍需实现。

置信度：高。

### E-CD04：WebSocket

来源等级：A

来源：RFC 6455。

关键输出：

```text
WebSocket provides full-duplex communication over one connection.
The WebSocket handshake uses HTTP and can use TLS.
```

观察：WebSocket 适合请求、响应和状态事件。

限制：需要定义应用消息和重连语义。

置信度：高。

### E-CD05：JSON-RPC

来源等级：A

来源：JSON-RPC 2.0 规范。

关键输出：

```text
JSON-RPC uses request, response and notification objects.
Requests carry a method, params and id.
Responses carry result or error.
```

观察：JSON-RPC 能提供统一请求关联和错误结构。

限制：JSON-RPC 本身不提供认证和授权。

置信度：高。

### E-CD06：Tailscale 数据面

来源等级：A

来源：Tailscale 官方架构文档。

关键输出：

```text
Tailscale uses WireGuard as its data plane.
Tailscale coordinates NAT traversal and peer endpoints.
Nodes can form direct encrypted tunnels.
```

观察：Tailscale 可以建立跨公网覆盖网络。

限制：用户必须安装和登录 Tailscale。

置信度：高。

### E-CD07：Tailscale 控制

来源等级：A

来源：Tailscale MagicDNS、ACL 和 Serve 文档。

关键输出：

```text
MagicDNS assigns device names in the tailnet.
Tailscale ACLs are deny-by-default when configured, directional and locally enforced.
Without an ACL section, the default policy allows all devices.
Tailscale Serve can proxy a local service to the tailnet over HTTPS.
```

观察：Tailscale 提供名称和网络层控制。

观察：默认策略并不等于最小权限。

推论：Covio 必须使用应用层授权。

置信度：高。

### E-CD08：Windows 防火墙

来源等级：A

来源：Microsoft Learn，Windows Firewall rules。

关键输出：

```text
Inbound traffic is blocked by default when no allow rule exists.
A user who is not a local administrator creates block rules regardless of the choice in the prompt.
Outbound rules can be configured, but outbound is commonly allowed.
```

观察：Windows 标准用户不能自行放行入站监听。

推论：Windows 客户端只发起连接。

置信度：高。

### E-CD09：Ktor 目标与编译

来源等级：A

来源：Maven Central 的 Ktor 3.5.2 module metadata，以及 2026-10-24 的临时 Amper 工程。

环境：macOS，Amper 0.12.1，Kotlin 2.4.10，Ktor 3.5.2。

依赖：

```text
io.ktor:ktor-server-core:3.5.2
io.ktor:ktor-server-cio:3.5.2
io.ktor:ktor-server-websockets:3.5.2
```

最小代码创建 CIO 服务端并注册 `/control` WebSocket。

命令：

```text
kotlin build
```

关键输出：

```text
✓ Compilation successful for 'transportSpike' [macosArm64]
✓ Compilation successful for 'transportSpike' [jvm]
Build successful
```

观察：同一段 CIO 服务端与 WebSocket 代码可以编译到两端。

限制：尚未验证 macOS framework 导出、证书配置和实际网络运行。

置信度：高。

### E-CD10：本机能力状态

来源等级：A

来源：仓库代码和 Issue 状态。

关键输出：

```text
Privileged helper allows setDisableSleep and setHibernateMode.
Sleep now and display sleep exist in the local engine.
#137 tracks the charge limit.
#313 tracks fan control.
No brightness control API exists in the current repository.
```

观察：四个写能力处于不同成熟度。

推论：远程控制能力必须分批上线。

置信度：高。

## 4. 失败和反证

1. mDNS 不能保证跨局域网工作。
2. Tailscale 不能替代设备证书。
3. 6 位配对码不能单独提供足够熵。
4. Windows 默认阻止入站连接。
5. SSDP 不能解决认证和公网。
6. Ktor 发布物支持不等于 macOS 宿主已集成。
7. 充电、亮度和风扇能力尚未全部可用。

## 5. 参考来源

- [RFC 6762: Multicast DNS](https://www.rfc-editor.org/rfc/rfc6762.html)
- [RFC 6763: DNS-Based Service Discovery](https://www.rfc-editor.org/rfc/rfc6763.html)
- [RFC 8446: TLS 1.3](https://www.rfc-editor.org/rfc/rfc8446.html)
- [RFC 6455: WebSocket](https://www.rfc-editor.org/rfc/rfc6455.html)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [Tailscale architecture](https://tailscale.com/blog/how-tailscale-works)
- [Tailscale MagicDNS](https://tailscale.com/docs/features/magicdns)
- [Tailscale ACLs](https://tailscale.com/docs/features/access-control/acls)
- [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)
- [Microsoft Windows Firewall rules](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules)
- [Ktor server CIO module metadata](https://repo1.maven.org/maven2/io/ktor/ktor-server-cio/3.5.2/ktor-server-cio-3.5.2.module)
- [Ktor WebSocket module metadata](https://repo1.maven.org/maven2/io/ktor/ktor-server-websockets/3.5.2/ktor-server-websockets-3.5.2.module)
