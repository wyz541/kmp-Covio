# ADR-0008：文件自动命名采用 Apple 平台集成优先的运行时

- Status：accepted
- Kind：architecture
- Date：2026-10-21
- Supersedes：none
- Implements：#187
- 相关：[文件自动命名调研](../research/file-auto-naming/README.md)、[#170](https://github.com/wyz541/kmp-Covio/issues/170)、[#185](https://github.com/wyz541/kmp-Covio/issues/185)

## 背景

文件自动命名需要在本机处理文本、PDF、图片和代码。  
产品要求离线运行、结构化输出和 8 GB 内存支持。  
当前实现使用 `Qwen3-VL-2B-Instruct-4bit` 和官方 MLX Swift。  

近期备选包括 CoreML/ANE、MiniCPM-V、FastVLM、mllm 和 Osaurus 的 Swift 推理引擎。  
这些项目在社区规模、运行后端和许可证上差异很大。  
本项目需要区分模型、运行时和系统提取能力，不能用单一 star 数代替平台判断。

当前工作负载是用户发起的短时文件批处理。  
它不是持续视觉问答，也不是高并发模型服务。  
因此平台最优解要优先保证结构化输出、原生集成、稳定维护和离线分发。

## 决策

1. 生产运行时使用官方 `ml-explore/mlx-swift-lm` 和官方 MLX Swift。
2. 当前模型保持 `Qwen3-VL-2B-Instruct-4bit`。
3. 模型 revision 固定为 `9c4f5209e57b31f4b9dfba735de3fb983739c9cc`。
4. `mlx-swift-lm` revision 固定为 `48114eedf3c3d4a682a6b1d644cc5af5c2945d10`。
5. PDFKit、Vision 和 UniformTypeIdentifiers 负责本地内容提取。
6. 模型只生成 `title` 和 `category`。
7. 日期、语言、置信度、模板、扩展名和路径由确定性代码处理。
8. 模型输出使用 MLX Guided Generation 和 JSON Schema 约束。
9. `NamingModel` 端口保留为运行时边界。后续后端必须实现同一契约。
10. 不把自定义推理引擎或小型 fork 加入生产依赖。
11. CoreML/ANE 只能作为受控 Research 候选。
12. MiniCPM-V 1B 只能作为模型候选。进入生产前必须有稳定的 Swift 运行时适配。
13. FastVLM 不进入商业产品默认方案。其模型权重许可证限制为研究用途。
14. 当前不采用 `vmlx-swift-lm` 和 mllm 作为生产运行时。

## CoreML/ANE 准入条件

CoreML/ANE 进入生产前必须单独完成 Research issue。  
Research issue 只回答一个兼容性问题：同一 12 样本矩阵能否在 8 GB Apple Silicon Mac 上通过。

准入条件如下。

1. JSON Schema 约束或等价的确定性结构化输出通过。
2. 12 样本结果不低于当前 MLX 基线。
3. 提示注入风险仍能被识别。
4. 峰值常驻内存不超过 4 GiB。
5. 文本、图片和扫描 PDF 的延迟满足现有门槛。
6. 应用安装包保持离线可用。
7. 模型资源、tokenizer 和许可证可以随应用分发。
8. 安全重命名、部分失败和撤销全部通过。

CoreML/ANE 不满足上述条件时，MLX Swift 保持生产基线。

## 后果

### 正面

- 运行时依赖 Apple ML 官方项目。
- Qwen3-VL 有官方 Swift 模型实现和等价测试。
- JSON Schema 继续提供可靠的结构化输出。
- PDFKit、Vision 和 UTType 减少自研平台代码。
- 当前已验收的功能不需要重写。
- 后续运行时可以通过 `NamingModel` 端口替换。

### 负面

- MLX 使用 GPU，能效可能低于 ANE。
- 模型和应用包体积约 1.8 GB。
- 当前仍有 Qwen3-VL 上游问题需要跟踪。
- Qwen3-VL 2B 不是社区规模最大的模型。

### 风险

- 上游 Qwen3-VL 回归会改变输出。缓解：固定 revision，并在升级前跑 12 样本矩阵。
- 真实图片可能触发上游预处理问题。缓解：增加 M1 和 M5 图片回归测试。
- ANE 路径可能缺少结构化输出。缓解：先做 Research，不直接修改生产后端。
- MiniCPM 适配器可能长期不可用。缓解：只把它记为模型候选，不纳入当前交付。
- FastVLM 许可证可能限制商业分发。缓解：不把它加入默认产品。

## 备选方案

### 备选 1：CoreML-LLM 的 ANE 运行时

该方案直接提供 Qwen3-VL 2B 的 Core ML stateful 版本。  
其优势是 ANE 能效和较小的运行时内存。  
当前公开 API 没有等价的 JSON Schema 引导输出。  
macOS 真机和 8 GB 内存数据也需要单独验证。  
因此该方案进入 Research，不直接进入生产。

### 备选 2：Osaurus 的 `vmlx-swift-lm`

Osaurus 应用维护活跃。  
其独立推理 fork 规模很小，最后更新时间为 2026-05-15。  
公开加速数据主要针对 MoE、MLA 和混合 SSM 模型。  
当前稠密 2B 模型没有对应收益证据。  
因此不采用该 fork 作为运行时。

### 备选 3：mllm

mllm 是 MIT 许可的活跃端侧推理项目。  
本项目能引用的 Qwen3-VL 数据来自 Jetson CUDA。  
macOS 构建使用 Apple Accelerate CPU 后端。  
它没有当前项目可直接依赖的 Swift VLM 路径。  
因此不采用。

### 备选 4：FastVLM

FastVLM 是 Apple 官方研究项目。  
其模型权重只允许研究用途。  
它也不覆盖当前文本、代码和 PDF 的统一命名链路。  
因此不进入商业产品默认方案。

### 备选 5：MiniCPM-V 1B

MiniCPM-V 使用 Apache-2.0。  
4.7 系列提供 1B 模型。  
当前 `mlx-swift-lm` 没有 MiniCPM 适配器。  
因此保留为后续模型候选。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 8 GB Apple Silicon Mac 真机验收 | pending #185 | 运行 12 样本矩阵并记录峰值内存 |
| CoreML/ANE 结构化输出和 8 GB 兼容性 | 未开始 | 独立 Research issue |
| MiniCPM-V 1B 的 Swift 运行时适配 | 未开始 | 独立 Research issue |
| M1 和 M5 的图片回归 | 未开始 | 固定 runtime revision 后跑图片矩阵 |

## 参考

- [官方 MLX Swift](https://github.com/ml-explore/mlx-swift)
- [官方 mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)
- [Qwen3-VL Swift 实现](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXVLM/Models/Qwen3VL.swift)
- [Qwen3-VL 等价测试](https://github.com/ml-explore/mlx-swift-lm/blob/main/Tests/MLXLMTests/Qwen3VLContinuationTests.swift)
- [CoreML-LLM](https://github.com/john-rocky/CoreML-LLM)
- [Qwen3-VL Stateful Core ML](https://huggingface.co/mlboydaisuke/qwen3-vl-2b-stateful-coreml)
- [Osaurus](https://github.com/osaurus-ai/osaurus)
- [vmlx-swift-lm](https://github.com/osaurus-ai/vmlx-swift-lm)
- [mllm](https://github.com/UbiquitousLearning/mllm)
- [FastVLM](https://github.com/apple-aiml-research/ml-fastvlm)
- [FastVLM 模型许可证](https://github.com/apple-aiml-research/ml-fastvlm/blob/main/LICENSE_MODEL)
- [MiniCPM-V](https://github.com/OpenBMB/MiniCPM-V)
- [文件自动命名推荐方案](../research/file-auto-naming/solution.md)
