# Covio 0.6.0（内测 build 8）

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

## 从 build 7 到 build 8 的变化

### Monitor

- Power 设置进入 Power card 第三段浮层。
- Power 浮层提供“详情 / 电源”切换。
- Monitor 增加独立 Screen card。
- Screen card 显示屏幕状态、亮度、外接屏、分辨率和刷新率。
- Screen card 显示显示功耗是否可用，不使用系统总功耗代替。
- Screen card 提供合盖策略、合盖屏幕模式、外接屏暂停和 Helper 状态。

### 合盖策略

- 合盖保持条件改为一个互斥菜单。
- 菜单提供合盖时睡眠、接通电源、使用电池和始终四种策略。
- PowerRuntime 根据电源状态自动申请或释放合盖租约。
- 外接屏暂停、Helper 缺失、低电量、温度和时间上限可以阻止或释放租约。
- 删除 `Settings > Lid` 和重复合盖开关。
- 没有合盖租约时，合盖统一执行立即睡眠。
- 旧合盖配置自动迁移到新的 `DisplayConfig`。

### 界面

- Screen、Power、Fan 和文件动作浮层使用统一的原生 Liquid Glass 外观。
- 浮层内容卡使用标准材质。
- 减少透明度或提高对比度时，内容卡使用不透明表面。
- 主要动作保留 44 点命中高度和键盘焦点环。
- Power card 不再显示合盖策略、外接屏条件或 Helper 状态。

## 验证

- Kotlin 共享测试在 JVM 和 macOS Arm64 上通过。
- macOS XCTest：`945` 项通过，`3` 项跳过，`0` 失败。
- `bash scripts/test-all.sh` 通过。
- 合同生成与校验通过。
- Screen card 和 Power card 通过中文、英文、亮色和深色真机窗口检查。
- 外接屏暂停、电源切换、Helper 丢失、低电量和策略变更的租约释放通过自动化测试。

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
