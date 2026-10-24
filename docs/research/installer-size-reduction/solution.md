# 推荐方案、接口与实施计划

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 可评审 |
| 日期 | `2026-10-24` |
| 推荐方案 | 瘦 app + 受控模型下载 + 可选离线整包 |
| 实施状态 | 尚未执行 |

## 推荐架构

默认发布物只包含 `Covio.app`。
模型通过独立的模型包交付。
模型包可以来自 Hugging Face Hub。
模型包也可以来自用户导入的本地目录。
需要无网络安装时，发布单独的离线整包。

发布物如下：

| 发布物 | 内容 | 默认 | 目标大小 |
| --- | --- | --- | ---: |
| `Covio-<version>.dmg` | app、manifest、许可证 | 是 | 不大于 `50 MB` |
| Hugging Face 模型包 | 固定 revision 的模型文件 | 按需 | 当前 2B 约 `1.80 GB` |
| `Covio-Offline-<version>.dmg` | app 和模型 | 否 | 接近当前完整 DMG |

离线整包按单档位生成。
如果单文件超过 GitHub Release 限制，发布物拆成有顺序的资产。
发布清单记录每个分片的 SHA-256 和重组顺序。

## 组件职责

| 组件 | 职责 |
| --- | --- |
| `package-macos-swift.sh` | 默认不复制模型，生成瘦 app |
| `package-offline-macos.sh` | 复制已校验模型，生成可选离线整包 |
| `ModelInstallState` | 保存 `not_installed`、下载、校验、就绪和错误状态 |
| `ModelDownloader` | 请求固定 revision，显示进度，支持恢复 |
| `LocalModelPackageVerifier` | 校验 revision、硬件、文件大小、SHA-256 和许可证 |
| `LocalModelPackageRegistryStore` | 原子登记已完成模型 |
| `NamingModelConfiguration` | 优先选择已登记模型，再选择兼容的内置模型 |
| `AppRuntime` | 没有模型时进入 `not_installed`，不创建无效加载器 |
| Settings UI | 提供下载、暂停、恢复、导入和移除入口 |
| Offline packaging script | 生成无网络安装用的大包 |
| `release/release-manifest.json` | 保持 app、helper、模型和离线包的版本来源 |

## 调用路径

1. `AppRuntime` 读取 `imported-packages.json`。
2. `AppRuntime` 选择硬件允许的最高已登记档位。
3. 如果没有已登记模型，状态为 `not_installed`。
4. 用户打开 AI 功能时，UI 显示模型大小和许可证。
5. 用户确认后，`ModelDownloader` 创建暂存目录。
6. Hub 客户端按 manifest 下载文件。
7. 下载进度写入 `ModelInstallState`。
8. 所有文件完成后，`LocalModelPackageVerifier` 执行校验。
9. registry 以原子写入登记模型。
10. `ModelInstallState` 进入 `ready`。
11. MLX runtime 从正式模型目录加载。
12. 后续启动只读本地目录，不访问模型源。

## 文件位置

默认模型目录：

```text
$HOME/Library/Application Support/com.wyz.covio/Models/
├── imported-packages.json
├── staging/
│   └── <download-id>/
└── packages/
    └── Qwen3VL-2B-Instruct-4bit/
        └── <revision>/
            ├── FileNamingModelManifest.json
            ├── model.safetensors
            ├── tokenizer.json
            └── other-manifest-files
```

规则：

1. `staging/` 只保存未完成或未验证文件。
2. `packages/<tier>/<revision>/` 只保存完成校验的模型。
3. app 更新不修改 `Models/`。
4. 删除模型必须由用户确认。
5. 模型目录不得使用符号链接指向目录外文件。

## 接口契约

### 传输

1. 默认模型源使用 HTTPS。
2. 模型 ID、revision 和文件列表来自 app 内 manifest。
3. 下载层读取 manifest，不接受远端 manifest 替换本地 manifest。
4. 模型完成校验前不进入 `packages/`。

### 权限

1. 模型下载由用户主动确认。
2. 导入模型包由用户通过文件选择器确认。
3. app 不申请管理员权限来安装模型。
4. 模型保存在当前用户目录。

### Manifest 请求字段

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| `schemaVersion` | Integer | 首版为 `1` |
| `tier` | String | `2b`、`4b`、`8b` 或 `30b-a3b` |
| `modelID` | String | 固定上游模型 ID |
| `revision` | String | 固定 SHA revision |
| `runtimeDirectory` | String | 必须匹配档位 |
| `license` | String | 当前为 `Apache-2.0` |
| `licenseFile` | String | 模型目录内相对路径 |
| `noticeFile` | String | 模型目录内相对路径 |
| `totalBytes` | Integer | 等于所有 manifest 文件大小之和 |
| `files` | Array | 每项含 `path`、`size`、`sha256` |

### Manifest 响应字段

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| `verifiedTier` | String | 与实际档位相同 |
| `verifiedRevision` | String | 与 manifest 相同 |
| `verifiedBytes` | Integer | 与 manifest 相同 |
| `verifiedAtEpochMilliseconds` | Integer | 校验完成时间 |
| `directoryPath` | String | 已提交的正式目录 |

### 操作列表

| 操作 | 前置条件 | 结果 |
| --- | --- | --- |
| `model.check` | app 已启动 | 返回本地模型状态 |
| `model.download` | 用户确认、网络可用、磁盘足够 | 下载到暂存目录 |
| `model.pause` | 正在下载 | 保留可恢复状态 |
| `model.resume` | 存在可恢复下载 | 继续下载 |
| `model.verify` | 文件集完整 | 返回通过或错误 |
| `model.activate` | 校验通过 | 原子登记模型 |
| `model.import` | 用户选择目录 | 校验并登记模型 |
| `model.remove` | 非当前加载或已释放 | 删除模型和登记 |

### 错误码

| 错误码 | 含义 | 用户动作 |
| --- | --- | --- |
| `model_source_unavailable` | 模型源不可达 | 检查网络或稍后重试 |
| `model_download_cancelled` | 用户暂停或退出 | 继续下载 |
| `model_download_incomplete` | 文件集不完整 | 重试缺失文件 |
| `model_hash_mismatch` | SHA-256 不匹配 | 重新下载 |
| `model_size_mismatch` | 文件大小不匹配 | 重新下载 |
| `model_revision_mismatch` | revision 不匹配 | 更新 app 或模型清单 |
| `model_license_rejected` | 许可证不匹配 | 拒绝加载 |
| `model_insufficient_disk` | 可用磁盘不足 | 释放磁盘 |
| `model_insufficient_memory` | 硬件或可用内存不足 | 选择较低档位 |
| `model_path_unsafe` | 相对路径或符号链接不安全 | 拒绝加载 |
| `model_activation_failed` | 原子登记失败 | 保留旧模型并重试 |

## 关键流程

### 下载流程

1. 用户选择 AI 功能。
2. UI 显示模型大小、许可证和网络需求。
3. 用户确认下载。
4. app 检查可用磁盘。
5. app 创建唯一暂存目录。
6. Hub 客户端逐文件下载。
7. 每个文件记录进度和速率。
8. 下载完成后执行全量校验。
9. 校验通过后原子移动到正式目录。
10. registry 写入模型记录。
11. runtime 加载模型。

### 恢复流程

1. app 启动时扫描未完成下载。
2. registry 不包含暂存目录。
3. UI 显示可恢复下载。
4. 用户恢复后复用 HTTP 缓存或临时文件。
5. 完成校验后才允许加载。

### 更新流程

1. app 更新时只替换 `Covio.app`。
2. registry 继续指向 `Application Support` 中的模型。
3. app 校验模型 revision 是否兼容。
4. 兼容时直接加载，不下载模型。
5. 不兼容时保留旧模型，直到新模型完成。
6. 新模型可用后，用户确认删除旧 revision。

### 离线整包流程

1. 发布脚本读取已校验模型目录。
2. 脚本把模型复制进离线 app 的 Resources。
3. 脚本执行模型清单校验。
4. 脚本生成独立 DMG。
5. 首次启动发现内置模型，直接登记。
6. app 在断网环境完成 AI 功能验收。

## 安全设计

1. app 内 manifest 是模型身份的唯一信任根。
2. 模型下载源不能修改允许的 revision 或文件哈希。
3. 每个文件在加载前校验 SHA-256。
4. manifest 路径只能是安全的相对路径。
5. 正式目录不能包含符号链接逃逸。
6. 模型包许可证和 NOTICE 随模型保存。
7. 下载器不读取用户文件、会话、剪贴板或 Agent 内容。
8. 模型请求不包含用户标识和应用数据。
9. 失败时保留旧模型，不覆盖已可用目录。
10. 可选离线整包继续使用 Developer ID 与 notarization 发布链。

## 合规设计

1. 模型许可证为 `Apache-2.0`。
2. app 和模型目录都保留 LICENSE 与 NOTICE。
3. 第三方许可证清单继续随 app 发布。
4. 下载来源和 revision 写入发布记录。
5. 发布说明写明默认包不含模型。
6. 发布说明写明离线整包路径和大小。

## 可靠性设计

1. 下载写入 `staging/`，完成校验后原子提交。
2. 提交前不修改 registry。
3. 模型文件修改时间不参与身份判断。
4. 下载中断后保留恢复所需元数据。
5. 模型校验失败时删除无效暂存文件。
6. app 更新不删除模型目录。
7. 模型加载失败时释放 runtime 租约。
8. 磁盘不足时在下载前拒绝。
9. 模型源不可用时允许本地导入。
10. 离线整包不经过模型下载器。

## 失败模式

| 失败 | 结果 | 恢复 |
| --- | --- | --- |
| 网络中断 | `paused` 或 `failed` | 恢复下载 |
| 下载文件损坏 | `failed` | 删除文件并重试 |
| 磁盘不足 | `failed` | 释放磁盘后重试 |
| 校验超时 | `failed` | 重试校验 |
| registry 写入失败 | 旧 registry 不变 | 重试原子写入 |
| app 更新后 revision 不兼容 | 旧模型保留但不加载 | 下载兼容模型 |
| 模型源下线 | 下载失败 | 使用镜像或本地导入 |
| 用户删除模型 | `not_installed` | 重新下载或导入 |

## 验收标准

1. 默认 DMG 不大于 `50 MB`。
2. app 在模型缺失时可以启动。
3. 非 AI 功能在模型缺失时可用。
4. 用户确认后才开始下载。
5. 下载中断后可以恢复。
6. 损坏文件无法登记或加载。
7. 模型就绪后断网可用。
8. app 更新不重下相同 revision。
9. 离线整包可以在断网环境完成安装。
10. 发布物包含大小、SHA-256 和签名验证记录。

## 实施计划

| 步骤 | 工作 | 工期 | 验收 |
| --- | --- | ---: | --- |
| 1 | 拆分默认和离线打包脚本 | 1 天 | 默认 DMG 不含模型，大小不大于 `50 MB` |
| 2 | 增加模型安装状态和下载器 | 2 天 | 下载、暂停、恢复和进度可观察 |
| 3 | 接入 verifier 和 registry 原子提交 | 1 天 | 损坏模型不登记 |
| 4 | 增加 AI 功能下载入口和离线错误 | 1 天 | 无模型时 app 可用且说明清楚 |
| 5 | 增加可选离线整包流程 | 1 天 | 断网安装后可推理 |
| 6 | 扩展发布清单记录两个 artifact | 1 天 | 默认包和离线包都有大小、顺序和 SHA-256 |
| 7 | 真机验收和发布记录 | 1 到 2 天 | `V01` 到 `V09` 有结果 |

一个子 issue 只覆盖一个会话能完成的工作。
每个子 issue 必须有一行可验证的验收标准。

## 回滚条件

满足任一条件时回滚到完整内置模型包：

1. 默认 DMG 大于 `50 MB`。
2. 模型下载无法可靠恢复。
3. 模型校验导致无法完成安装。
4. 无模型时 app 启动失败。
5. 模型就绪后仍依赖网络。
6. app 更新删除或破坏已有模型。
7. 离线整包无法在断网环境运行。

回滚不删除用户已下载模型。
回滚发布时先恢复完整内置模型 DMG。

## 产品化条件

1. `V01` 到 `V08` 通过。
2. 默认发布脚本不再要求模型目录。
3. 离线整包发布脚本执行模型校验。
4. 发布说明区分默认包和离线整包。
5. 发布目录记录两个包的 SHA-256。
6. Developer ID 和 notarization 验证由发布链任务完成。
7. ADR 记录取代 ADR-0007 的范围。
