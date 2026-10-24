# Case 2：专注配置应用与恢复

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 案例编号 | Case 2 |
| 状态 | 尚未执行 |
| 覆盖测试 | V07 至 V10 |
| 日期 | `2026-10-24` |
| 执行人 | 待填写 |
| 复核人 | 待填写 |

案例会修改 Focus、应用可见性和睡眠断言。
执行前必须先取得用户确认。
执行前必须备份个人 Focus 和 Shortcut 配置。

## 1. 验证目标

1. 验证 Focus 租约和释放。
2. 验证进入和退出 Shortcut。
3. 验证应用隐藏、退出和恢复。
4. 验证崩溃后的恢复入口。

## 2. 预检记录

| 项目 | 值 | 状态 |
| --- | --- | --- |
| 系统版本 | 待填写 | 待执行 |
| 电源状态 | 待填写 | 待执行 |
| 当前 Focus | 待填写 | 待执行 |
| 当前活动会话 | 待填写 | 待执行 |
| 测试文档 | 待填写 | 待执行 |

## 3. 测试前采集

命令：

```sh
sw_vers
pmset -g assertions
shortcuts list
```

记录字段：

```text
System:
Assertions:
Shortcut count:
Current Focus:
```

## 4. V07：Focus 唤醒租约和释放

前置：实现 Focus 租约来源。

请求模板：

```json
{
  "request_id": "v07-start",
  "op": "focus.session.start",
  "args": {
    "profile_id": "test-coding",
    "duration_seconds": 120,
    "dry_run": false,
    "allow_degraded": false
  }
}
```

预期结果：

1. 会话进入 `active`。
2. `pmset -g assertions` 显示 Covio 的保持唤醒断言。
3. 停止后断言消失。

记录：

```text
Start time:
End time:
Start response:
Assertion before stop:
Assertion after stop:
Error code:
Result: PENDING
```

通过条件：断言创建和释放都能回读。

## 5. V08：Focus Shortcut 进入和退出

前置：用户创建临时 Focus 和两个 Shortcut。

用户操作：

1. 打开“系统设置 > 专注模式”。
2. 新建自定义 Focus，名称为 `Covio Test Focus`。
3. 打开 Shortcuts。
4. 新建 `Covio Test Enter`。
5. 添加 `Set Focus` 动作，选择 `Covio Test Focus`，选择开启。
6. 新建 `Covio Test Exit`。
7. 添加 `Set Focus` 动作，选择 `Covio Test Focus`，选择关闭。

基线命令：

```sh
shortcuts run 'Covio Test Enter'
shortcuts run 'Covio Test Exit'
```

应用内步骤：

1. 从 Covio 测试入口进入模板。
2. 确认 Covio 启动 `FocusShortcutRunner`。
3. 让 runner 运行同一个进入 Shortcut。
4. 从 Covio 停止模板。
5. 确认 runner 运行同一个退出 Shortcut。

预期结果：

1. 进入命令返回 `0`。
2. Focus 状态变为开启。
3. 退出命令返回 `0`。
4. Focus 状态变为关闭。

记录：

```text
Start time:
End time:
Enter exit code:
Focus after enter:
Exit exit code:
Focus after exit:
Error code:
Result: PENDING
```

通过条件：两个命令成功，状态可回读。

## 6. V09：应用隐藏、退出和恢复

前置：只使用可丢弃的 TextEdit 文档。

命令模板：

```sh
open -a TextEdit
```

应用动作：

1. 记录 TextEdit 的可见状态。
2. 启动测试配置。
3. 让配置隐藏 TextEdit。
4. 确认 TextEdit 隐藏。
5. 停止测试配置。
6. 确认 TextEdit 恢复可见。
7. 对未保存文档重复请求退出。
8. 确认出现保存提示。
9. 取消退出并确认应用继续运行。

预期结果：

1. 隐藏状态可恢复。
2. 原本隐藏的应用不被取消隐藏。
3. 取消退出不会触发强制退出。
4. 应用继续运行。

记录：

```text
Start time:
End time:
Before visibility:
During visibility:
After visibility:
Quit prompt:
Cancelled state:
Error code:
Result: PENDING
```

通过条件：应用可见状态和取消退出行为符合规则。

## 7. V10：崩溃恢复

前置：测试配置已经启动。

步骤：

1. 启动测试配置。
2. 确认恢复日志存在。
3. 终止 Covio 进程。
4. 重新启动 Covio。
5. 检查残留会话提示。
6. 执行恢复。
7. 检查应用和断言状态。

预期结果：

1. 重启后发现残留会话。
2. 用户能看到恢复入口。
3. 恢复后应用可见状态正确。
4. 恢复后没有 Focus 租约。
5. 恢复失败时日志保留。

记录：

```text
Start time:
End time:
Journal before restart:
Recovery prompt:
Recovery result:
Journal after recovery:
Error code:
Result: PENDING
```

通过条件：会话可被发现和恢复。

## 8. 错误码

| 错误码 | 记录位置 |
| --- | --- |
| `focus_shortcut_missing` | V08 |
| `focus_shortcut_failed` | V08 |
| `focus_shortcut_timeout` | V08 |
| `app_hide_failed` | V09 |
| `app_quit_cancelled` | V09 |
| `wake_lease_failed` | V07 |
| `restore_failed` | V10 |
| `journal_corrupt` | V10 |

## 9. 结果汇总

当前状态：尚未执行。

待验证项目：

1. Focus 租约。
2. Focus Shortcut。
3. 应用隐藏和退出。
4. 崩溃恢复。

## 10. 清理记录

执行后填写。

1. 退出测试专注模式。
2. 删除 `Covio Test Enter`。
3. 删除 `Covio Test Exit`。
4. 删除 `Covio Test Focus`。
5. 关闭测试文档，不保存。
6. 删除测试会话日志。
7. 检查没有活动断言。

## 11. 更新规则

1. 每步完成后回填时间和实际结果。
2. 失败项写明错误码。
3. 结果变化时更新 [验证计划](README.md)。
4. 证据变化时更新 [证据附录](../evidence.md)。
5. 结论变化时更新 [结论与限制](../conclusion.md)。

## 12. 关联文档

- [主题索引](../README.md)
- [证据附录](../evidence.md)
- [验证目录](README.md)
- [Case 1](case-readonly-focus-probe.md)
