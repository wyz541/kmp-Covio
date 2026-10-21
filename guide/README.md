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
