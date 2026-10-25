# macOS 安装包体积缩减

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | internal/local 验证通过；Draft 待审阅 |
| 日期 | `2026-10-26` |
| 适用对象 | 产品、研发、发布、测试和安全评审人员 |
| 当前结论 | 默认发布瘦 app 安装包。模型通过受控的首次使用下载交付。需要完全离线安装的用户使用可选大包。 |

## 前因

`Covio 0.5.2` 的 DMG 为 `1,538,632,192` bytes。
模型文件占 app 文件总量的 `98.10%`。
继续压缩 DMG 不能解决包体过大的问题。

问题定义、边界和成功标准见 [context.md](context.md)。

## 背景

当前发布脚本把 `Qwen3-VL-2B-Instruct-4bit` 放入 app 资源。
单个模型目录为 `1,798,035,956` bytes。
该决定来自 [ADR-0007](../../adr/adr-0007-offline-file-naming-model-package.md)。
ADR-0007 优先保证安装后直接离线使用。
新增需求要求降低默认安装包体积。
因此，本调研重新比较模型交付方式。

GitHub 方案、约束模型和候选矩阵见 [investigation.md](investigation.md)。

## 过程

本调研读取 Covio 发布脚本、模型清单、运行时和既有 ADR。
本调研检查本机已有的 `0.5.0` 发布 app 和 DMG。
本调研执行一个移除模型后的 DMG 体积探针。
本调研审计 GitHub 上的 `WhisperKit`、`swift-transformers`、`mlx-swift-examples`、`Sparkle`、`Dynamic Universal App` 和 `Stats`。
所有参考仓库固定到报告中的 commit、标签或 release。

环境、命令、输出和证据链见 [evidence.md](evidence.md)。

## 结果

Covio 的安装包问题不是 Swift 或 KMP 二进制过大。
实测非模型内容只有 `34,731,377` bytes。
移除模型后的临时 DMG 为 `10,877,952` bytes。
完整 DMG 是瘦 DMG 的约 `141.45` 倍。

全局最优方案是：

1. 默认 DMG 只包含 app。
2. app 在首次使用 AI 功能前下载固定 revision 的模型包。
3. app 校验文件大小、SHA-256、许可证和硬件档位。
4. 模型就绪后，AI 功能保持离线运行。
5. 需要无网络安装时，提供单独的可选离线整包。

完整结论、评分和限制见 [conclusion.md](conclusion.md)。

## 实施验证

内部渠道已经生成默认瘦包和可选离线整包。

| 发布物 | 大小 | 模型 |
| --- | --- | --- |
| 默认 DMG | `13,218,304` bytes | 不包含 |
| 离线 DMG | `1,540,934,144` bytes | Qwen3-VL 2B |

`V01` 到 `V09` 的真机结果见 [validation/README.md](validation/README.md)。
Developer ID 和 notarization 按 ADR-0020 不在当前 internal/local 范围。

## 预期

目标发布物应满足以下条件：

1. 默认 DMG 不大于 `50 MB`。
2. app 更新不重复下载未变化的模型。
3. 模型下载支持暂停、恢复和原子提交。
4. 模型缺失或损坏时，app 仍能启动。
5. 下载完成后，断网环境可以使用 AI 功能。
6. 可选离线整包保留完整离线安装能力。

推荐架构、接口和失败模式见 [solution.md](solution.md)。
验证矩阵见 [validation/README.md](validation/README.md)。

## 实现预期的手段

实现分为五步：

1. 发布脚本停止把模型目录复制进默认 app。
2. 增加模型下载状态和临时目录。
3. 复用现有 `LocalModelPackageVerifier` 完成校验。
4. 增加模型下载界面、离线错误和导入入口。
5. 生成默认瘦 DMG 和可选离线整包，并运行验证矩阵。

实施顺序、回滚条件和产品化条件见 [solution.md](solution.md)。
每次实现的证据写入 [evidence.md](evidence.md)。
每次实现的验收按 [validation/README.md](validation/README.md) 执行。
架构决策见 [ADR-0019](../../adr/adr-0019-slim-install-and-on-demand-model.md)。

## 子文档

| 文件 | 内容 |
| --- | --- |
| [context.md](context.md) | 问题定义、边界、状态矩阵和成功标准 |
| [investigation.md](investigation.md) | GitHub 参考、约束、候选方案和反证 |
| [conclusion.md](conclusion.md) | 根因、全局选型、限制和未决项 |
| [solution.md](solution.md) | 发布架构、模型管理器、安全、实施和回滚 |
| [evidence.md](evidence.md) | 来源、命令、观察、推论和证据链 |
| [validation/README.md](validation/README.md) | 验证目标、矩阵、风险和清理要求 |

## 证据链阅读顺序

1. 阅读 [context.md](context.md)，确认问题和成功标准。
2. 阅读 [evidence.md](evidence.md) 的 `E-01` 到 `E-07`，确认当前包体结构。
3. 阅读 [evidence.md](evidence.md) 的 `E-08` 到 `E-16`，检查 GitHub 和项目约束。
4. 阅读 [investigation.md](investigation.md)，检查候选矩阵。
5. 阅读 [conclusion.md](conclusion.md)，检查唯一推荐和限制。
6. 阅读 [solution.md](solution.md)，检查实施设计。
7. 执行 [validation/README.md](validation/README.md) 中的验证项。

## 更新规则

1. 发布包结构变化时更新 `evidence.md`。
2. 模型来源、revision 或大小变化时更新 `evidence.md` 和 `solution.md`。
3. 验证状态变化时同步更新主题索引和验证索引。
4. 结论变化时更新 `conclusion.md`，并检查 ADR-0007 是否仍有效。
5. 默认下载源变化时重新执行模型下载和离线验证。
