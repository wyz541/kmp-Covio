# 验证

## 状态

源码调研已完成。
硬件写入验证尚未执行。

## 单元验证

| 检查 | 预期 |
| --- | --- |
| 模式持久化 | `automatic`、`curve`、`manual` 往返一致 |
| 旧配置迁移 | `enabled + automatic` 变为 `curve` |
| 系统自动 | helper payload 使用 `auto` |
| 百分比同步 | 两台不同范围风扇得到相同速度位置 |
| 同步关闭 | 只改当前风扇 |
| helper 模式 | `curve` 可以写入，`automatic` 只恢复 |

## UI 验证

截取手动模式和同步开关的亮色、深色 Popover。
截图必须来自生产 SwiftUI 视图。
不执行风扇写入。

## 限制

本次验证不能证明所有 Apple Silicon 和 Intel 机型行为一致。
模式 `3` 的行为需要后续真机安全验收。
