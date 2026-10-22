// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://wyz541.github.io',
  integrations: [
    starlight({
      title: 'Covio 项目说明书',
      description: '从产品地图到组件样张，读懂 Covio 的界面、状态和真实取舍。',
      defaultLocale: 'root',
      locales: {
        root: { label: '简体中文', lang: 'zh-CN' },
      },
      customCss: ['./src/styles/guide.css'],
      components: {
        PageTitle: './src/components/guide/PageTitle.astro',
      },
      tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
      sidebar: [
        {
          label: '开始阅读',
          items: [
            { label: '封面', slug: 'index' },
            { label: '阅读方法', slug: 'read/how-to-read' },
          ],
        },
        {
          label: '产品地图',
          items: [
            { label: '章节总览', slug: 'chapters' },
            { label: 'Covio 是什么', slug: 'chapters/what-is-covio' },
            { label: '界面地图', slug: 'chapters/interface-map' },
            { label: '核心流程', slug: 'chapters/core-loop' },
          ],
        },
        {
          label: '组件图鉴',
          items: [
            { label: '组件总览', slug: 'components' },
            { label: '按钮', slug: 'components/button' },
            { label: '截图卡片', slug: 'components/screenshot-card' },
            { label: '菜单栏图标', slug: 'components/tray-icon' },
            { label: '电源管理工作区', slug: 'components/power-management' },
          ],
        },
        {
          label: '附录',
          items: [{ label: '图例与约定', slug: 'appendices/legend' }],
        },
      ],
    }),
  ],
});
