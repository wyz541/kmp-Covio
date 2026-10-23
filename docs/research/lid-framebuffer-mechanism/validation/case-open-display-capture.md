# Case 1：开盖显示与捕获基线

## 状态

已执行。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | `2026-10-23` |
| 机器 | MacBook Pro，Apple M1 Max |
| 系统 | macOS `27.0.1 (26A434)` |
| 目标 commit | `b7065b2` |
| 合盖状态 | `AppleClamshellState=No` |

## 步骤

1. 编译并运行显示状态探针。
2. 读取内建屏亮度。
3. 执行 `/usr/sbin/screencapture -x`。
4. 用 `sips` 读取图片尺寸。

## 观察

```text
display_id=1
builtin=1
online=1
active=1
asleep=0
main=1
pixel_width=3456
pixel_height=2234
refresh_rate=120.000
display_services_dlopen=1
get_brightness_symbol=1
set_brightness_symbol=1
get_brightness_result=0
brightness=0.08575986
```

截图：

```text
pixelWidth: 3456
pixelHeight: 2234
format: png
```

## 结论

开盖时内建屏 online、active、未 asleep。
DisplayServices 动态符号存在。
`CGMainDisplayID` 和屏幕捕获路径可用。
本次截图没有提交到仓库。

## 限制

1. 本案例只验证开盖状态。
2. 不能证明合盖黑屏时捕获可用。
3. 截图可能包含隐私内容，未归档。

## 清理

没有修改系统设置。
临时截图保存在 scratch，任务结束前删除。
