# ADR-0009：项目说明书网站采用 Astro Starlight

- Status：accepted
- Kind：architecture
- Date：2026-10-21
- Supersedes：none
- Implements：pending
- 相关：[Research #205](https://github.com/wyz541/kmp-Covio/issues/205)、[设计合同](../covio-design-contract.json)

## 背景

Covio 需要一份面向读者、类似科普读物的项目说明网站。  
网站要有目录、章节、图例、组件定义、功能说明和真机实例。  
现有 Markdown 文档不能稳定表达图例、视觉层级和跨章节导航。  

网站内容会持续变化。  
用户要求正文和素材统一管理。  
每个组件应能独立修改。  
真机截图必须可追溯。  
静态构建后应能直接发布。  

Research #205 比较了 Astro Starlight、Docusaurus、VitePress、Fumadocs 和 Nextra。  
在当前约束下，Astro Starlight 的内容模型、构建校验和静态搜索更符合需求。  

## 决策

1. 项目说明书放在仓库的 `guide/` 目录。
2. 使用 Astro Starlight 构建静态网站。
3. 当前基线固定为 `astro@7.4.1` 和 `@astrojs/starlight@0.42.6`。
4. 使用 `package-lock.json` 锁定完整依赖树。
5. 升级 Astro 或 Starlight 必须单独提交 PR，并重新跑内容、证据、链接和可访问性检查。
6. 所有正文、图例和组件素材放在 `guide/src/content/docs/`。
7. 每个组件使用一个独立目录。
8. 每个正式组件目录包含 `index.mdx` 和 `evidence/`。
9. 组件正文使用 MDX。MDX 是可以在 Markdown 中嵌入组件的格式。
10. 组件元数据写在 MDX frontmatter 中，并由 Astro Content Collections 和 Zod 校验。
11. 组件页必须定义 `id`、`kind`、`status`、`definition`、`capabilities`、`states` 和 `platforms`。
12. 每个组件至少提供一个功能说明。正式页面至少提供一个真机实例。
13. 真机实例必须记录图片、采集日期、设备、系统、外观、场景、来源提交和 SHA-256。
14. 正式页面只接受 `status: real-device` 的实例。占位素材只能出现在预览或测试中。
15. 每个实例图片放在所属组件的 `evidence/` 下。
16. 构建前校验实例图片存在、SHA-256 匹配且证据 ID 唯一。
17. 使用 `docs/covio-design-contract.json` 检查设计合同组件覆盖率。
18. 设计合同组件缺少页面时，检查失败。
19. 不在设计合同中的高层页面，必须登记在明确的扩展清单中。
20. 组件总索引从内容集合生成，不手工维护重复列表。
21. 使用 Pagefind 提供静态全文搜索。
22. 站点根语言固定为 `zh-CN`。Pagefind 按页面语言生成中文索引。
23. 使用自定义 Astro 组件承载组件定义、功能卡片、图例和真机实例画廊。
24. 普通内容默认输出 HTML。只有需要交互时加载客户端组件。
25. 图例同时使用文字和图形。状态不能只靠颜色表达。
26. 图表和截图必须提供替代文本。键盘焦点必须可见。
27. 动画必须遵循 `prefers-reduced-motion`。
28. 网站通过 GitHub Pages 发布。构建产物是普通静态文件。
29. `guide/node_modules/`、`guide/dist/` 和构建缓存不提交。
30. 内容 CI 必须执行 Astro 构建、相对链接检查、证据校验、合同覆盖检查和无障碍检查。
31. 网站 UI 变化先提交 web 预览。预览通过评审后，再进入正式实现。

## 内容结构

每个组件页按下列顺序组织。

1. 一句话定义。
2. 它解决的问题。
3. 功能列表。
4. 状态与变化。
5. 真机实例。
6. 无障碍要求。
7. 实现映射。
8. 已知限制。
9. 相关组件。

章节页面只引用组件页。  
章节页面不复制组件定义和功能说明。  
同一条事实只维护一处。  

## 后果

### 正面

- 正文、图例和截图可以按组件统一管理。
- 缺少定义、功能或证据时，构建失败。
- 新增组件时只修改一个目录。
- 设计合同和说明书可以自动对账。
- 中文全文搜索无需运行时服务。
- 普通页面保持静态 HTML，运行时依赖较少。
- 主体格式是 MDX 和普通图片，退出成本较低。
- 后续可以用 Astro 或 React 组件增加交互演示。

### 负面

- 仓库增加 Node 和 Astro 工具链。
- 贡献者需要了解 frontmatter、MDX 和 Astro 组件。
- 真机截图需要额外采集和复核。
- Starlight 当前仍处于 `0.x`，升级需要单独验证。
- 自定义科普布局需要维护少量 Astro 组件。

### 风险

- Starlight 升级产生破坏性变化。缓解：锁定版本，升级 PR 重跑全部内容检查。
- 设计合同与组件页 ID 漂移。缓解：CI 覆盖率检查。
- 真机证据被替换或误用。缓解：SHA-256、来源提交和人工复核。
- 截图包含隐私信息。缓解：采集前隐藏私人内容，评审时检查。
- 颜色成为唯一状态线索。缓解：图例使用文字和图形，并执行无障碍检查。
- Node 工具链影响主应用构建。缓解：Node 依赖只放在 `guide/`，CI 独立缓存。
- GitHub Pages 路径变化破坏链接。缓解：构建时检查站内相对链接。

## 备选方案

### 备选 1：Docusaurus 3

Docusaurus 有成熟的 React 插件生态。  
它也支持 MDX、静态生成和图片同目录引用。  
它的基础模板不提供本地全文搜索。  
本地搜索需要社区插件或 Algolia。  
组件元数据没有 Starlight 式的内容 schema。  
因此保留为备用方案，不选为主方案。  

### 备选 2：VitePress

VitePress 构建快，体积小，内置本地搜索。  
它也支持 Markdown 和 Vue 组件。  
它缺少当前需求所需的内容 schema 和开箱即用的文档结构。  
科普布局和组件目录需要更多自定义代码。  
因此不选为主方案。  

### 备选 3：Fumadocs

Fumadocs 的 React 定制能力强。  
它支持静态导出和多种搜索方案。  
它默认偏服务端，静态构建和静态搜索需要额外配置。  
它依赖 Next.js 或 React 框架，维护面更大。  
因此不选为主方案。  

### 备选 4：Nextra

Nextra 支持 MDX、静态导出和 Pagefind。  
它的最新发布和维护节奏弱于其他候选。  
静态导出还需要设置 `images.unoptimized`。  
因此不选为主方案。  

## 未决事项

| 项目 | 状态 | 确认方法 |
| --- | --- | --- |
| 真机截图采集流程 | 未开始 | 用 3 个代表性组件完成采集、校验和复核 |
| 高层页面扩展清单 | 未开始 | 首个 Feature 中列出外壳、工作区、设置等高层对象 |
| GitHub Pages 发布地址 | 未开始 | 首个站点 PR 验证项目页路径和相对链接 |
| 中文搜索相关性 | 未开始 | 用真实组件名和功能词执行搜索验收 |
| 设计合同覆盖率 | 未开始 | 构建脚本检查 21 个合同组件 |

## 参考

- [Research #205](https://github.com/wyz541/kmp-Covio/issues/205)
- [Starlight](https://github.com/withastro/starlight)
- [Starlight 内容编写](https://starlight.astro.build/guides/authoring-content/)
- [Starlight 搜索](https://starlight.astro.build/guides/site-search/)
- [Starlight 组件覆盖](https://starlight.astro.build/guides/overriding-components/)
- [Astro Images](https://docs.astro.build/en/guides/images/)
- [Pagefind Multilingual Search](https://pagefind.app/docs/multilingual/)
- [设计合同](../covio-design-contract.json)
