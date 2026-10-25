# 证据、复现与逻辑链

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 可评审 |
| 日期 | `2026-10-24` |
| 目标产品 commit | `cf663d5` |
| 目标发布版本 | `0.5.2` |

## 问题类别和案例映射

| 问题类别 | 验证案例 |
| --- | --- |
| 默认安装包体积 | [case-slim-install.md](validation/case-slim-install.md) |
| 模型下载、恢复和校验 | [case-model-delivery.md](validation/case-model-delivery.md) |
| 完全离线安装 | [case-offline-bundle.md](validation/case-offline-bundle.md) |
| app 更新保留模型 | [case-app-update.md](validation/case-app-update.md) |
| 发布物签名和校验和 | [case-release.md](validation/case-release.md) |

## 来源等级

| 等级 | 本报告中的来源 |
| --- | --- |
| A | GitHub 官方发布限制 |
| B | Covio 固定 commit、发布产物、manifest、ADR；GitHub 参考仓库固定 commit |
| C | 项目 README 和官方项目文档 |
| D | 本机 app、DMG 和体积探针 |
| E | 无 |

## 环境事实

| 项目 | 值 |
| --- | --- |
| 系统 | macOS 27.0.1 |
| Build | 26A434 |
| 架构 | arm64 |
| 内存 | `68,719,476,736` bytes |
| Xcode | 27.1 |
| Python | 3.9.6 |
| Covio 本机 app | `0.5.0` |
| Covio release metadata | `0.5.2` |

## 复现命令

以下变量是占位符：

```bash
RELEASE_APP="<release-app>"
RELEASE_DMG="<release-dmg>"
PROBE_ROOT="<probe-root>"
```

统计 app 和模型：

```bash
find "$RELEASE_APP" -type f -exec stat -f '%z' {} + | awk '{s+=$1} END {print s}'
find "$RELEASE_APP/Contents/Resources/Models" -type f \
  -exec stat -f '%z' {} + | awk '{s+=$1} END {print s}'
```

读取 DMG 信息：

```bash
hdiutil imageinfo "$RELEASE_DMG"
```

制作瘦包探针：

```bash
rsync -a --exclude='Contents/Resources/Models' \
  "$RELEASE_APP/" "$PROBE_ROOT/Covio-slim-probe.app/"
codesign --force --deep --sign - "$PROBE_ROOT/Covio-slim-probe.app"
mkdir -p "$PROBE_ROOT/stage"
ditto "$PROBE_ROOT/Covio-slim-probe.app" "$PROBE_ROOT/stage/Covio.app"
ln -s /Applications "$PROBE_ROOT/stage/Applications"
diskutil image create from --format UDZO --volumeName Covio \
  "$PROBE_ROOT/stage" "$PROBE_ROOT/Covio-slim-probe.dmg"
stat -f '%z' "$PROBE_ROOT/Covio-slim-probe.dmg"
```

读取模型 manifest：

```bash
for manifest in macosApp/src/AutoNaming/FileNamingModelManifest*.json; do
  jq -r '[.tier,.totalBytes,.modelID,.revision] | @tsv' "$manifest"
done
```

读取 release asset：

```bash
gh release view v0.5.2 --json assets \
  --jq '.assets[] | select(.name == "Covio-0.5.2.dmg") | .size'
```

## 证据索引

| 编号 | 主题 | 等级 | 置信度 |
| --- | --- | --- | --- |
| E-01 | `0.5.2` DMG 大小 | B | 高 |
| E-02 | 本地 app 和模型大小 | D | 高，范围有限 |
| E-03 | 非模型 app 组成 | D | 高，范围有限 |
| E-04 | 完整 DMG 压缩信息 | D | 高，范围有限 |
| E-05 | 无模型 DMG 探针 | D | 高，范围有限 |
| E-06 | 模型档位大小 | B | 高 |
| E-07 | 发布脚本复制模型 | B | 高 |
| E-08 | 现有校验和导入能力 | B | 高 |
| E-09 | 当前 app 内含 Hub bundle | D | 高，范围有限 |
| E-10 | WhisperKit 按需模型模式 | B、C | 中高 |
| E-11 | swift-transformers Hub 能力 | B | 高 |
| E-12 | mlx-swift-examples 下载和缓存 | B | 高 |
| E-13 | Sparkle BinaryDelta | B | 高 |
| E-14 | Dynamic Universal App | B、C | 中高 |
| E-15 | Stats 发布包大小 | B | 中 |
| E-16 | ADR-0007 的内置约束 | B | 高 |
| E-17 | ADR-0013 的模型档位 | B | 高 |
| E-18 | GitHub Release 单文件限制 | A | 高 |
| E-19 | 当前发布架构和系统要求 | B | 高 |
| E-20 | 统一发布身份和 artifact manifest | B | 高 |

## 证据详情

### E-01：Covio 0.5.2 DMG 为 1.54 GB

来源等级：B

环境：GitHub Release `v0.5.2`，查询日期 `2026-10-24`。

命令或来源：`gh release view v0.5.2 --json assets`。

关键输出：

```text
Covio-0.5.2.dmg  1,538,632,192 bytes
```

观察：当前最新内测 DMG 为 `1,538,632,192` bytes。

推论：默认安装包处于 GB 级，超过普通菜单栏 app 的下载规模。

反证：没有其他发布档位比该文件更小。

限制：GitHub 资产大小不等于安装后磁盘占用。

置信度：高

关联：`V01`

### E-02：本地 app 的模型占 98.10%

来源等级：D

环境：本机 `0.5.0` 发布 app；Covio `0.5.2` 与 `0.5.0` DMG 相差 `38,400` bytes。

命令或来源：对 `<release-app>` 执行 `find -type f -exec stat` 求和。

关键输出：

```text
app files:   1,832,767,333 bytes
model files: 1,798,035,956 bytes
model share: 98.10%
```

观察：模型目录包含 `1,798,035,956` bytes。

推论：模型是包体的唯一数量级来源。

反证：非模型文件仍有约 `34.7 MB`，但不足以改变结论。

限制：详细拆分来自 `0.5.0` 本机 app；`0.5.2` 全量下载未完成。

置信度：高，范围有限

关联：`E-01`、`E-03`、`V01`

### E-03：非模型 app 为 34,731,377 bytes

来源等级：D

环境：本机 `0.5.0` 发布 app。

命令或来源：按 `Contents` 子目录分别求和。

关键输出：

```text
Contents/MacOS                         25,571,232
Contents/Frameworks                     6,186,991
Contents/Resources excluding Models     2,955,288
Contents root files                         1,577
Contents/_CodeSignature                    16,289
base total                             34,731,377
```

观察：Swift 可执行文件为 `25,571,232` bytes。

推论：即使完全删除非模型内容，默认包仍不会因代码优化下降一个数量级。

反证：代码裁剪仍有几 MB 收益，但优先级低于模型交付。

限制：未测试删除未使用 framework 或资源后的功能影响。

置信度：高，范围有限

关联：`E-05`

### E-04：完整 DMG 使用 UDZO，压缩比约为 0.832

来源等级：D

环境：本机 `0.5.0` DMG，`1,538,593,792` bytes。

命令或来源：`hdiutil imageinfo <release-dmg>`。

关键输出：

```text
Format: UDZO
Total Non-Empty Bytes: 1,849,271,808
Compressed Bytes: 1,538,480,934
Compressed Ratio: 0.83193862218873993
```

观察：UDZO 已压缩约 `16.8%`。

推论：量化权重是高熵数据，只换压缩算法不能把包降到 `50 MB` 级。

反证：不同压缩器可能有小幅差异，但没有数量级变化。

限制：未执行 XZ 或 LZFSE 全量对比。

置信度：高，范围有限

关联：`E-03`、`E-05`

### E-05：移除模型后的 DMG 为 10,877,952 bytes

来源等级：D

环境：本机 `0.5.0` 发布 app 的临时副本；系统 macOS 27.0.1。

命令或来源：`rsync --exclude='Contents/Resources/Models'`，重新 ad-hoc 签名，再执行 `diskutil image create from`。

关键输出：

```text
Covio-slim-probe.app  33 MB allocated; 34,689,980 file bytes after re-sign
Covio-slim-probe.dmg  10,877,952 bytes
hdiutil verify        VALID
```

观察：无模型 DMG 为 `10,877,952` bytes。

推论：默认包具有降到 `50 MB` 以下的直接可行路径。

反证：该探针没有验证无模型启动和模型下载。

限制：探针只证明体积，不证明产品可用性。

置信度：高，范围有限

关联：`V01`、`V02`

### E-06：四个模型档位都已固定 revision、大小和哈希

来源等级：B

环境：Covio commit `cf663d5`。

命令或来源：`macosApp/src/AutoNaming/FileNamingModelManifest*.json`。

关键输出：

```text
2b      1,798,021,605  mlx-community/Qwen3-VL-2B-Instruct-4bit
4b      3,109,729,929  mlx-community/Qwen3-VL-4B-Instruct-4bit
8b      5,776,630,909  mlx-community/Qwen3-VL-8B-Instruct-4bit
30b-a3b 18,268,088,064 lmstudio-community/Qwen3-VL-30B-A3B-Instruct-MLX-4bit
```

观察：每个 manifest 都有固定 `revision`、逐文件大小和 SHA-256。

推论：模型可以脱离 app 交付，并保持相同完整性校验。

反证：manifest 本身需要由签名 app 提供信任根。

限制：清单总量不含 LICENSE、NOTICE 和 manifest 本身。

置信度：高

关联：`E-08`、`V03`、`V04`

### E-07：发布脚本把模型复制进 app

来源等级：B

环境：Covio commit `cf663d5`。

命令或来源：`scripts/package-macos-swift.sh`。

关键输出：

```text
Set COVIO_FILE_NAMING_MODEL_DIR to the verified local model directory.
MODEL_RESOURCE="$APP_IMAGE/Contents/Resources/Models/Qwen3VL-2B-Instruct-4bit"
ditto "$FILE_NAMING_MODEL_DIR" "$MODEL_RESOURCE"
```

观察：默认打包脚本要求外部模型目录，并把模型复制进 app。

推论：不修改发布脚本，就无法生成瘦 DMG。

反证：当前也能导入 app bundle 外的模型，但默认包仍带 2B 模型。

限制：未评估其他发布脚本对模型目录的复用。

置信度：高

关联：`E-08`、`V01`

### E-08：现有代码已能校验和登记外部模型

来源等级：B

环境：Covio commit `cf663d5`。

命令或来源：`macosApp/src/Model/LocalModelPackage.swift`、`macosApp/src/App/AppRuntime.swift`。

关键输出：

```text
LocalModelPackageVerifier.verify
LocalModelPackageRegistryStore.register
registeredModelConfiguration(registry:memory:)
```

观察：代码已支持导入模型包、校验 revision、大小、SHA-256、许可证和内存。

推论：按需下载可以复用现有信任与注册模型。

反证：当前没有产品内下载状态或原子下载目录。

限制：现有 registry 不负责删除、恢复和进度。

置信度：高

关联：`E-06`、`E-07`、`V03`、`V04`

### E-09：当前 app 已打包 Hub bundle

来源等级：D

环境：本机 `0.5.0` 发布 app。

命令或来源：发布 app 的 `Contents/Resources` 文件清单。

关键输出：

```text
swift-transformers_Hub.bundle
swift-crypto_Crypto.bundle
```

观察：发布 app 已包含 Hub 运行时资源。

推论：模型下载不需要引入新的 Hub 二进制依赖。

反证：bundle 存在不等于 app 已完成下载状态管理。

限制：依赖版本和 target 配置仍需在实施时核对。

置信度：高，范围有限

关联：`E-11`、`V03`

### E-10：WhisperKit 在首次使用时下载模型

来源等级：B、C

环境：`argmaxinc/argmax-oss-swift` commit `9f99b5cb6a907730543823ad271b82532782a899`。

命令或来源：
`https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/README.md`

关键输出：

```text
Models are hosted on HuggingFace and cached locally after the first download.
This will download only the model specified by MODEL.
```

观察：模型不随 app 内置；代码支持 `modelRepo` 和 `modelFolder`。

推论：模型按需下载并支持本地目录，是成熟的 Swift 应用模式。

反证：WhisperKit 不是 Covio，且模型和许可证不同。

限制：未在本机运行 WhisperKit。

置信度：中高

关联：`E-11`、`V03`

### E-11：swift-transformers Hub 支持后台下载和离线检查

来源等级：B

环境：`huggingface/swift-transformers` commit `e37cacea74498bba66002bb83ecafee3e4ab8884`。

命令或来源：
`https://github.com/huggingface/swift-transformers/blob/e37cacea74498bba66002bb83ecafee3e4ab8884/Sources/Hub/HubApi.swift`

关键输出：

```text
HubApi supports offline mode, background downloads, and automatic retry.
useBackgroundSession: Bool
downloadBase: URL
progressHandler: (Progress, Double?) -> Void
```

观察：Hub API 有下载目录、后台会话、进度、缓存和离线模式。

推论：Covio 的下载层可以直接建立在现有依赖之上。

反证：后台会话跨进程恢复仍需 app 生命周期接入。

限制：源码能力不等于 Covio 集成已经通过。

置信度：高

关联：`E-09`、`V03`

### E-12：MLX 示例下载并缓存模型

来源等级：B

环境：`ml-explore/mlx-swift-examples` commit `378f2449c257788c5067b9f8b086731d76b39b33`。

命令或来源：
`https://github.com/ml-explore/mlx-swift-examples/blob/378f2449c257788c5067b9f8b086731d76b39b33/Applications/MLXChatExample/Services/MLXService.swift`

关键输出：

```text
let downloader = #hubDownloader()
factory.loadContainer(from: downloader, ...)
self.modelDownloadProgress = progress
modelCache.setObject(container, ...)
```

观察：官方 MLX 示例把模型下载和模型加载接到同一个进度状态。

推论：Covio 可以沿用现有 MLX 加载路径，只替换模型目录来源。

反证：示例没有处理许可证、磁盘不足和 app 退出恢复。

限制：示例不是发布产品。

置信度：高

关联：`E-08`、`E-11`、`V03`

### E-13：Sparkle 提供 app BinaryDelta

来源等级：B

环境：`sparkle-project/Sparkle` commit `19688c1a0ae10240d884888e5b3190c15aee524b`。

命令或来源：
`https://github.com/sparkle-project/Sparkle/tree/19688c1a0ae10240d884888e5b3190c15aee524b/BinaryDelta`

关键输出：

```text
Create and apply small and efficient delta patches
between an old and new version of a bundle.
generate_appcast writes delta enclosures into the appcast.
```

观察：Sparkle 支持签名 appcast 和 app bundle 差分。

推论：Sparkle 适合后续 app 更新，但不解决首次安装携带模型。

反证：如果将来 app 体积仍较大，Sparkle 可以减少更新流量。

限制：当前发布链采用手工更新入口。

置信度：高

关联：`G` 方案

### E-14：Dynamic Universal App 下载完整架构包

来源等级：B、C

环境：`figma/dynamic-universal-app` commit `2966766912f44eb7be64e04f454f5c96b10df2dc`。

命令或来源：
`https://github.com/figma/dynamic-universal-app/blob/2966766912f44eb7be64e04f454f5c96b10df2dc/README.md`

关键输出：

```text
Users download the DUA bundle instead of the real app.
On launch, it will automatically download the architecture specific build.
```

观察：引导器按架构下载完整 app。

推论：该方法适合减少 Universal 2 的重复字节。

反证：Covio 只构建 arm64，且完整 app 仍包含模型。

限制：没有在 Covio 上运行引导器。

置信度：中高

关联：`E-19`、`D` 方案

### E-15：Stats 的默认 DMG 为 7.72 MB

来源等级：B

环境：`exelban/stats` release `v3.0.22`，查询日期 `2026-10-24`。

命令或来源：GitHub Releases API。

关键输出：

```text
Stats.dmg  7,724,844 bytes
```

观察：不带大模型的原生菜单栏 app 可以发布为个位数 MB。

推论：Covio 的 `10.88 MB` 瘦包探针处于合理范围。

反证：两个 app 的功能不同，不能直接比较性能或实现质量。

限制：未检查 Stats 内部资源和架构。

置信度：中

关联：`E-05`

### E-16：ADR-0007 要求模型随 app 内置

来源等级：B

环境：Covio commit `cf663d5`。

命令或来源：`docs/adr/adr-0007-offline-file-naming-model-package.md`。

关键输出：

```text
模型随应用内置
运行时只读取应用资源，不传入下载器
未采纳：首次启动下载模型
```

观察：当前架构明确选择内置模型，并优先保证安装后直接离线。

推论：新的默认下载方案必须写新 ADR，并明确取代旧决策的范围。

反证：可选离线整包可以保留旧决策的目标。

限制：ADR-0007 没有评估 `50 MB` 级默认包目标。

置信度：高

关联：`E-17`、`V06`、`V07`

### E-17：ADR-0013 保留多档模型

来源等级：B

环境：Covio commit `cf663d5`。

命令或来源：`docs/adr/adr-0013-local-model-tiers.md`。

关键输出：

```text
8–12 GB：Qwen3-VL-2B-Instruct-4bit
16 GB 以上：Qwen3-VL-4B-Instruct-4bit
24 GB 以上：可选 8B
32 GB 以上：可导入 30B-A3B
```

观察：模型选择由硬件档位决定。

推论：模型外置不改变档位策略，模型包必须按档位交付。

反证：4B 及更大模型不适合放在单个 GitHub Release 资产中。

限制：当前发布脚本默认仍复制 2B。

置信度：高

关联：`E-06`、`E-18`

### E-18：GitHub Release 单文件必须小于 2 GiB

来源等级：A

环境：GitHub Docs，查询日期 `2026-10-24`。

命令或来源：
`https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases`

关键输出：

```text
Each file included in a release must be under 2 GiB.
```

观察：GitHub Release 有单文件大小上限。

推论：4B、8B 和 30B-A3B 模型不能直接作为单个 GitHub Release 资产。

反证：2B 可以放在单个资产中，但该方案仍不覆盖全部档位。

限制：模型可以拆文件，但会增加发布和校验复杂度。

置信度：高

关联：`E-06`、`E-17`

### E-19：当前发布只支持 arm64 和 macOS 26+

来源等级：B

环境：Covio `0.5.2` 发布说明和 `0.5.0` app。

命令或来源：`RELEASE_NOTES.md`、`codesign -dvvv <release-app>`、`file <release-app>/Contents/MacOS/Covio`。

关键输出：

```text
Mach-O 64-bit executable arm64
LSMinimumSystemVersion 26.0
No Intel or Universal 2 build.
```

观察：当前发布只构建 Apple Silicon。

推论：按架构拆分的 Dynamic Universal App 不是本问题的主要解法。

反证：将来支持 Intel 时需要重新评估按架构分发。

限制：该事实不约束模型文件架构。

置信度：高

关联：`E-14`

### E-20：发布链已有统一身份和 artifact manifest

来源等级：B

环境：Covio commit `922ef31`。

命令或来源：`release/README.md`、`release/release-manifest.json`、`scripts/release_manifest.py`。

关键输出：

```text
release/release-manifest.json is the source of truth for:
- product version
- build number
- release channel
- helper protocol version

The artifact manifest adds gitCommit, releaseId and helperSHA256.
```

观察：发布版本已有单一来源，artifact manifest 已记录 commit、releaseId 和 helper SHA-256。

推论：默认包和离线整包必须共用同一发布身份。

反证：当前 artifact manifest 没有记录两个 DMG 或模型 revision。

限制：扩展 artifact manifest 属于后续 Feature。

置信度：高

关联：`V09`

## 逻辑证据链

1. 用户看到 `1.54 GB` DMG。证据：`E-01`。
2. 模型目录为 `1.80 GB`，占 app 文件总量 `98.10%`。证据：`E-02`。
3. 非模型 app 只有 `34.73 MB`。证据：`E-03`。
4. UDZO 压缩已把完整 app 压缩到约 `83.2%`。证据：`E-04`。
5. 移除模型后的 DMG 为 `10.88 MB`。证据：`E-05`。
6. 所有模型档位已有固定 revision 和 SHA-256。证据：`E-06`。
7. 当前发布脚本仍强制内置模型。证据：`E-07`。
8. Covio 已能校验和登记外部模型。证据：`E-08`。
9. Covio 已包含 Hub bundle。证据：`E-09`。
10. GitHub 项目已验证按需下载、缓存和进度模式。证据：`E-10`、`E-11`、`E-12`。
11. 差分更新不能解决首次安装。证据：`E-13`。
12. 架构引导器不能解决模型体积。证据：`E-14`、`E-19`。
13. 新方案需要新 ADR，并保留可选离线整包。证据：`E-16`、`E-17`。
14. 模型默认源应采用 Hugging Face Hub，而不是单个 GitHub Release 资产。证据：`E-17`、`E-18`。
15. 默认包和离线整包必须复用统一发布身份。证据：`E-20`。

## 反证和限制

1. 模型外置只减少默认下载，不减少安装后的模型占用。
2. 首次使用需要一次网络连接。
3. `0.5.2` 全量下载受网络速度限制，详细拆分使用 `0.5.0` 发布 app。
4. 默认瘦包已经完成无模型启动和 UI 验证。
5. `swift-transformers` 的真实下载、暂停和跨实例恢复已经验证。
6. Hugging Face 在部分网络的可用性未知。
7. 可选离线整包仍需承担约 `1.54 GB` 下载。
8. 没有 Developer ID 和 notarization。ADR-0020 把这两项划为当前 internal/local 渠道之外。

## 已知缺口

| 项目 | 状态 | 证据 |
| --- | --- | --- |
| 默认包和离线包拆分 | 完成 | 默认 `13,218,304` bytes；离线 `1,540,934,144` bytes |
| 无模型启动 | 通过 | [case-slim-install.md](validation/case-slim-install.md) |
| 真实下载恢复 | 通过 | [model-download.json](validation/evidence/2026-10-25-model-download.json) |
| 损坏模型拒绝 | 通过 | 返回 `checksumMismatch` |
| app 更新保留模型 | 通过 | registry SHA-256 不变 |
| 离线推理 | 通过 | 文件命名和 Agent 都没有非 loopback 网络行 |
| 默认包完整远程回读 | 通过 | 下载后的 SHA-256 一致 |
| 离线包完整远程回读 | 未完成 | 网络速度不足；GitHub digest 与本地 SHA-256 一致 |
| Developer ID 和 notarization | 范围外 | ADR-0020 |

## 复核方法

1. 重新执行 `E-01`，确认最新 release asset 大小。
2. 重新执行 `E-02` 到 `E-05`，确认包体结构。
3. 检查 manifest 的 `revision`、`totalBytes` 和 SHA-256。
4. 检查 GitHub 参考仓库的固定 commit。
5. 按 [validation/README.md](validation/README.md) 执行 `V01` 到 `V09`。
6. 使用 `bash scripts/verify-model-download.sh` 和 `bash scripts/verify-model-disk-guard.sh` 复核模型下载与磁盘保护。
7. 发布后记录默认包和离线整包的 SHA-256。

## 参考来源

- [Covio v0.5.2 release](https://github.com/wyz541/kmp-Covio/releases/tag/v0.5.2)
- [ADR-0007](../../adr/adr-0007-offline-file-naming-model-package.md)
- [ADR-0013](../../adr/adr-0013-local-model-tiers.md)
- [WhisperKit model acquisition](https://github.com/argmaxinc/argmax-oss-swift/blob/9f99b5cb6a907730543823ad271b82532782a899/README.md)
- [swift-transformers HubApi](https://github.com/huggingface/swift-transformers/blob/e37cacea74498bba66002bb83ecafee3e4ab8884/Sources/Hub/HubApi.swift)
- [mlx-swift-examples MLXChatExample](https://github.com/ml-explore/mlx-swift-examples/blob/378f2449c257788c5067b9f8b086731d76b39b33/Applications/MLXChatExample/Services/MLXService.swift)
- [Sparkle BinaryDelta](https://github.com/sparkle-project/Sparkle/tree/19688c1a0ae10240d884888e5b3190c15aee524b/BinaryDelta)
- [Dynamic Universal App](https://github.com/figma/dynamic-universal-app/blob/2966766912f44eb7be64e04f454f5c96b10df2dc/README.md)
- [Stats v3.0.22](https://github.com/exelban/stats/releases/tag/v3.0.22)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

## 关联文档

- [主题索引](README.md)
- [问题与边界](context.md)
- [调研与候选方案](investigation.md)
- [结论](conclusion.md)
- [推荐方案](solution.md)
- [验证矩阵](validation/README.md)
