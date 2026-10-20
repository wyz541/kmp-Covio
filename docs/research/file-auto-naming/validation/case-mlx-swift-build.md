# Case 2：MLX Swift 构建

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 部分通过 |
| 执行时间 | 2026-10-20 |
| 环境 | macOS 27.0.1，arm64，Xcode 27.1 |
| 依赖 | `mlx-swift-lm` commit `48114eedf3c3d4a682a6b1d644cc5af5c2945d10` |

[返回验证目录](README.md)  
[证据附录](../evidence.md)  
[主题索引](../README.md)

## 验证目标

验证最小 Swift 包能够构建 `MLXVLM`。
验证 MLX Swift 是否可作为 Covio 的主运行时。

## 预检记录

| 项目 | 结果 |
| --- | --- |
| Xcode | 27.1 |
| Swift | 6.4 |
| macOS SDK | 27.0 |
| Metal Toolchain | 27A266a，已安装 |
| Swift Package 解析 | 通过 |
| 宏验证 | 通过 Xcode 参数跳过 |

## 测试前采集

最小包依赖：

```text
mlx-swift-lm
swift-huggingface
swift-transformers
```

最小包产品：

```text
MLXVLM
MLXLMCommon
MLXHuggingFace
```

## 执行步骤

### 直接 SwiftPM

前置条件：进入最小 Swift 包目录。

命令：

```bash
swift build -c release
```

预期结果：生成 `NamingBench` 可执行文件。

实际结果：Metal 编译失败。

错误输出：

```text
error: cannot execute tool 'metal' due to missing Metal Toolchain
error: Build failed
```

错误码：`metal_toolchain_shim`

备注：

1. `xcodebuild -showComponent MetalToolchain -json` 返回 `installed`。
2. `xcrun metal --version` 成功。
3. 直接 `swift build` 仍调用 Xcode 的旧 shim。

### Xcode Swift Package

前置条件：使用同一最小包。

命令：

```bash
xcodebuild -scheme NamingBench -configuration Release \
  -destination 'platform=macOS' \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build
```

预期结果：生成 Release 可执行文件。

实际结果：构建成功。

关键输出：

```text
CompileMetalFile ... rope.metal
CompileMetalFile ... steel_attention.metal
BUILD SUCCEEDED
```

错误码：无。

## 结果汇总

| 项目 | 结果 |
| --- | --- |
| Swift 依赖解析 | 通过 |
| Metal Toolchain | 已安装 |
| 直接 SwiftPM | 失败 |
| Xcode Swift Package | 通过 |
| Metal 文件编译 | 通过 |
| Covio 工程集成 | 未执行 |

## 清理记录

1. Metal Toolchain 保持安装。
2. 没有修改 Covio 工程。
3. 临时包和 DerivedData 在任务临时目录。
4. 构建缓存将在任务结束时删除。

## 更新规则

1. 接入 Covio 工程后重新执行。
2. 直接 SwiftPM 修复后删除 `metal_toolchain_shim` 阻塞。
3. Xcode 构建参数变化时更新本文件。
4. 如果 Covio 构建失败，保留失败日志。

## 关联文档

- [验证目录](README.md)
- [MLX Swift 运行](case-mlx-swift-runtime.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
- [推荐方案](../solution.md)
