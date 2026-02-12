<script setup lang="ts">
const agents = [
  { name: 'Claude Code', logo: 'https://github.com/anthropics.png?size=256', link: '/agent-investigations/claude-code' },
  { name: 'Codex', logo: 'https://github.com/openai.png?size=256', link: '/agent-investigations/codex' },
  { name: 'OpenCode', logo: 'https://github.com/opencode-ai.png?size=256', link: '/agent-investigations/opencode' },
  { name: 'Amp', logo: 'https://github.com/ampcode-com.png?size=256', link: '' },
  { name: 'Gemini CLI', logo: 'https://geminicli.com/icon.png', link: '/agent-investigations/gemini-cli' },
  { name: 'Aider', logo: 'https://github.com/Aider-AI.png?size=256', link: '/agent-investigations/aider' },
  { name: 'Goose', logo: 'https://block.github.io/goose/img/logo_dark.png', link: '/agent-investigations/goose' },
  { name: 'Auggie', logo: 'https://www.augmentcode.com/favicon.svg', link: '/agent-investigations/auggie' },
  { name: 'Pi', logo: 'https://pi.dev/logo.svg', link: '/agent-investigations/pi' },
  { name: 'Cursor Agent', logo: 'https://github.com/cursor.png?size=256', link: '/agent-investigations/cursor-agent' },
  { name: 'Cline', logo: 'https://github.com/cline.png?size=256', link: '/agent-investigations/cline' },
  { name: 'Kilo Code', logo: 'https://raw.githubusercontent.com/Kilo-Org/kilocode/main/src/assets/icons/kilo-dark.png', link: '/agent-investigations/kilo-code' },
  { name: 'Droid', logo: 'https://github.com/Factory-AI.png?size=256', link: '/agent-investigations/droid' },
]

const withoutRows = [
  { path: '~/', tag: 'full access', cls: 'rw' },
  { path: '~/.ssh/id_ed25519', tag: 'full access', cls: 'rw' },
  { path: '~/.aws/credentials', tag: 'full access', cls: 'rw' },
  { path: '~/other-repos/', tag: 'full access', cls: 'rw' },
  { path: '~/Documents/', tag: 'full access', cls: 'rw' },
]

const withRows = [
  { path: '~/my-project/', tag: 'read/write', cls: 'rw-safe' },
  { path: '~/shared-lib/', tag: 'read-only', cls: 'ro' },
  { path: '~/.ssh/id_ed25519', tag: 'denied', cls: 'denied' },
  { path: '~/.aws/credentials', tag: 'denied', cls: 'denied' },
  { path: '~/other-repos/', tag: 'denied', cls: 'denied' },
]
</script>

<template>
  <!-- Agents grid -->
  <section class="home-section">
    <div class="home-container">
      <h2 class="section-title">
        Successfully contained <span class="struck">agents</span> <span class="scribble">clunkers</span>
      </h2>
      <p class="section-sub">All major agents work perfectly inside Safehouse. They just can't touch anything outside it.</p>
      <div class="agents-grid">
        <a
          v-for="agent in agents"
          :key="agent.name"
          :href="agent.link || undefined"
          class="agent-card"
          :class="{ 'no-link': !agent.link }"
        >
          <img :src="agent.logo" :alt="agent.name" loading="lazy" />
          <span class="agent-name">{{ agent.name }}</span>
        </a>
        <div class="agent-card agent-placeholder">
          <div class="plus-icon">+</div>
          <span class="agent-name">yours</span>
        </div>
      </div>
    </div>
  </section>

  <!-- Without / With comparison -->
  <section class="home-section">
    <div class="home-container">
      <div class="value-banner">
        <h2 class="banner-title"><span class="c-red">No</span> read access to your entire home. <span class="c-green">Only</span> what the agent needs.</h2>
        <p class="banner-sub">Agents inherit your full user permissions. Safehouse flips this to deny-first — nothing is readable unless explicitly granted.</p>
        <div class="access-compare">
          <div class="access-box without">
            <h4>Without Safehouse</h4>
            <ul>
              <li v-for="r in withoutRows" :key="r.path">
                <span class="path-name">{{ r.path }}</span>
                <span class="access-tag" :class="r.cls">{{ r.tag }}</span>
              </li>
            </ul>
          </div>
          <div class="access-box with-sh">
            <h4>With Safehouse</h4>
            <ul>
              <li v-for="r in withRows" :key="r.path">
                <span class="path-name">{{ r.path }}</span>
                <span class="access-tag" :class="r.cls">{{ r.tag }}</span>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- Getting started -->
  <section class="home-section">
    <div class="home-container">
      <h2 class="section-title">Getting started</h2>
      <p class="section-sub">Download a single shell script, make it executable, and run your agent inside it. No build step, no dependencies — just Bash and macOS.</p>
      <div class="code-block"><pre><code><span class="c"># 1. Download safehouse (single self-contained script)</span>
<span class="k">mkdir</span> <span class="f">-p</span> <span class="s">~/.local/bin</span>
<span class="k">curl</span> <span class="f">-fsSL</span> <span class="s">https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/safehouse.sh</span> \
  <span class="f">-o</span> <span class="s">~/.local/bin/safehouse</span>
<span class="k">chmod</span> <span class="f">+x</span> <span class="s">~/.local/bin/safehouse</span>

<span class="c"># 2. Run any agent inside Safehouse</span>
<span class="k">cd</span> ~/projects/my-app
<span class="k">safehouse</span> claude <span class="f">--dangerously-skip-permissions</span></code></pre></div>
      <p class="muted-text">Safehouse automatically grants read/write access to the selected workdir (git root by default) and read access to your installed toolchains. Most of your home directory — SSH keys, other repos, personal files — is denied by the kernel.</p>

      <h3 class="subsection-title">See it fail — proof the sandbox works</h3>
      <p class="muted-text" style="margin-bottom: 16px;">Try reading something sensitive inside safehouse. The kernel blocks it before the process ever sees the data.</p>
      <div class="code-block"><pre><code><span class="c"># Try to read your SSH private key — denied by the kernel</span>
<span class="k">safehouse</span> cat ~/.ssh/id_ed25519
<span class="c"># cat: /Users/you/.ssh/id_ed25519: Operation not permitted</span>

<span class="c"># Try to list another repo — invisible</span>
<span class="k">safehouse</span> ls ~/other-project
<span class="c"># ls: /Users/you/other-project: Operation not permitted</span>

<span class="c"># But your current project works fine</span>
<span class="k">safehouse</span> ls .
<span class="c"># README.md  src/  package.json  ...</span></code></pre></div>
    </div>
  </section>

  <!-- Shell functions -->
  <section class="home-section">
    <div class="home-container">
      <h2 class="section-title">Safe by default with shell functions</h2>
      <p class="section-sub">Add these to your shell config and every agent runs inside Safehouse automatically — you don't have to remember. To run without the sandbox, use <code>command claude</code> to bypass the function.</p>
      <div class="code-block"><pre><code><span class="c"># ~/.zshrc or ~/.bashrc</span>
<span class="k">safe</span>() { safehouse <span class="f">--add-dirs-ro=</span><span class="s">~/mywork</span> <span class="s">"$@"</span>; }

<span class="c"># Sandboxed — the default. Just type the command name.</span>
<span class="k">claude</span>()   { <span class="k">safe</span> claude <span class="f">--dangerously-skip-permissions</span> <span class="s">"$@"</span>; }
<span class="k">codex</span>()    { <span class="k">safe</span> codex <span class="f">--dangerously-bypass-approvals-and-sandbox</span> <span class="s">"$@"</span>; }
<span class="k">amp</span>()      { <span class="k">safe</span> amp <span class="f">--dangerously-allow-all</span> <span class="s">"$@"</span>; }
<span class="k">gemini</span>()   { NO_BROWSER=true <span class="k">safe</span> gemini <span class="f">--yolo</span> <span class="s">"$@"</span>; }

<span class="c"># Unsandboxed — bypass the function with `command`</span>
<span class="c"># command claude               — plain interactive session</span></code></pre></div>
    </div>
  </section>
</template>

<style scoped>
/* ---- Layout ---- */
.home-section {
  padding: 64px 0;
  position: relative;
}
.home-section::before {
  content: '';
  position: absolute;
  top: 0; left: 0; right: 0;
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--vp-c-border), transparent);
}
.home-container {
  max-width: 1040px;
  margin: 0 auto;
  padding: 0 24px;
}

/* ---- Section typography ---- */
.section-title {
  font-size: 2.2rem;
  font-weight: 700;
  color: var(--vp-c-text-1);
  margin-bottom: 12px;
  letter-spacing: -0.5px;
  line-height: 1.15;
}
.section-sub {
  color: var(--vp-c-text-2);
  font-size: 1.05rem;
  margin-bottom: 40px;
  line-height: 1.7;
  max-width: 720px;
}
.section-sub code {
  font-family: var(--vp-font-family-mono);
  font-size: 0.84rem;
  color: var(--vp-c-text-2);
  background: rgba(255,255,255,0.04);
  padding: 2px 7px;
  border-radius: 4px;
  border: 1px solid var(--vp-c-border);
}
.subsection-title {
  margin-top: 40px;
  margin-bottom: 8px;
  font-size: 1rem;
  font-weight: 600;
  color: var(--vp-c-text-1);
}
.muted-text {
  color: var(--vp-c-text-2);
  font-size: 0.94rem;
  line-height: 1.7;
  margin-top: 16px;
}

/* ---- Struck / Scribble ---- */
.struck {
  text-decoration: line-through;
  text-decoration-color: #ef5350;
  text-decoration-thickness: 3px;
  opacity: 0.5;
}
.scribble {
  display: inline-block;
  position: relative;
  font-family: 'Marker Felt', 'Comic Sans MS', cursive;
  color: #4ade80;
  transform: rotate(-2deg);
  margin-left: 6px;
  font-style: italic;
}

/* ---- Agents grid ---- */
.agents-grid {
  display: grid;
  grid-template-columns: repeat(7, 72px);
  justify-content: space-between;
  gap: 32px 0;
}
.agent-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  text-decoration: none;
  transition: transform 0.2s;
}
.agent-card:hover { transform: translateY(-3px); }
.agent-card.no-link { cursor: default; }
.agent-card.no-link:hover { transform: none; }
.agent-card img {
  width: 72px;
  height: 72px;
  border-radius: 16px;
  background: var(--vp-c-bg-alt);
  flex-shrink: 0;
}
.agent-name {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--vp-c-text-2);
  text-align: center;
  white-space: nowrap;
  transition: color 0.2s;
}
.agent-card:hover .agent-name { color: var(--vp-c-text-1); }
.agent-placeholder {
  cursor: default;
}
.agent-placeholder:hover { transform: none; }
.plus-icon {
  width: 72px;
  height: 72px;
  border-radius: 16px;
  border: 2px dashed rgba(255,255,255,0.15);
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgba(255,255,255,0.25);
  font-size: 1.5rem;
  font-weight: 300;
}

/* ---- Value banner / comparison ---- */
.value-banner {
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-border);
  border-radius: 16px;
  padding: 48px;
  position: relative;
  overflow: hidden;
}
.value-banner::before {
  content: '';
  position: absolute;
  top: 0; left: 0; right: 0;
  height: 3px;
  background: linear-gradient(90deg, #c62828, #d4a017, #22c55e);
}
.banner-title {
  font-size: 2rem;
  font-weight: 700;
  line-height: 1.25;
  margin-bottom: 14px;
  color: var(--vp-c-text-1);
}
.c-red { color: #ef5350; }
.c-green { color: #4ade80; }
.banner-sub {
  color: var(--vp-c-text-2);
  font-size: 1rem;
  max-width: 580px;
  margin-bottom: 36px;
  line-height: 1.7;
}
.access-compare {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}
.access-box {
  border-radius: 10px;
  padding: 24px;
  border: 1px solid var(--vp-c-border);
}
.access-box.without {
  background: rgba(239, 83, 80, 0.06);
  border-color: rgba(239, 83, 80, 0.15);
}
.access-box.with-sh {
  background: rgba(74, 222, 128, 0.06);
  border-color: rgba(74, 222, 128, 0.15);
}
.access-box h4 {
  font-family: var(--vp-font-family-mono);
  font-size: 0.625rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 2px;
  margin-bottom: 16px;
}
.access-box.without h4 { color: #ef5350; }
.access-box.with-sh h4 { color: #4ade80; }
.access-box ul { list-style: none; padding: 0; margin: 0; }
.access-box li {
  padding: 5px 0;
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  color: var(--vp-c-text-2);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.path-name { min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.access-tag {
  font-family: var(--vp-font-family-mono);
  font-size: 0.56rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 1px;
  padding: 2px 8px;
  border-radius: 3px;
  white-space: nowrap;
  flex-shrink: 0;
}
.access-tag.rw { background: rgba(239, 83, 80, 0.1); color: #ef5350; border: 1px solid rgba(239, 83, 80, 0.15); }
.access-tag.rw-safe { background: rgba(74, 222, 128, 0.1); color: #4ade80; border: 1px solid rgba(74, 222, 128, 0.15); }
.access-tag.ro { background: rgba(212, 160, 23, 0.08); color: #d4a017; border: 1px solid rgba(212, 160, 23, 0.15); }
.access-tag.denied { background: rgba(239, 83, 80, 0.1); color: #ef5350; border: 1px solid rgba(239, 83, 80, 0.15); }

/* ---- Code blocks ---- */
.code-block pre {
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-border);
  border-radius: 10px;
  padding: 18px 22px;
  overflow-x: auto;
  font-size: 0.81rem;
  line-height: 1.8;
  margin: 0;
}
.code-block code {
  font-family: var(--vp-font-family-mono);
}
.code-block .c { color: var(--vp-c-text-2); }
.code-block .k { color: #4ade80; }
.code-block .f { color: #d4a017; }
.code-block .s { color: #a78bfa; }

/* ---- Responsive ---- */
@media (max-width: 768px) {
  .agents-grid { grid-template-columns: repeat(4, 72px); justify-content: space-around; }
  .access-compare { grid-template-columns: 1fr; }
  .value-banner { padding: 28px; }
  .banner-title { font-size: 1.4rem; }
  .section-title { font-size: 1.75rem; }
}

@media (max-width: 480px) {
  .agents-grid { grid-template-columns: repeat(3, 72px); }
  .danger-flag { font-size: 0.68rem; padding: 6px 10px; }
}
</style>
