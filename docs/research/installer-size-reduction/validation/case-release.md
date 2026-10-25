# Case 5：发布物大小、身份和校验和

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 通过 internal/local 检查 |
| 日期 | `2026-10-25` 至 `2026-10-26` |
| 关联测试 | `V09` |
| 渠道 | internal/local |
| 签名 | ad-hoc |
| Draft | `v0.5.2-internal.5` |

## 验证目标

验证默认 DMG 和离线 DMG 的大小与 SHA-256。
验证默认 DMG 不含模型。
验证离线 DMG 含固定 revision 的模型。
验证 app bundle 签名。
验证 Draft 资产可重新下载并复核。

## 预检记录

| 检查 | 期望 | 实际 |
| --- | --- | --- |
| 发布版本 | 唯一 | `0.5.2` build `5` |
| 默认 DMG | 不大于 `50 MB` | `13,218,304` bytes |
| 离线 DMG | 含完整模型 | 含 1 个 `model.safetensors` |
| 签名身份 | internal/local 可用 | ad-hoc |
| Developer ID | 当前范围外 | 未配置 |

## V09：发布物检查

### 大小和 SHA-256

| 发布物 | 大小 | SHA-256 |
| --- | --- | --- |
| `Covio-0.5.2.dmg` | `13,218,304` bytes | `5eced02d91ca0eb9585cd028afb6ed5c63d24e06bd55e40e2730b073997aee99` |
| `Covio-Offline-0.5.2.dmg` | `1,540,934,144` bytes | `8bea35be7bd4c7dd7a439142153292f9672edaee63b3f1d2710eea92d6a754d7` |

两个 DMG 的 `hdiutil verify` 都通过。
`dist/release-manifest.json` 记录的 size 和 SHA-256 与本地文件一致。

### App bundle

| 检查 | 默认 app | 离线 app |
| --- | --- | --- |
| `codesign --verify --deep --strict` | 通过 | 通过 |
| 签名 | ad-hoc | ad-hoc |
| Gatekeeper | rejected | rejected |
| `model.safetensors` | 0 | 1 |

Gatekeeper 拒绝是 ADR-0020 的已知结果。
当前渠道不要求 Developer ID 或 notarization。

### Draft 资产

Draft 包含：

- `Covio-0.5.2.app.zip`
- `Covio-0.5.2.pkg`
- `Covio-0.5.2.dmg`
- `Covio-Offline-0.5.2.dmg`
- `release-manifest.json`
- `checksums.txt`
- `release-evidence.json`
- `release-notes.generated.md`
- `release-operation.json`

远程复核命令：

```sh
bash scripts/publish-release.sh v0.5.2-internal.5 --dry-run
```

实际复核：

1. 下载 `Covio-0.5.2.dmg`、`release-manifest.json` 和 `checksums.txt`。
2. 重新计算下载文件的 SHA-256。
3. 通过 GitHub API 读取全部 9 个资产的 digest。
4. 比较本地文件和 GitHub digest。

结果：9 个资产的 size 和 SHA-256 全部一致。
默认 DMG 完成远程下载复核。
离线 DMG 的完整远程下载因网络速度中止；GitHub digest、本地 SHA-256、`checksums.txt` 和 `release-manifest.json` 四者一致。

## 结果汇总

| 测试 | 结果 | 证据 |
| --- | --- | --- |
| V09 | 通过 internal/local 检查 | [release-final.json](evidence/2026-10-25-release-final.json)、[draft-assets.json](evidence/2026-10-25-draft-assets.json) |

## 错误码

无。

## 清理记录

1. 卸载两个 DMG。
2. 删除本地测试副本。
3. 保留脱敏发布记录。
4. 保留 Draft，等待发布负责人审阅。

## 关联文档

- [验证索引](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
- [ADR-0020](../../../adr/adr-0020-local-only-helper-distribution.md)
