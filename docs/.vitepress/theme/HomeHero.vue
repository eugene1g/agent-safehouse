<template>
  <div class="hero-custom">
    <div class="hero-grid-bg"></div>
    <div class="hero-container">

      <!-- Row 1: headline + badges -->
      <div class="headline-row">
        <div class="headline-group">
          <h1 class="headline">Native macOS sandboxing for Agents</h1>
          <p class="desc"><code class="code-amber">sandbox-exec</code> policies for coding agents — deny-first, composable, thoroughly tested.</p>
        </div>
        <div class="badges">
          <span class="badge"><span class="badge-check"><svg viewBox="0 0 12 12"><polyline points="2.5 6 5 8.5 9.5 3.5" fill="none" stroke="#4ade80" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg></span>Pure Bash</span>
          <span class="badge"><span class="badge-check"><svg viewBox="0 0 12 12"><polyline points="2.5 6 5 8.5 9.5 3.5" fill="none" stroke="#4ade80" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg></span>Zero dependencies</span>
          <span class="badge"><span class="badge-check"><svg viewBox="0 0 12 12"><polyline points="2.5 6 5 8.5 9.5 3.5" fill="none" stroke="#4ade80" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg></span>Open source</span>
        </div>
      </div>

      <!-- Row 2: safety points + danger box -->
      <div class="split">
        <div class="split-left">
          <h2 class="tagline">Live <span class="word-dangerous">dangerously</span>, but do it <em class="word-safely">safely.</em></h2>
          <div class="safety-points">
            <div class="sp"><span class="sp-icon deny">✕</span><span><code class="code-red">rm -rf /</code> goes nowhere</span></div>
            <div class="sp"><span class="sp-icon allow">✓</span><span><strong>No full read access</strong> — only what the agent needs</span></div>
            <div class="sp"><span class="sp-icon allow">✓</span><span><code class="code-amber-sm">Write access</code> via explicit allow-list only</span></div>
            <div class="sp"><span class="sp-icon allow">✓</span><span>Sane, dev-friendly defaults</span></div>
            <div class="sp"><span class="sp-icon allow">✓</span><span>Fully customizable for your setup</span></div>
          </div>
        </div>
        <div class="split-right">
          <div class="danger-box">
            <div class="danger-label">Every agent ships the same escape hatch</div>
            <div class="danger-flag"><span class="prompt">$</span> claude <span class="flag">--dangerously-skip-permissions</span></div>
            <div class="danger-flag"><span class="prompt">$</span> codex <span class="flag">--dangerously-bypass-approvals-and-sandbox</span></div>
            <div class="danger-flag"><span class="prompt">$</span> amp <span class="flag">--dangerously-allow-all</span></div>
          </div>
        </div>
      </div>

    </div>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&display=swap');

.hero-custom {
  position: relative;
  padding: 88px 0 72px;
  overflow: hidden;
}

/* Radial glow */
.hero-custom::before {
  content: '';
  position: absolute;
  top: -200px;
  right: -200px;
  width: 600px;
  height: 600px;
  background: radial-gradient(circle, rgba(212, 160, 23, 0.06) 0%, transparent 70%);
  pointer-events: none;
}

/* Bottom divider */
.hero-custom::after {
  content: '';
  position: absolute;
  bottom: 0; left: 0; right: 0;
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--vp-c-border), transparent);
}

/* Grid lines behind hero */
.hero-grid-bg {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(var(--vp-c-border) 1px, transparent 1px),
    linear-gradient(90deg, var(--vp-c-border) 1px, transparent 1px);
  background-size: 80px 80px;
  opacity: 0.15;
  mask-image: radial-gradient(ellipse 80% 60% at 50% 40%, black 20%, transparent 70%);
  -webkit-mask-image: radial-gradient(ellipse 80% 60% at 50% 40%, black 20%, transparent 70%);
  pointer-events: none;
}

.hero-container {
  position: relative;
  z-index: 1;
  max-width: 1040px;
  margin: 0 auto;
  padding: 0 28px;
}

/* ---- Row 1: Headline + badges ---- */
.headline-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 32px;
  margin-bottom: 56px;
}

.headline-group {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.headline {
  font-family: 'DM Serif Display', Georgia, 'Times New Roman', serif;
  font-size: 3rem;
  font-weight: 400;
  line-height: 1.1;
  letter-spacing: -1.5px;
  color: var(--vp-c-text-1);
  white-space: nowrap;
}

.desc {
  font-size: 1.06rem;
  color: var(--vp-c-text-2);
  line-height: 1.6;
}

.code-amber {
  font-family: var(--vp-font-family-mono);
  font-size: 0.875rem;
  color: #d4a017;
  background: rgba(212, 160, 23, 0.08);
  padding: 2px 7px;
  border-radius: 4px;
  border: 1px solid rgba(212, 160, 23, 0.12);
}

.badges {
  display: flex;
  flex-direction: column;
  gap: 6px;
  flex-shrink: 0;
}

.badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-family: var(--vp-font-family-mono);
  font-size: 0.688rem;
  font-weight: 500;
  letter-spacing: 0.5px;
  padding: 5px 12px;
  border-radius: 4px;
  border: 1px solid var(--vp-c-border);
  color: var(--vp-c-text-2);
}

.badge-check {
  width: 14px;
  height: 14px;
  border-radius: 3px;
  border: 1.5px solid #22c55e;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.badge-check svg {
  width: 9px;
  height: 9px;
}

/* ---- Row 2: Split ---- */
.split {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 40px;
  align-items: center;
}

.tagline {
  font-family: 'DM Serif Display', Georgia, 'Times New Roman', serif;
  font-size: 1.875rem;
  font-weight: 400;
  line-height: 1.15;
  letter-spacing: -0.5px;
  color: var(--vp-c-text-1);
  margin-bottom: 18px;
  white-space: nowrap;
}

.word-dangerous { color: #ef5350; }
.word-safely { font-style: italic; color: #4ade80; font-size: 1.12em; }

.safety-points { display: flex; flex-direction: column; gap: 8px; }

.sp {
  display: flex;
  align-items: baseline;
  gap: 8px;
  font-size: 0.94rem;
  color: var(--vp-c-text-1);
  line-height: 1.5;
}
.sp strong { color: var(--vp-c-text-1); font-weight: 600; }

.sp-icon {
  flex-shrink: 0;
  font-weight: 700;
  font-size: 0.78rem;
  width: 18px;
  text-align: center;
}
.sp-icon.allow { color: #4ade80; }
.sp-icon.deny { color: #ef5350; }

.code-red {
  font-family: var(--vp-font-family-mono);
  font-size: 0.75rem;
  color: #ef5350;
  background: rgba(239, 83, 80, 0.06);
  padding: 2px 7px;
  border-radius: 4px;
  border: 1px solid rgba(239, 83, 80, 0.12);
}

.code-amber-sm {
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  color: #d4a017;
  background: rgba(212, 160, 23, 0.08);
  padding: 2px 7px;
  border-radius: 4px;
  border: 1px solid rgba(212, 160, 23, 0.15);
}

/* Danger box */
.danger-box {
  background: var(--vp-c-bg-alt);
  border: 1px solid var(--vp-c-border);
  border-radius: 10px;
  padding: 20px;
  border-top: 3px solid #ef5350;
}

.danger-label {
  font-family: var(--vp-font-family-mono);
  font-size: 0.563rem;
  font-weight: 600;
  letter-spacing: 1.5px;
  text-transform: uppercase;
  color: var(--vp-c-text-2);
  margin-bottom: 12px;
}

.danger-flag {
  font-family: var(--vp-font-family-mono);
  font-size: 0.78rem;
  color: var(--vp-c-text-2);
  padding: 7px 12px;
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-border);
  border-radius: 6px;
  white-space: nowrap;
  overflow-x: auto;
  margin-bottom: 5px;
}
.danger-flag:last-child { margin-bottom: 0; }

.prompt { color: var(--vp-c-text-2); margin-right: 8px; opacity: 0.4; }
.flag { color: #ef5350; }

/* ---- Responsive ---- */
@media (max-width: 768px) {
  .hero-custom { padding: 48px 0 40px; }
  .headline-row {
    flex-direction: column;
    gap: 14px;
    margin-bottom: 3rem;
  }
  .badges { flex-direction: row; flex-wrap: wrap; gap: 6px; }
  .headline { font-size: 1.875rem; letter-spacing: -0.5px; white-space: normal; }
  .split { grid-template-columns: 1fr; gap: 24px; }
  .tagline { font-size: 1.625rem; white-space: normal; }
  .danger-flag { font-size: 0.688rem; padding: 6px 10px; }
}

@media (max-width: 380px) {
  .headline { font-size: 1.625rem; }
  .tagline { font-size: 1.5rem; }
  .badge { font-size: 0.625rem; padding: 4px 8px; }
}
</style>
