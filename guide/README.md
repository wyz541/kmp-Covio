# Covio 项目说明书

静态科普手册，使用 Astro Starlight 构建。

## 开发

```sh
npm install
npm run dev
```

## 页面入口

- 首页：`/`
- 章节总览：`/chapters/`
- 组件图鉴：`/components/`
- 组件样张：`/components/power-management/`

## 组件内容模型

组件目录格式：

```text
src/content/docs/components/<id>/
├── index.mdx
└── evidence/
```

新增组件页后，从 `pending.json` 删除对应 ID。
高层组件不在设计合同中，登记到 `extensions.json`。
检查内容模型：

```sh
npm run check:model
```

检查完整覆盖：

```sh
npm run check:contract:complete
```

## 构建

```sh
npm run build
```

正文和素材的权威目录是 `src/content/docs/`。


## 真机证据

先隐藏私人内容，再采集截图。
用窗口 ID 采集：

```sh
node scripts/capture-evidence.mjs \
  --component power-management \
  --id EV-POWER-002 \
  --scene "保持唤醒" \
  --window-id 12345
```

用已有截图采集：

```sh
node scripts/capture-evidence.mjs \
  --component power-management \
  --id EV-POWER-002 \
  --scene "保持唤醒" \
  --input ./capture.png
```

脚本会写入组件自己的 `evidence/`，并输出可直接粘贴到组件页的 YAML。
提交前运行：

```sh
npm run check:model
```

检查会验证：

1. 证据必填字段。
2. 图片存在和文件类型。
3. SHA-256。
4. 证据 ID 格式和全局唯一性。
5. 文件名中的日期和证据 ID。
6. 稳定组件不能使用占位素材。
