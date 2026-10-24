# 验证计划

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 部分通过 |
| 日期 | `2026-10-24` |
| 目标环境 | Apple Silicon Mac，macOS 27.0.1 |
| 问题类别 | 系统策略的可恢复自动化 |
| 主文 | [主题索引](../README.md) |
| 证据附录 | [证据附录](../evidence.md) |
| 只读记录 | [Case 1](case-readonly-focus-probe.md) |
| 写入计划 | [Case 2](case-focus-profile-apply.md) |

## 1. 案例索引

| 编号 | 案例 | 覆盖测试 | 结果文件 |
| --- | --- | --- | --- |
| Case 1 | 只读能力探针 | V01 至 V06 | `case-readonly-focus-probe.md` |
| Case 2 | 专注配置应用与恢复 | V07 至 V10 | `case-focus-profile-apply.md` |

## 2. 验证目标

1. 确认公开接口和能力缺口。
2. 确认 Shortcuts 可以承载 Focus 写入。
3. 确认应用隐藏和恢复正常。
4. 确认睡眠租约可以释放。
5. 确认崩溃后可以发现残留会话。

## 3. 范围内事项

1. macOS 27 的只读接口探针。
2. 用户创建的临时 Focus。
3. 用户创建的临时进入和退出 Shortcut。
4. TextEdit 的隐藏和退出。
5. `HoldLeaseManager` 的 Focus 来源。
6. 会话日志和恢复入口。

## 4. 范围外事项

1. 修改音量。
2. 修改亮度。
3. 修改 Wi-Fi、VPN 或蓝牙。
4. 修改风扇和功耗。
5. 修改真实用户 Focus。
6. 使用真实个人 Shortcut。
7. 强制退出应用。
8. Mac App Store 审核。

## 5. 当前事实

| 项目 | 值 |
| --- | --- |
| 系统 | macOS 27.0.1 |
| SDK | MacOSX27.0 |
| Focus 授权 | 未决定 |
| Shortcut 数量 | 0 |
| 只读探针 | 部分通过 |
| 系统写入测试 | 尚未执行 |

## 6. 成功标准

1. 每个测试有命令、结果和清理记录。
2. 系统写入只使用临时对象。
3. 应用恢复后可见状态与测试前一致。
4. 会话退出后没有活动 Focus 租约。
5. Shortcut 失败返回明确错误。
6. 退出请求取消时不调用强制退出。
7. 崩溃后下次启动显示恢复入口。
8. 测试结束后删除临时 Focus 和 Shortcut。

## 7. 前置条件

1. 用户先备份个人 Focus 和 Shortcut 配置。
2. 用户先关闭真实专注会话。
3. 测试只使用 `Covio Test` 前缀。
4. 测试只用可丢弃的 TextEdit 文档。
5. 测试期间接通电源。
6. 测试期间不运行重要远程会话。
7. 每步完成后记录系统状态。
8. 高风险步骤前取得用户确认。

## 8. 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| VR-01 | 临时 Focus 被遗忘 | 清理步骤检查并删除 |
| VR-02 | 真实应用有未保存文档 | 只用可丢弃文档 |
| VR-03 | 睡眠断言未释放 | 检查 `pmset` 和 Focus 会话状态 |
| VR-04 | Shortcut 修改其他系统设置 | 只允许 `Set Focus` 动作 |
| VR-05 | 会话崩溃留下未知状态 | 使用恢复日志和人工入口 |
| VR-06 | 测试覆盖真实用户 Focus | 只使用 `Covio Test` 名称 |

## 9. 测试矩阵

| 编号 | 场景 | 当前状态 | 结果文件 |
| --- | --- | --- | --- |
| V01 | SDK 提供 Focus 状态读取 | 通过 | `case-readonly-focus-probe.md` |
| V02 | SDK 不提供公开 Focus 写入 | 通过 | `case-readonly-focus-probe.md` |
| V03 | Shortcuts CLI 可运行 | 通过 | `case-readonly-focus-probe.md` |
| V04 | Focus 状态授权和布尔结果 | 部分通过 | `case-readonly-focus-probe.md` |
| V05 | `Set Focus` 动作存在 | 通过 | `case-readonly-focus-probe.md` |
| V06 | 应用和电源公开接口存在 | 通过 | `case-readonly-focus-probe.md` |
| V07 | Focus 唤醒租约和释放 | 尚未执行 | `case-focus-profile-apply.md` |
| V08 | Focus Shortcut 进入和退出 | 尚未执行 | `case-focus-profile-apply.md` |
| V09 | 应用隐藏、退出和恢复 | 尚未执行 | `case-focus-profile-apply.md` |
| V10 | 崩溃恢复 | 尚未执行 | `case-focus-profile-apply.md` |

## 10. 证据要求

1. 每项测试记录开始时间和结束时间。
2. 每项测试记录命令或请求。
3. 每项测试记录退出码。
4. 每项测试记录系统回读结果。
5. 失败项记录错误码。
6. 不记录通知内容。
7. 不记录文档内容。
8. 不记录 Shortcut 中的敏感数据。

## 11. 清理步骤

1. 退出 `Covio Test` 专注模式。
2. 关闭或隐藏测试应用。
3. 删除 `Covio Test Enter`。
4. 删除 `Covio Test Exit`。
5. 删除 `Covio Test Focus`。
6. 删除临时会话日志。
7. 检查没有活动睡眠断言。
8. 检查系统恢复原 Focus 设置。
9. 如果任何步骤失败，保留日志并标记 `recovery_required`。

## 12. 关联文档

- [主题索引](../README.md)
- [问题边界](../context.md)
- [调研分析](../investigation.md)
- [结论与限制](../conclusion.md)
- [推荐方案](../solution.md)
- [证据附录](../evidence.md)
- [Case 1](case-readonly-focus-probe.md)
- [Case 2](case-focus-profile-apply.md)
