# Case 2：模型下载、恢复、校验和离线推理

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 通过 |
| 日期 | `2026-10-25` |
| 关联测试 | `V03`、`V04`、`V05`、`V08` |
| 环境 | MacBook Pro `18,2`，Apple M1 Max，64 GB，macOS `27.0.1`（`26A434`） |

## 验证目标

验证半成品不会登记为可用模型。
验证下载可以跨 app 重启恢复。
验证损坏模型被拒绝。
验证磁盘不足时给出明确错误。
验证模型就绪后断网可以推理。

## 预检记录

| 检查 | 期望 | 实际 |
| --- | --- | --- |
| 模型 manifest | 固定 revision 和 SHA-256 | `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |
| 可用磁盘 | 大于模型和暂存空间 | `566 GiB` |
| 网络 | 可连接 Hugging Face | 通过 |
| 用户数据目录 | 使用隔离目录 | 通过 |

## V03：下载、暂停和恢复

前置条件：没有本地模型，网络可用，真实 Hugging Face 源。

操作：

1. 启动真实下载。
2. 达到暂停阈值后暂停。
3. 销毁下载器实例。
4. 创建新下载器实例。
5. 读取持久化状态并恢复。
6. 等待校验、登记和 ready。

实际结果：

| 阶段 | 状态 | 字节数 |
| --- | --- | --- |
| 暂停 | `paused` | `1,284,301,146` |
| 新实例读取 | `paused` | `1,284,301,146` |
| 完成 | `ready` | `1,798,021,605` |

结果：通过。
新实例保留暂停位置。
完成包登记到 `2b` tier 和固定 revision。

## V04：损坏模型被拒绝

操作：在真实已下载包内修改 `config.json` 的一个字节，然后再次校验。

实际结果：返回 `checksumMismatch`。
恢复原始字节后再次校验通过。
`testChecksumFailureDoesNotRegisterOrKeepStaging` 同时通过。

结果：通过。

## V05：断网推理

### 下载模型

使用已下载的 2B 包启动 Agent 验收，并在 `sandbox-exec` 中拒绝全部网络。

结果：

| 项目 | 值 |
| --- | --- |
| 步骤 | `6` |
| 完成步骤 | `6` |
| 峰值常驻内存 | `1,994,162,176` bytes |
| 非 loopback 网络行 | `0` |

### 离线 DMG

最终离线 DMG 再次执行文件自动命名和 Agent 验收。

| 验证 | 结果 |
| --- | --- |
| 文件自动命名 | 12 个语料项，7 个重命名，7 个撤销 |
| Agent | 6 个步骤全部通过 |
| 非 loopback 网络行 | 两次均为 `0` |

结果：通过。

## V08：磁盘不足

前置条件：64 MiB APFS sparse image，挂载为独立卷。

操作：使用该卷作为 `COVIO_SUPPORT_DIR`，启动真实下载预检。

实际结果：

| 项目 | 值 |
| --- | --- |
| 错误码 | `insufficientDisk` |
| registry 记录 | `false` |
| 模型大小 | `1,798,021,605` bytes |
| 测试卷容量 | 64 MiB |

结果：通过。

## 结果汇总

| 测试 | 结果 | 证据 |
| --- | --- | --- |
| V03 | 通过 | [model-download.json](evidence/2026-10-25-model-download.json) |
| V04 | 通过 | [model-download.json](evidence/2026-10-25-model-download.json) |
| V05 | 通过 | [file-naming-final.json](evidence/2026-10-25-file-naming-final.json)、[agent-final.json](evidence/2026-10-25-agent-final.json) |
| V08 | 通过 | [disk-guard.json](evidence/2026-10-25-disk-guard.json) |

## 清理记录

1. 退出测试 app。
2. 删除隔离用户数据目录。
3. 删除损坏测试副本。
4. 卸载磁盘保护测试卷。
5. 恢复网络。

## 关联文档

- [验证索引](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
