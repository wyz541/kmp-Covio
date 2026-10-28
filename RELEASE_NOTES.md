# Covio 0.6.0（内测 build 7）

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

## 从 build 6 到 build 7 的变化

### 性能

- helper 状态读取改为缓存和后台探测。
- helper 不可达或身份不匹配时，周期读取不再阻塞主线程。
- 同一时刻只保留一个 helper 探测。
- 失败探测按 `5s → 10s → 20s → 40s → 60s` 退避。

### 工作台

- 导航栏切换前后保持固定尺寸和位置。
- 切换界面语言后，工作台导航保持一致的页签状态。
- 首页组件支持自由位置调整和布局保存。

### 充电与电源

- 新安装的默认充电上限改为 70%。
- 实验性合盖黑屏预览默认启用。
- build 6 的合盖租约、睡眠保护和恢复行为保持不变。

## 验证

- Kotlin 共享测试：`498` 项通过。
- macOS XCTest：`932` 项通过，`3` 项跳过。
- helper 不匹配的真机样本中，主线程没有 `OS_dispatch_semaphore.wait` 样本。
- 发布 PKG 完成 App 与 helper 的成对安装和精确握手。
- 所有发布资产通过 Draft 复核。

## 安装

1. 打开 `Covio-0.6.0.dmg`。
2. 将 `Covio.app` 拖入 `Applications`。
3. 打开 `Covio.app`。

升级已有内测版时，使用 `Covio-0.6.0.pkg`。
PKG 会保留配置、历史、工作区和模型文件。
PKG 会成对更新 App 与 helper。

**警告：** 此构建使用 ad-hoc 签名。
macOS Gatekeeper 会阻止此构建。
请到“隐私与安全性”允许应用，或清除隔离属性：

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

## 内测说明

- 使用测试 Mac。
- 风扇控制会写入 SMC 值，并需要特权 helper。
- 电池合盖保持会增加电池消耗。
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
