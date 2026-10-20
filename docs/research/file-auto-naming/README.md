# 本地离线文件自动命名

> 结论：采用条件性 go。主方案是 `MLX Swift + Qwen3-VL-2B-Instruct`。重命名必须经过预览和确认。

## 前因

用户希望 Covio 根据文件内容生成文件名。
用户已选择本地小体积 LLM 方向。
运行时不依赖远程 AI 服务。
详见 [context.md](context.md)。

## 背景

Covio 当前是 macOS 26、Apple Silicon 应用。
应用已有 Vision OCR，但没有 PDF 文本提取、模型运行时和重命名事务层。
工作区保存文件副本，不保存用户原文件路径。
详见 [context.md](context.md) 和 [investigation.md](investigation.md)。

## 过程

本次工作分三步：

1. 审计 Covio 的 Swift、KMP 和文件操作边界。
2. 审计固定 commit 的 GitHub 参考实现。
3. 用合成样例测试本地模型、PDF 提取、图片 OCR、离线运行和提示注入。

详见 [investigation.md](investigation.md) 和 [evidence.md](evidence.md)。

## 结果

结论是条件性 go。
模型使用 `Qwen3-VL-2B-Instruct` 的 4 bit 或 Q4_K_M 版本。
运行时首选 MLX Swift。
运行时备选 llama.cpp。
日期、语言和置信度不能直接信任模型。
详见 [conclusion.md](conclusion.md) 和 [evidence.md](evidence.md)。

## 预期

首版只重命名同一目录内的普通文件。
首版同时覆盖纯文本、PDF、图片、代码文件和混合文件。
首版使用确定性模板、校验器、预览、原子重命名和撤销记录。
详见 [solution.md](solution.md) 和 [validation/README.md](validation/README.md)。

## 实现预期的手段

实现顺序如下：

1. 在 `kmpDomain` 定义配置、模板、校验和冲突规则。
2. 在 Swift 层实现 PDFKit、Vision、FileHandle 和类型识别。
3. 接入本地 `Qwen3-VL-2B-Instruct`。
4. 在 Files 页增加预览与确认流程。
5. 实现原子重命名和撤销。
6. 完成模型资产、真机、隐私和恢复验收。

详见 [solution.md](solution.md)、[validation/README.md](validation/README.md) 和 [evidence.md](evidence.md)。

## 子文档

| 文件 | 职责 |
| --- | --- |
| [context.md](context.md) | 问题、范围、系统模型和成功标准 |
| [investigation.md](investigation.md) | 工具、方案、参考实现和反证 |
| [conclusion.md](conclusion.md) | 结论、决策、限制和未决项 |
| [solution.md](solution.md) | 推荐架构、接口、安全、验收和实施计划 |
| [evidence.md](evidence.md) | 固定证据、命令、结果和限制 |
| [validation/README.md](validation/README.md) | 验证矩阵、风险和清理要求 |
| [validation/case-local-model-smoke.md](validation/case-local-model-smoke.md) | 本地模型质量、耗时和内存 |
| [validation/case-mlx-swift-build.md](validation/case-mlx-swift-build.md) | MLX Swift 构建与 Xcode 路径 |
| [validation/case-local-runtime-network.md](validation/case-local-runtime-network.md) | 本地运行网络检查 |
| [validation/case-mlx-swift-runtime.md](validation/case-mlx-swift-runtime.md) | MLX Swift 文本、图片和网络结果 |
| [validation/case-safe-rename.md](validation/case-safe-rename.md) | 预览、原子重命名和撤销结果 |

## 证据链阅读顺序

1. [context.md](context.md)：确认问题和边界。
2. [investigation.md](investigation.md)：确认比较方法和候选路径。
3. [evidence.md](evidence.md)：读取固定来源和本机结果。
4. [conclusion.md](conclusion.md)：确认决策与限制。
5. [solution.md](solution.md)：确认推荐架构。
6. [validation/README.md](validation/README.md)：确认验证计划。
7. 验证案例：读取实际执行记录。

## 更新规则

- 模型、运行时或模型版本变化时，更新 [investigation.md](investigation.md)、[conclusion.md](conclusion.md) 和 [evidence.md](evidence.md)。
- 配置、接口或重命名流程变化时，更新 [solution.md](solution.md)。
- 验证状态变化时，更新本文件、[validation/README.md](validation/README.md) 和对应案例。
- 结论变化时，同步更新关联 issue。
