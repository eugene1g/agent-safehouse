<template>
  <div class="hero-custom">
    <div class="hero-grid-bg"></div>
    <div class="hero-container">

      <!-- Row 1: headline + badges -->
      <div class="headline-row">
        <div class="headline-group">
          <h1 class="headline">Go full <code class="code-yolo">--yolo</code>. We've got you.</h1>
          <p class="desc">macOS-native sandboxing for local agents. Move fast, break nothing.</p>
        </div>
        <!-- badges hidden for now -->
      </div>


    </div>
  </div>
</template>

<style scoped>
@import url('https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&display=swap');

.hero-custom {
  position: relative;
  padding: 72px 0 40px;
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
  max-width: var(--safehouse-page-max-width);
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
  font-size: 1.25rem;
  font-weight: 500;
  color: var(--vp-c-text-1);
  line-height: 1.5;
  letter-spacing: -0.3px;
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

.code-yolo {
  font-family: var(--vp-font-family-mono);
  font-size: 0.65em;
  color: #ef5350;
  background: rgba(239, 83, 80, 0.08);
  padding: 4px 10px;
  border-radius: 5px;
  border: 1px solid rgba(239, 83, 80, 0.18);
  letter-spacing: 0;
}

.desc-sub {
  font-size: 1.1rem;
  font-style: italic;
  color: var(--vp-c-text-2);
  margin-top: 4px;
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
