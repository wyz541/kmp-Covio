# Windows CMP 客户端宿主可行性研究

> 结论：条件可行。Compose Multiplatform 可以承载 Windows JVM 客户端。Amper 0.12.1 可以编译 Windows 宿主并生成可执行 JAR。现有共享测试有 12 个 Windows 失败。安装包必须由 Windows 本机工具生成，Windows 真机验收仍待执行。

| 项目 | 内容 |
| --- | --- |
| 状态 | 初稿，可评审 |
| 日期 | 2026-10-24 |
| 负责人 | @wyz541 |
| Issue | #318 |
| 范围 | Windows 宿主、构建、打包和运行边界 |
| 范围外 | 跨设备发现、配对和远程控制协议 |

## 前因

Covio 的 macOS 宿主使用 SwiftUI。共享领域逻辑使用 `kmpDomain`。仓库尚无 Windows 宿主。用户要求 Windows 客户端使用 Kotlin Multiplatform 与 Compose Multiplatform（CMP）。

## 背景

Amper 0.12.1 是唯一构建入口。仓库明确禁止改用 Gradle。CMP 常与 Gradle Compose 插件一起使用。这个组合是否能满足 Covio 的约束需要验证。

当前 `kmpDomain` 已包含 `jvm` 平台。Windows 可以使用这份共享代码。Windows 宿主仍需自己的托盘、单实例、启动项和系统信息适配器。

## 过程

调研分四步。

1. 读取 Amper 0.12.1 的产品类型与 Compose 配置。
2. 在临时工程编译并打包最小 CMP 应用。
3. 在 Windows CI 编译、测试并验证 `jpackage`。
4. 对照官方 CMP 与 `jpackage` 文档，确定发行边界。

详细过程见 [investigation.md](investigation.md)。原始观察见 [evidence.md](evidence.md)。

## 结果

结论是 `conditional-go`。

Windows 宿主应使用 `jvm/app`，不要使用 `windows/app`。`jvm/app` 能运行 CMP，`windows/app` 是 Kotlin/Native 应用，不承载 CMP Desktop。

Amper 的 `package` 命令只生成 JAR。仓库需要增加 Windows 打包脚本。脚本使用 JDK 25 的 `jpackage`。安装包构建必须在 Windows 上执行。

结论与限制见 [conclusion.md](conclusion.md)。

## 预期

首个可交付版本应满足以下条件。

1. Windows 11 上以单个托盘进程运行。
2. 复用 `kmpDomain` 的配置与领域模型。
3. 支持普通用户启动，不默认提权。
4. 能生成包含运行时的应用镜像。
5. 能在 Windows CI 生成 MSI。
6. 有真机托盘、启动和高 DPI 验收记录。

方案见 [solution.md](solution.md)。验收计划见 [validation/README.md](validation/README.md)。

## 实现预期的手段

1. 新增 `windowsApp` 模块，产品类型设为 `jvm/app`。
2. 把平台无关的 Compose 组件移入共享界面模块。
3. 在 `windowsApp` 提供 CMP 窗口、托盘、单实例和启动项适配器。
4. 用 `kotlin.bat build` 和 `kotlin.bat test` 跑 Windows CI。
5. 用 `kotlin.bat package -f executable-jar` 生成应用 JAR。
6. 用 `jpackage` 在 Windows 生成 app-image 和 MSI。
7. 在 Windows 11 真机执行验收矩阵。

## 子文档

| 文件 | 职责 |
| --- | --- |
| [context.md](context.md) | 问题、模型、场景和成功标准 |
| [investigation.md](investigation.md) | 工具实验、方案矩阵和反证 |
| [conclusion.md](conclusion.md) | 结论、依据、限制和未决项 |
| [solution.md](solution.md) | 推荐模块、构建、发行和验收方案 |
| [evidence.md](evidence.md) | 来源、命令、观察、推论和置信度 |
| [validation/README.md](validation/README.md) | 验证矩阵、风险和清理要求 |
| [validation/case-windows-cmp-host.md](validation/case-windows-cmp-host.md) | Windows 宿主验证记录 |

## 证据链阅读顺序

1. 先读 [context.md](context.md) 的问题与边界。
2. 再读 [evidence.md](evidence.md) 的 `E-WC01` 到 `E-WC07`。
3. 用 [investigation.md](investigation.md) 对照实验和候选方案。
4. 用 [conclusion.md](conclusion.md) 核对结论。
5. 用 [solution.md](solution.md) 制定 Feature 子任务。
6. 最后按 [validation/README.md](validation/README.md) 执行真机验证。

## 更新规则

1. Windows CI 结果写入 [evidence.md](evidence.md)。
2. 真机验收结果写入 [validation/case-windows-cmp-host.md](validation/case-windows-cmp-host.md)。
3. 结论变化时同步更新本文件、[conclusion.md](conclusion.md) 和 Issue #318。
4. 安装工具或 Amper 版本变化时，重跑宿主实验。
