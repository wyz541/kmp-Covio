# ADR-0007：文件自动命名模型随应用内置

- Status：accepted
- Kind：architecture
- Date：2026-10-21
- Supersedes：none
- Implements：#178
- 相关：[文件自动命名调研](../research/file-auto-naming/README.md)

## 背景

Covio 的文件自动命名使用本地 `Qwen3-VL-2B-Instruct-4bit`。
模型文件约 1.8 GB。
用户安装后应直接离线使用。
运行时不接受远程 AI 服务。
应用也不应要求用户另行安装服务或维护本地端口。

## 决策

1. 模型随应用内置在 `Contents/Resources/Models/Qwen3VL-2B-Instruct-4bit/`。
2. 模型权重不进入 Git。
3. 发布脚本要求 `COVIO_FILE_NAMING_MODEL_DIR` 指向已校验的本地模型目录。
4. 模型清单固定在 `macosApp/src/AutoNaming/FileNamingModelManifest.json`。
5. 发布前校验文件大小和 SHA-256。
6. 运行时只读取应用资源，不传入下载器。
7. Apache-2.0 许可证、NOTICE 和第三方许可证随应用打包。
8. 发布包在拒绝网络访问的沙箱中完成文本和图片烟雾测试。

## 后果

### 正面

- 用户安装后直接获得离线能力。
- 不需要 Ollama 或其他外部服务。
- 模型 revision 和文件内容可重复验证。
- 运行时网络行为可以用拒绝网络访问直接验证。

### 负面

- 应用包体积增加约 1.8 GB。
- 发布前需要先下载和校验模型。
- GitHub Release 单文件资产接近 2 GB 上限。

### 风险

- 模型资产变更会改变输出。缓解：固定 revision、清单和 SHA-256。
- 下载中断会留下不完整模型。缓解：`curl --continue-at -` 和逐文件校验。
- 模型许可证或归属遗漏。缓解：发布脚本检查许可证和 NOTICE。
- 大包上传失败。缓解：记录 DMG 字节数，超限时改用拆分发布方案。

## 备选方案

### 备选 1：独立模型安装包

模型由单独下载安装在首次启动时完成。

未采纳的原因：首次使用仍需联网。
用户会得到不完整的初始安装。
模型目录和版本会增加额外迁移逻辑。

### 备选 2：首次启动下载模型

应用启动后从模型站点下载。

未采纳的原因：违反离线运行目标。
文件命名功能依赖远程服务可达性。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| GitHub Release 资产是否小于 2 GB | 通过，1,537,739,776 bytes | 打包后读取 DMG 字节数 |
| Developer ID 公证 | 不在本 ADR 范围 | 后续发布决策 |

## 参考

- [推荐方案](../research/file-auto-naming/solution.md)
- [模型清单](../../macosApp/src/AutoNaming/FileNamingModelManifest.json)
- [Qwen3-VL-2B-Instruct](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct)
- [MLX 4-bit conversion](https://huggingface.co/mlx-community/Qwen3-VL-2B-Instruct-4bit)
