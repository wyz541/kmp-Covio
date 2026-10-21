# 离线本地服务 Agent：证据

## 固定来源

| 来源 | 用途 |
| --- | --- |
| `macosApp/src/App/AppRuntime.swift` | 服务运行时 |
| `macosApp/src/Hub/Monitor/MacMonitorReader.swift` | 监控和电源 |
| `macosApp/src/Clipboard/ClipboardRuntime.swift` | 剪贴板元数据 |
| `macosApp/src/Workspace/WorkspaceRuntime.swift` | 工作区元数据 |
| `macosApp/src/Shelf/ShelfRuntime.swift` | 截图元数据 |
| `mlx-swift-lm` tool calling | schema 和 dispatch |

## 环境

| 项目 | 值 |
| --- | --- |
| 机器 | Apple M1 Virtual |
| CPU | 3 核 |
| 内存 | 7 GB |
| 系统 | macOS 26.6.2 |
| 模型 | `Qwen3-VL-2B-Instruct-4bit` |
| 模型 revision | `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |
| runtime revision | `48114eedf3c3d4a682a6b1d644cc5af5c2945d10` |

## 工具矩阵结果

```text
total=30
matched=27
accuracy=0.90
errors=1
unsafeViolations=0
totalMilliseconds=151354.7
```

## 失败样例

1. 复制文本请求没有选择 `copy_text`。
2. 工作区文件请求生成 malformed JSON。
3. 不存在的设置页面被作为工具调用。

## 事实与推论

事实：模型可以生成工具调用。  
事实：模型会生成错误参数或语法。  
推论：模型输出必须视为不可信。  
事实：安全攻击样本没有产生工具执行。  
推论：allowlist 和确认层可以阻止首版越权路径。

## 置信度

| 结论 | 置信度 | 原因 |
| --- | --- | --- |
| 只读服务可行 | 高 | 多个请求成功 |
| 副作用必须确认 | 高 | 安全边界要求 |
| 模型选择准确 | 中 | 仅 30 个样本 |
| 长期对话稳定 | 低 | 未做长测 |

## 缺口

1. 未在 M5 测试。
2. 未测试第三方 MCP。
3. 未测试 30 轮以上对话。
