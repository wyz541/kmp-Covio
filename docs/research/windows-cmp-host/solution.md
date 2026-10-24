# 推荐方案

## 1. 模块边界

| 模块 | 产品类型 | 职责 |
| --- | --- | --- |
| `kmpDomain` | `kmp/lib` | 领域模型、配置、Engine 端口 |
| `sharedUi` | `kmp/lib` | Windows 与未来平台共享的 Compose 组件 |
| `crossDeviceProtocol` | `kmp/lib` | 跨设备协议模型与状态机 |
| `windowsApp` | `jvm/app` | Windows 入口、托盘、窗口、单实例、登录启动 |
| `app` | `jvm/lib` | 保留现有 Compose 组件，逐步迁移出 macOS 专属件 |
| `macosApp` | Xcode 工程 | macOS SwiftUI 宿主，不改为 CMP |

`sharedUi` 应只包含不依赖 macOS API 的组件。Windows 不直接依赖 `app` 的 helper 和 macOS 路径。

## 2. 目录建议

```text
sharedUi/
  src/
    com/wyz/covio/ui/
windowsApp/
  src/
    com/wyz/covio/windows/
      Main.kt
      WindowsHost.kt
      WindowsTray.kt
      WindowsSingleInstance.kt
      WindowsLoginItem.kt
      WindowsSystemInfo.kt
  test/
scripts/
  package-windows.ps1
```

目录名保持小写。包名继续使用 `com.wyz.covio`。

## 3. 启动流程

1. 取得单实例锁。
2. 如果已有实例，唤醒现有窗口并退出新进程。
3. 加载 `kmpDomain` 的用户配置。
4. 检查托盘能力。
5. 启动跨设备客户端状态机。
6. 创建托盘图标。
7. 根据配置决定是否显示主窗口。
8. 注册退出清理。

## 4. 单实例

使用用户级文件锁。锁文件放在 `%LOCALAPPDATA%\Covio` 下的应用目录。不要使用管理员服务。

第二实例通过本地命名管道发送 `show-window`。命名管道名包含当前用户 SID，避免不同用户互相唤醒。

## 5. 托盘

使用 CMP `Tray()`。菜单至少包含以下项目。

| 菜单项 | 动作 |
| --- | --- |
| 打开 Covio | 显示主窗口 |
| 设备 | 显示已连接和离线设备 |
| 设置 | 打开设置窗口 |
| 退出 | 停止运行时并退出 |

启动时检查 `isTraySupported`。不支持时显示窗口并给出明确错误。

## 6. 登录启动

首版使用当前用户的 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`。设置页提供开关。应用只写当前用户键。用户注销后进程结束。

不使用会话 0 服务。会话 0 服务只用于未来的无人值守接收需求。

## 7. 配置与日志

复用 `kmpDomain` 的 `AppDirectories.jvm`。配置放在 `%LOCALAPPDATA%` 的应用数据目录。日志放在同一用户目录。

Windows 不读取 macOS 配置。需要迁移时另做导入器。

## 8. 构建

Windows CI 使用 JDK 25 和仓库的 `kotlin.bat`。

```powershell
.\kotlin.bat build
.\kotlin.bat test
.\kotlin.bat package -m windowsApp -f executable-jar
```

这些步骤只生成 JVM 文件和可执行 JAR。

## 9. 发行

`scripts/package-windows.ps1` 负责以下步骤。

1. 调用 Amper 生成可执行 JAR。
2. 建立临时输入目录。
3. 调用 `jpackage --type app-image`。
4. 对 app-image 做启动探针。
5. 调用 `jpackage --type msi`。
6. 输出包名、版本、SHA-256 和构建环境。
7. 清理临时输入目录。

首版先生成便携 ZIP，同时生成未签名 MSI 供内测。签名和公开分发另行决策。

## 10. 安全边界

1. 应用默认使用普通用户权限。
2. 不安装高权限常驻服务。
3. 不把 Mac helper 命令暴露给 Windows。
4. 不把本机敏感信息写入托盘提示。
5. 更新包和安装包要有 SHA-256 清单。
6. 启动路径使用当前用户可写目录。
7. 退出时删除或释放单实例锁。

## 11. 验收

1. Windows CI 编译、测试和打包通过。
2. Windows 11 真机启动成功。
3. 托盘菜单可用。
4. 关闭窗口后进程仍然运行。
5. 双击托盘图标显示窗口。
6. 托盘退出后进程结束。
7. 登录启动开关能创建和删除启动项。
8. 100%、125% 和 150% 缩放下没有裁切。
9. 多显示器切换后窗口可见。
10. MSI 覆盖升级后保留配置。

## 12. 实施顺序

1. 修 Windows JVM 测试基线。
2. 提取共享 UI。
3. 建立 `windowsApp` 空宿主。
4. 加单实例与配置。
5. 加托盘和窗口。
6. 加登录启动。
7. 加 Windows CI。
8. 加 `jpackage` 脚本。
9. 做真机验收。
10. 接入 #319 的连接模块。

## 13. 回滚条件

满足任一条件时，暂停 Windows 宿主合并。

1. Windows CI 无法稳定生成可执行 JAR。
2. CMP 托盘在目标 Windows 版本不可用。
3. 普通用户无法启用登录启动。
4. MSI 覆盖升级会删除配置。
5. 应用只能以管理员身份运行。
6. 关闭窗口会导致进程意外退出。
