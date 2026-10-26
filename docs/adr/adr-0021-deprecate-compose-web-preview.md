# ADR-0021：废弃 Compose Web 打样路径

- Status：accepted
- Kind：process
- Date：2026-10-26
- Supersedes：none
- Implements：#414
- 相关：#98、#103、#106、#107、#201

## 背景

Feature #98 把 Compose Web 打样设为设计源和 UI 决策闸门。
Research #103 验证了 Amper 0.12.1 可以运行 `wasm-js/app` 模块。
#107 与 #201 随后加入了工作台和文件区打样。

这套路径维护了两份界面实现。Compose 打样无法验证真机 Liquid Glass，也自带一份数据模型。
打样要求还让普通 UI 改动先生成浏览器原型。
项目负责人已决定废弃这套方案。

## 决策

1. Compose Web 打样退出设计源和必选评审闸门。
2. 删除 `designPreview` 模块、打样说明和专用脚本。
3. 删除 `AGENTS.md`、Issue 模板与研发流程中的强制 Web 预览要求。
4. 保留 `docs/design/previews/` 的历史截图。旧图不删除。
5. UI 代码变更继续使用 `Visual verification`，提供亮色和深色真机截图。
6. UI 决策可以使用当前界面、静态方案或真机原型。选定方案必须留存截图。
7. 设计合同仍描述当前界面合同。来源改为 Covio macOS 宿主实现。
8. 如以后恢复浏览器原型，必须先写新 ADR。

## 后果

### 正面

- 不再维护第二套界面实现。
- UI 评审以真实 macOS 渲染为准。
- Issue 模板和研发流程少一道固定等待。
- 历史截图仍可追溯旧方案。

### 负面

- 不再提供可点击的浏览器交互原型。
- 复杂交互的早期评审需要运行 macosApp 或准备静态方案。
- 旧 Issue 与 ADR 仍保留 Compose Web 打样的历史链接。

### 风险

- 删除模块可能漏掉命令或链接。缓解：全仓库搜索旧入口，并运行全量测试。
- 旧截图可能被误认为当前效果。缓解：预览说明写明历史状态，并新增 ADR 记录废弃。
- 新方案可能再次引入重复渲染器。缓解：恢复浏览器原型前必须写新 ADR。

## 备选方案

### 备选 1：冻结模块，不再新增打样

该方案保住浏览器原型，同时停止新增内容。

未采纳。模块仍要随 Compose 和 Amper 升级维护，废弃边界也不清楚。

### 备选 2：只在复杂 UI 改动时使用 Compose Web

该方案保留交互原型能力。

未采纳。两套界面实现仍会漂移，评审规则也不稳定。

### 备选 3：只用真机 SwiftUI 原型

该方案直接验证最终渲染和系统材质。

采纳。UI 代码变更用真机截图完成 `Visual verification`。

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 历史截图是否迁移目录 | out of scope | 只有当前目录影响证据链接时再议 |
| 是否需要通用静态原型工具 | out of scope | 出现重复需求后另开 Research |

## 参考

- [Feature #98](https://github.com/wyz541/kmp-Covio/issues/98)
- [Research #103](https://github.com/wyz541/kmp-Covio/issues/103)
- [Compose Web 工作台预览 #107](https://github.com/wyz541/kmp-Covio/issues/107)
- [统一文件区 Web 预览 #201](https://github.com/wyz541/kmp-Covio/issues/201)
- [清理任务 #414](https://github.com/wyz541/kmp-Covio/issues/414)
