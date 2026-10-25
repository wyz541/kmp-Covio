# Draft-first 发布流水线

## 状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 已实现；正式签名门槛待凭据 |
| 日期 | `2026-10-25` |
| Issue | #356 |
| 上游决策 | ADR-0018 |

## 目标

发布先进入 Draft。
只有全部验证通过后，维护者才能显式发布。
任一步失败时，Draft 保持未发布状态。

## 资产

一次发布包含：

```text
Covio-<version>.app.zip
Covio-<version>.dmg
Covio-<version>.pkg
release-manifest.json
checksums.txt
release-evidence.json
release-notes.generated.md
release-operation.json
```

`release-evidence.json` 记录全部资产摘要、releaseId、commit、协议和验证结果。
`release-notes.generated.md` 从同一份证据生成。
`checksums.txt` 只包含四个载荷文件。
`Covio.app` 的 Resources 同时携带同一份 `release-manifest.json`。
PKG 把 app 写入暂存区，再通过原子 bundle 交换完成 app 与 helper 的成对安装。

## 创建 Draft

内部渠道：

```sh
bash scripts/create-release.sh
```

该命令默认构建制品并创建 Draft。
内部 tag 使用 `v<version>-internal.<build>`。
内部 Draft 同时标记为 pre-release。

复用刚构建的制品：

```sh
bash scripts/create-release.sh --skip-package
```

只检查命令，不调用 GitHub：

```sh
bash scripts/create-release.sh --dry-run --skip-package
```

## 发布 Draft

```sh
bash scripts/publish-release.sh v<tag>
```

发布命令重新下载 Draft 资产。
发布命令重算 release evidence。
发布命令检查 Draft、tag、pre-release 标记和 app/helper 成对资产。
任一检查失败时，命令在 `gh release edit` 前退出。

内部渠道发布后保持 pre-release。
内部渠道不会成为正式 latest。

## 正式发布环境

正式渠道必须设置：

```text
COVIO_CODE_SIGN_IDENTITY
COVIO_INSTALLER_SIGN_IDENTITY
COVIO_DEVELOPMENT_TEAM
COVIO_NOTARY_PROFILE
```

正式渠道还必须满足：

- app 和 helper 使用 Developer ID Application 和 hardened runtime。
- DMG 使用 Developer ID Application。
- PKG 使用 Developer ID Installer。
- app、DMG 和 PKG 通过 notarization staple。
- app 和 PKG 通过 Gatekeeper。
- helper 和 app 的 releaseId、commit、协议和摘要完全一致。
- app 和 helper 都包含在 app zip 中。

当前机器没有 Developer ID 和 notarization 凭据。
正式发布命令会在构建前失败关闭。

## 失败行为

| 阶段 | 失败结果 |
| --- | --- |
| 构建 | 不创建 Release |
| 资产校验 | 不创建 Release |
| Draft 上传 | 已创建的 Draft 保持未发布 |
| Draft 重验 | Draft 保持未发布 |
| 操作记录上传 | Draft 保持未发布 |
| 显式发布 | Draft 保持未发布 |

## 检查项

| 检查 | 内部 | 正式 |
| --- | --- | --- |
| release manifest 和源清单一致 | 必须 | 必须 |
| app/helper releaseId 一致 | 必须 | 必须 |
| app/helper 版本、build、commit、协议一致 | 必须 | 必须 |
| helper SHA-256 一致 | 必须 | 必须 |
| app/helper 架构为 arm64 | 必须 | 必须 |
| app zip、DMG、PKG 和 checksums 完整 | 必须 | 必须 |
| DMG 中的 app/helper 与 app zip 一致 | 必须 | 必须 |
| PKG 包含暂存 app、helper、交易工具和恢复命令 | 必须 | 必须 |
| Developer ID Application | 不要求 | 必须 |
| Developer ID Installer | 不要求 | 必须 |
| hardened runtime | 不要求 | 必须 |
| notarization 和 Gatekeeper | 不要求 | 必须 |

## 操作记录

`release-operation.json` 记录：

- action。
- repository 和 tag。
- channel。
- releaseId 和 Git commit。
- 全部资产摘要。
- 验证状态。
- 记录时间。

创建 Draft 时上传 `create-draft` 记录。
发布前用 `publish` 记录替换 Draft 中的旧记录。

## 验证命令

```sh
python3 -I scripts/test_release_pipeline.py
bash scripts/test-all.sh
```
