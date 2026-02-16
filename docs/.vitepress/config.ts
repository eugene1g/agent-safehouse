import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Agent Safehouse',
  description: 'Sandbox your LLM coding agents on macOS. Kernel-level enforcement via sandbox-exec — deny-first, composable, zero dependencies.',

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32.png' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16.png' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:url', content: 'https://agent-safehouse.dev/' }],
    ['meta', { property: 'og:title', content: 'Agent Safehouse' }],
    ['meta', { property: 'og:description', content: 'Sandbox your LLM coding agents on macOS. Kernel-level enforcement via sandbox-exec — deny-first, composable, zero dependencies.' }],
    ['meta', { property: 'og:image', content: 'https://agent-safehouse.dev/og-image.png' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:title', content: 'Agent Safehouse' }],
    ['meta', { name: 'twitter:description', content: 'Sandbox your LLM coding agents on macOS. Kernel-level enforcement via sandbox-exec — deny-first, composable, zero dependencies.' }],
    ['meta', { name: 'twitter:image', content: 'https://agent-safehouse.dev/og-image.png' }],
  ],

  appearance: false,

  markdown: {
    theme: {
      light: 'one-light',
      dark: 'one-dark-pro',
    },
  },

  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Investigations', link: '/agent-investigations/' },
      { text: 'Policy Builder', link: '/policy-builder' },
    ],

    sidebar: [
      {
        text: 'Agent Investigations',
        link: '/agent-investigations/',
        items: [
          { text: 'Aider', link: '/agent-investigations/aider' },
          { text: 'Auggie (Augment Code)', link: '/agent-investigations/auggie' },
          { text: 'Claude Code', link: '/agent-investigations/claude-code' },
          { text: 'Cline', link: '/agent-investigations/cline' },
          { text: 'Codex', link: '/agent-investigations/codex' },
          { text: 'Cursor Agent', link: '/agent-investigations/cursor-agent' },
          { text: 'Droid (Factory CLI)', link: '/agent-investigations/droid' },
          { text: 'Gemini CLI', link: '/agent-investigations/gemini-cli' },
          { text: 'Goose', link: '/agent-investigations/goose' },
          { text: 'Kilo Code', link: '/agent-investigations/kilo-code' },
          { text: 'OpenCode', link: '/agent-investigations/opencode' },
          { text: 'Pi', link: '/agent-investigations/pi' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/eugene1g/agent-safehouse' },
    ],

    footer: {
      message: 'Open source under the Apache 2.0 License.',
      copyright: 'Agent Safehouse',
    },
  },
})
