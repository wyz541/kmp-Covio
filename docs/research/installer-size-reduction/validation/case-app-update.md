# Case 3：app 更新保留模型

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 尚未执行 |
| 日期 | `2026-10-24` |
| 关联测试 | `V06` |

## 验证目标

验证 app 更新不删除模型。
验证 app 更新不重下相同 revision。
验证模型 revision 不兼容时保留旧模型。

## 预检记录

| 检查 | 期望 | 实际 |
| --- | --- | --- |
| 旧 app | 可使用当前模型 | 待填写 |
| 新 app | 使用相同或兼容 manifest | 待填写 |
| 模型目录 | 位于 Application Support | 待填写 |
| registry | 指向已验证模型 | 待填写 |

## 测试前采集

```bash
cat "<support-dir>/Models/imported-packages.json"
find "<support-dir>/Models/packages" -type f -exec stat -f '%z %N' {} +
```

预期结果：记录模型 revision、路径和文件大小。

## 步骤

### V06：覆盖更新 app

前置条件：旧 app 已安装，模型状态为 `ready`。

操作：

1. 用新 app 替换旧 app。
2. 启动新 app。
3. 检查模型状态。
4. 执行一次推理。

预期结果：模型仍为 `ready`，不下载相同模型，推理成功。

实际结果：待填写。

错误码：待填写。

### V06B：revision 不兼容

前置条件：新 app 要求不同 revision。

操作：

1. 用新 app 替换旧 app。
2. 启动 app。

预期结果：旧模型保留但不加载，app 显示兼容模型下载入口。

实际结果：待填写。

错误码：待填写。

## 结果汇总

| 测试 | 结果 | 证据 |
| --- | --- | --- |
| V06 | 待填写 | 待填写 |
| V06B | 待填写 | 待填写 |

## 清理记录

1. 恢复旧 app 与旧模型。
2. 删除测试 app。
3. 删除隔离用户数据目录。
4. 检查 helper 版本。

## 更新规则

1. 更新前记录 app 版本和模型 revision。
2. 更新后再次记录相同字段。
3. 下载日志中出现相同 revision 下载时判定失败。

## 关联文档

- [验证索引](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
