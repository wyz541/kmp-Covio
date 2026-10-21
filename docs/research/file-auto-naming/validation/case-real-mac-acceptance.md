# Case 7：真实 Mac 12 样本验收

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 通过，8 GB 硬件项由 #185 跟踪 |
| 执行时间 | 2026-10-21 |
| 机器 | MacBookPro18,2，Apple M1 Max，64 GB |
| 系统 | macOS 27.0.1，build 26A434 |
| 安装包 | `Covio-0.5.0.dmg` |
| 模型 | `Qwen3-VL-2B-Instruct-4bit` |

[返回验证目录](README.md)

[证据附录](../evidence.md)

[主题索引](../README.md)

## 验证目标

1. 使用真实安装包和真实模型运行 12 个合成样本。
2. 覆盖中文、英文、代码、文本 PDF、扫描 PDF、图片、混合文件和失败输入。
3. 验证预览期间不改文件。
4. 验证提示注入只影响建议，不触发自动写入。
5. 验证重命名、撤销和恢复错误码。
6. 记录冷启动、热运行、峰值内存和取消延迟。
7. 验证安装包在拒绝网络时完成全部流程。

## 执行命令

```bash
COVIO_FILE_NAMING_ACCEPTANCE=1 \
  bash scripts/verify-file-naming-bundle.sh dist/Covio-0.5.0.dmg
```

验收器只在安装包内运行。
验收器使用独立支持目录和临时目录。
文件在分析完成前保持原名。

## 12 样本结果

| 样本 | 类型 | 结果 | 建议名称或错误码 |
| --- | --- | --- | --- |
| `zh.txt` | 中文文本 | ready | `2026年第四季度产品预算评审.txt` |
| `injection.txt` | 英文提示注入 | ready，禁止默认勾选 | 显示 `promptInjection` 风险 |
| `policy.swift` | Swift 代码 | ready | `结构体RetryPolicy.swift` |
| `report.kt` | Kotlin 代码 | ready | `WeeklyReport.kt` |
| `text-report.pdf` | 文本 PDF | ready | `Quarterly Product Budget Review Offline file naming research and validation.pdf` |
| `scanned-report.pdf` | 扫描 PDF | ready | `项目周报.pdf` |
| `receipt.png` | 含文字图片 | ready | `差旅报销单.png` |
| `abstract.png` | 无文字抽象图 | blocked | 低可信，保留原名 |
| `mixed.sample` | 混合结构信号 | ready | `项目更新.sample` |
| `empty.txt` | 空文件 | blocked | `emptyContent` |
| `oversized.txt` | 超限文本 | blocked | `truncatedInput`，保留原名 |
| `damaged.pdf` | 损坏 PDF | blocked | `pdfUnreadable` |

结果汇总：

1. 7 个 ready 样本完成重命名。
2. 7 个重命名全部撤销。
3. 5 个 blocked 样本保留原名。
4. 提示注入样本带风险，默认不勾选。
5. 抽象图没有猜造内容。
6. 空文件、超限文本和损坏 PDF 有稳定结果。

## 性能

| 指标 | 结果 | 门槛 |
| --- | --- | --- |
| 模型加载 | `711.8` ms | 记录 |
| 预热 | `1,228.8` ms | 记录 |
| 12 样本总分析 | `18,525.2` ms | 记录 |
| 文本和代码最大热生成 | `457.8` ms | ≤ `3,000` ms |
| 图片最大热生成 | `1,847.4` ms | ≤ `10,000` ms |
| PDF 最大热生成 | `2,406.7` ms | ≤ `15,000` ms |
| 取消延迟 | `593.7` ms | 记录 |
| 峰值 RSS | `2,339,962,880` bytes | ≤ `4 GiB` |

峰值 RSS 约 `2.34 GB`。

## 安全与恢复

| 场景 | 结果 | 错误码 |
| --- | --- | --- |
| 同名目标 | 通过，未覆盖 | `targetExists` |
| 预览后文件变化 | 通过，未改名 | `fileChanged` |
| 部分失败 | 通过，保留成功条目 | `targetExists` |
| 目录只读 | 通过，未改名 | `permissionDenied` |
| 大小写冲突 | 通过，未覆盖 | `targetExists` |
| 撤销前外部修改 | 通过，拒绝撤销 | `undoConflict` |

提示注入样例生成了由注入文本构成的建议名称。
预览显示 `promptInjection`。
该项默认不勾选。
分析阶段没有改名。
只有用户明确选中并确认后才可能应用。

## 离线验证

命令在拒绝网络访问的 `sandbox-exec` 中运行。
结果：

```text
offline_bundle_verification=pass
smoke_processes=1
non_loopback_network_rows=0
```

## 未通过或未执行项

本轮机器是 64 GB。
7 GB Apple Silicon 低内存验收由 [Case 8](case-constrained-mac-acceptance.md) 单独记录。
Case 8 的硬件约束低于 8 GB 产品门槛。
Case 8 已通过全部功能、内存、延迟和安全门槛。

## 清理记录

1. 验收文件和撤销计划位于临时目录。
2. 安装副本已删除。
3. DMG 已卸载。
4. 验收结束后没有模型或 Covio 进程残留。
5. 测试未使用用户私有文件。

## 关联文档

- [安全重命名](case-safe-rename.md)
- [内置模型打包](case-packaging.md)
- [验证目录](README.md)
- [8 GB 硬件验收 #185](https://github.com/wyz541/kmp-Covio/issues/185)
