# ADR-0019：默认发布瘦 app，按需下载模型并保留离线整包

- Status：accepted
- Kind：architecture
- Date：2026-10-25
- Supersedes：ADR-0007
- Implements：pending
- 相关：[安装包体积缩减研究](../research/installer-size-reduction/README.md)、[Research #360](https://github.com/wyz541/kmp-Covio/issues/360)、[PR #370](https://github.com/wyz541/kmp-Covio/pull/370)

## 背景

`Covio 0.5.2` 的 DMG 为 `1,538,632,192` bytes。
模型目录为 `1,798,035,956` bytes。
模型占 app 文件总量的 `98.10%`。
完整 DMG 使用 UDZO，压缩比约为 `0.832`。
移除模型后的临时 DMG 为 `10,877,952` bytes。

ADR-0007 选择把模型内置，以便用户安装后直接离线使用。
该选择造成默认安装包过大。
代码和资源优化无法消除模型带来的数量级差异。

GitHub Release 单文件必须小于 `2 GiB`。
4B、8B 和 30B-A3B 模型都超过该限制。
GitHub 上的 WhisperKit、swift-transformers 和 mlx-swift-examples 已采用按需模型下载。

## 决策

1. 默认 `Covio-<version>.dmg` 只包含 app、manifest 和许可证。
2. 大模型通过独立模型包交付，不进入默认 app bundle。
3. 模型下载由用户主动确认。app 不静默消耗网络流量。
4. 默认模型源是 Hugging Face Hub 的固定 `revision`。
5. app 继续支持用户导入本地模型包。
6. app 内 manifest 是模型身份的信任根。远端不能替换允许的 revision 或文件哈希。
7. 模型加载前校验档位、硬件、文件大小、SHA-256、许可证和安全相对路径。
8. 下载写入暂存目录。校验通过后以原子操作写入模型注册表。
9. 未完成或校验失败的模型不得登记，也不得加载。
10. 模型保存在 `$HOME/Library/Application Support/com.wyz.covio/Models/`。
11. 模型就绪后，文件命名和 Agent 保持离线运行。
12. 模型下载不得发送用户文件、会话、剪贴板或 Agent 内容。
13. app 更新不删除模型。相同 revision 不重复下载。
14. 新 revision 可用后保留旧模型，直到用户确认删除。
15. 提供单独的 `Covio-Offline-<version>.dmg` 或无网络安装资产。
16. 离线整包超过 GitHub 单文件限制时，拆分资产并记录顺序与 SHA-256。
17. 默认 DMG 的目标大小为不大于 `50 MB`。
18. `release/release-manifest.json` 继续作为版本、构建号和 helper 协议版本的唯一来源。
19. 发布清单记录默认包、离线包和模型 revision 的身份与摘要。
20. ADR-0013 的模型档位和 ADR-0008 的 MLX 运行时保持不变。

## 后果

### 正面

- 默认下载从约 `1.54 GB` 降到目标 `50 MB` 以下。
- 普通用户不再为一次 app 下载重复获取模型。
- app 更新和模型 revision 可以独立交付。
- 模型仍使用固定 revision、SHA-256 和许可证校验。
- 下载完成后保持离线推理。
- 可选离线整包保留无网络安装能力。
- 模型目录位于 Application Support，不受 app 覆盖安装影响。

### 负面

- 默认安装后首次使用 AI 功能仍需要一次网络连接。
- 模型安装后的磁盘占用仍约 `1.8 GB` 或更高。
- 需要新增下载状态、进度、暂停、恢复、校验和错误界面。
- Hugging Face Hub 的可用性会影响首次模型获取。
- 离线整包仍然很大。
- 发布流程需要维护默认包、模型包和可选离线包三套身份。

### 风险

- 模型源不可达。缓解：保留本地导入、离线整包和后续镜像入口。
- 下载文件损坏。缓解：逐文件 SHA-256 校验和原子提交。
- app 更新删除模型。缓解：模型存到 Application Support，并执行覆盖更新测试。
- 用户流量被静默消耗。缓解：下载前显示模型大小并要求确认。
- 模型 revision 不兼容。缓解：保留旧模型，显示兼容模型下载入口。
- 离线整包超过资产上限。缓解：拆分资产并在发布清单记录顺序和摘要。
- 许可证或归属缺失。缓解：app 和模型目录同时保留 LICENSE 与 NOTICE。
- 模型下载影响后台任务。缓解：使用后台会话、暂停和恢复状态。

## 备选方案

### 备选 1：继续内置模型

该方案保留最简单的一次安装体验。
该方案继续产生约 `1.54 GB` 的默认 DMG。
每次 app 更新还会重复携带未变化的模型。

未采纳。

### 备选 2：只优化压缩和构建

当前 UDZO 压缩比约为 `0.832`。
非模型内容只有 `34,731,377` bytes。
代码和资源优化无法把模型包降到 `50 MB` 级。

未采纳。

### 备选 3：用引导器下载完整 app

Figma 的 Dynamic Universal App 适合按架构分发完整 app。
Covio 只发布 arm64。
该引导器仍会下载包含模型的完整 app。

未采纳。

### 备选 4：使用 Ollama 或外部模型服务

该方案把模型移出 app。
它要求用户安装和维护外部服务。
它还增加进程、端口、模型迁移和版本兼容风险。

未采纳。

### 备选 5：只换成更小模型

较小模型仍会产生 GB 级包体。
该方案还会改变模型质量、内存和许可证边界。

未作为包体方案单独采用。

### 备选 6：只增加 Sparkle 差分更新

Sparkle BinaryDelta 可以减少后续 app 更新流量。
它不能减少首次安装包。

未作为本决策的主方案。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 瘦包默认构建 | pending | 实现 Feature 后读取 DMG 字节数 |
| 无模型启动 | pending | 执行研究验证 `V02` |
| 下载暂停与恢复 | pending | 执行研究验证 `V03` |
| 损坏模型拒绝 | pending | 执行研究验证 `V04` |
| 模型就绪后离线推理 | pending | 执行研究验证 `V05` |
| app 更新保留模型 | pending | 执行研究验证 `V06` |
| 可选离线整包 | pending | 执行研究验证 `V07` |
| Developer ID 与 notarization | pending | 接入正式发布签名链 |
| Feature issue | pending | ADR 合并后创建 Feature 或 task issue |

## 参考

- [安装包体积缩减研究](../research/installer-size-reduction/README.md)
- [研究结论](../research/installer-size-reduction/conclusion.md)
- [推荐方案](../research/installer-size-reduction/solution.md)
- [验证矩阵](../research/installer-size-reduction/validation/README.md)
- [ADR-0007](adr-0007-offline-file-naming-model-package.md)
- [ADR-0008](adr-0008-file-naming-runtime-platform-choice.md)
- [ADR-0013](adr-0013-local-model-tiers.md)
- [Research #360](https://github.com/wyz541/kmp-Covio/issues/360)
- [PR #370](https://github.com/wyz541/kmp-Covio/pull/370)
- [WhisperKit model acquisition](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/README.md)
- [swift-transformers HubApi](https://github.com/huggingface/swift-transformers/blob/e37cacea74498bba66002bb83ecafee3e4ab8884/Sources/Hub/HubApi.swift)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
