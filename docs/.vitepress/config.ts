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
      { text: 'Docs', link: '/docs/' },
      { text: 'Policy Builder', link: '/policy-builder' },
    ],

    sidebar: {
      '/docs/': [
        {
          text: 'Start Here',
          items: [
            { text: 'Docs Home', link: '/docs/' },
            { text: 'Overview & Philosophy', link: '/docs/overview' },
            { text: 'Isolation Models', link: '/docs/isolation-models' },
            { text: 'Default Assumptions', link: '/docs/default-assumptions' },
            { text: 'Getting Started', link: '/docs/getting-started' },
            { text: 'Usage', link: '/docs/usage' },
            { text: 'Options', link: '/docs/options' },
          ],
        },
        {
          text: 'Build Up',
          items: [
            { text: 'Policy Architecture', link: '/docs/policy-architecture' },
            { text: 'Distribution Artifacts', link: '/docs/distribution' },
            { text: 'Customization', link: '/docs/customization' },
            { text: 'Testing', link: '/docs/testing' },
            { text: 'Debugging Sandbox Denials', link: '/docs/debugging' },
            { text: 'Reference & Prior Art', link: '/docs/references' },
          ],
        },
        {
          text: 'Agent Investigations',
          link: '/docs/agent-investigations/',
          items: [
            { text: 'Aider', link: '/docs/agent-investigations/aider' },
            { text: 'Auggie (Augment Code)', link: '/docs/agent-investigations/auggie' },
            { text: 'Claude Code', link: '/docs/agent-investigations/claude-code' },
            { text: 'Cline', link: '/docs/agent-investigations/cline' },
            { text: 'Codex', link: '/docs/agent-investigations/codex' },
            { text: 'Cursor Agent', link: '/docs/agent-investigations/cursor-agent' },
            { text: 'Droid (Factory CLI)', link: '/docs/agent-investigations/droid' },
            { text: 'Gemini CLI', link: '/docs/agent-investigations/gemini-cli' },
            { text: 'Goose', link: '/docs/agent-investigations/goose' },
            { text: 'Kilo Code', link: '/docs/agent-investigations/kilo-code' },
            { text: 'OpenCode', link: '/docs/agent-investigations/opencode' },
            { text: 'Pi', link: '/docs/agent-investigations/pi' },
          ],
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/eugene1g/agent-safehouse' },
    ],

    footer: {
      message: 'Open source under the Apache 2.0 License.',
      copyright: 'Agent Safehouse',
    },
  },
})
