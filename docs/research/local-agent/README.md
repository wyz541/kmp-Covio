# 离线本地服务 Agent

> 结论：采用条件性 go。Agent 使用本地模型选择 allowlist 工具，服务在进程内执行，副作用必须确认。

> 模型档位：2B 保留为低内存回退。4B 作为 16 GB 以上默认档。8B 和 30B-A3B 暂不作为默认。

## 前因

用户需要在导航级页签中与 Agent 对话。  
Agent 的主要职责是访问 Covio 的离线本地服务。  
运行时不依赖远程 AI 服务。  
详见 [context.md](context.md)。

## 背景

Covio 已有本地 `Qwen3-VL-2B-Instruct-4bit`、监控、截图、剪贴板、工作区和文件命名运行时。  
这些能力都在主应用信任边界内。  
首版不引入外部 daemon 或任意代码执行。  
详见 [context.md](context.md) 和 [investigation.md](investigation.md)。

## 过程

本次工作分四步：

1. 用 30 个请求测试模型的工具选择。
2. 比较进程内 registry、Unix socket、本地 HTTP 和 MCP。
3. 实现 Agent 页签、服务白名单、确认和审计模型。
4. 在 7 GB Apple Silicon 虚拟 Mac 运行安装包验收。

详见 [evidence.md](evidence.md) 和 [validation/README.md](validation/README.md)。

## 结果

工具选择正确率为 90%。  
4B 档位工具矩阵为 30 / 30。
未授权副作用为 0。  
模型不能单独执行工具。  
服务协议采用进程内 typed registry。  
7 GB Apple Silicon 验收通过。
峰值 RSS 为 `657,293,312` bytes。
非 loopback 网络连接为 0。
详见 [conclusion.md](conclusion.md) 和 [evidence.md](evidence.md)。

## 预期

Agent 提供普通对话和受控本地服务。  
只读服务可以自动执行。  
有副作用服务必须显示参数摘要并请求确认。  
详见 [solution.md](solution.md) 和 [validation/README.md](validation/README.md)。

## 实现预期的手段

1. 在 KMP 工作区模型中加入 Agent 页签。
2. 在 Swift 层加入 Agent runtime 和聊天界面。
3. 复用本地模型和 `mlx-swift-lm` tool calling。
4. 建立 allowlist 服务 registry。
5. 把服务限制在 `AppRuntime` 已有运行时内。
6. 运行低内存和离线验收。

详见 [solution.md](solution.md)、[validation/README.md](validation/README.md) 和 [evidence.md](evidence.md)。

## 子文档

| 文件 | 职责 |
| --- | --- |
| [context.md](context.md) | 问题、边界、状态和成功标准 |
| [investigation.md](investigation.md) | 工具调研、协议比较和源码分析 |
| [conclusion.md](conclusion.md) | 结论、决策和限制 |
| [solution.md](solution.md) | 推荐架构、接口、安全和验收 |
| [evidence.md](evidence.md) | 工具矩阵、运行环境和证据 |
| [model-tiers.md](model-tiers.md) | 2B、4B、8B、30B-A3B 对比与档位决策 |
| [validation/README.md](validation/README.md) | 验证矩阵和清理要求 |
| [validation/case-tool-calling.md](validation/case-tool-calling.md) | 30 个工具调用样本 |
| [validation/case-service-boundary.md](validation/case-service-boundary.md) | 服务协议和权限比较 |
| [validation/case-constrained-agent-acceptance.md](validation/case-constrained-agent-acceptance.md) | 7 GB Apple Silicon 安装包验收 |

## 证据链阅读顺序

1. [context.md](context.md)：确认问题和边界。
2. [investigation.md](investigation.md)：确认候选协议和源码事实。
3. [evidence.md](evidence.md)：读取工具矩阵结果。
4. [model-tiers.md](model-tiers.md)：确认模型档位。
5. [conclusion.md](conclusion.md)：确认条件性 go。
6. [solution.md](solution.md)：确认实现和权限模型。
7. 验证案例：读取实际结果。

## 更新规则

- 模型或工具调用协议变化时，更新 [investigation.md](investigation.md) 和 [evidence.md](evidence.md)。
- 服务权限变化时，更新 [solution.md](solution.md) 和 ADR-0009。
- 验证状态变化时，更新 [validation/README.md](validation/README.md)。
