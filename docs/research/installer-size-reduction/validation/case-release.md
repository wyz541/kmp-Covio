# Case 5：发布物大小、签名和校验和

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 尚未执行 |
| 日期 | `2026-10-24` |
| 关联测试 | `V09` |

## 验证目标

验证默认 DMG 和离线整包都有大小、SHA-256、签名和 notarization 记录。
验证默认 DMG 不含模型。
验证离线整包含固定 revision 的模型。

## 预检记录

| 检查 | 期望 | 实际 |
| --- | --- | --- |
| 发布版本 | 唯一 | 待填写 |
| 默认 DMG | 不大于 `50 MB` | 待填写 |
| 离线 DMG | 含完整模型 | 待填写 |
| 签名身份 | Developer ID Application | 待填写 |
| 公证凭据 | 可用 | 待填写 |

## 测试前采集

```bash
stat -f '%z' "<default-dmg>" "<offline-dmg>"
shasum -a 256 "<default-dmg>" "<offline-dmg>"
codesign --verify --deep --strict --verbose=2 "<release-app>"
spctl --assess --type execute --verbose=4 "<release-app>"
```

预期结果：默认包和离线包大小、哈希、签名和 Gatekeeper 结果均有记录。

## 步骤

### V09：发布物检查

前置条件：发布候选包已生成。

操作：

1. 挂载两个 DMG。
2. 检查默认 app 不含模型。
3. 检查离线 app 含模型。
4. 校验 app 签名和 notarization。
5. 上传 GitHub Release 草稿。
6. 下载刚上传的资产并复核 SHA-256。

预期结果：两类包通过检查，上传后哈希与本地一致。

实际结果：待填写。

错误码：待填写。

## 结果汇总

| 测试 | 结果 | 证据 |
| --- | --- | --- |
| V09 | 待填写 | 待填写 |

## 清理记录

1. 卸载两个 DMG。
2. 删除本地测试副本。
3. 保留脱敏发布记录。
4. 不删除已签名的发布资产。

## 更新规则

1. 每个发布版本记录一次。
2. 任一包大小超限时判定失败。
3. 任一签名或 notarization 失败时判定失败。
4. 上传后哈希不一致时停止发布。

## 关联文档

- [验证索引](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
