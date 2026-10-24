# 证据、命令与逻辑链

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 初稿，可评审 |
| 环境 | Apple M1 Max，macOS 27.0.1（26A434），Xcode 27.1 |
| 目标基线 | `main@b7c80f1`，Covio `0.5.2` |
| 验证状态 | 只执行只读检查；`SMAppService` 新验证阻塞 |

## 问题类别和案例映射

| 项目 | 内容 |
| --- | --- |
| 问题类别 | 用户态应用调用系统级特权能力 |
| 案例 | Covio 睡眠、充电和风扇控制 |
| 决策目标 | 判断 root helper 是否为必要条件，并选择长期机制 |

## 来源等级

| 等级 | 来源 |
| --- | --- |
| A | Apple SDK、Apple 官方文档、本机 man page |
| B | Covio 源码、ADR、既有测试 |
| C | Apple 官方示例 |
| D | 本机只读检查、日志和既有探针结果 |

## 环境事实

| 项目 | 值 |
| --- | --- |
| 系统 | macOS 27.0.1 |
| Build | 26A434 |
| 芯片 | Apple M1 Max |
| 架构 | arm64 |
| Xcode | 27.1 |
| 当前 Covio | `0.5.2` |
| helper 协议 | `8` |
| Developer ID | 未配置 |

## 复现命令

```sh
sw_vers
uname -m
xcodebuild -version
security find-identity -v -p codesigning

SDK=$(xcrun --sdk macosx --show-sdk-path)
rg -n -A20 -B5 'notarized|code signed' \
  "$SDK/System/Library/Frameworks/ServiceManagement.framework/Headers/SMAppService.h"

man pmset
man launchd.plist

stat -f '%Sp %Su:%Sg %N' \
  '/Library/Application Support/Covio/helper.sock' \
  '/Library/LaunchDaemons/com.wyz.covio.helper.plist'

launchctl print system/com.wyz.covio.helper

otool -L /Applications/Covio.app/Contents/MacOS/Covio
```

## 证据索引

| 编号 | 主题 | 等级 | 置信度 |
| --- | --- | --- | --- |
| `E-01` | `SMAppService` 签名、公证和重新注册要求 | A | 高 |
| `E-02` | daemon plist 位置与 `BundleProgram` | A | 高 |
| `E-03` | daemon 注册、批准和状态语义 | A | 高 |
| `E-04` | `SMJobBless` 已废弃 | A | 高 |
| `E-05` | `AuthorizationExecuteWithPrivileges` 已废弃且风险高 | A | 高 |
| `E-06` | 用户态断言不能阻止合盖睡眠 | A、D | 高 |
| `E-07` | `pmset` 修改设置需要 root | A | 高 |
| `E-08` | SMC 受保护写入需要特权 | B | 高 |
| `E-09` | 当前 helper 复用完整 app 二进制 | B | 高 |
| `E-10` | root 二进制包含大量用户态依赖 | B、D | 高 |
| `E-11` | 当前 helper 使用 `0666` Unix socket | B、D | 高 |
| `E-12` | 当前环境没有有效签名身份 | A、D | 高 |
| `E-13` | 自签名与 ad-hoc 的 `SMAppService` 探针失败 | D | 高，范围有限 |
| `E-14` | XPC 可在连接前校验代码签名 | A | 高 |
| `E-15` | Apple 官方示例的 bundle 与 XPC 结构 | A、C | 高 |
| `E-16` | Authorization Services 不支持 App Sandbox | A | 高 |

## 证据详情

### E-01：`SMAppService` 的签名与公证要求

来源等级：A

来源：macOS 27 SDK 的 `SMAppService.h` 第 49、54、55、60、61、62、168 行。

观察：

```text
Apps that use SMAppService APIs must be code signed.
Apps that contain LaunchDaemons must be notarized.
If an app updates either the plist or the executable for a LaunchAgent or LaunchDaemon,
the SMAppService must be re-registered or it may not launch.
If the app bundle is not properly code signed, this API will return kSMErrorInvalidSignature.
```

推论：目标 daemon 必须有有效签名与公证。helper 或 plist 更新后必须重新注册。

限制：头文件定义硬要求，不证明当前证书链一定注册成功。

置信度：高

### E-02：daemon plist 与 `BundleProgram`

来源等级：A

来源：`SMAppService.h` 第 121 到 129 行；`man launchd.plist` 的 `BundleProgram` 条目。

观察：

```text
The plistName must correspond to a plist in the calling app's Contents/Library/LaunchDaemons directory.
SMAppService plists may use the BundleProgram launchd plist key to specify an app bundle relative path.
For a LaunchDaemon to be bootstrapped during boot, the containing application must be accessible before a user logs in.
The BundleProgram key is only supported for plists that are installed using SMAppService.
```

推论：目标结构应把 daemon plist 放进签名 app bundle，并让 helper 位于 bundle 内。

限制：Apple 建议 app 位于 `/Applications`，但当前没有在 notarized app 上复测。

置信度：高

### E-03：daemon 注册与批准

来源等级：A

来源：Apple `SMAppService.register()`、`status`、`unregister()` 文档。

观察：

```text
For a LaunchDaemon, the system won't bootstrap the service until an admin approves it in System Settings.
The service has been successfully registered, but the user needs to take action.
Unregister terminates a running LaunchAgent or LaunchDaemon.
```

推论：注册、批准和退出是可观测状态。UI 必须区分 `requiresApproval`、`enabled` 和 `notFound`。

限制：更新后是否再次要求批准，文档未写清。

置信度：高

### E-04：`SMJobBless` 已废弃

来源等级：A

来源：Apple `SMJobBless(_:_:_:_:)` 文档。

观察：

```text
macOS deprecatedAt: 13.0
message: Please use SMAppService instead
```

推论：新架构不采用 `SMJobBless`。

限制：无。

置信度：高

### E-05：`AuthorizationExecuteWithPrivileges` 已废弃且风险高

来源等级：A

来源：Apple `AuthorizationExecuteWithPrivileges` 文档。

观察：

```text
Deprecated in macOS 10.7.
Use a launchd-launched helper tool and/or the Service Management framework.
This function poses a security concern because it will indiscriminately run any tool or application.
```

推论：不能用每次执行任意工具的方式替代受控 helper。

限制：该接口仍可用于旧安装器，但不应作为新设计。

置信度：高

### E-06：用户态断言不能阻止合盖睡眠

来源等级：A、D

来源：[合盖睡眠控制与权限边界](../lid-sleep-control/evidence.md) 的 `E-01`、`E-05`、`E-06`。

观察：`PreventSystemSleep` 被 SDK 标为不受支持。持有该断言时，合盖后系统仍进入完全睡眠。

推论：合盖功能不能只用用户态 `IOPMAssertion` 覆盖。

限制：实验针对合盖，不覆盖所有睡眠场景。

置信度：高

### E-07：`pmset` 修改需要 root

来源等级：A

来源：本机 `man pmset`。

观察：

```text
pmset must be run as root in order to modify any settings.
```

本机 `/usr/bin/pmset` 的字符串还包含：

```text
pmset: Must be run as root to modify settings
```

推论：持久修改睡眠和休眠设置必须有 root 进程。

限制：读取不需要 root。

置信度：高

### E-08：SMC 受保护写入需要特权

来源等级：B

来源：`macosApp/src/Platform/SMC/SMCAccess.swift`。

观察：`IOConnectCallStructMethod` 返回 `kIOReturnNotPrivileged` 时，代码抛出 `SMCAccessError.notPrivileged`。

推论：风扇控制和主动放电写入必须有特权进程。

限制：不同 SMC key 的权限可能不同；结论只覆盖已知受保护写入。

置信度：高

### E-09：当前 helper 复用完整 app 二进制

来源等级：B

来源：`macosApp/src/App/CovioApp.swift`、`kmpDomain/src/com/wyz/covio/core/HelperInstallScript.kt`。

观察：`Covio --helper` 在 SwiftUI 启动前调用 `HelperServer.run()`。LaunchDaemon 的 program 是 app 主可执行文件。

推论：root helper 加载完整应用代码和依赖。

限制：SwiftUI 未必初始化，但代码和动态依赖仍在 root 进程中。

置信度：高

### E-10：root 二进制包含大量用户态依赖

来源等级：B、D

来源：`otool -L /Applications/Covio.app/Contents/MacOS/Covio` 与当前源码。

观察：主二进制链接 SwiftUI、AppKit、Vision、AVFoundation、CoreML、Metal、PDFKit 等框架。

推论：当前 helper 的加载依赖和潜在攻击面大于特权操作所需范围。

限制：动态链接不等于所有代码都执行；该观察只支持“可进一步缩小”的结论。

置信度：高

### E-11：当前 helper 使用 `0666` Unix socket

来源等级：B、D

来源：`HelperContract.kt`、`HelperServer.swift`、本机 `stat`。

观察：

```text
srw-rw-rw- root:wheel /Library/Application Support/Covio/helper.sock
```

源码先设置 socket 权限，再在连接后校验 UID。部分命令再校验客户端签名。

推论：连接准入不是 XPC 级别的预先代码签名校验。

限制：UID 校验仍阻止其他用户执行命令，但协议暴露面更大。

置信度：高

### E-12：当前环境没有有效签名身份

来源等级：A、D

来源：`security find-identity -v -p codesigning`、ADR-0005。

观察：

```text
0 valid identities found
```

发布脚本使用 ad-hoc 签名。

推论：当前不能完成 notarized `SMAppService.daemon` 验证。

限制：证书可以在未来配置；这不是永久限制。

置信度：高

### E-13：自签名与 ad-hoc 的注册探针失败

来源等级：D

来源：[合盖睡眠控制与权限边界](../lid-sleep-control/evidence.md) 的 `SMAppService` 签名探针记录。

观察：两种签名配置都返回 `SMAppServiceErrorDomain code 1 Operation not permitted`。状态停在 `RequiresApproval`，但服务没有运行。

推论：自签名和 ad-hoc 不能满足当前 `SMAppService` 注册要求。

限制：探针从临时路径运行，未覆盖 Developer ID 和 `/Applications`。

置信度：高，范围有限

### E-14：XPC 可以预先校验客户端签名

来源等级：A

来源：`NSXPCConnection.h` 第 211 到 214 行；Apple `setConnectionCodeSigningRequirement(_:)` 文档。

观察：

```text
Sets the code signing requirement for new connections.
If new peer connections do not match the requirement,
the incoming connection is automatically rejected before consulting the delegate.
```

推论：XPC 可以在业务处理前拒绝未授权客户端。

限制：requirement 字符串必须正确生成并维护。

置信度：高

### E-15：Apple Service Management 示例的 bundle 与 XPC 结构

来源等级：A、C

来源：Apple 示例 `Updating your app package installer to use the new Service Management API`。

示例 ZIP SHA-256：

```text
d765c4c235ba703da37431d97124627475c5e2f9407834f892415ea170478cc5
```

观察：示例把 plist 放进签名 app bundle，使用 `BundleProgram`，通过 XPC 调用 helper，并要求配置 Team ID 与签名 PKG。

推论：目标架构与 Apple 官方结构一致。

限制：示例使用 LaunchAgent，不是 root LaunchDaemon。

置信度：高

### E-16：Authorization Services 不支持 App Sandbox

来源等级：A

来源：Apple `Authorization Services` 文档。

观察：

```text
The Authorization Services API is not supported within an App Sandbox
because the API allows privilege escalation.
```

推论：App Sandbox 版本不能依赖 Authorization Services 完成特权操作。

限制：Covio 当前不走 App Store，但该限制影响未来沙盒化。

置信度：高

## 逻辑证据链

1. 合盖控制和系统级 `pmset` 写入需要 root。证据：`E-06`、`E-07`。
2. SMC 受保护写入需要 root。证据：`E-08`。
3. 因此，保留全部功能时不能完全移除特权服务。证据：`E-06`、`E-07`、`E-08`。
4. 当前完整 app 以 root 运行，依赖和攻击面大于必要范围。证据：`E-09`、`E-10`。
5. 当前 socket 允许任意本机用户建立连接，之后才做身份检查。证据：`E-11`。
6. Apple 已废弃 `SMJobBless` 和 `AuthorizationExecuteWithPrivileges`。证据：`E-04`、`E-05`。
7. `SMAppService.daemon` 是 Apple 当前机制，但要求签名与公证。证据：`E-01`、`E-02`、`E-03`。
8. 当前没有 Developer ID，既有非公证探针失败。证据：`E-12`、`E-13`。
9. XPC 可以提供连接前的代码签名准入。证据：`E-14`。
10. 因此，全局目标是独立最小 XPC daemon 与 `SMAppService`；当前只能把 Legacy LaunchDaemon 作为受限路径。

## 反证和限制

- `SMAppService` 的 Developer ID 成功案例尚未在本机执行。
- daemon 更新后的批准行为未验证。
- 独立 helper 仍需要共享协议，可能增加构建复杂度。
- Apple 文档没有承诺手写 LaunchDaemon 的永久兼容性。

## 已知缺口

| 缺口 | 原因 | 影响 |
| --- | --- | --- |
| 无 Developer ID | 本机没有有效身份 | 无法验证目标 daemon |
| 无 notarization 凭据 | 发布链未配置 | 无法验证 Gatekeeper |
| 未做两版本升级 | 需要应用签名前提 | 更新批准行为未知 |
| 未做 XPC 基准 | 目标代码不存在 | 高频状态查询性能未知 |

## 复核方法

1. 重新执行本文件的复现命令。
2. 检查 SDK 头文件版本与报告是否一致。
3. 检查 Covio 当前 commit 和发布版本。
4. 取得 Developer ID 后执行 `validation/README.md` 的 `V02` 到 `V06`。
5. 决策变化时更新 `conclusion.md` 和 ADR。

## 参考来源

- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Updating your app package installer to use the new Service Management API](https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api)
- [SMJobBless(_:_:_:_:)](https://developer.apple.com/documentation/servicemanagement/smjobbless(_:_:_:_:))
- [AuthorizationExecuteWithPrivileges](https://developer.apple.com/documentation/security/authorizationexecutewithprivileges)
- [Authorization Services](https://developer.apple.com/documentation/security/authorization-services)
- [NSXPCListener.setConnectionCodeSigningRequirement](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:))

## 关联文档

- [主题索引](README.md)
- [问题与边界](context.md)
- [调研与方案矩阵](investigation.md)
- [结论](conclusion.md)
- [推荐架构](solution.md)
- [验证矩阵](validation/README.md)
- [合盖睡眠控制与权限边界](../lid-sleep-control/README.md)
- [ADR-0005](../../adr/adr-0005-local-code-signing.md)
- [ADR-0006](../../adr/adr-0006-lid-sleep-privileged-helper.md)
