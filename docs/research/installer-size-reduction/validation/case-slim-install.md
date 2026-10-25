# Case 1：瘦包体积和无模型启动

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 通过 |
| 日期 | `2026-10-25` |
| 关联测试 | `V01`、`V02` |
| 环境 | MacBook Pro `18,2`，Apple M1 Max，64 GB，macOS `27.0.1`（`26A434`） |

## 验证目标

验证默认 DMG 不大于 `50 MB`。
验证无模型时 app 可以启动。
验证非 AI 功能仍可使用。

## 预检记录

| 检查 | 期望 | 实际 |
| --- | --- | --- |
| app 版本 | `0.5.2` build `3` | `0.5.2` build `3` |
| 模型目录 | 默认 app 不含模型 | `Models` 目录不存在 |
| 用户数据目录 | 使用隔离目录 | 使用独立目录 |
| 网络 | 关闭 | `sandbox-exec` 拒绝全部网络 |

## V01：安装包体积

默认 DMG：

| 项目 | 值 |
| --- | --- |
| 文件名 | `Covio-0.5.2.dmg` |
| 大小 | `13,223,936` bytes |
| SHA-256 | `03ceca15468b0faa77994a0a0971db46a113a570711e2fbafe3bdc4e28a223f0` |
| `hdiutil verify` | 通过 |
| `model.safetensors` | `0` |

结果：通过。
默认 DMG 比 `50 MB` 门槛少 `39,205,664` bytes。
app 只携带模型 manifest、许可证和 NOTICE。

## V02：无模型启动

操作：直接启动默认 app，设置独立 `COVIO_SUPPORT_DIR`，并拒绝全部网络。

观察：

1. 进程保持运行。
2. `config.json` 生成。
3. Monitor 历史数据库生成。
4. `Models` 状态文件数量为 `0`。
5. 模型安装面板显示大小、许可证、网络需求、下载和导入入口。

模型安装面板证据：[model-setup-uninstalled.png](evidence/2026-10-25-model-setup-uninstalled.png)。

结果：通过。
UI 渲染检查没有发现溢出或重叠。
`AppRuntimeTests.testStartupWithoutModelKeepsNonAIFeaturesAvailable` 同时通过。

## 结果汇总

| 测试 | 结果 | 证据 |
| --- | --- | --- |
| V01 | 通过 | [release-final.json](evidence/2026-10-25-release-final.json) |
| V02 | 通过 | [model-setup-uninstalled.png](evidence/2026-10-25-model-setup-uninstalled.png) |

## 错误码

无。

## 清理记录

1. 退出测试 app。
2. 删除隔离用户数据目录。
3. 卸载测试 DMG。
4. 检查没有测试 app 或 helper 在运行。

## 关联文档

- [验证索引](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
