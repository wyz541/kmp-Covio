# ADR-0013：离线 Agent 使用分档 Qwen3-VL 模型

- Status：accepted
- Kind：architecture
- Date：2026-10-22
- Supersedes：none
- Implements：#240
- 相关：[模型档位研究](../research/local-agent/model-tiers.md)、[#237](https://github.com/wyz541/kmp-Covio/issues/237)、[#247](https://github.com/wyz541/kmp-Covio/issues/247)

## 背景

Covio Agent 首版使用 `Qwen3-VL-2B-Instruct-4bit`。
2B 的工具选择准确率只有 90%。
用户允许使用更重的本地模型。
本地模型必须一次只加载一个。
文件自动命名和 Agent 必须共用模型容器。

## 决策

1. 8–12 GB 机器使用 `Qwen3-VL-2B-Instruct-4bit`。
2. 16 GB 以上机器使用 `Qwen3-VL-4B-Instruct-4bit`。
3. 24 GB 以上机器可以选择 `Qwen3-VL-8B-Instruct-4bit`。
4. 32 GB 以上机器可以导入 `Qwen3-VL-30B-A3B-Instruct-4bit`。
5. 30B-A3B 不得进入 Agent tool-calling 路径。
6. 8B 和 30B-A3B 只能由用户主动选择。
7. 始终保留 2B 低内存回退。
8. 一次只加载一个模型容器。
9. 模型切换必须先释放旧模型。
10. 模型包必须校验 revision、文件大小、SHA-256 和许可证。

## 后果

### 正面

- 16 GB Mac 可以获得更好的工具选择质量。
- 低内存机器仍有可用回退。
- 文件命名和 Agent 共用同一模型投资。
- 高端机器可以选择更高质量模型。
- 模型包策略避免在安装包中内置全部权重。

### 负面

- 4B 比 2B 多约 1.3 GB 模型文件。
- 4B 的峰值内存更高。
- 8B 在当前样本中没有收益。
- 30B-A3B 需要单独的上游修复。
- 模型切换会带来冷加载等待。

### 风险

- 4B 在低内存机器上 OOM。缓解：硬件档位守卫。
- 8B 速度不满足要求。缓解：只作为可选包。
- 30B-A3B 崩溃。缓解：禁止进入 Agent 工具路径。
- 同时加载两个模型。缓解：共享 runtime 和单模型租约。

## 备选方案

### 8B 作为默认

8B 的内存约为 4B 的 1.8 倍。
8B 的工具准确率为 96.7%。
8B 的速度更慢。
因此 8B 不作为默认。

### 30B-A3B 作为默认

30B-A3B 的模型文件为 18.27 GB。
30B-A3B 在 tool-calling 路径崩溃。
因此 30B-A3B 暂不进入 Agent 生产路径。

### MiniCPM-V 4.5

MiniCPM-V 4.5 的 OCR 和文档解析能力强。
当前官方 MLX Swift 没有适配器。
首版不引入新的模型移植风险。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 30B tool-calling 崩溃 | 等待上游修复 | 跟踪 `mlx-swift-lm` |
| 8B 长文档质量 | 未验证 | 后续扩大样本 |
| 4B 默认打包 | 已实现 #247 | 固定 manifest 与 SHA-256 |
| 模型切换内存 | 待真机验收 #247 | 64 GB 和 24 GB 真机 |

## 参考

- [模型档位研究](../research/local-agent/model-tiers.md)
- [Qwen3-VL 4B](https://huggingface.co/mlx-community/Qwen3-VL-4B-Instruct-4bit)
- [Qwen3-VL 8B](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit)
- [MLX Swift VLM 支持](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXVLM/README.md)
