# Case 4：离线整包安装

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 通过 |
| 日期 | `2026-10-25` |
| 关联测试 | `V07` |
| 环境 | macOS `27.0.1`（`26A434`），Apple M1 Max，64 GB |

## 验证目标

验证离线整包包含 app 和模型。
验证无网络时可以完成本地推理。
验证 app 不访问远程模型源。

## 预检记录

| 检查 | 期望 | 实际 |
| --- | --- | --- |
| 离线 DMG | 存在且可校验 | `1,540,934,656` bytes |
| SHA-256 | 与 manifest 一致 | `6d2154b826df104d17fc950e87f2ef607a90ade6eecf7a36446076a466c8fd5c` |
| 模型 manifest | 与内置模型一致 | 14 个文件全部通过 |
| 网络 | 关闭 | `sandbox-exec` 拒绝全部网络 |
| 用户数据目录 | 为空 | 使用隔离目录 |

## V07：断网安装和推理

操作：

1. 校验并挂载离线 DMG。
2. 把 app 复制到隔离的 Applications 目录。
3. 在空用户数据目录启动 app。
4. 使用拒绝网络的沙箱运行文件自动命名。
5. 使用拒绝网络的沙箱运行 Agent。

实际结果：

| 验证 | 结果 |
| --- | --- |
| DMG `hdiutil verify` | 通过 |
| 模型文件 | 17 个，其中 1 个 `model.safetensors` |
| manifest 文件 | 14 个全部通过 SHA-256 |
| 文件自动命名 | 7 个重命名，7 个撤销 |
| Agent | 6 个步骤通过 |
| 非 loopback 网络行 | 两次均为 `0` |

结果：通过。
离线 DMG 不需要远程模型下载。
文件自动命名和 Agent 都能使用内置模型完成推理。

## 结果汇总

| 测试 | 结果 | 证据 |
| --- | --- | --- |
| V07 | 通过 | [release-final.json](evidence/2026-10-25-release-final.json)、[file-naming-final.json](evidence/2026-10-25-file-naming-final.json)、[agent-final.json](evidence/2026-10-25-agent-final.json) |

## 错误码

无。

## 清理记录

1. 删除隔离 Applications 目录。
2. 删除隔离用户数据目录。
3. 卸载 DMG。
4. 恢复网络。

## 关联文档

- [验证索引](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
