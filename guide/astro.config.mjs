// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
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
          items: [{ label: 'Covio 是什么', slug: 'chapters/what-is-covio' }],
        },
        {
          label: '组件样张',
          items: [{ label: '电源管理工作区', slug: 'components/power-management' }],
        },
      ],
    }),
  ],
});
