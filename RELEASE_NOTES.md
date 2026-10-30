# Covio 0.6.0（内测 build 11）

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

## 从 build 10 到 build 11 的变化

### 全局 Helper

- Helper 收敛为 Covio 的全局运行能力。
- Overview 不再显示 helper 卡、版本、安装或卸载入口。
- Settings 搜索不再返回 helper、助手或 privileged 设置项。
- Display 不再显示独立的 helper 行和安装或修复按钮。
- Fan 不再显示独立的 helper 安装或修复按钮。
- Fan 控制读取同一个 AppRuntime helper 状态。
- Lid、Display、Fan 和充电上限只显示能力级状态。
- 安装、升级、签名校验和恢复仍由全局 helper 路径负责。

### 用户界面

- 用户不需要理解 helper、LaunchDaemon 或特权服务。
- 功能不可用时显示“Covio 系统支持不可用”或“需要 Covio 系统支持”。
- 技术错误继续写入日志，供诊断使用。
- 亮色和深色界面保持原有布局，不新增替代 helper 卡片。

## 验证

- Kotlin 共享测试在 JVM 和 macOS Arm64 上通过。
- macOS XCTest：`982` 项通过，`3` 项跳过，`0` 失败。
- `bash scripts/test-all.sh` 通过。
- Settings 搜索测试确认 helper 不再作为设置项出现。
- Fan 状态映射测试覆盖全局 helper 的 ready、missing、outdated 和 unavailable 状态。
- 真机亮色和深色截图覆盖 Display 详情浮层 Before/After。
- GitHub Actions：Contract and scripts、Kotlin、macOS SwiftUI 全部通过。

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
- 风扇控制会写入 SMC 值，并需要全局特权 helper。
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
