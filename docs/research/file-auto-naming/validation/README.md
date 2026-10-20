# 文件自动命名验证

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 执行中 |
| 日期 | 2026-10-20 |

[返回主题索引](../README.md)  
[证据附录](../evidence.md)

## 案例索引

| 案例 | 状态 | 文件 |
| --- | --- | --- |
| Case 1：本地模型质量、耗时和安全 | 部分通过 | [case-local-model-smoke.md](case-local-model-smoke.md) |
| Case 2：MLX Swift 构建 | 通过 | [case-mlx-swift-build.md](case-mlx-swift-build.md) |
| Case 3：本地运行网络检查 | 部分通过 | [case-local-runtime-network.md](case-local-runtime-network.md) |
| Case 4：MLX Swift 运行 | 通过 | [case-mlx-swift-runtime.md](case-mlx-swift-runtime.md) |
| Case 5：安全预览与重命名 | 通过 | [case-safe-rename.md](case-safe-rename.md) |

## 验证目标

1. 验证模型能处理必须覆盖的文件类型。
2. 验证模型包和峰值内存符合目标。
3. 验证扫描 PDF 和图片的提取路径。
4. 验证离线运行时没有远程 AI 请求。
5. 验证提示注入不能控制系统。
6. 验证 MLX Swift 能在目标开发环境构建。
7. 验证最终重命名不覆盖文件。
8. 验证重命名可以撤销。

## 范围内事项

1. 合成文本。
2. 合成代码文件。
3. 合成图片。
4. 合成文本 PDF。
5. 合成扫描 PDF。
6. 本地模型 CLI。
7. MLX Swift 构建。
8. APFS 同目录重命名测试。

## 范围外事项

1. 用户私有文件。
2. 真实云盘或网络卷。
3. 远程 AI 服务。
4. App Store 沙盒发布。
5. Intel Mac。
6. 音频和视频。
7. 模型训练或微调。
8. 大规模生产压测。

## 当前事实

1. Qwen3-VL 2B GGUF CLI 已运行。
2. 文本和代码峰值内存约 1.75 GB。
3. 图片峰值内存约 2.58 GB。
4. 扫描 PDF 页面峰值内存约 2.85 GB。
5. 文件内容可以触发提示注入。
6. MLX Swift 已通过 Xcode 构建路径。
7. Covio 已离线完成文本和图片命名。
8. 峰值 RSS 约 2.26 GB。
9. Covio 产品内预览、原子重命名和撤销已实现。

## 成功标准

1. 文本、PDF、图片和代码都有可复现路径。
2. 未知或低可信输入有明确拒绝条件。
3. 模型包不大于 2 GB。
4. 峰值内存不大于 4 GB。
5. 文本和代码热运行不超过 3 秒。
6. 图片热运行不超过 10 秒。
7. 扫描 PDF 热运行不超过 15 秒。
8. 离线运行时没有非 loopback 网络连接。
9. 提示注入不能引发工具或文件系统动作。
10. MLX Swift 在目标环境构建成功。
11. 重命名冲突不覆盖。
12. 撤销可以恢复原名称。

## 前置条件

1. macOS 26 或更高版本。
2. Apple Silicon。
3. Xcode 和 Swift 工具链。
4. 首版需要 Xcode Metal Toolchain。
5. 本地模型 revision 固定。
6. 合成语料固定。
7. 不包含用户数据。
8. 所有临时文件放在 `$TMPDIR`。

## 风险

| 风险 | 后果 | 控制 |
| --- | --- | --- |
| 提示注入 | 错误文件名 | 预览、字段限制和人工审查 |
| 模型内存高 | 影响其他应用 | 4 GB 门槛和内存监控 |
| OCR 冷启动慢 | 首次操作卡顿 | 后台预热 |
| 扫描 PDF 编码慢 | 用户等待 | OCR 优先 |
| 直接 SwiftPM Metal shim | 构建命令失败 | 使用 Xcode 构建并记录工具链 |
| 文件在预览后变化 | 错改名 | 身份、大小和时间复核 |
| 撤销记录冲突 | 恢复错误文件 | 拒绝该条撤销 |
| 部分样本偏差 | 结论过强 | 扩大验收集 |

## 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | 中文文本命名 | 部分通过 | [case-local-model-smoke.md](case-local-model-smoke.md) |
| V02 | Swift 代码命名 | 部分通过 | [case-local-model-smoke.md](case-local-model-smoke.md) |
| V03 | 图片命名 | 部分通过 | [case-local-model-smoke.md](case-local-model-smoke.md) |
| V04 | 扫描 PDF 命名 | 部分通过 | [case-local-model-smoke.md](case-local-model-smoke.md) |
| V05 | MLX Swift 构建 | 通过 | [case-mlx-swift-build.md](case-mlx-swift-build.md) |
| V06 | 本地运行网络检查 | 部分通过 | [case-local-runtime-network.md](case-local-runtime-network.md) |
| V07 | 提示注入防护 | 失败 | [case-local-model-smoke.md](case-local-model-smoke.md) |
| V08 | 原子重命名与冲突 | 通过 | [case-safe-rename.md](case-safe-rename.md) |
| V09 | 撤销和外部修改 | 通过 | [case-safe-rename.md](case-safe-rename.md) |
| V10 | Covio 真机验收 | 尚未执行 | 待创建 |
| V11 | MLX Swift 文本运行 | 通过 | [case-mlx-swift-runtime.md](case-mlx-swift-runtime.md) |
| V12 | MLX Swift 图片运行 | 通过 | [case-mlx-swift-runtime.md](case-mlx-swift-runtime.md) |
| V13 | MLX Swift 本地网络检查 | 部分通过 | [case-mlx-swift-runtime.md](case-mlx-swift-runtime.md) |
| V14 | Covio 文本和图片模型接入 | 通过 | [case-mlx-swift-runtime.md](case-mlx-swift-runtime.md) |
| V15 | Covio 进程网络采样 | 通过 | [case-mlx-swift-runtime.md](case-mlx-swift-runtime.md) |

## 证据要求

1. 记录系统版本、架构和工具版本。
2. 记录模型 revision。
3. 记录模型文件大小和 SHA-256。
4. 记录命令。
5. 记录实际输出。
6. 记录耗时和内存。
7. 记录失败和反例。
8. 不记录用户正文。
9. 不记录令牌。
10. 不把 CLI 结果写成应用结果。

## 清理步骤

1. 停止所有模型和 OCR 进程。
2. 删除临时模型缓存。
3. 删除合成样例。
4. 删除构建缓存。
5. 确认没有修改用户文件。
6. 确认没有后台进程。
7. 记录清理结果。

## 关联文档

- [主题索引](../README.md)
- [证据附录](../evidence.md)
- [推荐方案](../solution.md)
- [结论](../conclusion.md)
