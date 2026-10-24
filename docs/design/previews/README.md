# UI 截图

本目录存打样、UI 决策和 UI 代码变更的截图。截图的固定 commit URL 填入对应 issue 的 `Visual verification` 表格。

## 命名

```text
<issue 号>-<页面名>-<状态>-<角色>-<序号>.png
```

角色取值：

| 角色 | 用途 |
| --- | --- |
| `current` | 当前界面 |
| `candidate` | 候选方案 |
| `selected` | 选定方案 |
| `before` | UI 代码变更前 |
| `after` | UI 代码变更后 |

示例：

- `231-file-area-960-before-1.png`
- `231-file-area-960-after-1.png`
- `231-file-area-960-candidate-a-1.png`
- `231-file-area-960-selected-a-1.png`

只有打样图、没有前后对比或方案选择时，可以继续使用旧格式：`<issue 号>-<打样名>-<序号>.png`。
例如 `106-device-pane-1.png`。

序号从 1 起。同一场景改了之后重截，序号加一。旧图不删，
评审要看改之前是什么样。

## 取图

1. 起服务。见 `docs/design/design-preview.md` 第 3 节。
2. 浏览器打开 `http://127.0.0.1:8080`，进到要截的那一屏。
3. 截图。窗口宽度按要评审的宽度取。窗口太窄或太宽都要另截一张。
4. 存进本目录。

## 注意

**注意：** 图是评审和追溯依据，不是发布物。发布物不含本目录。

**注意：** 仓库是公开仓库。截图必须使用测试数据，并遮挡用户名、文件名、通知和其他个人信息。
