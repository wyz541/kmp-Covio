# 验证目标、矩阵与结果

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | internal/local 真机矩阵通过 |
| 日期 | `2026-10-25` 至 `2026-10-26` |
| 环境 | MacBook Pro `18,2`，Apple M1 Max，64 GB，macOS `27.0.1`（`26A434`） |
| 发布身份 | `0.5.2` build `5`，internal，ad-hoc |
| 默认 DMG | `13,218,304` bytes |
| 离线 DMG | `1,540,934,144` bytes |
| 模型 | Qwen3-VL 2B，revision `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |

## 案例索引

| 案例 | 场景 | 状态 | 结果 |
| --- | --- | --- | --- |
| [case-slim-install.md](case-slim-install.md) | 瘦包体积和无模型启动 | 通过 | V01、V02 通过 |
| [case-model-delivery.md](case-model-delivery.md) | 模型下载、恢复、校验和离线推理 | 通过 | V03、V04、V05、V08 通过 |
| [case-app-update.md](case-app-update.md) | app 更新保留模型 | 通过 | V06 通过；V06B 未执行 |
| [case-offline-bundle.md](case-offline-bundle.md) | 完全离线安装 | 通过 | V07 通过 |
| [case-release.md](case-release.md) | 发布物大小、签名、校验和 | 通过内部渠道检查 | V09 通过；公开签名不在范围 |

## 验证目标

1. 证明默认 DMG 不大于 `50 MB`。
2. 证明无模型时 app 可以启动。
3. 证明模型下载支持暂停、重启恢复和原子登记。
4. 证明损坏模型无法登记或加载。
5. 证明模型就绪后断网可用。
6. 证明 app 更新不删除模型。
7. 证明可选离线整包可在断网环境安装。
8. 证明发布物有可复核的大小、校验和与发布身份。

## 环境与范围

验证在真实 Apple Silicon Mac 上执行。
网络拒绝使用 `sandbox-exec` 的 `(deny network*)` 规则。
用户数据使用独立目录，不触碰日常配置。

范围内：

- macOS 26 及后续版本。
- 默认在线安装。
- 可选离线安装。
- 模型下载、暂停、恢复和移除。
- app 替换更新。
- internal/local 发布身份。

范围外：

- Developer ID。
- Apple notarization。
- 公开分发。
- Intel 或 Universal 2。
- App Store。
- 模型质量重评。

## 当前事实

1. 默认 DMG 为 `13,218,304` bytes，比 `50 MB` 门槛少 `39,210,496` bytes。
2. 默认 app 没有 `Models` 目录，没有 `model.safetensors`。
3. 离线 DMG 含 1 个 `model.safetensors`，manifest 的 14 个文件全部通过 SHA-256 校验。
4. 真实下载在 `1,284,301,146` bytes 暂停，重启后恢复到 `1,798,021,605` bytes。
5. app 替换前后 registry SHA-256 都是 `b8d24a3151601131425effa98e6682fe6eda82a38b4e9f71e29e5333336c10ef`。
6. 断网文件自动命名通过 12 个语料项，其中 7 个重命名和 7 个撤销成功。
7. 断网 Agent 通过 6 个步骤。
8. 两次断网验证都记录 `0` 条非 loopback 网络连接。

## 测试矩阵

| 编号 | 场景 | 状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | 默认 DMG 不大于 `50 MB` | 通过 | [case-slim-install.md](case-slim-install.md) |
| V02 | 无模型启动和非 AI 功能 | 通过 | [case-slim-install.md](case-slim-install.md) |
| V03 | 模型下载、暂停和恢复 | 通过 | [case-model-delivery.md](case-model-delivery.md) |
| V04 | 损坏模型被拒绝 | 通过 | [case-model-delivery.md](case-model-delivery.md) |
| V05 | 模型就绪后断网推理 | 通过 | [case-model-delivery.md](case-model-delivery.md) |
| V06 | app 更新保留模型 | 通过 | [case-app-update.md](case-app-update.md) |
| V07 | 离线整包断网安装 | 通过 | [case-offline-bundle.md](case-offline-bundle.md) |
| V08 | 磁盘不足时不登记模型 | 通过 | [case-model-delivery.md](case-model-delivery.md) |
| V09 | 发布物大小、校验和和身份 | 通过内部渠道检查 | [case-release.md](case-release.md) |

## 证据

| 证据 | 内容 |
| --- | --- |
| [model-setup-uninstalled.png](evidence/2026-10-25-model-setup-uninstalled.png) | 无模型安装面板，显示大小、许可证、网络需求和四个档位 |
| [model-download.json](evidence/2026-10-25-model-download.json) | 暂停、重启恢复、完成登记和损坏拒绝 |
| [app-update.json](evidence/2026-10-25-app-update.json) | app 替换前后的推理和 registry 摘要 |
| [disk-guard.json](evidence/2026-10-25-disk-guard.json) | 64 MiB 卷的磁盘保护结果 |
| [release-final.json](evidence/2026-10-25-release-final.json) | 最终 DMG 大小、SHA-256、manifest、签名和 Gatekeeper 结果 |
| [release-assets.json](evidence/2026-10-25-release-assets.json) | 已发布 Release 的 9 个资产、远端 digest 和本地 SHA-256 对比 |
| [file-naming-final.json](evidence/2026-10-25-file-naming-final.json) | 最终离线 DMG 的断网文件命名结果 |
| [agent-final.json](evidence/2026-10-25-agent-final.json) | 最终离线 DMG 的断网 Agent 结果 |

## 限制

1. 当前渠道是 internal/local。ADR-0020 明确不要求 Developer ID、notarization 或 Gatekeeper 自动信任。
2. V06B 的 revision 不兼容更新没有真实双版本构建。自动化测试覆盖 `revisionMismatch` 状态。
3. V07 使用隔离的 Applications 目录模拟拖放安装，没有改动用户真实 `/Applications/Covio.app`。
4. 8 GB 内存边界没有单独的真机设备。
5. 稳定标签 `v0.5.2` 仍是旧整包。新的 slim/offline 构建已作为 `v0.5.2-internal.5` internal prerelease 发布。
6. 离线 DMG 的完整远程回读因网络速度中止。远端 digest 和 `checksums.txt` 已一致；完整回读需要更快的网络窗口。

## 清理步骤

1. 退出测试 app。
2. 删除隔离用户数据目录。
3. 删除磁盘保护测试卷。
4. 删除测试 app 副本。
5. 保留脱敏结果、SHA-256 和已发布资产记录。
6. 检查没有测试 app 或 helper 在运行。
