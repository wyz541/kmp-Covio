# 真机调查与失败根因

## 方法

1. 记录旧 app、helper、协议、签名和 LaunchDaemon 状态。
2. 构建 internal/local ad-hoc PKG。
3. 通过真实 `installer` 安装。
4. 读取 `/var/log/install.log` 和事务日志。
5. 对失败项增加回归测试。
6. 重复安装并注入真实文件系统失败。
7. 记录升级后的 app、helper、plist、记录和系统状态。

## 失败 1：PKG 重定位 staged app

观察：

```text
Installer: Staged helper identity cannot be read
PackageKit: Parent bundle com.wyz.covio will be atomically shoved.
```

`pkgbuild` 自动把 `Installer/staged/Covio.app` 识别为 bundle。
Installer 因而进入 bundle 重定位流程。
postinstall 读取 staged app 时，原路径不可用。

修复：使用空 component plist。
PKG 构建后断言 `PackageInfo` 不含 `<bundle path=...>`。

## 失败 2：helper 身份依赖 TMPDIR

修复重定位后，staged helper 仍无法读取身份。
根因是事务使用 `mktemp` 和安装进程的 `TMPDIR`。
PKG 脚本环境不能保证该临时目录可用。

修复：

- helper 输出直接写入事务目录。
- 保留 helper stdout。
- 保留 helper stderr。
- 记录退出码。
- 回归测试使用不可用的 `TMPDIR`。

## 失败 3：Legacy 安装调用 SMAppService

重复安装日志：

```text
Unregistering the dormant SMAppService helper
Cannot unregister CovioHelper: Requestor lacks required entitlement
```

Legacy 路径调用了退役的 `SMAppService.unregister()`。
ad-hoc app 没有该 API 要求的 entitlement。
该调用阻止固定 helper 安装。

修复：Legacy 安装不再调用 `SMAppService.unregister()`。

## 失败 4：Debug 充电写入绕过握手

真机使用不匹配 helper 时，正常状态为 OUTDATED。
Debug 命令仍直接发送 `chargeLimitConfigure`。
写入成功，违反安全模式约束。

修复：

- Debug `configure` 先执行完整身份握手。
- 非 MATCH 时拒绝写入。
- Debug `restore` 保留为安全恢复入口。

## 失败 5：注册阶段错误信息不足

最初只记录：

```text
new helper registration or exact handshake failed
```

无法区分 helper 安装失败和 XPC 握手失败。
修复：记录阶段、退出码、stdout、stderr 和最后一次握手探测结果。

## 结论

五个问题都属于真实发布路径。
单元测试目录没有空格和不可用 `TMPDIR`，没有发现前两项。
重复安装发现 SMAppService entitlement 问题。
安全模式实测发现 Debug 写入绕过。
失败注入证明回滚路径可以在 helper 目录不可写时恢复旧对象并保持 MATCH。
