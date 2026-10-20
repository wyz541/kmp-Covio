# Case 4：MLX Swift 运行

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 通过 |
| 执行时间 | 2026-10-20 至 2026-10-21 |
| 环境 | macOS 27.0.1，arm64，64 GiB |
| 模型 | `mlx-community/Qwen3-VL-2B-Instruct-4bit` |
| 运行器 | MLX Swift，`mlx-swift-lm` revision `48114eedf3c3d4a682a6b1d644cc5af5c2945d10` |

[返回验证目录](README.md)  
[证据附录](../evidence.md)  
[主题索引](../README.md)

## 验证目标

1. 验证 MLX Swift 可以加载 Qwen3-VL 2B。
2. 验证文本热生成延迟。
3. 验证图片热生成延迟。
4. 验证峰值内存。
5. 观察本地运行网络连接。

## 预检记录

| 项目 | 结果 |
| --- | --- |
| MLX Swift 构建 | 通过 |
| 模型目录 | 本地路径 |
| 文本模型 | Qwen3-VL 2B 4 bit |
| 图像模型 | 同一 VLM |
| Covio 接口 | `NamingModelPort` |
| Covio 运行时 | `MLXNamingModel` |
| 合成样例 | 通过 |
| 用户私有数据 | 未使用 |

模型 SHA-256：

```text
model.safetensors
4750d95a2162829e127a94e83ac350d498d02070aab216c4687da48804a06ffb
```

## 测试前采集

| 数据 | 值 |
| --- | --- |
| MLX 权重 | 1,782,040,921 bytes |
| 文本 context | 默认模型配置 |
| 最大生成 | 96 tokens |
| temperature | 0 |
| 图像缩放 | 1024 × 1024 |
| 预热 | 每个进程先执行一次短生成 |

## 执行步骤

### V11：文本

前置条件：MLX 模型目录和 `budget-review.txt` 存在。

命令：

```bash
MODEL_DIR="$MODEL_DIR" "$BUILT/NamingBench" \
  --file "$CORPUS/budget-review.txt"
```

预期结果：返回合法 JSON。

实际结果：

```json
{
  "title": "2026年第四季度AI文件整理功能预算评审",
  "category": "文档",
  "date": "2026-04-01",
  "confidence": 0.95
}
```

加载：`1.28` 秒。  
预热：`0.26` 秒。  
生成：`1.19` 秒。  
总耗时：`3.59` 秒。  
最大 RSS：`1,942,536,192` bytes。  
错误码：无。  
备注：日期错误，不能使用模型日期。

### V12：图片

前置条件：MLX 模型目录和 `receipt.png` 存在。

命令：

```bash
MODEL_DIR="$MODEL_DIR" "$BUILT/NamingBench" \
  --file "$CORPUS/image-prompt.txt" \
  --image "$CORPUS/receipt.png"
```

预期结果：识别报销单。

实际结果：

```json
{
  "title": "差旅报销单",
  "category": "文档",
  "date": "2026-10-18",
  "confidence": 0.95
}
```

加载：`0.64` 秒。  
预热：`0.10` 秒。  
生成：`1.63` 秒。  
总耗时：`2.41` 秒。  
最大 RSS：`1,990,115,328` bytes。  
错误码：无。  
备注：第一次图片运行生成耗时 `4.85` 秒，后续运行更快。

### V13：本地网络

前置条件：模型路径为本地目录。

命令：后台启动文本运行，并在 `0.4` 秒后执行 `lsof`。

实际结果：

```text
(no network rows)
```

观察：运行窗口内没有网络 socket。  
错误码：无。  
备注：这是一次采样，不是完整网络审计。

### V14：Covio 工程集成

前置条件：

1. `macosApp` 已接入固定 revision 的 `mlx-swift-lm`。
2. `COVIO_FILE_NAMING_MODEL_DIR` 指向本地模型目录。
3. 模型目录不进入 Git。

命令：

```bash
COVIO_FILE_NAMING_MODEL_DIR="$MODEL_DIR" \
  bash scripts/test-file-naming-model.sh
```

实际结果：

| 指标 | 值 |
| --- | --- |
| 模型文件 SHA-256 | `4750d95a2162829e127a94e83ac350d498d02070aab216c4687da48804a06ffb` |
| 模型加载 | `2,084.9` ms |
| 预热 | `14,411.5` ms |
| 文本热生成 | `1,667.9` ms |
| 图片热生成 | `2,591.7` ms |
| 文本输入 | `192` tokens |
| 文本输出 | `28` tokens |
| 图片输入 | `1,116` tokens |
| 图片输出 | `16` tokens |
| 峰值 RSS | `2,260,172,800` bytes |
| 文本结果 | `2026年第四季度产品预算评审` / `文档` |
| 图片结果 | `差旅报销单` / `财务` |

说明：

1. 预热包含首次 Metal 内核加载和 JSON Schema 编译。
2. 文本和图片结果都通过 `GuidedGenerationLoop` 返回合法 JSON。
3. 生成结果只含 `title` 和 `category`。
4. 日期、语言、置信度和路径不由模型生成。
5. 模型目录和结果文件只存在于任务临时工作区。

### V15：Covio 进程网络采样

前置条件：V14 运行期间，每秒定位 `task-176` 的 Covio 测试宿主。

命令：

```bash
lsof -nP -a -p "$PID" -i
```

实际结果：

```text
observed_process=1
network_sample=no_rows
```

说明：

1. 采样覆盖整个测试宿主进程生命周期。
2. 模型通过本地目录加载，没有传入下载器。
3. 这是一次采样，不是完整的全系统网络审计。
4. 正式安装包验收仍由 #178 和 #179 完成。

## 结果汇总

| 测试 | 状态 | 结论 |
| --- | --- | --- |
| V11 | 通过 | 文本热生成和内存符合目标 |
| V12 | 通过 | 图片热生成和内存符合目标 |
| V13 | 部分通过 | 原 CLI 网络采样未观察到 socket |
| V14 | 通过 | Covio 文本和图片都返回合法字段 |
| V15 | 通过 | Covio 测试宿主未观察到网络 socket |

## 清理记录

1. 测试进程已退出。
2. 用户文件未修改。
3. 模型和测试结果在任务临时目录。
4. 临时文件将在任务结束时清理。

## 更新规则

1. 模型 revision 变化时重跑全部步骤。
2. 提示或字段变化时重跑 V11 和 V12。
3. 引入应用沙盒或签名变化时重跑 V13。
4. 将新证据编号回填 [evidence.md](../evidence.md)。

## 关联文档

- [验证目录](README.md)
- [构建记录](case-mlx-swift-build.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
- [推荐方案](../solution.md)
