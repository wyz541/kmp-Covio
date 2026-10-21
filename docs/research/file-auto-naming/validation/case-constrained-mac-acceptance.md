# Case 8：7 GB Apple Silicon 低内存验收

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 通过 |
| 执行时间 | 2026-10-21 |
| 机器 | Apple Virtual Machine 1，Apple M1 (Virtual) |
| 型号 | `VirtualMac2,1` |
| CPU | 3 核 |
| 内存 | 7 GB，`7,516,192,768` bytes |
| 系统 | macOS 26.6.2，build 25G83 |
| 模型 | `Qwen3-VL-2B-Instruct-4bit` |
| 模型 revision | `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |

[返回验证目录](README.md)

[返回主题索引](../README.md)

## 目标

在低于 8 GB 产品门槛的 Apple Silicon 环境运行完整验收。  
本轮运行器是 GitHub Actions 的 `macos-26` M1 虚拟 Mac。  
机器只有 3 核和 7 GB 内存。  
该环境比 8 GB 物理 Mac 更受约束。

## 执行命令

```bash
COVIO_FILE_NAMING_ACCEPTANCE=1 \
  bash scripts/verify-file-naming-bundle.sh dist/Covio.app
```

工作流文件是 `.github/workflows/file-naming-acceptance.yml`。  
工作流先下载固定模型并校验 SHA-256。  
然后构建安装包并在拒绝网络的沙箱中运行验收。

## 性能优化

本轮同时调整了视觉输入策略。

1. OCR 文本达到 24 个字符时，图片和扫描 PDF 只走文本模型。
2. 没有可用 OCR 文本时，才把图片送入 VLM。
3. 视觉输入最大尺寸收紧到 `448 × 448`。

优化前后的 7 GB 运行结果如下。

| 指标 | 优化前 | 优化后 | 门槛 |
| --- | ---: | ---: | ---: |
| 图片最大热生成 | `10,696.6` ms | `1,263.4` ms | ≤ `10,000` ms |
| PDF 最大热生成 | `22,156.2` ms | `1,350.2` ms | ≤ `15,000` ms |
| 峰值 RSS | `1,184,317,440` bytes | `798,359,552` bytes | ≤ `4 GiB` |

## 12 样本结果

| 样本 | 类型 | 结果 |
| --- | --- | --- |
| `zh.txt` | 中文文本 | ready |
| `injection.txt` | 提示注入 | ready，显示 `promptInjection`，默认不勾选 |
| `policy.swift` | Swift 代码 | ready |
| `report.kt` | Kotlin 代码 | ready |
| `text-report.pdf` | 文本 PDF | ready |
| `scanned-report.pdf` | 扫描 PDF | ready |
| `receipt.png` | 含文字图片 | ready |
| `abstract.png` | 无文字抽象图 | blocked，低可信 |
| `mixed.sample` | 混合结构 | ready |
| `empty.txt` | 空文件 | blocked，`emptyContent` |
| `oversized.txt` | 超限文本 | blocked，`truncatedInput` |
| `damaged.pdf` | 损坏 PDF | blocked，`pdfUnreadable` |

结果汇总：

1. 7 个已选样本完成重命名。
2. 7 个重命名全部撤销。
3. 提示注入样本保留为 ready，并显示风险。
4. 4 个 blocked 样本保留原名。
5. 抽象图没有生成建议名称。
6. 所有恢复场景通过。

## 性能

| 指标 | 结果 | 门槛 |
| --- | ---: | ---: |
| 模型加载 | `3,363.0` ms | 记录 |
| 预热 | `8,607.3` ms | 记录 |
| 12 样本总分析 | `45,483.9` ms | 记录 |
| 文本和代码最大热生成 | `1,550.5` ms | ≤ `3,000` ms |
| 图片最大热生成 | `1,263.4` ms | ≤ `10,000` ms |
| PDF 最大热生成 | `1,350.2` ms | ≤ `15,000` ms |
| 取消延迟 | `5,554.5` ms | 记录 |
| 峰值 RSS | `798,359,552` bytes | ≤ `4 GiB` |

## 安全与恢复

| 场景 | 结果 |
| --- | --- |
| 同名目标 | 通过，未覆盖 |
| 预览后文件变化 | 通过，未改名 |
| 部分失败 | 通过 |
| 目录只读 | 通过，未改名 |
| 大小写冲突 | 通过，未覆盖 |
| 撤销前外部修改 | 通过，拒绝撤销 |

## 离线和硬件

```text
physical_memory_bytes=7516192768
offline_bundle_verification=pass
smoke_processes=1
non_loopback_network_rows=0
```

全部硬件和性能门槛通过。

## 结论

7 GB Apple Silicon 虚拟 Mac 通过完整验收。  
其内存低于 8 GB 产品门槛，CPU 也少于常规 8 GB Mac。  
因此 8 GB Apple Silicon Mac 的最低内存结论从 `pending` 改为 `supported`。  
当前结论不覆盖 M5 性能和复杂表格、手写文本或大规模压测。

## 清理记录

1. 工作流在临时目录生成合成样本。
2. 验收结束后删除模型、构建输入、安装副本和临时文件。
3. 上传产物只包含验收日志。
4. 测试未使用用户私有文件。

## 关联文档

- [真实 Mac 12 样本验收](case-real-mac-acceptance.md)
- [验证目录](README.md)
- [8 GB 硬件验收 #185](https://github.com/wyz541/kmp-Covio/issues/185)
- [持续验收工作流](../../../../.github/workflows/file-naming-acceptance.yml)
