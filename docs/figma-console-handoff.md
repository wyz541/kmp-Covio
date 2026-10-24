# Talk to Figma 交接说明

结论：继续工作只用 `Talk to Figma` 插件。禁止使用 Desktop Bridge。

## 1. 工具与连接

- 工具是 `Talk to Figma` 插件。
- 通道是 `cmp-liquid-glass-27`。
- WebSocket 地址是 `ws://127.0.0.1:3055`。
- 客户端 ID 保存在 `/tmp/figma-target.txt` 和 `.git/covio-figma/figma-target.txt`。
- 通信库是 `.git/covio-figma/lib_figma.mjs`。
- 写入封装是 `.git/covio-figma/ops.mjs`。
- 批量操作使用 `run_ops`。
- `execute_code` 不可用。需要时使用 `run_ops`。

调用示例：

```bash
node .git/covio-figma/ops.mjs '[{"op":"getFileInfo"}]'
```

`run_ops` 支持 `noop`、`getPages`、`getFileInfo`、`getTextStyles`、`getVariables`、`getComponents`、`getNodeProps`、`getInstanceSlots`、`frame`、`section`、`rect`、`text`、`instance`、`slotAppend`、`set`、`bindVar`、`setMode`、`setProps`、`textOf`、`clearReactions`、`reaction`、`rename`、`delete`、`select`、`pluginData`、`loadFont` 和 `scrollIntoView`。

## 2. 目标文件

- 目标文件名称是 `Covio — Product Design · macOS 27`。
- 目标文件 key 是 `Bktv2SGgjcHuUZ7KJXEkPx`。
- 目标文件 URL 是 https://www.figma.com/design/Bktv2SGgjcHuUZ7KJXEkPx/Covio--Product-Design---macOS-27 。
- 源库名称是 `macOS 27 (Community)`。
- 源库 key 是 `Sh6AKZJPJXTf3GxM0mvBjj`。
- 源库 URL 是 https://www.figma.com/design/Sh6AKZJPJXTf3GxM0mvBjj/macOS-27--Community- 。
- `docs/covio-design-contract.json` 是机器可读权威。
- 目标文件是设计合同的视觉投影。

**警告：** 每次写入前核对文件 key `Bktv2SGgjcHuUZ7KJXEkPx`。错误的 key 会改动错误文件。

**警告：** 禁止复用其他文件的节点 ID。复制后节点 ID 会变化。

## 3. 结构与计数

| 项目 | 数量 |
| --- | --- |
| 页面总数 | 50 |
| 源页面 | 42 |
| 交付页面 | 8 |
| 交付 Section | 8 |
| 顶层画板 | 35 |
| 合同角色 | 22 |
| 源组件集 | 130 |
| 组件节点 | 186 |
| 变量 | 147 |
| 文字样式 | 22 |
| 交付文字节点 | 1259 |
| 自绘系统控件 | 0 |

- 源页面保持原始内容。
- 交付页面追加在源页面之后。
- 每个交付页面包含 1 个同名 Section。
- Section 原点是 `[0,0]`。
- 画板起点是 `[120,120]`。
- 画板间距是 `120`。
- 交付页面只使用浅色模式。
- 源页面中的深色变体保留。

## 4. 变量

| 变量集合 | 数量 | 模式 | 权威来源 |
| --- | --- | --- | --- |
| Colors | 63 | Light、Dark | macOS 27 (Community) |
| Sizes | 65 | Default | macOS 27 (Community) |
| Kit | 18 | Light、Dark | macOS 27 (Community) |
| Context | 1 | Default | macOS 27 (Community) |

- 变量总数是 `147`。
- 颜色和尺寸优先绑定来源变量。
- 新增品牌变量只保存源库没有的品牌值。
- 禁止复制源库已有的原生颜色变量。

## 5. 文字样式

- 源库包含 `22` 个文字样式。
- 交付文字节点数量是 `1259`。
- 交付页面使用 `SF Pro`。
- 交付页面不使用 `Inter`。
- 交付页面不使用 `Title 2/Emphasized`。
- 缺失字体数量是 `0`。
- 交付页面不含中文界面文案。
- Figma UI 文案只使用英文。
- 需要标注时使用英文短句。

## 6. 交付页面与画板

| 页面 | 页面 ID | Section ID | 画板 |
| --- | --- | --- | --- |
| `Covio 01 · Product Overview` | `8303:68461` | `8303:68469` | `00 · Brand Cover`、`01 · Product Promise`、`02 · Core Loop Map` |
| `Covio 02 · First Run & Pairing` | `8303:68462` | `8303:68470` | `03 · Welcome & Mode Choice`、`04 · Permissions & Discovery`、`05 · Pairing Code`、`06 · Pairing Confirmation & Success`、`07 · Pairing Error & Recovery` |
| `Covio 03 · Transfer` | `8303:68463` | `8303:68471` | `08 · File Selection`、`09 · Transfer Setup & Readiness`、`10 · Transfer Progress & Pause`、`11 · Transfer Complete`、`12 · Transfer Error & Recovery` |
| `Covio 04 · Clipboard & Files` | `8303:68464` | `8303:68472` | `13 · Clipboard History`、`14 · Clipboard Detail & Send`、`15 · Temporary Files & Cleanup`、`16 · Clipboard & Files Errors` |
| `Covio 05 · Screenshots & Top Shelf` | `8303:68465` | `8303:68473` | `17 · Screenshot Received`、`18 · Screenshot Preview & Actions`、`19 · Screenshot Drag Destinations`、`20 · Top Shelf Empty`、`21 · Top Shelf Populated`、`22 · Top Shelf Context & Drop` |
| `Covio 06 · Menu Bar & Notch Hub` | `8303:68466` | `8303:68474` | `23 · Menu Bar & Tray`、`24 · Tray Menu`、`25 · Hub Collapsed & Ready`、`26 · Hub Expanded Output`、`27 · Hub Tabs`、`28 · Hub Error & Recovery` |
| `Covio 07 · Power & Settings` | `8303:68467` | `8303:68475` | `29 · Settings Overview & General`、`30 · Settings Battery`、`31 · Settings Lid`、`32 · Settings Idle`、`33 · Settings Top Shelf & About` |
| `Covio 08 · Prototype Map` | `8303:68468` | `8303:68476` | `34 · End-to-End Prototype Map` |

- 每个画板是内容驱动的 Auto Layout Frame。

截图接管画板 17 至 22 是历史设计记录。
当前运行时使用 macOS 原生截图，并只在「文件」区显示截图索引。
- 每个画板展示一个真实产品场景。
- 画板宽度和高度以合同 `figmaNodeMap.boards` 为准。
- `Covio 08 · Prototype Map` 的离屏品牌组件不是画板。
- `Covio 08 · Prototype Map` 不创建组件目录。

## 7. 原生组件边界

- 交互控件优先使用来源组件实例。
- 禁止分离来源组件实例。
- 禁止直接修改实例内部文字。
- 实例文字通过组件属性设置。
- 窗口内容放入 `Windows - Composed` 的 `Content Area` Slot。
- 来源组件没有 Slot 时，使用项目 Auto Layout 容器。
- 来源组件存在时，禁止重绘窗口、菜单、按钮和字段。
- 来源组件缺失时，允许自绘缺失的系统控件。
- 自绘控件绑定来源变量。自绘文字使用 `SF Pro`。
- 自绘前记录缺失原因。重复自绘控件建立本地组件。

22 个合同角色使用来源优先映射。完整映射见 `docs/covio-design-contract.json` 的 `figmaNodeMap.componentRoleMappings`。

允许的品牌自定义内容有 3 个：

- `Covio/Brand/Tray Icon`
- `Covio/Brand/Clothespin`
- `Covio/Content/Screenshot Card`

- `component/page-title`、`component/setting-row` 和 `component/badge` 是 `custom-gap` 组合角色。
- 组合角色使用 Auto Layout、`SF Pro` 和来源控件。
- 禁止复制旧文件中的 `Covio/...` 系统控件组件集。

## 8. 原型

- 原型 edges 总数是 `42`。
- 原型 reactions 总数是 `42`。
- 缺失 reactions 数量是 `0`。
- 含 reactions 的画板有 `33` 个。
- 主路径是 `00 → 01 → 02 → 03 → 04 → 05 → 06 → 08 → 09 → 10 → 11 → 13 → 17 → 18 → 20 → 25 → 29`。
- 配对错误由 `07` 返回 `05` 或 `06`。
- 传输错误由 `12` 返回 `09`。
- 剪切板错误由 `16` 返回 `13`。
- Tray Menu 连接「文件 → 截图」、Settings 和 About。
- Settings 页面通过来源 Tab 控件互联。
- Hub 按 `25 → 26 → 27` 展开。
- Hub 错误由 `28` 返回 `25` 或 `27`。
- 菜单、弹窗、Popover、Alert 和 Sheet 使用 `DISSOLVE`。
- 拖放使用 `On drag`。About 使用 `After delay`。

**警告：** Figma 演示模式不运行跨页 reactions。页内 reactions 可以运行。跨页流程需要手动翻页。

## 9. 验证命令

```bash
node .git/covio-figma/ops.mjs '[{"op":"getFileInfo"}]'
node .git/covio-figma/ops.mjs '[{"op":"getPages"}]'
node .git/covio-figma/ops.mjs '[{"op":"getVariables"}]'
node .git/covio-figma/ops.mjs '[{"op":"getTextStyles"}]'
node .git/covio-figma/ops.mjs '[{"op":"getComponents","types":["COMPONENT_SET"]}]'
node .git/covio-figma/proto_status.mjs
node .git/covio-figma/verify_text.mjs
```

```bash
python3 -m json.tool docs/covio-design-contract.json >/dev/null
python3 -m json.tool docs/covio-design-contract.schema.json >/dev/null
git diff --check
```

- `getFileInfo` 返回 `pageCount: 50`。
- `getPages` 返回 `50` 个页面。
- `getVariables` 返回 `4` 个集合和 `147` 个变量。
- `getTextStyles` 返回 `22` 个样式。
- `getComponents` 返回 `130` 个组件集。
- `proto_status.mjs` 返回 `42` 个 reactions。
- `verify_text.mjs` 返回 `1259` 个文字节点和 `0` 个中文匹配。

## 10. 验收清单

- [ ] 通道是 `cmp-liquid-glass-27`。
- [ ] WebSocket 地址是 `ws://127.0.0.1:3055`。
- [ ] 文件 key 是 `Bktv2SGgjcHuUZ7KJXEkPx`。
- [ ] 页面总数是 `50`。
- [ ] 源页面数量是 `42`。
- [ ] 交付页面数量是 `8`。
- [ ] 交付 Section 数量是 `8`。
- [ ] 顶层画板数量是 `35`。
- [ ] 合同角色数量是 `22`。
- [ ] 源组件集数量是 `130`。
- [ ] 组件节点数量是 `186`。
- [ ] 变量数量是 `147`。
- [ ] 文字样式数量是 `22`。
- [ ] 交付文字节点数量是 `1259`。
- [ ] 缺失字体数量是 `0`。
- [ ] 分离实例数量是 `0`。
- [ ] 自绘系统控件数量是 `0`。
- [ ] 原型 reactions 数量是 `42`。
- [ ] 含 reactions 的画板数量是 `33`。
- [ ] JSON Schema Draft 2020-12 校验通过。
- [ ] `git diff --check` 通过。

## 11. 警告

**警告：** 写入前核对文件 key。错误的 key 会改动错误文件。

**警告：** 禁止分离来源组件实例。分离会破坏来源组件边界。

**警告：** 禁止直接编辑实例内部文字。直接编辑会静默失败。

**警告：** 禁止按进程名批量结束 Node 或 Bun 进程。批量结束会中断其他 Agent。

**警告：** 禁止改动旧文件 `Covio — Product Design`。旧文件只作历史记录。

## 12. 历史归档

以下内容只作历史记录。当前工作不使用这些内容。

- 旧文件是 `Covio — Product Design`。旧文件 key 是 `8LZX9sDtCHLsVHAIktk2aN`。
- 旧文件禁止修改。
- 早期版本使用 `figma-console`。`figma-console` 依赖 Desktop Bridge。
- 早期 Desktop Bridge 使用 `9223-9232` 端口。
- 早期版本基于 macOS 15 Sequoia。早期版本记录只作历史。
- 当前文件基于 `macOS 27 (Community)` 源库。
- 当前工作只用 `Talk to Figma` 插件。
