# 上下文与边界

## 1. 问题类别

问题类别是跨平台桌面运行时与构建架构。

## 2. 研究问题

Compose Multiplatform 能否在现有 Amper 0.12.1 工程中复用 `kmpDomain`，并交付可安装、可常驻托盘的 Windows 客户端？

## 3. 问题定义

问题有三部分。

1. Windows 宿主能否编译并运行 CMP。
2. 现有共享模块能否直接服务 JVM Windows。
3. Amper 能否生成 Windows 安装件。

任何一部分不成立，Windows 客户端方案都需要调整。

## 4. 触发条件

以下条件同时成立。

- 用户需要 Windows 客户端。
- 工程继续使用 Amper 0.12.1。
- macOS 宿主继续使用 SwiftUI。
- 共享逻辑继续使用 KMP。
- Windows 用户可以使用普通账户。

## 5. 系统模型

| 组件 | 职责 | 当前状态 |
| --- | --- | --- |
| `kmpDomain` | 领域模型、配置、Engine 端口 | 已有 `jvm` 与 `macosArm64` |
| `app` | Compose 组件与旧宿主遗留代码 | 已有 `jvm/lib` |
| `macosApp` | SwiftUI 宿主与系统适配器 | 已有 |
| `windowsApp` | Windows CMP 宿主 | 缺失 |
| Amper 0.12.1 | 编译、测试和 JAR 打包 | 已有 |
| `jpackage` | Windows app-image、EXE 与 MSI | 工具链可用，仓库脚本缺失 |
| Windows CI | Windows 专属验证 | 缺失 |

## 6. 场景

### 6.1 启动

用户从开始菜单启动 Covio。应用显示托盘图标。主窗口可以打开和关闭。关闭窗口不退出进程。

### 6.2 普通用户运行

用户没有管理员权限。应用读取用户目录并写入用户配置。应用不要求安装特权服务。

### 6.3 随登录启动

用户启用“登录时启动”。Windows 在用户登录后启动 Covio。用户注销后托盘进程结束。

### 6.4 安装和升级

用户安装新的 MSI。应用保留用户配置。升级不复制 macOS 设置。

## 7. 约束

1. 构建系统保持 Amper 0.12.1。
2. JDK 基线是 25。
3. 界面使用 CMP。
4. 领域逻辑优先复用 `kmpDomain`。
5. macOS 宿主不改用 Compose。
6. 应用默认使用普通用户权限。
7. 仓库不写本机绝对路径。
8. Windows 安装件在 Windows 上构建。
9. UI 改动必须做真机验收。

## 8. 成功标准

1. `kotlin.bat build` 在 Windows 通过。
2. `kotlin.bat test` 在 Windows 通过。
3. `kotlin.bat package -f executable-jar` 生成可执行 JAR。
4. `jpackage --type app-image` 生成可启动应用镜像。
5. `jpackage --type msi` 生成 MSI。
6. Windows 11 真机显示托盘菜单。
7. 窗口关闭后进程继续运行。
8. 普通用户可以启用登录启动项。
9. 配置写入 Windows 用户目录。
10. 高 DPI 和 100%、125%、150% 缩放下布局可读。

## 9. 范围外

1. 跨设备发现协议。
2. 设备配对和证书。
3. 远程控制命令。
4. Windows 系统指标采集的完整实现。
5. Windows 商店发行和代码签名证书采购。
6. macOS 宿主改动。
