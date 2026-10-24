# 验证目标、矩阵与风险

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 待执行 |
| 日期 | `2026-10-24` |
| 当前事实 | 已完成移除模型后的体积探针；产品下载流程尚未实现 |
| 目标验证 | 默认瘦包、模型下载、离线整包和 app 更新 |

## 案例索引

| 案例 | 场景 | 状态 | 结果 |
| --- | --- | --- | --- |
| [case-slim-install.md](case-slim-install.md) | 瘦包体积和无模型启动 | 尚未执行 | 待填写 |
| [case-model-delivery.md](case-model-delivery.md) | 模型下载、恢复、校验和离线推理 | 尚未执行 | 待填写 |
| [case-app-update.md](case-app-update.md) | app 更新保留模型 | 尚未执行 | 待填写 |
| [case-offline-bundle.md](case-offline-bundle.md) | 完全离线安装 | 尚未执行 | 待填写 |
| [case-release.md](case-release.md) | 发布物大小、签名、校验和 | 尚未执行 | 待填写 |

## 验证目标

1. 证明默认 DMG 不大于 `50 MB`。
2. 证明无模型时 app 可以启动。
3. 证明模型下载支持暂停、恢复和原子提交。
4. 证明损坏模型无法登记或加载。
5. 证明模型就绪后断网可用。
6. 证明 app 更新不删除或重下相同 revision。
7. 证明可选离线整包可在断网环境安装。
8. 证明发布物有可复核的大小、校验和与签名记录。

## 范围内事项

- macOS 26 及后续版本。
- Apple Silicon arm64。
- 默认在线安装。
- 可选离线安装。
- Hugging Face 模型源。
- 模型导入。
- app 更新。
- Developer ID 与 notarization 的发布验证。

## 范围外事项

- 模型准确率评测。
- 模型量化实验。
- Intel 或 Universal 2。
- App Store 审核。
- 企业 MDM 分发。
- 模型差分更新。

## 当前事实

1. `0.5.2` DMG 为 `1,538,632,192` bytes。
2. 本地 `0.5.0` app 的模型占 `98.10%`。
3. 临时无模型 DMG 为 `10,877,952` bytes。
4. 模型 manifest 已包含 revision、大小和 SHA-256。
5. 产品内模型下载尚未实现。

## 成功标准

- 默认 DMG 不大于 `50 MB`。
- app 在无模型时仍能完成启动。
- 无模型时非 AI 功能可用。
- 用户确认后才开始下载。
- 下载中断后可以继续。
- 不完整或哈希错误的模型被拒绝。
- 模型就绪后断网可以推理。
- app 更新后模型仍可用。
- 离线整包在断网环境可以使用。
- 发布记录包含两个 DMG 的 SHA-256。

## 前置条件

- 可运行的瘦 app 构建。
- 固定的模型 manifest。
- 可模拟断网和低速网络的测试环境。
- 足够的磁盘空间，用于完整模型和暂存文件。
- 可选离线整包。
- 发布签名配置。
- 一个干净的用户数据目录。

## 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 模型源不可达 | 首次使用失败 | 本地导入、镜像或重试 |
| 后台下载不能恢复 | 大文件重复下载 | 暂存目录和 HTTP 缓存 |
| 校验时间过长 | 用户等待 | 显示校验进度 |
| 模型目录被破坏 | 推理失败 | registry 重新校验和修复入口 |
| app 更新覆盖模型 | 用户重新下载 | 模型放到 Application Support |
| 离线整包体积继续过大 | 下载不便 | 明确标为非默认包 |
| 签名缺失 | Gatekeeper 拒绝 | 完成 Developer ID 与 notarization |
| 模型许可证遗漏 | 分发不合规 | app 和模型包同时保留许可证 |

## 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | 默认 DMG 不大于 `50 MB` | 部分通过，仅临时体积探针 | [case-slim-install.md](case-slim-install.md) |
| V02 | 无模型启动和非 AI 功能 | 尚未执行 | [case-slim-install.md](case-slim-install.md) |
| V03 | 模型下载、暂停和恢复 | 尚未执行 | [case-model-delivery.md](case-model-delivery.md) |
| V04 | 损坏模型被拒绝 | 尚未执行 | [case-model-delivery.md](case-model-delivery.md) |
| V05 | 模型就绪后断网推理 | 尚未执行 | [case-model-delivery.md](case-model-delivery.md) |
| V06 | app 更新保留模型 | 尚未执行 | [case-app-update.md](case-app-update.md) |
| V07 | 离线整包断网安装 | 尚未执行 | [case-offline-bundle.md](case-offline-bundle.md) |
| V08 | 磁盘不足时不登记模型 | 尚未执行 | [case-model-delivery.md](case-model-delivery.md) |
| V09 | 发布物签名、校验和和大小 | 尚未执行 | [case-release.md](case-release.md) |

## 证据要求

1. 记录 macOS build、硬件、app 版本和模型 revision。
2. 记录 DMG 和 app 的文件字节数。
3. 记录下载进度、暂停位置和恢复位置。
4. 记录每个失败的错误码。
5. 记录模型校验结果和 SHA-256。
6. 记录断网前后的推理结果。
7. 记录 app 更新前后的 registry。
8. 记录离线整包安装过程。
9. 记录签名、notarization 和 Gatekeeper 结果。
10. 不记录用户文件、令牌或完整隐私日志。

## 清理步骤

1. 退出测试 app。
2. 删除隔离的用户数据目录。
3. 删除临时模型和暂存目录。
4. 删除测试 DMG。
5. 卸载测试模型包。
6. 恢复测试前的网络与代理设置。
7. 检查没有测试 app 或 helper 在运行。
8. 保留脱敏后的命令输出和 SHA-256。

## 关联文档

- [主题索引](../README.md)
- [推荐方案](../solution.md)
- [结论](../conclusion.md)
- [证据](../evidence.md)
