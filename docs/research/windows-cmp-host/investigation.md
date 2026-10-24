# 调研过程

## 1. 方法

调研使用三类证据。

1. Amper 0.12.1 的实机输出。
2. Compose Multiplatform 与 JDK 官方文档。
3. Windows CI 的编译和打包结果。

本机是 macOS。Windows 专属结论只接受 Windows CI 或 Windows 真机结果。没有证据的项目保持待验证。

## 2. 构建工具事实

Amper 0.12.1 的版本输出如下。

```text
Kotlin Toolchain version 0.12.1 (a1635a7, 2026-09-14)
```

当前 Module 的 Compose 默认版本如下。

| 设置 | 值 |
| --- | --- |
| Kotlin | 2.4.10 |
| Compose Multiplatform | 1.11.1 |
| JDK | 25 |
| Ktor | 3.5.2 |

`kotlin package --help` 只接受四种格式：`jar`、`executable-jar`、`aab` 和 `maven-central-bundle`。它不接受 EXE 或 MSI。

## 3. 候选产品类型

| 产品类型 | 运行模型 | CMP | 判断 |
| --- | --- | --- | --- |
| `jvm/app` | JVM 桌面应用 | 支持 | 采用 |
| `windows/app` | Kotlin/Native Windows 应用 | 不承载 CMP Desktop | 不采用 |
| `jvm/lib` | 库 | 可承载组件 | 用于共享界面或协议库 |

Windows 宿主应使用 `jvm/app`。CMP Desktop 的运行时与 Skiko 都属于 JVM 生态。`windows/app` 适合 Kotlin/Native 程序，不适合本需求。

## 4. 最小宿主实验

临时工程使用以下结构。

```text
project.yaml
windowsSpike/
├── module.yaml
└── src/main.kt
```

`module.yaml` 使用 `jvm/app`、`$compose.desktop.currentOs` 和 `settings.compose.enabled=true`。入口创建一个 CMP `Window`。

本机输出如下。

```text
✓ Compilation successful for 'windowsSpike' [jvm]
Build successful
```

可执行 JAR 输出如下。

```text
build/tasks/_windowsSpike_executableJarJvm/windowsSpike-jvm-executable.jar
```

JAR 大小为 38 MB。JAR 包含 Compose 依赖。编译和 JAR 打包成立。

## 5. CMP 桌面能力

CMP 官方文档明确支持 Windows 桌面应用。桌面 API 包含窗口、对话框、系统托盘、通知、上下文菜单和菜单栏。

托盘 API 在 Windows 上支持以下行为。

- 右键打开托盘菜单。
- 双击执行默认动作。
- 在托盘内发送系统通知。
- 无主窗口时继续运行。
- 用 `isTraySupported` 检查托盘支持。

这些能力覆盖 Windows 菜单栏客户端的基本需要。

## 6. 安装包路径

CMP 原生发行文档描述的是 Gradle Compose 插件。该插件调用 `jpackage` 并支持 Windows 的 EXE 与 MSI。文档同时说明安装包不能在其它系统交叉构建。

Covio 不使用 Gradle。仓库不能直接使用这个插件。可行路径有两种。

| 路径 | 优点 | 限制 |
| --- | --- | --- |
| 可执行 JAR 加 `jpackage` 脚本 | 符合当前 Amper 约束 | 需要维护 Windows 脚本和 WiX |
| 临时引入 Gradle Compose 插件 | 工具成熟 | 违反“Amper 是构建系统”的项目约束 |

采用第一种。窗口型程序先交付 app-image。需要在开始菜单安装时再交付 MSI。

## 7. Windows CI 探针

探针分支使用 `jvm/app` 新增最小 `windowsProbe` 模块。CI 执行以下步骤。

1. 安装 JDK 25。
2. 编译并测试 `windowsProbe`。
3. 生成 executable JAR。
4. 用 `jpackage --type app-image` 生成应用镜像。
5. 安装 WiX。
6. 用 `jpackage --type msi` 生成安装包。

第一次全量测试暴露 12 个 Windows 失败。失败集中在路径、目录布局和临时文件假设。探针随后只跑 Windows 宿主模块。

第二次运行通过。`Covio.exe` 为 506,880 字节。`Covio-1.0.msi` 为 80,797,984 字节。CI 没有启动桌面应用。

探针结果见 [evidence.md](evidence.md) 的 `E-WC07`。

## 8. 反证与失败边界

### 8.1 不能用 `windows/app`

`windows/app` 是 Kotlin/Native 产品类型。它不提供 CMP Desktop 的 JVM 运行时。选择它会让 CMP 编译链失配。

### 8.2 不能把可执行 JAR 当作安装包

可执行 JAR 依赖用户已有 JVM。MSI 和应用镜像包含运行时。产品发行不能只交 JAR。

### 8.3 不能在 macOS 生成 Windows MSI

JDK 文档明确说明 `jpackage` 不支持跨平台打包。Windows 安装件必须在 Windows 上生成并验收。

### 8.4 不能用管理员权限来掩盖设计问题

普通用户必须能启动和管理托盘客户端。安装器可以请求一次管理员授权。应用运行时不应每次请求提权。

## 9. 尚未验证

1. Windows 11 真机的托盘外观。
2. 关闭窗口后应用继续运行的完整行为。
3. 登录启动项在标准账户下的删除和更新。
4. 高 DPI 与多显示器布局。
5. MSI 升级保留用户配置。
6. 代码签名、SmartScreen 和商店发行。
