# Case 3：app 更新保留模型

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | V06 通过；V06B 未执行 |
| 日期 | `2026-10-25` 至 `2026-10-26` |
| 关联测试 | `V06` |
| 环境 | macOS `27.0.1`（`26A434`），Apple M1 Max，64 GB |

## 验证目标

验证 app 替换不删除模型。
验证 app 替换后 registry 不变化。
验证替换前后的本地模型推理都通过。

## 预检记录

| 检查 | 期望 | 实际 |
| --- | --- | --- |
| 旧 app | 可使用当前模型 | 替换前文件命名通过 |
| 新 app | 使用相同 manifest | 同 revision `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |
| 模型目录 | 位于 Application Support | 位于独立 `COVIO_SUPPORT_DIR/Models/Packages` |
| registry | 指向已验证模型 | `selectedTier=2b` |

## V06：覆盖更新 app

前置条件：模型已完成校验并登记。

操作：

1. 从同一独立根目录启动旧 app。
2. 在断网沙箱执行 12 个语料项的完整文件命名验收。
3. 备份旧 app。
4. 用新 app 替换旧 app。
5. 使用同一 `COVIO_SUPPORT_DIR` 启动新 app。
6. 再次执行同一文件命名验收。
7. 比较 registry SHA-256。

实际结果：

| 项目 | 替换前 | 替换后 |
| --- | --- | --- |
| 重命名 | 7 | 7 |
| 撤销恢复 | 7 | 7 |
| 峰值常驻内存 | `2,272,133,120` bytes | `2,267,283,456` bytes |
| registry SHA-256 | `b8d24a3151601131425effa98e6682fe6eda82a38b4e9f71e29e5333336c10ef` | 同左 |

结果：通过。
app 替换没有删除模型。
同 revision 没有重新下载。
替换前后都可在断网沙箱内推理。

## V06B：revision 不兼容

没有构造要求不同 revision 的真实双版本 app。
自动化测试覆盖 `revisionMismatch` 状态。
该项不作为 #381 的阻塞条件。

## 结果汇总

| 测试 | 结果 | 证据 |
| --- | --- | --- |
| V06 | 通过 | [app-update.json](evidence/2026-10-25-app-update.json) |
| V06B | 未执行 | 自动化状态测试覆盖 |

## 错误码

无。

## 清理记录

1. 删除旧 app 和替换 app 的测试副本。
2. 删除隔离用户数据目录。
3. 检查 helper 版本。

## 关联文档

- [验证索引](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
