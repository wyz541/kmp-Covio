# Covio 0.6.0（内测 build 9）

Covio 0.6.0 是内测版。
此版本不用于公开分发。

## 系统要求

- macOS 26 或更高版本。
- Apple Silicon Mac（arm64）。

## 安装包

本版提供默认瘦身 DMG、事务安装 PKG 和 App ZIP。
默认包不包含模型权重。
模型在用户确认后下载、校验并登记。
本版不构建离线模型 DMG。

## 从 build 8 到 build 9 的变化

### 合盖黑屏

- 实验性黑屏合盖时，Covio 同时持有合盖租约和系统加显示唤醒租约。
- Covio 自己阻止显示器空闲睡眠，不再依赖 Sunshine、Caffeine 或其它外部工具。
- 内建屏保持在线、活动、未睡眠。
- 黑屏亮度保持为 `0.0`。
- 显示器不进入空闲睡眠时，macOS 不会触发自动空闲锁屏。
- 开盖、策略切换、外接屏暂停、Helper 丢失和安全护栏会同时释放两个租约。
- 两个租约共用 4 小时合盖上限。
- 关闭显示器模式不额外阻止显示器睡眠。

### 安全边界

- Covio 不绕过用户主动锁屏。
- Covio 不绕过 Wake 后的身份验证。
- macOS 继续管理密码策略。

## 验证

- Kotlin 共享测试在 JVM 和 macOS Arm64 上通过。
- macOS XCTest：`949` 项通过，`3` 项跳过，`0` 失败。
- `bash scripts/test-all.sh` 通过。
- PowerRuntime 定向测试：`29` 项通过。
- 自动化测试覆盖双租约、开盖释放、外接屏暂停、策略切换、Helper 丢失、安全护栏和 4 小时上限。
- IOKit 测试覆盖 `SYSTEM_AND_DISPLAY` 断言创建、回读和释放。
- 真机合盖验证：Covio 持有 `PreventUserIdleDisplaySleep`，黑屏亮度为 `0.0`，系统保持未锁屏。

## 安装

1. 打开 `Covio-0.6.0.dmg`。
2. 将 `Covio.app` 拖入 `Applications`。
3. 打开 `Covio.app`。
4. 打开 AI 功能并确认模型下载。

事务安装与升级使用 `Covio-0.6.0.pkg`。

**警告：** 此构建使用本地签名。
macOS Gatekeeper 可能阻止此构建。
请到“隐私与安全性”允许应用，或清除隔离属性：

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

## 内测说明

- 使用测试 Mac。
- 风扇控制会写入 SMC 值，并需要特权 helper。
- 合盖保持会增加电池消耗。
- 更新检查读取 GitHub Releases 页面。
- 更新检查忽略 pre-release。

## 本版不包含

- 离线模型 DMG。
- Developer ID 签名。
- Apple 公证。
- 公开分发。
- 自动安装更新。
- Intel 或 Universal 2 构建。
- App Store 构建。
