# Developer ID 与 SMAppService 生命周期

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 状态 | 阻塞 |
| 阻塞条件 | 没有 Developer ID、notarization 凭据和测试签名包 |
| 目标 | 验证签名 daemon 的注册、批准、更新和回滚 |

## 验证目标

验证 `SMAppService.daemon` 在 Developer ID 签名和 notarization 条件下能否满足 Covio 的特权服务生命周期。

## 预检记录

执行前记录：

```sh
sw_vers
xcodebuild -version
security find-identity -v -p codesigning
codesign -dv --verbose=4 /Applications/Covio.app
spctl -a -vv /Applications/Covio.app
```

当前预检结果：`0 valid identities found`。

## 测试前采集

```sh
pmset -g
pmset -g assertions
launchctl print system/com.wyz.covio.helper 2>/dev/null || true
```

记录电源、休眠、风扇和充电状态。
如果测试会影响用户设备，先使用专用测试 Mac。

## 步骤模板

### V02：首次注册

前置条件：Developer ID 公证 app 已安装到 `/Applications`。

命令模板：

```sh
# 以下命令由待实现的签名探针提供。
open /Applications/CovioSMAppServiceProbe.app
CovioSMAppServiceProbe --register
```

预期：`register()` 成功，状态进入 `requiresApproval`。
管理员在 System Settings 批准后，状态进入 `enabled`。
daemon 可以完成 handshake。

实际结果：尚未执行。

### V03：更新后重新注册

前置条件：V02 已通过，存在第二个签名版本。

预期：更新后按 Apple 要求执行 `unregister()` 与 `register()`。
新 daemon 启动，releaseId 与 app 一致。

实际结果：尚未执行。

### V04：Unsupported Client

前置条件：目标 daemon 和 XPC listener 已实现。

预期：Team ID、bundle identifier 或签名 requirement 不匹配的客户端在 XPC 层被拒绝。

实际结果：尚未执行。

## 错误码

记录实际 `SMAppServiceErrorDomain` 和 Foundation XPC 错误域。
不把超时或权限拒绝合并成同一个错误。

## 结果汇总

| 测试 | 状态 | 结果 |
| --- | --- | --- |
| V02 | 阻塞 | 等待签名前提 |
| V03 | 阻塞 | 等待 V02 |
| V04 | 阻塞 | 等待实现 |

## 清理记录

1. 调用 `unregister()`。
2. 确认测试 daemon 停止。
3. 删除测试 app 和测试状态目录。
4. 确认测试 plist 不存在。
5. 恢复系统电源设置。

清理结果：尚未执行。

## 更新规则

- 每个步骤完成后填写时间和实际结果。
- 失败时记录错误域、错误码和可恢复状态。
- 修改签名或升级顺序时，更新本案例和 `validation/README.md`。

## 关联文档

- [验证矩阵](README.md)
- [推荐架构](../solution.md)
- [证据](../evidence.md)
