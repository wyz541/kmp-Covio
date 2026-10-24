# CovioHelper 服务生命周期

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 待真机签名验收 |
| 日期 | `2026-10-24` |
| Issue | #355 |
| 上游决策 | ADR-0018 |

## 目标

`CovioHelper` 是独立的最小 root daemon。
app 使用 `SMAppService.daemon` 注册、查询和注销服务。
app 不再为新安装拼接自定义 LaunchDaemon shell 脚本。

## Bundle 布局

```text
Covio.app/
└── Contents/
    ├── MacOS/
    │   ├── Covio
    │   └── CovioHelper
    └── Library/
        └── LaunchDaemons/
            └── com.wyz.covio.helper.plist
```

daemon plist 使用 `BundleProgram` 指向 `Contents/MacOS/CovioHelper`。
plist 声明 XPC Mach service `com.wyz.covio.helper.xpc`。

## 自包含边界

`CovioHelper` 静态链接 `kmpDomain`。
`CovioHelper` 不加载 app 内的 `kmpDomain.framework`。
`CovioHelper` 不链接 SwiftUI、AppKit、Vision、AVFoundation 或模型运行库。

## 状态

| 状态 | 含义 | 用户动作 |
| --- | --- | --- |
| `ENABLED` | macOS 已启用 daemon | 无 |
| `REQUIRES_APPROVAL` | 已注册，等待管理员批准 | 打开系统设置并批准 |
| `NOT_REGISTERED` | 服务尚未注册 | 安装或修复 helper |
| `NOT_FOUND` | app bundle 内缺少 daemon plist 或可执行文件 | 重新安装完整 app |
| `LEGACY` | 检测到旧 LaunchDaemon | 执行一次迁移 |
| `ERROR` | 注册、注销或签名失败 | 查看错误并修复签名或 app |

发布身份握手状态继续使用 `MATCH`、`MISSING`、`OUTDATED`、`IDENTITY_MISMATCH` 和 `UNTRUSTED`。

## 首次安装

1. 用户点击“安装或修复 Helper”。
2. app 检查 `SMAppService.status`。
3. app 调用 `register()`。
4. macOS 将服务置为等待批准。
5. app 打开“系统设置 > 通用 > 登录项与扩展”。
6. 管理员批准 daemon。
7. helper 启动 XPC listener。
8. app 完成发布身份握手。
9. 只有 `MATCH` 开放特权写入。

## Legacy 迁移

1. app 检测 `/Library/LaunchDaemons/com.wyz.covio.helper.plist`。
2. app 通过旧 helper 恢复风扇、充电上限和活动租约。
3. app 注销旧 `SMAppService`（如果存在）。
4. app 用一次管理员授权移除旧 LaunchDaemon 和临时文件。
5. app 注册 bundle 内的新 daemon。
6. 管理员批准后，app 重新握手。

第 2 步失败时禁止迁移。
第 2 步成功但第 4 或第 5 步失败时，app 保持只读安全模式。

## 用户修复

1. 打开 Covio 设置。
2. 查看 Helper 和“服务”状态。
3. 如果状态是 `REQUIRES_APPROVAL`，点击“打开系统设置”。
4. 在系统设置中批准 `CovioHelper`。
5. 如果状态是 `NOT_FOUND` 或签名错误，重新安装完整 app。
6. 如果状态是 `LEGACY`，点击“安装或修复 Helper”执行迁移。
7. 返回 Covio，等待发布身份变为 `MATCH`。

## 故障说明

| 故障 | 结果 |
| --- | --- |
| 注册被拒绝 | 保持只读，显示系统错误 |
| app 未公证 | 注册失败，保持只读 |
| helper 签名错误 | 注册或握手失败，保持只读 |
| daemon 崩溃 | macOS 重启 daemon；app 重试 XPC 握手 |
| plist 缺失 | `NOT_FOUND`；要求重新安装完整 app |
| 发布身份不一致 | 保持只读；要求修复 helper |
| 状态恢复失败 | 禁止迁移或卸载 |

## 验证边界

- 非签名测试验证 bundle 布局、静态链接、身份摘要、状态映射和 XPC 编译。
- 当前机器没有 Developer ID 和 notarization 凭据。
- 首次批准、真实注册、从 N-1 升级和回滚由 #358 在签名环境验证。
