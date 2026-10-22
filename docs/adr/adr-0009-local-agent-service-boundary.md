# ADR-0009：离线 Agent 使用进程内本地服务 registry

- Status：accepted
- Kind：architecture
- Date：2026-10-21
- Supersedes：none
- Implements：#197
- 相关：[离线本地服务 Agent 研究](../research/local-agent/README.md)、[#194](https://github.com/wyz541/kmp-Covio/issues/194)、[#196](https://github.com/wyz541/kmp-Covio/issues/196)

## 背景

Covio 新增导航级 Agent 页签。  
Agent 使用本地 `Qwen3-VL-2B-Instruct-4bit`。  
Agent 需要访问监控、电源、工作区、截图和剪贴板等本地服务。  
运行时不得依赖远程 AI 服务。  
模型工具选择准确率为 90%。  
模型会生成 malformed syntax 或错误参数。  

## 决策

1. 首版服务通过进程内 typed registry 提供。
2. 每个工具声明稳定名称、风险、输入 schema 和输出 schema。
3. registry 在模型输出后再次校验工具名和参数。
4. 只读工具可以自动执行。
5. 有副作用工具只生成 pending call。
6. pending call 必须由用户确认。
7. 取消后不得执行。
8. 工具结果只包含脱敏数据。
9. 不开放任意 shell、任意路径和网络请求。
10. privileged helper 保持现有固定命令白名单。
11. MCP 只作为未来适配器，不作为首版 daemon。
12. 本机 HTTP 不作为首版服务协议。

## 后果

### 正面

- 调用延迟低。
- 不增加外部进程和端口。
- 服务实现可以直接测试。
- 权限和确认逻辑集中。
- 模型可以替换而后端契约不变。

### 负面

- 首版服务只能来自 Covio 进程。
- 第三方工具需要后续 MCP 适配。
- registry 需要维护每个工具的 schema。

### 风险

- 模型产生错误调用。缓解：registry 校验和拒绝。
- 模型直接触发副作用。缓解：pending call 和确认。
- 工具结果包含敏感内容。缓解：结果字段白名单。
- helper 权限扩大。缓解：helper 不接入通用 registry。

## 验收

| 项目 | 结果 |
| --- | --- |
| 环境 | Apple M1 Virtual，3 核，`7,516,192,768` bytes |
| 安装包验收 | 通过，#206 |
| 峰值 RSS | `657,293,312` bytes |
| 非 loopback 网络连接 | 0 |
| 确认后复制 | 1 次 |
| 取消后复制 | 0 次 |
| 未授权副作用 | 0 |

详细结果见 [Case 3](../research/local-agent/validation/case-constrained-agent-acceptance.md)。

## 备选方案

### Unix domain socket

适合特权 helper。  
不适合普通本地服务。  
首版采用会扩大协议和认证复杂度。

### 本地 HTTP

会增加端口、认证、生命周期和防火墙问题。  
首版没有跨进程需求。

### MCP server

适合第三方服务生态。  
首版没有第三方接入需求。  
后续通过 registry adapter 接入。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 第三方 MCP 适配 | 后续 | 单独 Research |
| 文件命名服务接入 | 后续 | 单独 Feature |

## 参考

- [研究索引](../research/local-agent/README.md)
- [工具矩阵](https://github.com/wyz541/kmp-Covio/actions/runs/39552460336)
- [7 GB 安装包验收](https://github.com/wyz541/kmp-Covio/actions/runs/39585450321)
- [服务方案](../research/local-agent/solution.md)
