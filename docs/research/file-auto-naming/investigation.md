# 文件自动命名调研

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 初稿，可评审 |
| 日期 | 2026-10-20 |
| 目标 commit | `9b80f73e7e28e7a776825911543a2089bbe1184d` |

[返回主题索引](README.md)

## 调研方法

1. 阅读 Covio 的 SwiftUI、KMP、配置和文件操作代码。
2. 选择固定 commit 的公开参考仓库。
3. 对运行时、模型、文件提取和重命名安全做矩阵比较。
4. 用合成文件执行本地 smoke test。
5. 记录成功、失败、反证和未执行项。

## 来源范围

| 来源 | 范围 |
| --- | --- |
| Covio 源码 | SwiftUI、KMP、配置和文件操作边界 |
| Apple 原生能力 | PDFKit、Vision、UniformTypeIdentifiers、FileManager |
| 模型仓库 | Qwen3-VL 2B 的模型卡、许可证和权重体积 |
| 运行时仓库 | MLX Swift、llama.cpp、LocalLLMClient |
| 文件命名项目 | AI File Sorter、ollama-rename-files、ai-renamer |
| macOS 应用 | Sidekick |
| 文档提取 | MDFlux |

每条来源都固定了 commit、release 或模型 revision。
详见 [evidence.md](evidence.md)。

## 领域模型

| 对象 | 含义 |
| --- | --- |
| FileCandidate | 用户选择、尚未修改的文件 |
| ExtractedContent | 文本、OCR、图片、元数据和提取置信度 |
| NamingFacts | 模型产生的标题、类别等语义字段 |
| NamePolicy | 模板、字符、长度、日期和冲突约束 |
| NamePlan | 原名、目标名、证据、风险和撤销字段 |
| RenameResult | 成功、失败、冲突和恢复状态 |

## 约束模型

1. 目标平台是 macOS 26 或更高版本。
2. 应用只构建 Apple Silicon。
3. 运行时不依赖远程 AI。
4. 文件内容不上传。
5. 模型资产必须可控。
6. 模型输出不能直接成为路径。
7. 配置必须可测试、可迁移和可拒绝。
8. 重命名必须保留扩展名并阻止覆盖。
9. 用户必须看到预览。
10. 失败必须可恢复。

## 控制路径

```mermaid
flowchart LR
  U["不受信任文件"] --> X["受限提取器"]
  X --> C["证据与质量评分"]
  C --> M["无工具本地模型"]
  M --> J["JSON 语义字段"]
  J --> V["可信模板与校验器"]
  V --> P["用户确认"]
  P --> A["原子文件操作"]
  A --> H["撤销记录"]
```

关键不变量如下：

1. 模型没有文件系统工具。
2. 模型没有网络工具。
3. 模型只输出预先声明的字段。
4. 模板和校验器由代码执行。
5. 用户确认发生在文件系统写入前。

## 信任边界

| 边界 | 不可信输入 | 可信输出 | 验证 |
| --- | --- | --- | --- |
| 文件读取 | 文件字节、元数据和嵌入指令 | 有上限的文本或图片 | 文件类型、权限和大小检查 |
| 模型推理 | 提取文本和图片 | 结构化语义字段 | JSON Schema 和字段长度 |
| 名称生成 | 模型字段 | 候选文件名 | 模板、字符、长度和保留扩展名 |
| 文件写入 | 候选文件名和原路径 | 已校验目标路径 | 同目录、普通文件和无覆盖 |
| 撤销 | 历史计划文件 | 恢复结果 | 身份、大小、时间和版本校验 |

## 原生能力矩阵

| 能力 | 当前能力 | 限制 | 依赖 | 证据 |
| --- | --- | --- | --- | --- |
| UTType | 根据类型和扩展名分类 | 扩展名可能错误或缺失 | macOS | Covio 已使用 |
| FileHandle | 读取文本和代码片段 | 需要大小上限和编码回退 | Foundation | 需新增 |
| PDFKit | 提取 PDF 文本和页面 | 扫描件没有文本层 | PDFKit | 本机实验 |
| Vision | 中英文 OCR | 首次调用可能很慢 | Vision | Covio 已使用 |
| Vision | 图片本地处理 | 不是通用视觉描述模型 | Vision | 本机实验 |
| Qwen3-VL | 文本、代码和图片理解 | 小模型会受提示注入影响 | MLX 或 llama.cpp | 本机实验 |
| FileManager | 同目录改名 | 需额外保证不覆盖 | Foundation | 需新增 |
| NaturalLanguage | 本地语言识别 | 短文本可能误判 | NaturalLanguage | 需验证 |

## 候选方案

| 方案 | 成本 | 风险 | 成熟度 | 可维护性 | 判断 |
| --- | --- | --- | --- | --- | --- |
| MLX Swift + Qwen3-VL 4 bit | 中 | 缺少 Metal Toolchain 时不能构建 | 中高 | 高 | 主方案 |
| llama.cpp + Qwen3-VL GGUF | 中 | 需要 C++ 库或本地服务生命周期 | 高 | 中 | 备选 |
| Ollama 外部服务 | 低代码成本 | 依赖用户安装和守护进程 | 高 | 低 | 不采用 |
| Core ML 转换 | 高 | 转换、兼容和视觉模型支持成本高 | 中 | 中 | 暂缓 |
| FoundationModels | 低资产成本 | 依赖系统模型、可用性和能力集合 | 中 | 中 | 可选增强 |
| 只用 OCR，不用 LLM | 低 | 无法处理无字图片和语义主题 | 高 | 高 | 不满足范围 |

`PyTorch`、`Transformers` 和 Python 运行时不作为产品依赖。
它们会扩大安装体积和供应链。

## 目标产品源码分析

| 观察 | 影响 |
| --- | --- |
| Swift 应用只构建 `arm64` | 可优先使用 Apple Silicon 专属运行时 |
| 部署目标是 macOS 26 | 可使用较新的 Swift 和系统能力 |
| 已有 Vision OCR | 图片文本提取可以复用 |
| 没有 PDFKit 提取模块 | PDF 文本层需要新模块 |
| 工作区只保存副本 | 自动命名必须直接处理用户选择的原文件 |
| 配置文件已有稳定入口 | 可增加命名配置，但要保持旧配置兼容 |
| KMP 已有共享逻辑 | 模板、校验和冲突规则适合放在 KMP |
| 没有 App Sandbox 配置 | 首版可直接访问用户选择的文件 |
| 没有 hardened runtime | 产品签名和模型库权限仍需重新设计 |

## 参考实现分析

| 项目 | 许可证 | 可复用点 | 不可直接复用点 |
| --- | --- | --- | --- |
| [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm/blob/48114eedf3c3d4a682a6b1d644cc5af5c2945d10/Libraries/MLXVLM/README.md#L10-L85) | MIT | Swift VLM、模型加载、引导生成 | MLX 构建需要 Metal Toolchain |
| [LocalLLMClient](https://github.com/tattn/LocalLLMClient/blob/b68f71244baf308469a190cce4f54edf2fde4887/README.md#L37-L43) | MIT | GGUF/MLX Swift API、多模态实验接口 | 多模态 API 仍标记为实验性 |
| [Sidekick](https://github.com/johnbean393/Sidekick/blob/83b3e6e0d8d6831a890e4df73435a3987b086e20/Sidekick/Logic/Inference/Model+Lifecycle.swift#L22-L35) | MIT | 本地模型预热、主模型与工作模型分离 | 进程和服务生命周期复杂 |
| [AI File Sorter](https://github.com/hyperfield/ai-file-sorter/blob/4eaccb878b09af198392f23b2fc1144640293a1a/app/lib/UndoManager.cpp#L24-L72) | AGPL-3.0 | 预览、校验、撤销记录和身份检查思路 | 许可证不适合直接复制到 MIT 项目 |
| [ollama-rename-files](https://github.com/octrow/ollama-rename-files/blob/cf4c299cc8f9b1284b22bd836b8e1585a814ae6d/src/ollama_rename_files/rename_files.py#L29-L83) | MIT | 提示词、清洗、备份和唯一名称 | 只读文本，不覆盖 PDF 和图片 |
| [ai-renamer](https://github.com/ozgrozer/ai-renamer/blob/f45d4f64cb14d33f5791e573c54843029ccb55b7/src/getNewName.js#L8-L41) | GPL-3.0 | 多类型处理思路 | 无预览、无撤销，许可证不兼容 |
| [MDFlux](https://github.com/ibrahimqureshae/mdflux/blob/00c602534cf3a23174ef48f12d44ba00036d3398/README.md#L73-L105) | MIT | OCR 与纯文本路径的成本对比 | 产品范围是 Windows/Linux 文档转换 |

## 主要发现

1. `Qwen3-VL-2B-Instruct` 能处理中文文本、Swift 代码、报销截图和扫描 PDF 页面。
2. 文本和代码的热运行约 1 到 2 秒。
3. GGUF 图片直接走 VLM 约 7.8 秒。
4. 扫描 PDF 页面直接走 VLM 约 15 秒。
5. 扫描 PDF 先走 Vision OCR 约 0.45 秒。
6. 文本模型峰值内存约 1.7 GB。
7. 图片和 PDF 页面峰值内存约 2.6 到 2.9 GB。
8. 模型会接受文件内容中的恶意指令。
9. 模型会误判日期、语言和置信度。
10. MLX Swift 已通过 Xcode 构建并在本机运行。
11. 直接 `swift build` 仍受 Metal shim 影响。
12. MLX 热文本生成约 1.19 秒，热图片生成约 1.63 秒。
13. MLX 文本和图片峰值内存约 1.94 到 1.99 GB。

## 反证和限制

- 小模型标题可能只复述类型名。
- 文件内容可以诱发提示注入。
- 模型自报的置信度没有校准。
- 模型自报的语言和日期不可靠。
- 图像编码时间与图片分辨率和 token 预算有关。
- PDF 页面直接走 VLM 比 OCR 慢很多。
- 扫描 PDF 样例只有一页，不代表复杂文档。
- 现有测试未覆盖真实用户文件。
- 未在 Covio 工程内完成 MLX Swift 运行时基准。
- 未实现 Covio 产品内的重命名事务。

## 已知缺口

1. 未把 MLX Swift 接入 Covio Xcode 工程。
2. 直接 `swift build` 仍调用旧 Metal shim。
3. 未验证 8 GB Mac。
4. 未验证复杂 PDF、表格和手写内容。
5. 未验证多语言文件名质量。
6. 未验证应用签名、硬件运行时和 hardened runtime。
7. 未建立 12 个样例的正式验收集。
8. 未验证真实文件系统上的原子重命名封装。
9. 未验证撤销计划在外部修改时的行为。
