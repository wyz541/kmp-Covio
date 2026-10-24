# 结论与限制

> 本文件承载结论摘要、决策因素、决策表、限制和未决项。

## 1. 结论摘要

Windows CMP 宿主条件可行。

结论等级是 `conditional-go`。

成立的部分是 CMP 编译、共享 `jvm` 代码、可执行 JAR、app-image、MSI 和 `jpackage` 工具链。未完成的部分是 Windows 真机 UI、托盘、登录启动和 MSI 升级验收。

Windows 宿主应使用 `jvm/app`。Amper 继续作为编译、测试和 JAR 打包入口。Windows 专用发行脚本使用 JDK 25 的 `jpackage`。

## 2. 决策因素

### 2.1 主要因素

**F1：`kmpDomain` 已有 JVM 平台。**
Windows 可以直接使用 `jvm` 目标。共享模型、配置和 Engine 端口不需要第二套 Kotlin 实现。

**F2：CMP 支持 Windows。**
官方桌面文档列出 Windows。系统托盘、窗口、通知和菜单都有桌面 API。

**F3：Amper 不生成原生安装包。**
`kotlin package` 只生成 JAR。EXE、MSI 和应用镜像必须交给 `jpackage`。

**F4：安装包必须在本平台构建。**
Windows MSI 不能在 macOS 或 Linux 生成。CI 必须包含 Windows 作业。

**F5：应用要按普通用户设计。**
Windows 防火墙和特权操作不能改变基本启动模型。Covio 不应依赖常驻管理员服务才能运行。

### 2.2 次要因素

**F6：现有 `app` 模块不是现成 Windows 宿主。**
`app` 是 `jvm/lib`。它包含 Compose 组件，也包含 macOS 形设计件和 helper 遗留代码。Windows 宿主需要新的入口和平台适配层。

**F7：发行策略应分阶段。**
app-image 能先验证程序。MSI 再解决安装位置、开始菜单和升级。

**F8：现有 JVM 测试没有 Windows 基线。**
首次 Windows 全量测试有 12 个失败。失败集中在路径、目录布局和文件系统假设。Windows Feature 必须先补测试基线。

## 3. 决策表

| 决策 | 选择 | 原因 | 备选路径 |
| --- | --- | --- | --- |
| Windows 产品类型 | `jvm/app` | 支持 CMP Desktop | `windows/app` 不支持 CMP Desktop |
| 共享领域代码 | 复用 `kmpDomain` | 已有 `jvm` 平台 | 复制 Windows 模型，风险高 |
| UI | Compose Multiplatform | 用户要求与跨平台目标 | 原生 WinUI，放弃共享 UI |
| 构建 | Amper 0.12.1 | 项目约束 | Gradle，未采用 |
| 应用打包 | executable JAR | Amper 原生输出 | 只有源码，不可交付 |
| 安装器 | `jpackage` 脚本 | 不引入 Gradle | Compose Gradle 插件，违反约束 |
| 首个发行件 | app-image 或便携包 | 先验证运行 | 首版即 MSI，风险较高 |
| 后续发行件 | MSI | 开始菜单和升级体验 | 永久使用便携包 |
| 默认权限 | 普通用户 | 托盘应用不需要管理员常驻 | 常驻高权限服务 |
| 真机验收 | Windows 11 | 目标系统 | 只靠 CI 编译 |

## 4. 逻辑证据链

### 4.1 观察一：Amper 能编译 CMP JVM 应用

观察：临时工程在 `jvm/app` 中编译成功。
观察：`kotlin package` 生成 38 MB 可执行 JAR。
推论：CMP 与 Amper 的组合成立。
置信度：高。

### 4.2 观察二：Windows 需要独立发行步骤

观察：Amper 的格式列表没有 EXE 或 MSI。
观察：`jpackage` 支持 Windows app-image、EXE 和 MSI。
推论：发行步骤必须增加 Windows 脚本。
置信度：高。

### 4.3 观察三：CMP 提供托盘能力

观察：官方文档列出 `Tray()`、托盘菜单、通知和 `isTraySupported`。
观察：Windows 右键菜单与双击动作有明确语义。
推论：CMP 能承载菜单栏应用的主交互。
置信度：高。

### 4.4 观察四：CI 不能替代真机

观察：Windows 防火墙、窗口、托盘和登录启动受用户会话影响。
观察：项目要求 UI 改动做真机验收。
推论：CI 通过只能作为技术门槛。
置信度：高。

## 5. 限制

1. 本机实验在 macOS 上完成。
2. Windows CMP 边界只由 CI 证明编译和打包。
3. 托盘、多显示器、高 DPI 和开始菜单尚未真机验收。
4. MSI 代码签名和 SmartScreen 未设计。
5. 当前设计合同以 macOS 为主。Windows 视觉映射尚未定义。
6. 共享 Compose 组件需要先拆分 macOS 专属依赖。
7. Windows 入站网络能力仍受防火墙和普通用户限制。此问题由 #319 处理。
8. `kmpDomain` 全量 JVM 测试尚未在 Windows 通过。
9. 序列化库在 Amper 默认版本与仓库声明版本之间存在覆盖警告。

## 6. 未决项

1. 首版发行包是 ZIP、MSI 还是两者同时提供。
2. Windows 应用的签名身份和证书来源。
3. Windows 自动更新方式。
4. Windows 11 的最低构建号。
5. 应用是否注册开机启动，还是只由用户在设置中启用。
6. 窗口关闭后是否保持托盘，以及首次启动是否显示主窗口。
7. Windows 本地化目录和字体回退。

## 7. 后续动作

1. 先修 Windows JVM 测试基线。
2. 立 Feature 父 Issue。
3. 拆分共享 UI、Windows 宿主、托盘、单实例、登录启动和发行脚本。
4. 在 Windows CI 增加构建和测试作业。
5. 在 Windows 11 真机执行验证矩阵。
6. 完成 #319 后再接入跨设备模块。

decision: pending
