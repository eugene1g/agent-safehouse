import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import HomeHero from './HomeHero.vue'
import HomeContent from './HomeContent.vue'
import { h } from 'vue'
import './style.css'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'home-hero-info': () => h(HomeHero),
      'home-features-after': () => h(HomeContent),
    })
  },
} satisfies Theme
