# Case 6：内置模型打包与断网运行

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 通过 |
| 执行时间 | 2026-10-21 |
| 环境 | macOS 27，Apple Silicon |
| 模型 | `Qwen3-VL-2B-Instruct-4bit` |
| 模型 revision | `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |
| 应用版本 | 0.5.0 |

[返回验证目录](README.md)

[证据附录](../evidence.md)

[主题索引](../README.md)

## 验证目标

1. 模型随应用内置。
2. 模型文件不进入 Git。
3. 发布前校验文件清单、大小和 SHA-256。
4. Apache-2.0 许可证、NOTICE 和第三方许可证进入安装包。
5. 签名后的 DMG 可挂载和干净复制。
6. 拒绝网络访问时仍可完成文本和图片自动命名。
7. 重命名和撤销在安装包内可用。
8. DMG 小于 GitHub Release 单文件上限。

## 发布决策

采用内置模型方案。
详见 [ADR-0007](../../../adr/adr-0007-offline-file-naming-model-package.md)。

## 固定模型清单

清单文件：

```text
macosApp/src/AutoNaming/FileNamingModelManifest.json
```

模型统计：

| 指标 | 值 |
| --- | --- |
| 文件数 | 14 |
| 模型文件合计 | 1,798,021,605 bytes |
| 主权重 SHA-256 | `4750d95a2162829e127a94e83ac350d498d02070aab216c4687da48804a06ffb` |
| 许可证 | Apache-2.0 |

下载和校验命令：

```bash
python3 scripts/file_naming_model.py download build/models/Qwen3VL-2B-Instruct-4bit
```

## 打包结果

命令：

```bash
COVIO_FILE_NAMING_MODEL_DIR=build/models/Qwen3VL-2B-Instruct-4bit \
  bash scripts/package-macos-swift.sh
```

实际结果：

| 产物 | 字节数 |
| --- | --- |
| `dist/Covio.app` | 1,830,531,072 |
| `dist/Covio-0.5.0.dmg` | 1,537,739,776 |

DMG SHA-256：

```text
d07c5fc1fad2219f4c41b0207836676ae6d2ca4c4d8291e6b8557649c64d5587
```

GitHub Release 单文件门槛是 2,147,483,648 bytes。
DMG 小于门槛。

## 断网运行验证

命令：

```bash
bash scripts/verify-file-naming-bundle.sh dist/Covio-0.5.0.dmg
```

步骤：

1. 只读挂载 DMG。
2. 把 `Covio.app` 复制到独立安装目录。
3. 校验代码签名。
4. 校验内置模型文件、许可证和 NOTICE。
5. 使用独立支持和临时目录启动应用。
6. 用 `sandbox-exec` 拒绝网络访问。
7. 采样进程网络 socket。
8. 运行真实文本和图片自动命名。
9. 应用两项重命名。
10. 撤销全部重命名。

实际结果：

```text
ok: true
stage: results
selected: 2
renamed: 2
undoSucceeded: 2
originalName: input.txt
targetName: 2026年第四季度产品预算评审.txt
originalName: receipt.png
targetName: 差旅报销单.png
smoke_processes: 1
non_loopback_network_rows: 0
```

结论：

1. 内置模型可加载。
2. 文本和图片都能生成名称。
3. 两项重命名都成功。
4. 两项撤销都成功。
5. 断网沙箱内运行通过。
6. 进程采样没有非 loopback 网络行。

## 许可证

应用包包含：

1. `ThirdPartyNotices/THIRD_PARTY_NOTICES.md`
2. `ThirdPartyNotices/licenses/`
3. `ThirdPartyNotices/model/Qwen3-VL-2B-Instruct/LICENSE`
4. `ThirdPartyNotices/model/Qwen3-VL-2B-Instruct/NOTICE`

## 限制

1. 本轮是安装目录复制，不是 Finder 拖入 `/Applications`。
2. 没有执行 Developer ID 公证。
3. 8 GB 和其他内存配置由 #179 验证。
4. 12 样本质量和性能矩阵由 #179 验证。
5. 网络拒绝使用进程级沙箱，不是全系统断网测试。

## 清理记录

1. DMG 挂载已卸载。
2. 安装副本已删除。
3. 支持目录和临时目录已删除。
4. 模型下载目录在任务结束时删除。

## 关联文档

- [ADR-0007](../../../adr/adr-0007-offline-file-naming-model-package.md)
- [验证目录](README.md)
- [安全重命名](case-safe-rename.md)
- [模型接入](case-mlx-swift-runtime.md)
