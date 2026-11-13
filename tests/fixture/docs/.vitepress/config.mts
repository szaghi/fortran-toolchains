// the fixture's site, shaped like the projects' (PENF): the API pages formal writes under api/, their sidebar
import { withMermaid } from 'vitepress-plugin-mermaid'
import apiSidebar from '../api/_sidebar.json'

export default withMermaid({
  title: 'fixture',
  description: 'The project the reusable workflows of fortran-toolchains are tested on',
  // the Pages site of the repository Selftest runs in
  base: '/fortran-toolchains/',

  markdown: {
    math: true,
    languages: ['fortran-free-form'],
    languageAlias: { fortran: 'fortran-free-form', f90: 'fortran-free-form' },
  },

  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/' },
      { text: 'API', link: '/api/' },
    ],
    sidebar: {
      '/guide/': [{ text: 'Guide', items: [{ text: 'About', link: '/guide/' }] }],
      '/api/': apiSidebar,
    },
    socialLinks: [{ icon: 'github', link: 'https://github.com/szaghi/fortran-toolchains' }],
  },

  mermaid: {},

  // as the scaffold: an explicit modern target, so esbuild never has to lower mermaid's syntax
  vite: { build: { target: 'es2022' } },
})
