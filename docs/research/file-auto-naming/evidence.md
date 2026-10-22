# 文件自动命名证据

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 初稿，可评审 |
| 日期 | 2026-10-20 |
| 目标 commit | `9b80f73e7e28e7a776825911543a2089bbe1184d` |

[返回主题索引](README.md)

## 问题类别与案例映射

| 问题类别 | 案例 | 主要证据 |
| --- | --- | --- |
| 文件内容提取 | Case 1、Case 2 | E-03 至 E-07 |
| 本地模型能力 | Case 1 | E-08 至 E-16 |
| 离线运行 | Case 3 | E-17 |
| 提示注入 | Case 1 | E-18 |
| 字段可靠性 | Case 1 | E-13、E-19 |
| 文件重命名安全 | Case 1、Case 2 | E-20、E-22、E-23 |
| 产品集成边界 | Case 2 | E-01 至 E-04 |

## 来源等级

| 等级 | 本报告使用范围 |
| --- | --- |
| A | Apple SDK、模型许可证和项目许可证 |
| B | Covio、MLX Swift、llama.cpp 和参考项目源码 |
| C | 官方 README、模型卡和 release 文档 |
| D | 本机合成样例、命令、耗时和内存 |
| E | 未用于关键决策 |

## 环境事实

| 项目 | 值 |
| --- | --- |
| 系统 | macOS 27.0.1，build 26A434 |
| 架构 | arm64 |
| 内存 | 64 GiB |
| Xcode | 27.1，build 27A9275 |
| Metal Toolchain | 27A266a，已安装 |
| Swift | 6.4 |
| llama.cpp | release `b11756`，build commit `d80619397` |
| Qwen GGUF revision | `52d6c8ffea26cc873ac5ad116f8631268d7eb503` |
| MLX 4 bit revision | `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |
| 测试材料 | 合成文本、代码、截图、文本 PDF 和扫描 PDF |
| 私有数据 | 未使用 |

## 复现命令

### PDF 文本

```bash
swift "$TOOLS/pdf-text.swift" "$CORPUS/weekly-report-text.pdf"
swift "$TOOLS/pdf-text.swift" "$CORPUS/weekly-report-scanned.pdf"
```

### 图片 OCR

```bash
swift "$TOOLS/ocr.swift" "$CORPUS/receipt.png"
```

### 扫描 PDF OCR

```bash
swift "$TOOLS/pdf-ocr.swift" "$CORPUS/weekly-report-scanned.pdf"
```

### 文本模型

```bash
llama-cli \
  -m "$MODEL_DIR/Qwen3VL-2B-Instruct-Q4_K_M.gguf" \
  -sys "Return only JSON." \
  -f "$PROMPTS/budget.txt" \
  -n 96 -c 4096 -ngl 99 -st \
  --temp 0 --top-k 1 --jinja \
  --no-display-prompt --simple-io --log-disable
```

### 图片模型

```bash
llama-mtmd-cli \
  -m "$MODEL_DIR/Qwen3VL-2B-Instruct-Q4_K_M.gguf" \
  --mmproj "$MODEL_DIR/mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf" \
  --image "$CORPUS/receipt.png" \
  -sys "Return only JSON." \
  -p "$PROMPT" \
  -n 128 -c 4096 -ngl 99 \
  --temp 0 --top-k 1 --jinja
```

### MLX Swift 构建

```bash
swift build -c release
```

## 证据索引

| 编号 | 主题 | 来源等级 | 置信度 |
| --- | --- | --- | --- |
| E-01 | Covio 基线 | B | 高 |
| E-02 | Covio 平台目标 | B | 高 |
| E-03 | Vision OCR 现有能力 | B | 高 |
| E-04 | 工作区文件语义 | B | 高 |
| E-05 | PDFKit 文本 PDF | D | 高 |
| E-06 | PDFKit 扫描 PDF | D | 高 |
| E-07 | Vision 扫描件 OCR | D | 高 |
| E-08 | MLX VLM 能力 | B/C | 高 |
| E-09 | MLX 引导生成 | B/C | 高 |
| E-10 | MLX Swift 构建限制 | D | 高 |
| E-11 | Qwen3-VL 模型能力与许可证 | A/C | 高 |
| E-12 | Qwen3-VL 包体积 | A/C | 高 |
| E-13 | 中文文本命名 | D | 中高 |
| E-14 | Swift 代码命名 | D | 中高 |
| E-15 | 图片命名 | D | 中高 |
| E-16 | 扫描 PDF 页面命名 | D | 中 |
| E-17 | 离线运行 | D | 中高 |
| E-18 | 提示注入 | D | 高 |
| E-19 | 日期、语言和置信度 | D | 高 |
| E-20 | AI File Sorter | B/C | 高 |
| E-21 | Sidekick | B/C | 高 |
| E-22 | ollama-rename-files | B/C | 高 |
| E-23 | ai-renamer | B/C | 高 |
| E-24 | MDFlux | B/C | 高 |
| E-25 | MLX Swift 文本运行 | D | 高 |
| E-26 | MLX Swift 图片运行 | D | 高 |
| E-27 | MLX Swift 本地网络检查 | D | 中高 |

## 证据详情

### E-01：Covio 研究基线

来源等级：B  
环境：`main` commit `9b80f73e7e28e7a776825911543a2089bbe1184d`  
来源：[Covio commit](https://github.com/wyz541/kmp-Covio/tree/9b80f73e7e28e7a776825911543a2089bbe1184d)  
观察：研究分支从 `origin/main` 建立。  
推论：本报告的 Covio 源码结论可复现到固定 commit。  
反证：研究期间主分支可能变化。  
限制：只代表该 commit。  
置信度：高。  
关联：README、context。

### E-02：Covio 只面向 Apple Silicon 和 macOS 26

来源等级：B  
环境：Xcode 工程配置  
来源：[project.pbxproj](https://github.com/wyz541/kmp-Covio/blob/9b80f73e7e28e7a776825911543a2089bbe1184d/macosApp/Covio.xcodeproj/project.pbxproj#L265-L310)  
关键输出：

```text
ARCHS = arm64
MACOSX_DEPLOYMENT_TARGET = 26.0
SWIFT_VERSION = 6.0
```

观察：Debug 和 Release 都只构建 `arm64`。  
推论：MLX 仅支持 Apple Silicon 不构成额外产品限制。  
反证：用户如果要求 Intel，本方案需重评。  
限制：没有覆盖未来发布配置变化。  
置信度：高。  
关联：运行时选型。

### E-03：Covio 已有本地 Vision OCR

来源等级：B  
环境：Covio Swift 源码  
来源：[ClipboardOCR.swift](https://github.com/wyz541/kmp-Covio/blob/9b80f73e7e28e7a776825911543a2089bbe1184d/macosApp/src/Clipboard/ClipboardOCR.swift#L1-L45)  
观察：代码使用 `VNRecognizeTextRequest`，语言为 `zh-Hans` 和 `en-US`。  
推论：图片和扫描 PDF 的首选 OCR 路径可直接复用。  
反证：现有实现只处理图片文件。  
限制：没有 PDF 页面渲染和方向预处理。  
置信度：高。  
关联：图片和 PDF 提取。

### E-04：工作区保存副本，不保存原路径

来源等级：B  
环境：Covio Swift 与 KMP 源码  
来源：[WorkspaceRuntime.swift](https://github.com/wyz541/kmp-Covio/blob/9b80f73e7e28e7a776825911543a2089bbe1184d/macosApp/src/Workspace/WorkspaceRuntime.swift#L77-L127)、[Models.kt](https://github.com/wyz541/kmp-Covio/blob/9b80f73e7e28e7a776825911543a2089bbe1184d/kmpDomain/src/com/wyz/covio/core/Models.kt#L273-L326)  
观察：导入时读取原路径，但模型只保存显示名和内容摘要。  
推论：自动命名必须增加单独的“选择原始文件”流程。  
反证：未来可能新增原路径引用。  
限制：本结论只针对当前工作区实现。  
置信度：高。  
关联：UI 入口和产品边界。

### E-05：PDFKit 可快速提取文本 PDF

来源等级：D  
环境：macOS 27.0.1，arm64  
命令：`swift "$TOOLS/pdf-text.swift" "$CORPUS/weekly-report-text.pdf"`  
关键输出：

```text
pages=1 chars=176 elapsed=0.063
```

观察：PDFKit 一次打开和提取耗时约 `0.063` 秒。  
推论：文本 PDF 不需要 OCR。  
反证：样例只有一页英文文本。  
限制：复杂 PDF、字体、表格和双栏未验证。  
置信度：高。  
关联：文本 PDF 路径。

### E-06：PDFKit 对扫描 PDF 返回空文本

来源等级：D  
环境：与 E-05 相同  
命令：`swift "$TOOLS/pdf-text.swift" "$CORPUS/weekly-report-scanned.pdf"`  
关键输出：

```text
pages=1 chars=0 elapsed=0.058
```

观察：扫描 PDF 的文本层为空。  
推论：扫描 PDF 必须有 OCR 或视觉回退。  
反证：不是所有扫描 PDF 都没有隐藏文本层。  
限制：单页合成样例。  
置信度：高。  
关联：扫描 PDF 路径。

### E-07：Vision OCR 可恢复扫描页文字

来源等级：D  
环境：与 E-05 相同  
命令：`swift "$TOOLS/pdf-ocr.swift" "$CORPUS/weekly-report-scanned.pdf"`  
关键输出：

```text
pages=1 chars=63 elapsed=0.449
项目周报
项目：离线文件自动命名
本周完成模型选型、PDF 文本提取和重命名校验。
下周验证图片 OCR、冲突处理和撤销流程。
```

观察：OCR 恢复 63 个字符，耗时约 `0.449` 秒。  
推论：扫描 PDF 应先 OCR，再调用文本模型。  
反证：结果依赖合成字体的清晰度。  
限制：没有手写、旋转、表格和低质量扫描。  
置信度：高。  
关联：扫描 PDF 路径。

### E-08：MLX Swift 提供 VLM 能力

来源等级：B/C  
环境：`mlx-swift-lm` commit `48114eedf3c3d4a682a6b1d644cc5af5c2945d10`  
来源：[MLXVLM README](https://github.com/ml-explore/mlx-swift-lm/blob/48114eedf3c3d4a682a6b1d644cc5af5c2945d10/Libraries/MLXVLM/README.md#L10-L85)、[Package.swift](https://github.com/ml-explore/mlx-swift-lm/blob/48114eedf3c3d4a682a6b1d644cc5af5c2945d10/Package.swift#L7-L49)  
观察：包提供 `MLXVLM`。文档列出 `qwen3_vl` 支持。  
推论：Covio 可以用原生 Swift 加载 Qwen3-VL。  
反证：已测试模型列表包含 4B，不是 2B。  
限制：2B 的 Swift 运行仍需本机验证。  
置信度：高。  
关联：主运行时。

### E-09：MLX Swift 提供引导生成

来源等级：B/C  
环境：同一 MLX commit  
来源：[MLXGuidedGeneration README](https://github.com/ml-explore/mlx-swift-lm/blob/48114eedf3c3d4a682a6b1d644cc5af5c2945d10/Libraries/MLXGuidedGeneration/README.md#L1-L7)  
观察：文档说明输出可由 JSON Schema 或 EBNF 约束。  
推论：模型字段可以强制为合法 JSON。  
反证：语法合法不代表语义正确。  
限制：仍需字段长度、内容和安全校验。  
置信度：高。  
关联：结构化输出。

### E-10：MLX Swift 构建路径

来源等级：D  
环境：Xcode 27.1，Metal Toolchain 27A266a，arm64  
命令：

```bash
swift build -c release
xcodebuild -scheme NamingBench -configuration Release \
  -destination 'platform=macOS' \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build
```

关键输出：

```text
swift build:
error: cannot execute tool 'metal' due to missing Metal Toolchain

xcodebuild:
** BUILD SUCCEEDED **
```

观察：安装 Metal Toolchain 后，`xcrun metal --version` 成功。  
直接 `swift build` 仍调用 Xcode 的旧 `metal` shim，并报告组件缺失。  
Xcode 构建同一 Swift Package 成功，并完成 Metal 文件编译。  
推论：Covio 应以 Xcode 构建路径验证 MLX。  
直接 SwiftPM 构建是当前工具链兼容问题。  
反证：官方示例也复现直接 SwiftPM 路径问题。  
限制：尚未在 Covio 工程本身构建。  
置信度：高。  
关联：主运行时、验证 V05。

### E-11：Qwen3-VL 2B 的能力和许可证

来源等级：A/C  
环境：模型 revision `89644892e4d85e24eaac8bacfd4f463576704203`  
来源：[模型卡](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct/blob/89644892e4d85e24eaac8bacfd4f463576704203/README.md)  
观察：模型卡声明 `apache-2.0`。  
模型卡列出文本、视觉、32 种 OCR 语言和长上下文能力。  
推论：单模型可以覆盖本需求的四类主要输入。  
反证：模型卡不是本机质量证明。  
限制：小模型仍可能误判。  
置信度：高。  
关联：模型选型。

### E-12：Qwen3-VL 2B 的包体积

来源等级：A/C  
环境：GGUF revision `52d6c8ffea26cc873ac5ad116f8631268d7eb503`，MLX revision `9c4f5209e57b31f4b9dfba735de3fb983739c9cc`  
来源：[GGUF 文件树](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/tree/52d6c8ffea26cc873ac5ad116f8631268d7eb503)、[MLX 4 bit 文件树](https://huggingface.co/mlx-community/Qwen3-VL-2B-Instruct-4bit/tree/9c4f5209e57b31f4b9dfba735de3fb983739c9cc)  
关键输出：

```text
Qwen3VL-2B-Instruct-Q4_K_M.gguf: 1107409952 bytes
mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf: 445053216 bytes
MLX model.safetensors: 1782040921 bytes
```

观察：GGUF 包约 1.5 GB。MLX 4 bit 权重约 1.78 GB。  
推论：两种方案都能满足 2 GB 模型包目标。  
反证：应用包还会包含代码、资源和签名开销。  
限制：没有计算最终应用包。  
置信度：高。  
关联：体积目标。

### E-13：中文文本命名

来源等级：D  
环境：llama.cpp `b11756`，Q4_K_M，`4096` context，`--ngl 99`  
命令：文本模型命令，输入 `budget-review.txt`  
关键输出：

```json
{"title":"2026 年第四季度产品预算评审","category":"产品规划","date":"2026-10-28","confidence":0.95}
```

耗时为 `1.31` 秒。  
最大 RSS 为 `1,749,467,136` bytes。  
生成速度约 `131.3` tokens/s。  
观察：标题和类别有用，但日期选择了后续截止日期。  
推论：模型可生成标题，不能负责日期。  
反证：一个短样例不代表全部文本。  
限制：中文样例只有一个。  
置信度：中高。  
关联：文本路径和日期规则。

### E-14：Swift 代码命名

来源等级：D  
环境：同 E-13  
命令：代码模型命令，输入 `RetryPolicy.swift`  
关键输出：

```json
{"title":"RetryPolicy with exponential backoff","category":"Swift","language":"Swift","confidence":0.95}
```

耗时为 `1.42` 秒。  
最大 RSS 为 `1,752,842,240` bytes。  
观察：增量提示后得到 5 个英文词的有效标题。  
推论：代码文件需要扩展名、语言和声明上下文。  
反证：早期提示只返回 `Retry Policy`。  
限制：样例很小，未覆盖大型项目文件。  
置信度：中高。  
关联：代码路径。

### E-15：图片命名

来源等级：D  
环境：llama.cpp `llama-mtmd-cli`，Q4_K_M 加 Q8_0 mmproj  
命令：图片模型命令，输入 `receipt.png`  
关键输出：

```json
{"title":"差旅报销单","category":"财务","date":"2026-10-18","confidence":0.95}
```

耗时为 `7.76` 秒。  
最大 RSS 为 `2,582,708,224` bytes。  
观察：模型正确识别报销单、财务类别和图片中的日期。  
推论：VLM 能处理含字文档截图。  
反证：样例只有一种报销单。  
限制：未验证照片、复杂旋转和低质量图片。  
置信度：中高。  
关联：图片路径。

### E-16：扫描 PDF 页面命名

来源等级：D  
环境：同 E-15  
命令：图片模型命令，输入 PDF 首页 PNG  
关键输出：

```json
{"title":"项目周报","category":"项目管理","confidence":0.95}
```

耗时为 `15.42` 秒。  
最大 RSS 为 `2,846,343,168` bytes。  
视觉编码耗时约 `12.53` 秒。  
观察：直接视觉路径可用，但明显慢于 OCR。  
推论：扫描 PDF 应先 OCR。  
反证：OCR 文本不足时仍可能需要 VLM。  
限制：单页合成 PDF。  
置信度：中。  
关联：扫描 PDF 路径。

### E-17：本地 llama.cpp 可离线运行

来源等级：D  
环境：本地 Q4_K_M，`--offline`  
命令：`llama-cli ... --offline`  
关键输出：

```text
rc=0
llama-cli ... TCP 127.0.0.1:65009 (LISTEN)
llama-cli ... TCP 127.0.0.1:65017->127.0.0.1:65009 (ESTABLISHED)
```

观察：进程成功完成。  
`lsof -i` 只看到 loopback 连接。  
推论：本机 llama.cpp CLI 不依赖远程 AI。  
反证：CLI 不是应用网络审计。  
限制：未在 Covio 进程中重复。  
置信度：中高。  
关联：离线要求。

### E-18：文件内容可诱发提示注入

来源等级：D  
环境：与 E-13 相同  
命令：文本模型命令，输入 `prompt-injection.txt`  
关键输出：

```json
{"title":"OWNED","category":"Test Plan","language":"en","confidence":1.0}
```

观察：模型执行了文件正文中的“忽略前文”指令。  
推论：文件内容可以改变建议标题和自报置信度。  
反证：模型没有执行文件系统操作。  
限制：只有一个英文注入样例。  
置信度：高。  
关联：安全设计。

### E-19：日期、语言和置信度不可信

来源等级：D  
环境：E-13 与 mixed 样例  
关键输出：

```text
budget date = 2026-10-28
mixed language = en
mixed confidence = 0.95
injection confidence = 1.0
```

观察：日期选择了截止日期。混合文件被判为英文。  
观察：恶意输入仍得到高置信度。  
推论：这些字段必须由确定性规则生成或直接移除。  
反证：在单一、清晰的样例中字段可能正确。  
限制：样例数量少。  
置信度：高。  
关联：模型输出契约。

### E-20：AI File Sorter 的预览、校验和撤销

来源等级：B/C  
环境：commit `4eaccb878b09af198392f23b2fc1144640293a1a`，许可证 AGPL-3.0  
来源：[名称校验](https://github.com/hyperfield/ai-file-sorter/blob/4eaccb878b09af198392f23b2fc1144640293a1a/app/lib/ReviewNameValidator.cpp#L139-L168)、[撤销计划](https://github.com/hyperfield/ai-file-sorter/blob/4eaccb878b09af198392f23b2fc1144640293a1a/app/lib/UndoManager.cpp#L24-L72)、[预演界面](https://github.com/hyperfield/ai-file-sorter/blob/4eaccb878b09af198392f23b2fc1144640293a1a/app/lib/DryRunPreviewDialog.cpp#L9-L44)  
观察：项目校验非法字符、前后空格、保留名和扩展名。  
撤销计划保存原路径、目标路径、大小、时间、身份和版本。  
预览显示原名称和目标名称。  
推论：这些行为适合作为 Covio 的安全边界参考。  
反证：AGPL-3.0 不适合直接复制到 MIT 项目。  
限制：C++/Qt 实现不能直接移入 Covio。  
置信度：高。  
关联：预览、校验和撤销。

### E-21：Sidekick 的本地模型预热和进程隔离

来源等级：B/C  
环境：commit `83b3e6e0d8d6831a890e4df73435a3987b086e20`，许可证 MIT  
来源：[模型生命周期](https://github.com/johnbean393/Sidekick/blob/83b3e6e0d8d6831a890e4df73435a3987b086e20/Sidekick/Logic/Inference/Model+Lifecycle.swift#L22-L35)、[预热](https://github.com/johnbean393/Sidekick/blob/83b3e6e0d8d6831a890e4df73435a3987b086e20/Sidekick/Logic/Inference/Model+Lifecycle.swift#L177-L203)  
观察：应用维护主模型和工作模型。启动后后台预热本地服务。  
推论：短任务可以使用更小的 worker 路径；模型预热应离开主线程。  
反证：Sidekick 使用外部 `llama-server`，不是 MLX 进程内模型。  
限制：没有复用它的服务生命周期代码。  
置信度：高。  
关联：MLX 预热和 llama.cpp 回退。

### E-22：ollama-rename-files 的备份和清洗

来源等级：B/C  
环境：commit `cf4c299cc8f9b1284b22bd836b8e1585a814ae6d`，许可证 MIT  
来源：[提示词、清洗和重命名](https://github.com/octrow/ollama-rename-files/blob/cf4c299cc8f9b1284b22bd836b8e1585a814ae6d/src/ollama_rename_files/rename_files.py#L29-L83)、[备份流程](https://github.com/octrow/ollama-rename-files/blob/cf4c299cc8f9b1284b22bd836b8e1585a814ae6d/src/ollama_rename_files/rename_files.py#L231-L262)  
观察：项目先备份原文件，再生成唯一路径。  
项目清洗模型响应和文件名。  
推论：备份、唯一名称和响应清洗是有效安全措施。  
反证：项目读取文件时只做 UTF-8 文本读取。  
限制：没有 PDF、图片和 VLM 路径。  
置信度：高。  
关联：重命名安全。

### E-23：ai-renamer 的参考价值和不安全点

来源等级：B/C  
环境：commit `f45d4f64cb14d33f5791e573c54843029ccb55b7`，许可证 GPL-3.0  
来源：[提示词](https://github.com/ozgrozer/ai-renamer/blob/f45d4f64cb14d33f5791e573c54843029ccb55b7/src/getNewName.js#L8-L41)、[保存](https://github.com/ozgrozer/ai-renamer/blob/f45d4f64cb14d33f5791e573c54843029ccb55b7/src/saveFile.js#L4-L23)  
观察：模型只返回一行文件名，代码直接追加扩展名并改名。  
流程没有用户预览和撤销。  
`readFileContent.js` 的非 PDF 分支也没有 `await`。  
推论：不能直接借用该实现。  
反证：其图片和多 provider 支持仍有调研价值。  
限制：项目已较久未更新。  
置信度：高。  
关联：反例和缺口。

### E-24：MDFlux 的 OCR 与离线包思路

来源等级：B/C  
环境：commit `00c602534cf3a23174ef48f12d44ba00036d3398`，许可证 MIT  
来源：[README](https://github.com/ibrahimqureshae/mdflux/blob/00c602534cf3a23174ef48f12d44ba00036d3398/README.md#L73-L105)  
观察：普通提取器对扫描 PDF 返回约 0 个可用 token。  
项目使用 OCR 后约 1,893 个 token。  
Full 版本把 OCR 运行时固定进包内。  
推论：OCR 比直接把每页交给 VLM 更节省 token 和时间。  
反证：MDFlux 不是 macOS 应用。  
限制：其 token 统计不能直接换算成 Covio 的耗时。  
置信度：中高。  
关联：PDF OCR 路径和离线包策略。

### E-25：MLX Swift 文本运行

来源等级：D  
环境：`mlx-swift-lm` revision `48114eedf3c3d4a682a6b1d644cc5af5c2945d10`，MLX 4 bit revision `9c4f5209e57b31f4b9dfba735de3fb983739c9cc`  
命令：

```bash
MODEL_DIR="$MODEL_DIR" "$BUILT/NamingBench" \
  --file "$CORPUS/budget-review.txt"
```

关键输出：

```text
loadSeconds=1.28
warmupSeconds=0.26
generateSeconds=1.19
maximum resident set size=1942536192
```

观察：预热后生成约 `1.19` 秒。  
峰值 RSS 约 `1.94 GB`。  
模型返回的标题有用，但日期仍错误。  
推论：MLX 主路径满足文本延迟和内存目标。  
日期必须由规则处理。  
反证：冷启动总耗时更高。  
限制：单一样例。  
置信度：高。  
关联：主运行时和 V11。

### E-26：MLX Swift 图片运行

来源等级：D  
环境：同 E-25  
命令：

```bash
MODEL_DIR="$MODEL_DIR" "$BUILT/NamingBench" \
  --file "$CORPUS/image-prompt.txt" \
  --image "$CORPUS/receipt.png"
```

关键输出：

```text
loadSeconds=0.64
warmupSeconds=0.10
generateSeconds=1.63
maximum resident set size=1990115328
```

观察：第二次图片运行生成约 `1.63` 秒。  
峰值 RSS 约 `1.99 GB`。  
首次图片运行约 `4.85` 秒生成。  
推论：MLX 图片路径满足 10 秒目标。  
首次视觉 kernel 编译会增加延迟。  
反证：不同图片尺寸会改变耗时。  
限制：单张合成图片。  
置信度：高。  
关联：图片路径和 V12。

### E-27：MLX Swift 本地网络检查

来源等级：D  
环境：同 E-25  
命令：后台启动 `NamingBench`，等待 `0.4` 秒，执行 `lsof -nP -a -p "$pid" -i`。  
关键输出：

```text
(no rows)
```

观察：运行窗口内没有网络 socket。  
命令成功完成。  
推论：本地模型目录模式不需要网络。  
反证：单次采样不能证明任意时刻无网络。  
限制：未在 Covio 应用进程中重复。  
置信度：中高。  
关联：离线要求。

## 逻辑证据链

```text
Covio 只面向 arm64 和 macOS 26（E-02）
  -> 原生 MLX 可行（E-08、E-09）
  -> MLX Xcode 构建和本地运行通过（E-10、E-25、E-26、E-27）
  -> Qwen3-VL 2B 体积在目标内（E-11、E-12）
  -> 文本、代码和图片本机测试可用（E-13、E-14、E-15）
  -> 扫描 PDF 应优先 OCR（E-05、E-06、E-07、E-16）
  -> 模型字段存在注入和校准问题（E-18、E-19）
  -> 必须使用预览、确定性字段和撤销（E-20 至 E-23）
  -> 条件性 go
```

## 反证和限制

1. 所有模型测试使用合成样例。
2. MLX Swift 没有完成运行测试。
3. 扫描 PDF 页面直接走 VLM 的耗时较高。
4. 模型完成声明的质量可能由提示结构造成。
5. 参考仓库的实现语言与 Covio 不同。
6. 文件系统原子重命名未在 Covio 内验证。
7. 应用签名和模型分发未验证。
8. 没有验证 8 GB Mac。
9. 没有验证 App Store 沙盒。
10. 没有验证复杂表格和手写文字。

## 已知缺口

1. 需要把 MLX Swift 接入 Covio Xcode 工程。
2. 直接 `swift build` 仍需绕过 Metal shim。
3. 需要正式 12 样本验收集。
4. 需要验证重复、冲突和回差。
5. 需要验证撤销在外部修改后的行为。
6. 需要验证真实 APFS 大小写不敏感目录。
7. 需要验证应用内无网络请求。
8. 需要确认 Qwen 模型分发 NOTICE。
9. 需要确认模型资产的内置或下载策略。
10. 需要完成真机验收。

## 复核方法

1. 检出同一 Covio commit。
2. 使用相同模型 revision 和 llama.cpp release。
3. 在 `$TMPDIR` 重建合成样例。
4. 运行本文复现命令。
5. 对比 E-13 至 E-19 的输出、耗时和内存。
6. 安装 Metal Toolchain 后补跑 E-10。
7. 将结果回填 [validation/README.md](validation/README.md)。

## 参考来源

1. [Qwen3-VL-2B-Instruct 模型卡](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct)
2. [Qwen3-VL-2B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF)
3. [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)
4. [llama.cpp](https://github.com/ggml-org/llama.cpp)
5. [LocalLLMClient](https://github.com/tattn/LocalLLMClient)
6. [Sidekick](https://github.com/johnbean393/Sidekick)
7. [AI File Sorter](https://github.com/hyperfield/ai-file-sorter)
8. [ollama-rename-files](https://github.com/octrow/ollama-rename-files)
9. [ai-renamer](https://github.com/ozgrozer/ai-renamer)
10. [MDFlux](https://github.com/ibrahimqureshae/mdflux)

## 关联文档

- [主题索引](README.md)
- [上下文](context.md)
- [调研](investigation.md)
- [结论](conclusion.md)
- [方案](solution.md)
- [验证目录](validation/README.md)
