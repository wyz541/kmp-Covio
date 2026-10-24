# 证据附录

## 1. 证据等级

| 等级 | 含义 |
| --- | --- |
| A | 官方文档、规范或可重复的本地命令 |
| B | 公开源码、产品实现或间接实验 |
| C | 推论或待验证假设 |

## 2. 证据清单

| ID | 主题 | 等级 | 摘要 |
| --- | --- | --- | --- |
| E-WC01 | Amper 版本与 Compose 设置 | A | 0.12.1、Kotlin 2.4.10、CMP 1.11.1、JDK 25 |
| E-WC02 | CMP 最小编译 | A | `jvm/app` 编译成功 |
| E-WC03 | 可执行 JAR | A | 38 MB executable JAR |
| E-WC04 | CMP 桌面 API | A | Windows、托盘、通知和窗口 |
| E-WC05 | CMP 原生发行 | A | Gradle 插件、jpackage、不可交叉构建 |
| E-WC06 | jpackage | A | Windows 支持 app-image、EXE 和 MSI |
| E-WC07 | Windows CI 探针 | A | Windows 编译、测试和打包结果 |
| E-WC08 | Windows 普通用户限制 | A | 入站防火墙与注销行为 |

## 3. 详细记录

### E-WC01：Amper 与 Compose 版本

来源等级：A

环境：2026-10-24，macOS，Amper 0.12.1。

命令：

```text
./kotlin --version
./kotlin show settings -m app
```

关键输出：

```text
Kotlin Toolchain version 0.12.1 (a1635a7, 2026-09-14)
compose.version: 1.11.1
kotlin.version: 2.4.10
jdk.version: 25
```

观察：仓库使用 Amper 0.12.1。Compose 由 Amper 内置配置提供。

推论：Windows 宿主必须跟随这套工具链。

置信度：高。

### E-WC02：CMP 最小编译

来源等级：A

环境：2026-10-24，macOS。

最小模块配置：

```yaml
product:
  type: jvm/app
dependencies:
  - $compose.desktop.currentOs
settings:
  compose:
    enabled: true
```

命令：

```text
kotlin build
```

关键输出：

```text
✓ Compilation successful for 'windowsSpike' [jvm]
Build successful
```

观察：`jvm/app` 能编译 CMP 入口。

限制：本机不是 Windows。此结果只证明编译链，不证明 Windows GUI。

置信度：高。

### E-WC03：可执行 JAR

来源等级：A

环境：2026-10-24，macOS。

命令：

```text
kotlin package -f executable-jar
```

关键输出：

```text
build/tasks/_windowsSpike_executableJarJvm/windowsSpike-jvm-executable.jar
```

JAR 大小为 38 MB。JAR 包含 Compose 和运行时依赖。

观察：Amper 能生成可执行 JAR。

限制：JAR 不是 Windows 安装包。

置信度：高。

### E-WC04：CMP 桌面 API

来源等级：A

来源：Compose Multiplatform 官方文档，Desktop-only API、Tray and notifications。

关键输出：

```text
Compose Multiplatform supports Windows desktop applications.
Tray() adds an application icon to the system tray.
Windows uses right-click for the tray menu and double-click for onAction.
Use isTraySupported before showing tray options.
```

观察：CMP 提供 Windows 托盘、菜单和通知 API。

推论：Windows 托盘宿主不需要引入 WinUI。

置信度：高。

### E-WC05：CMP 原生发行

来源等级：A

来源：Compose Multiplatform 官方文档，Native distributions。

关键输出：

```text
Windows formats: exe and msi.
The Compose Gradle plugin packages distributions with jpackage.
Cross-compilation is not supported.
Build the format on the compatible OS.
```

观察：CMP 的成熟安装流程依赖 Gradle Compose 插件。

推论：Covio 必须用 Amper 加外部 `jpackage` 脚本替代插件。

置信度：高。

### E-WC06：jpackage

来源等级：A

来源：Oracle JDK 25 `jpackage` 文档。

关键输出：

```text
jpackage produces platform-specific packages.
Windows types include app-image, exe, and msi.
Each format must be built on the platform it runs on.
```

观察：`jpackage` 能生成 Windows app-image 和安装器。

限制：签名、WiX 版本和 CI 工具可用性需要实测。

置信度：高。

### E-WC07：Windows CI 探针

来源等级：A

环境：Windows Server CI，JDK 25，Amper 0.12.1，提交 `c005f89`。

#### 第一次运行：全量项目

命令：

```text
.\kotlin.bat build
.\kotlin.bat test
```

结果：

```text
Compilation successful for 'kmpDomain' [jvm]
Compilation successful for 'windowsProbe' [jvm]
12 tests failed
JVM tests failed for module 'kmpDomain'
```

失败集中在以下假设。

- macOS 与 Windows 的路径分隔符不同。
- 测试期待 macOS 的应用目录布局。
- 部分测试把相对路径当作 POSIX 路径。
- 部分临时路径测试在 Windows 上多了一层目录。

运行地址：

```text
https://github.com/wyz541/kmp-Covio/actions/runs/40054784957
```

#### 第二次运行：Windows 宿主模块

命令：

```text
.\kotlin.bat build -m windowsProbe
.\kotlin.bat test -m windowsProbe
.\kotlin.bat package -m windowsProbe -f executable-jar
jpackage --type app-image ...
jpackage --type msi ...
```

结果：

```text
Compilation successful for 'kmpDomain' [jvm]
Compilation successful for 'windowsProbe' [jvm]
Compilation successful for 'windowsProbe' [jvm tests]
Build successful
1 tests successful
0 tests failed
Build successful
Covio.exe 506880 bytes
Covio-1.0.msi 80797984 bytes
```

观察：Windows 宿主模块可以编译、测试、生成 JAR、应用镜像和 MSI。

观察：全量共享测试还没有 Windows 基线。

限制：CI 没有启动桌面应用，也没有检查托盘和窗口。

运行地址：

```text
https://github.com/wyz541/kmp-Covio/actions/runs/40055291857
```

置信度：高。

### E-WC08：Windows 普通用户限制

来源等级：A

来源：Microsoft Learn 防火墙与会话文档。详细记录见 [跨设备内容读取能力证据](../cross-device-content-access/evidence.md) 的 `E-37` 与 `E-39`。

关键输出：

```text
Standard users cannot create allow rules for inbound listeners.
Sign-out ends processes in the interactive session.
Fast Startup behaves as sign-out for tray processes.
```

观察：Windows 托盘应用不保证注销后继续运行。

推论：Windows 宿主按普通用户、登录会话进程设计。不要把快速启动后的在线状态当真。

置信度：高。

## 4. 失败和反证

1. `windows/app` 是 Kotlin/Native 产品类型，不是 CMP Desktop 宿主。
2. Amper 0.12.1 的 `package` 不支持 EXE 或 MSI。
3. macOS 不能生成 Windows MSI。
4. Windows CI 通过不等于真机托盘验收通过。

## 5. 参考来源

- [Amper 0.12 JVM application](https://kotlin-toolchain.org/0.12/user-guide/product-types/jvm-app/)
- [Amper 0.12 Compose Multiplatform](https://kotlin-toolchain.org/0.12/user-guide/builtin-tech/compose-multiplatform/)
- [Compose Multiplatform Desktop-only API](https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-desktop-components.html)
- [Compose Multiplatform Tray and notifications](https://kotlinlang.org/docs/multiplatform/compose-desktop-tray.html)
- [Compose Multiplatform Native distributions](https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-native-distribution.html)
- [Oracle JDK 25 jpackage](https://docs.oracle.com/en/java/javase/25/docs/specs/man/jpackage.html)
