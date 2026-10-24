# 调研、约束与候选方案

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 可评审 |
| 日期 | `2026-10-24` |
| 目标产品 commit | `cf663d5` |
| 目标发布版本 | `0.5.2` |

## 调研方法

1. 读取发布脚本、模型清单、运行时和发布产物。
2. 对 app 文件按目录统计实际字节数。
3. 读取 DMG 的 UDIF 压缩信息。
4. 移除模型后重新签名并制作临时 DMG。
5. 审计 GitHub 仓库的固定版本源码和文档。
6. 用统一权重比较候选方案。

## 来源范围

| 来源 | 用途 |
| --- | --- |
| Covio `0.5.2` release metadata | 当前 DMG 大小 |
| Covio `0.5.0` 本机发布 app | 体积组成拆分 |
| Covio 源码 | 发布、校验和运行时约束 |
| `WhisperKit` | 首次使用下载模型的成熟模式 |
| `swift-transformers` | Hub 下载、缓存、后台会话和离线模式 |
| `mlx-swift-examples` | MLX 模型下载、进度和缓存 |
| `Sparkle` | 后续差分更新能力 |
| `Dynamic Universal App` | app 引导下载模式 |
| `Stats` | 原生菜单栏 app 的发布包基线 |

## 领域模型

| 对象 | 稳定术语 | 说明 |
| --- | --- | --- |
| 默认安装包 | 瘦 app 安装包 | 只包含 app 文件 |
| 可选安装包 | 离线整包 | 同时包含 app 和模型 |
| 模型单位 | 模型包 | 一个固定 revision 的文件集合 |
| 官方目录 | 模型目录 | app 可验证和加载的位置 |
| 临时目录 | 暂存目录 | 下载和校验未完成时的位置 |
| 发布身份 | release identity | app、helper 和发布记录的版本组合 |

## 约束模型

### 体积约束

模型 `model.safetensors` 为 `1,782,040,921` bytes。
模型目录合计为 `1,798,035,956` bytes。
非模型 app 文件合计为 `34,731,377` bytes。
完整 DMG 的压缩比约为 `0.832`。
压缩不能把 `1.8 GB` 模型降到可接受的小包。

### 离线约束

ADR-0007 要求安装后直接离线使用。
新方案必须保留这个能力。
默认在线安装允许一次模型下载。
可选离线整包满足无网络安装。
下载完成后，文件内容和推理请求不得发送到网络。

### 更新约束

app 更新和模型 revision 更新是两件事。
模型未变化时，app 更新不得删除或重下模型。
模型目录必须支持原子激活和回滚。
app 与 helper 的统一版本约束见 [#350](https://github.com/wyz541/kmp-Covio/issues/350)。
版本来源是 `release/release-manifest.json`。

### 分发约束

当前模型档位大小如下：

| 档位 | 文件总大小 |
| --- | ---: |
| 2B | `1,798,021,605` bytes |
| 4B | `3,109,729,929` bytes |
| 8B | `5,776,630,909` bytes |
| 30B-A3B | `18,268,088,064` bytes |

4B、8B 和 30B-A3B 超过单个 GitHub Release 资产的可用范围。
因此，模型默认源不能依赖一个 GitHub Release 大文件。
Hugging Face Hub 提供固定 revision、文件级下载和缓存。
可选离线整包也按单档位生成。
单文件超过 GitHub 限制时，发布脚本必须拆分资产并记录顺序与 SHA-256。

### 安全约束

模型是可执行推理流程的输入数据。
app 只接受固定 revision 和固定 SHA-256 的文件。
下载源不可信时，app 仍以 app 内 manifest 为信任根。
模型下载不得发送用户文件、会话或剪贴板内容。

## 控制路径

默认流程如下：

1. 用户安装瘦 app。
2. app 加载内置模型清单。
3. app 检查本地注册表。
4. 用户打开 AI 功能。
5. app 显示模型大小、许可证和下载入口。
6. 用户确认后，model manager 下载文件到暂存目录。
7. verifier 校验所有文件。
8. registry 原子登记模型。
9. runtime 从模型目录加载推理。
10. 后续启动不访问模型源。

## 信任边界

| 边界 | 信任内容 | 不信任内容 |
| --- | --- | --- |
| app bundle | 模型 manifest、允许的 revision、许可证 | 外部模型目录中的未校验文件 |
| Hugging Face Hub | 传输服务 | 模型内容本身；内容仍按 SHA-256 校验 |
| Application Support | 已校验模型和注册表 | 用户手工修改后的内容 |
| MLX runtime | 已校验的 safetensors 和配置 | 未校验路径、符号链接和不安全相对路径 |
| GitHub Releases | app 和校验和 | 与 manifest 不匹配的模型文件 |

## 工具或现有能力矩阵

| 能力 | 限制 | 依赖 | 证据 |
| --- | --- | --- | --- |
| 固定模型 manifest | manifest 本身需要签名 app 保护 | 发布版本 | `E-06` |
| 模型包校验 | 只校验本地目录，不下载文件 | `LocalModelPackageVerifier` | `E-08` |
| 模型包登记 | 不管理下载进度和恢复 | `LocalModelPackageRegistryStore` | `E-08` |
| 内置模型加载 | 会把模型复制进 app | 发布脚本和 app 资源 | `E-07` |
| 硬件档位选择 | 依赖可用内存探测 | `LocalModelSelector` | `E-06` |
| Hub 后台下载 | 需要处理 macOS 后台会话回调 | `swift-transformers` Hub | `E-09`、`E-11` |
| 下载进度 | 只能观察进度，不能代替原子提交 | Hub `Progress` | `E-11`、`E-12` |
| Sparkle 差分更新 | 只更新 app bundle | Sparkle appcast | `E-13` |

## GitHub 参考实现

### WhisperKit

- 仓库：`argmaxinc/argmax-oss-swift`，原 `WhisperKit` 地址。
- Commit：`9f99b5cb6a907730543823ad271b82532782a899`。
- 许可证：MIT。
- 模式：模型托管在 Hugging Face，首次使用时下载并缓存。
- 可复用点：模型不在 app 内、固定模型名、进度回调、本地目录覆盖。
- 不直接复用：Core ML 音频模型和项目配置。

### swift-transformers

- Commit：`e37cacea74498bba66002bb83ecafee3e4ab8884`。
- 许可证：Apache-2.0。
- 模式：Hub API 支持 `downloadBase`、后台 URLSession、进度、缓存和离线检查。
- 可复用点：Covio 已内含该 Hub bundle，可直接作为下载层。
- 限制：应用仍需处理登录会话、后台完成回调和原子提交。

### mlx-swift-examples

- Commit：`378f2449c257788c5067b9f8b086731d76b39b33`。
- 许可证：MIT。
- 模式：示例用 `#hubDownloader()` 下载模型，显示 `Progress`，并缓存已加载模型。
- 可复用点：模型选择、进度和 MLX 运行时组合。
- 限制：示例不是发布级下载器，没有 Covio 的许可证和注册表流程。

### Sparkle

- Commit：`19688c1a0ae10240d884888e5b3190c15aee524b`。
- 许可证：MIT 风格。
- 模式：提供 app 更新、EdDSA 签名和 BinaryDelta。
- 可复用范围：后续 app 更新。
- 不采用为主方案：它更新 app，不会把内置模型移到 app 外。

### Dynamic Universal App

- Commit：`2966766912f44eb7be64e04f454f5c96b10df2dc`。
- 许可证：MIT。
- 模式：小型引导 app 按 CPU 架构下载完整 app。
- 不采用：Covio 只发布 arm64，且启动下载完整 app 不会消除模型体积。

### Stats

- Release：`v3.0.22`。
- DMG：`7,724,844` bytes。
- 模式：原生菜单栏 app，不携带大模型。
- 用途：证明约 `10 MB` 的基础 app 包与本机体积探针一致。
- 限制：功能范围不同，不能把大小直接作为性能或质量比较。

## 候选方案

### 体积与体验

| 方案 | 体积收益 | 离线能力 | 首次体验 | 更新能力 |
| --- | --- | --- | --- | --- |
| A：继续内置模型 | 无 | 完整 | 最简单 | 每次带模型 |
| B：只优化压缩和构建 | 很低 | 完整 | 最简单 | 每次带模型 |
| C：瘦 app + 模型下载 + 可选离线整包 | 很高 | 下载后完整；离线整包完整 | 需要一次下载 | app 与模型独立更新 |
| D：引导器下载完整 app | 高 | 差 | 二次下载 | 需要引导器协议 |
| E：外部 Ollama 或模型服务 | 很高 | 低 | 需要额外安装 | 依赖外部服务 |
| F：只换更小模型 | 中 | 完整 | 最简单 | 仍需内置 |
| G：只加 Sparkle 差分更新 | 首次安装无收益 | 完整 | 与当前相同 | 更新包更小 |

### 成本、风险与成熟度

| 方案 | 实施成本 | 主要风险 | 成熟度 | 可维护性 |
| --- | --- | --- | --- | --- |
| A：继续内置模型 | 低 | 包体持续过大 | 高 | 高 |
| B：只优化压缩和构建 | 低 | 收益不足 | 高 | 高 |
| C：瘦 app + 模型下载 + 可选离线整包 | 中 | 首次网络和恢复失败 | 高 | 中 |
| D：引导器下载完整 app | 中高 | 二次下载和自替换失败 | 中 | 中低 |
| E：外部 Ollama 或模型服务 | 高 | 外部进程和端口故障 | 中 | 低 |
| F：只换更小模型 | 中 | 质量和兼容性变化 | 中 | 中 |
| G：只加 Sparkle 差分更新 | 中 | 不解决首次安装 | 高 | 中 |

## 目标产品源码分析

| 事实 | 影响 |
| --- | --- |
| 发布脚本要求 `COVIO_FILE_NAMING_MODEL_DIR` 并复制模型 | 默认 DMG 必然大于模型大小 |
| manifest 固定 14 个文件和 SHA-256 | 可直接作为下载校验契约 |
| `LocalModelPackageVerifier` 已校验 revision、大小、SHA-256 和许可证 | 不需要新建信任模型 |
| `LocalModelPackageRegistryStore` 已保存导入模型 | 可扩展为下载完成后的注册入口 |
| `NamingModelConfiguration.bundled` 从 app 资源选择模型 | 需要把外部模型目录加入选择顺序 |
| 当前 `AppRuntime` 在没有外部注册时回退到内置路径 | 无模型时需要显式 `not_installed` 状态 |
| app 已包含 `swift-transformers_Hub.bundle` | 下载层已有运行时依赖 |

## 反证和限制

1. 瘦 app 只缩小下载包，不缩小模型安装后的磁盘占用。
2. 默认在线安装会引入一次网络依赖。
3. Hugging Face 在不同网络的可用性需要真机验证。
4. 后台 URLSession 的完成回调需要 macOS app 生命周期接入。
5. 模型目录在 app bundle 外，不能依赖 app 代码签名保护。
6. 当前没有完成产品内下载器，因此 `solution.md` 中的流程仍是实施设计。

## 已知缺口

| 缺口 | 影响 | 下一步 |
| --- | --- | --- |
| 未在本机完成 `0.5.2` 全量下载 | 采用 `0.5.0` 同版本结构推算 | 发布前验证 `0.5.2` 文件清单 |
| 未测试真实网络的中断和恢复 | 恢复体验未知 | 执行 `V03` |
| 未实现后台下载完成回调 | 跨启动恢复未知 | 在 Feature 中接入并测试 |
| 未评估模型更新差分 | 新 revision 仍需完整模型 | 后续独立调研 |
| 未取得 Developer ID | 签名分发条件未定 | 与发布链任务联合验证 |
