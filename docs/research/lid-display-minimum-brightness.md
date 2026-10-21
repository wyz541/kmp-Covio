# 合盖显示与最低亮度

## 文档状态

| 项目 | 内容 |
| --- | --- |
| 文档版本 | `1.0` |
| 状态 | 结论：current constraints no-go |
| 日期 | `2026-10-21` |
| Issue | #191 |
| Feature | #148 |
| 关联任务 | #190 |

## 问题

Apple Silicon 内建屏能否在合盖后保持点亮，并设置为最低亮度？

## 结论

当前约束下不支持。

Covio 支持“合盖保持运行，内建屏关闭”。
Covio 不支持“合盖保持运行，内建屏点亮并降到最低亮度”。

## 依据

1. `IOPMLib.h` 没有合盖显示保持断言。
2. 公开断言只覆盖空闲系统睡眠和空闲显示器睡眠。
3. 内建屏在合盖后受硬件 clamshell 状态管理。
4. Apple M1 Max 上直接调用公开 IOKit 亮度接口返回 `kIOReturnUnsupported`。
5. 可用的内建屏亮度接口依赖私有 `DisplayServices`。
6. ADR 约束禁止私有亮度 API 和私有 entitlement。

## 决策

1. UI 使用“合盖关屏”，不显示“最低亮度”成功状态。
2. 不用 gamma 黑屏、遮罩或隐藏窗口冒充硬件亮度。
3. 不把外接屏行为标成内建屏行为。
4. 外接屏保持点亮需要单独产品需求。

## 关联证据

- `docs/research/lid-sleep-control/evidence.md` 的 `E-02`。
- Xcode 27 SDK 的 `IOPMLib.h`。
- Xcode 27 SDK 的 `IOGraphicsLib.h`。
- 本机 `AppleClamshellState` 与 IOKit 亮度探测。
