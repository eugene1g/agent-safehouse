<script setup lang="ts">
import { onMounted } from 'vue'

onMounted(() => {
  // Original vanilla JS from policy-builder.html — runs after DOM is ready.
  // Uses document.getElementById() throughout, which works fine post-mount.
  ;(function () {
    var HOME_TOKEN = '__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__'
    var BASES = ['https://raw.githubusercontent.com/eugene1g/agent-safehouse/main', '..', '.']

    var BASE_MODULES = ['profiles/00-base.sb', 'profiles/10-system-runtime.sb', 'profiles/20-network.sb']
    var SHARED_MODULES = ['profiles/40-shared/agent-common.sb']
    var CORE_INTEGRATION_MODULES = [
      'profiles/50-integrations-core/container-runtime-default-deny.sb',
      'profiles/50-integrations-core/git.sb',
      'profiles/50-integrations-core/scm-clis.sb',
    ]
    var OPTIONAL_INTEGRATION_MODULES = [
      'profiles/55-integrations-optional/1password.sb',
      'profiles/55-integrations-optional/browser-native-messaging.sb',
      'profiles/55-integrations-optional/cleanshot.sb',
      'profiles/55-integrations-optional/clipboard.sb',
      'profiles/55-integrations-optional/cloud-credentials.sb',
      'profiles/55-integrations-optional/docker.sb',
      'profiles/55-integrations-optional/electron.sb',
      'profiles/55-integrations-optional/keychain.sb',
      'profiles/55-integrations-optional/kubectl.sb',
      'profiles/55-integrations-optional/macos-gui.sb',
      'profiles/55-integrations-optional/shell-init.sb',
      'profiles/55-integrations-optional/spotlight.sb',
      'profiles/55-integrations-optional/ssh.sb',
    ]
    var OPTIONAL_INTEGRATION_BY_TOKEN: Record<string, string> = {}
    OPTIONAL_INTEGRATION_MODULES.forEach(function (p) {
      OPTIONAL_INTEGRATION_BY_TOKEN[p.toLowerCase()] = p
    })

    var AGENTS = [
      { key: 'claude-code', label: 'Claude Code', profile: 'claude-code.sb', command: 'claude --dangerously-skip-permissions', logo: 'https://github.com/anthropics.png?size=256', on: true },
      { key: 'codex', label: 'Codex', profile: 'codex.sb', command: 'codex --dangerously-bypass-approvals-and-sandbox', logo: 'https://github.com/openai.png?size=256', on: true },
      { key: 'opencode', label: 'OpenCode', profile: 'opencode.sb', command: 'OPENCODE_PERMISSION=\'{"*":"allow"}\' opencode', logo: 'https://github.com/opencode-ai.png?size=256', on: true },
      { key: 'amp', label: 'Amp', profile: 'amp.sb', command: 'amp --dangerously-allow-all', logo: 'https://github.com/ampcode-com.png?size=256', on: false },
      { key: 'gemini', label: 'Gemini CLI', profile: 'gemini.sb', command: 'NO_BROWSER=true gemini --yolo', logo: 'https://geminicli.com/icon.png', on: false },
      { key: 'aider', label: 'Aider', profile: 'aider.sb', command: 'aider', logo: 'https://github.com/Aider-AI.png?size=256', on: false },
      { key: 'goose', label: 'Goose', profile: 'goose.sb', command: 'goose', logo: 'https://block.github.io/goose/img/logo_dark.png', on: false },
      { key: 'auggie', label: 'Auggie', profile: 'auggie.sb', command: 'auggie', logo: 'https://www.augmentcode.com/favicon.svg', on: false },
      { key: 'pi', label: 'Pi', profile: 'pi.sb', command: 'pi', logo: 'https://pi.dev/logo.svg', on: false },
      { key: 'cursor-agent', label: 'Cursor Agent', profile: 'cursor-agent.sb', command: 'cursor-agent', logo: 'https://github.com/cursor.png?size=256', on: false },
      { key: 'cline', label: 'Cline', profile: 'cline.sb', command: 'cline', logo: 'https://github.com/cline.png?size=256', on: false },
      { key: 'kilo-code', label: 'Kilo Code', profile: 'kilo-code.sb', command: 'kilo', logo: 'https://raw.githubusercontent.com/Kilo-Org/kilocode/main/src/assets/icons/kilo-dark.png', on: false },
      { key: 'droid', label: 'Droid', profile: 'droid.sb', command: 'droid', logo: 'https://github.com/Factory-AI.png?size=256', on: false },
    ]

    var TOOLCHAINS = [
      { key: 'bun', label: 'Bun', profile: 'bun.sb', logo: 'https://bun.sh/logo.svg', on: true },
      { key: 'deno', label: 'Deno', profile: 'deno.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/denojs/denojs-original.svg', on: true },
      { key: 'go', label: 'Go', profile: 'go.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/go/go-original.svg', on: true },
      { key: 'node', label: 'Node.js', profile: 'node.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/nodejs/nodejs-original.svg', on: true },
      { key: 'python', label: 'Python', profile: 'python.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/python/python-original.svg', on: true },
      { key: 'ruby', label: 'Ruby', profile: 'ruby.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/ruby/ruby-original.svg', on: true },
      { key: 'runtime-managers', label: 'Runtime managers', profile: 'runtime-managers.sb', logo: 'https://github.com/asdf-vm.png?size=96', on: true },
      { key: 'rust', label: 'Rust', profile: 'rust.sb', logo: 'https://cdn.simpleicons.org/rust/F74C00', on: true },
      { key: 'java', label: 'Java', profile: 'java.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/java/java-original.svg', on: false },
      { key: 'perl', label: 'Perl', profile: 'perl.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/perl/perl-original.svg', on: false },
      { key: 'php', label: 'PHP', profile: 'php.sb', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/php/php-original.svg', on: false },
    ]

    var INTEGRATIONS = [
      { key: 'container-runtime-default-deny', label: 'Container runtime deny', path: 'profiles/50-integrations-core/container-runtime-default-deny.sb', group: 'default', glyph: '\u26D4', on: true, locked: true },
      { key: 'git', label: 'Git', path: 'profiles/50-integrations-core/git.sb', group: 'default', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/git/git-original.svg', on: true, locked: true },
      { key: 'scm-clis', label: 'SCM CLIs', path: 'profiles/50-integrations-core/scm-clis.sb', group: 'default', logo: 'https://github.com/github.png?size=96', on: true, locked: true },
      { key: '1password', label: '1Password', path: 'profiles/55-integrations-optional/1password.sb', group: 'extra', feature: '1password', logo: 'https://github.com/1Password.png?size=96', on: false },
      { key: 'browser-native-messaging', label: 'Browser native messaging', path: 'profiles/55-integrations-optional/browser-native-messaging.sb', group: 'extra', feature: 'browser-native-messaging', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/chrome/chrome-original.svg', on: false },
      { key: 'cleanshot', label: 'CleanShot', path: 'profiles/55-integrations-optional/cleanshot.sb', group: 'extra', feature: 'cleanshot', glyph: '\uD83D\uDCF8', on: false },
      { key: 'clipboard', label: 'Clipboard', path: 'profiles/55-integrations-optional/clipboard.sb', group: 'extra', feature: 'clipboard', glyph: '\uD83D\uDCCB', on: false },
      { key: 'cloud-credentials', label: 'Cloud credentials', path: 'profiles/55-integrations-optional/cloud-credentials.sb', group: 'extra', feature: 'cloud-credentials', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/amazonwebservices/amazonwebservices-original-wordmark.svg', on: false },
      { key: 'docker', label: 'Docker', path: 'profiles/55-integrations-optional/docker.sb', group: 'extra', feature: 'docker', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/docker/docker-original.svg', on: false },
      { key: 'electron', label: 'Electron', path: 'profiles/55-integrations-optional/electron.sb', group: 'extra', feature: 'electron', logo: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/electron/electron-original.svg', on: false },
      { key: 'env', label: 'Runtime env pass-through', group: 'extra', feature: 'env', glyph: '\uD83D\uDD13', on: false, desc: 'Use safehouse --env for command execution (runtime-only; no SB policy changes).' },
      { key: 'kubectl', label: 'kubectl', path: 'profiles/55-integrations-optional/kubectl.sb', group: 'extra', feature: 'kubectl', glyph: '\u2638', on: false },
      { key: 'macos-gui', label: 'macOS GUI', path: 'profiles/55-integrations-optional/macos-gui.sb', group: 'extra', feature: 'macosGui', glyph: '\uF8FF', on: false },
      { key: 'shell-init', label: 'Shell init files', path: 'profiles/55-integrations-optional/shell-init.sb', group: 'extra', feature: 'shellStartup', glyph: '\uD83D\uDDC2', on: false, desc: 'Allow reading ~/.zsh* and /private/etc shell startup files.' },
      { key: 'spotlight', label: 'Spotlight', path: 'profiles/55-integrations-optional/spotlight.sb', group: 'extra', feature: 'spotlight', glyph: '\uD83D\uDD0E', on: false },
      { key: 'ssh', label: 'SSH', path: 'profiles/55-integrations-optional/ssh.sb', group: 'extra', feature: 'ssh', glyph: '>_', on: false },
      { key: 'wide-read', label: 'Access entire file system (read-only)', group: 'extra', feature: 'wideRead', glyph: '\uD83D\uDC41', on: false },
    ] as any[]

    var ORD = {
      toolchains: TOOLCHAINS.map(function (x) { return x.profile }).slice().sort(),
      agents: AGENTS.map(function (x) { return x.profile }).slice().sort(),
      optionalIntegrations: OPTIONAL_INTEGRATION_MODULES.slice(),
    }

    var cache: Record<string, string> = {}
    var resolvedBase: string | null = null
    var lastPolicy = ''
    var stepNodes: HTMLElement[] = []
    var openStepByIndex: ((idx: number, scroll?: boolean) => void) | null = null
    var confirmedSteps: Record<number, boolean> = {}

    var el = {
      agentsGrid: document.getElementById('pb-agents-grid')!,
      toolchainsGrid: document.getElementById('pb-toolchains-grid')!,
      integrationsDefaultGrid: document.getElementById('pb-integrations-default-grid')!,
      integrationsExtraGrid: document.getElementById('pb-integrations-extra-grid')!,
      home: document.getElementById('pb-home-dir') as HTMLInputElement,
      homeFeedback: document.getElementById('pb-home-feedback')!,
      workdir: document.getElementById('pb-workdir') as HTMLInputElement,
      workdirFeedback: document.getElementById('pb-workdir-feedback')!,
      ro: document.getElementById('pb-add-ro') as HTMLTextAreaElement,
      roFeedback: document.getElementById('pb-ro-feedback')!,
      rw: document.getElementById('pb-add-rw') as HTMLTextAreaElement,
      rwFeedback: document.getElementById('pb-rw-feedback')!,
      append: document.getElementById('pb-append-profile') as HTMLTextAreaElement,
      appendFeedback: document.getElementById('pb-append-feedback')!,
      summaryAgents: document.getElementById('pb-summary-agents')!,
      summaryIntegrations: document.getElementById('pb-summary-integrations')!,
      summaryPaths: document.getElementById('pb-summary-paths')!,
      summaryIssues: document.getElementById('pb-summary-issues')!,
      summaryCommand: document.getElementById('pb-summary-command')!,
      status: document.getElementById('pb-status')!,
      moduleCount: document.getElementById('pb-module-count')!,
      command: document.getElementById('pb-command-output')!,
      policy: document.getElementById('pb-policy-output')!,
      gen: document.getElementById('pb-generate') as HTMLButtonElement,
      copy: document.getElementById('pb-copy') as HTMLButtonElement,
      dl: document.getElementById('pb-download') as HTMLButtonElement,
      launchers: document.getElementById('pb-download-launchers') as HTMLButtonElement,
    }

    function setStatus(msg: string, cls?: string) {
      el.status.textContent = msg || ''
      el.status.classList.remove('success', 'error')
      if (cls) el.status.classList.add(cls)
    }

    function uniq(arr: string[]) {
      var seen: Record<string, boolean> = {}
      var out: string[] = []
      arr.forEach(function (v) { if (!seen[v]) { seen[v] = true; out.push(v) } })
      return out
    }

    function esc(v: string) { return String(v || '').replace(/\\/g, '\\\\').replace(/"/g, '\\"') }

    function norm(raw: string, home: string) {
      var p = String(raw || '').trim()
      if (!p) return ''
      if (p === '~') p = home
      else if (p.indexOf('~/') === 0) p = home + p.slice(1)
      p = p.replace(/\/{2,}/g, '/')
      if (p.length > 1 && p.slice(-1) === '/') p = p.slice(0, -1)
      return p
    }

    function assertAbs(p: string, label: string) { if (p && p.charAt(0) !== '/') throw new Error(label + ' must be absolute: ' + p) }

    function parseListDetailed(raw: string, home: string, label: string) {
      var out: string[] = []
      var errors: string[] = []
      var normalized: string[] = []
      var seen: Record<string, boolean> = {}
      var duplicateCount = 0
      String(raw || '').split(/\r?\n/).forEach(function (line, idx) {
        var t = line.trim()
        if (!t || t.indexOf('#') === 0 || t.indexOf(';') === 0) return
        var p = norm(t, home)
        if (!p) return
        if (p.charAt(0) !== '/') {
          errors.push(label + ' line ' + String(idx + 1) + ' must be absolute: ' + t)
          return
        }
        if (seen[p]) { duplicateCount += 1; return }
        seen[p] = true
        if (p !== t && normalized.length < 2) normalized.push(t + ' -> ' + p)
        out.push(p)
      })
      return { values: out, errors: errors, normalized: normalized, duplicateCount: duplicateCount }
    }

    function parseList(raw: string, home: string, label: string) {
      var details = parseListDetailed(raw, home, label)
      if (details.errors.length) throw new Error(details.errors[0])
      return details.values
    }

    function emitAnc(path: string, label: string) {
      var l = [
        ';; Generated ancestor directory literals for ' + label + ': ' + path, ';;',
        ';; Why file-read* (not file-read-metadata) with literal (not subpath):',
        ';; Agents (notably Claude Code) call readdir() on every ancestor of the working',
        ';; directory during startup. If only file-read-metadata (stat) is granted, the',
        ';; agent cannot list directory contents, which causes it to blank PATH and break.',
        ';; Using literal (not subpath) keeps this safe: it grants read access to the',
        ';; directory entry itself, but does NOT grant recursive read access below it.',
        '(allow file-read*', '    (literal "/")',
      ]
      var t = path.replace(/^\/+/, ''); var cur = ''
      if (t) { t.split('/').forEach(function (part) { if (!part) return; cur += '/' + part; l.push('    (literal "' + esc(cur) + '")') }) }
      l.push(')'); l.push('')
      return l.join('\n')
    }

    function emitGrant(path: string, label: string, mode: string) {
      var l = [emitAnc(path, label)]
      if (mode === 'rw') l.push('(allow file-read* file-write* (subpath "' + esc(path) + '"))')
      else l.push('(allow file-read* (subpath "' + esc(path) + '"))')
      l.push('')
      return l.join('\n')
    }

    function emitIntPreamble(s: any) {
      var l: string[] = []
      var offOpt: string[] = []
      if (!s.docker) offOpt.push('docker'); if (!s.kubectl) offOpt.push('kubectl')
      if (!s.macosGui) offOpt.push('macos-gui'); if (!s.electron) offOpt.push('electron')
      if (!s.ssh) offOpt.push('ssh'); if (!s.spotlight) offOpt.push('spotlight')
      if (!s.cleanshot) offOpt.push('cleanshot'); if (!s.onepassword) offOpt.push('1password')
      if (!s.clipboard) offOpt.push('clipboard')
      if (!s.cloudCredentials) offOpt.push('cloud-credentials'); if (!s.browserNativeMessaging) offOpt.push('browser-native-messaging')
      if (!s.shellStartup) offOpt.push('shell-init')
      if (offOpt.length) {
        l.push(';; Opt-in integrations not enabled: ' + offOpt.join(' '))
        l.push(';; Use --enable=<feature> (comma-separated) to include them.')
        l.push(';; Note: --enable=electron also enables macos-gui.')
        l.push('')
      }
      l.push(';; Threat-model note: blocking exfiltration/C2 is explicitly NOT a goal for this sandbox.'); l.push('')
      return l.join('\n')
    }

    async function extractRequiredIntegrationPathsFromModule(path: string) {
      var text = await getProfile(path); var req: string[] = []; var re = /\$\$require=([^$]+)\$\$/g; var m
      while ((m = re.exec(text)) !== null) {
        String(m[1] || '').split(',').forEach(function (rawToken) {
          var token = String(rawToken || '').trim().toLowerCase()
          if (!token) return
          if (OPTIONAL_INTEGRATION_BY_TOKEN[token]) req.push(OPTIONAL_INTEGRATION_BY_TOKEN[token])
        })
      }
      return uniq(req)
    }

    async function resolveOptionalIntegrationPaths(explicitOptionalPaths: string[], selectedProfilePaths: string[]) {
      var included: Record<string, boolean> = {}; var queue: string[] = []; var scanned: Record<string, boolean> = {}
      function enqueueOptional(path: string) {
        if (!path || !OPTIONAL_INTEGRATION_BY_TOKEN[String(path).toLowerCase()] || included[path]) return
        included[path] = true; queue.push(path)
      }
      explicitOptionalPaths.forEach(enqueueOptional)
      var profileScanQueue = selectedProfilePaths.slice()
      while (profileScanQueue.length) {
        var profilePath = profileScanQueue.shift()!
        if (!profilePath || scanned[profilePath]) continue; scanned[profilePath] = true
        ;(await extractRequiredIntegrationPathsFromModule(profilePath)).forEach(enqueueOptional)
      }
      while (queue.length) {
        var optionalPath = queue.shift()!
        if (!optionalPath || scanned[optionalPath]) continue; scanned[optionalPath] = true
        ;(await extractRequiredIntegrationPathsFromModule(optionalPath)).forEach(enqueueOptional)
      }
      return ordered('', Object.keys(included), ORD.optionalIntegrations)
    }

    function buildUrl(base: string, p: string) { return String(base || '').replace(/\/+$/, '') + '/' + p }

    async function getProfile(path: string) {
      if (cache[path]) return cache[path]
      var candidates = resolvedBase ? [resolvedBase] : BASES.slice()
      if (resolvedBase) BASES.forEach(function (b) { if (b !== resolvedBase) candidates.push(b) })
      var err: any = null
      for (var i = 0; i < candidates.length; i += 1) {
        var url = buildUrl(candidates[i], path)
        try {
          var r = await fetch(url)
          if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + url)
          var t = await r.text(); cache[path] = t; resolvedBase = candidates[i]; return t
        } catch (e) { err = e }
      }
      throw new Error('Failed to fetch profile module: ' + path + (err ? ' (' + err.message + ')' : ''))
    }

    function selected(items: any[], prefix: string) {
      return items.filter(function (x) { var i = document.getElementById(prefix + x.key) as HTMLInputElement | null; return i && i.checked })
    }

    function ordered(prefix: string, list: string[], order: string[]) {
      var s: Record<string, number> = {}; list.forEach(function (p) { s[p] = 1 })
      var out: string[] = []; order.forEach(function (p) { if (s[p]) out.push(prefix + p) }); return out
    }

    function buildLiveState() {
      var homeRaw = String(el.home.value || '').trim()
      var home = norm(homeRaw, '/Users/you')
      var homeErrors: string[] = []
      if (!home) homeErrors.push('HOME_DIR is required.')
      else if (home.charAt(0) !== '/') homeErrors.push('HOME_DIR must be an absolute path (example: /Users/you).')

      var homeForExpansion = home && home.charAt(0) === '/' ? home : '/Users/you'
      var workRaw = String(el.workdir.value || '').trim()
      var work = norm(workRaw, homeForExpansion)
      var workErrors: string[] = []
      if (work && work.charAt(0) !== '/') workErrors.push('Workdir must be an absolute path.')

      var roInfo = parseListDetailed(el.ro.value, homeForExpansion, 'Read-only path')
      var rwInfo = parseListDetailed(el.rw.value, homeForExpansion, 'Read/write path')

      var selAgents = selected(AGENTS, 'agent-')
      var selInts = selected(INTEGRATIONS, 'integration-')
      var byKey: Record<string, boolean> = {}
      selInts.forEach(function (i) { byKey[i.key] = true })
      var electron = !!byKey['electron']
      var macosGui = !!byKey['macos-gui'] || electron
      if (electron) byKey['macos-gui'] = true

      var errors = homeErrors.concat(workErrors).concat(roInfo.errors).concat(rwInfo.errors)

      return {
        homeRaw: homeRaw,
        workRaw: workRaw,
        home: home,
        work: work,
        homeErrors: homeErrors,
        workErrors: workErrors,
        roInfo: roInfo,
        rwInfo: rwInfo,
        append: String(el.append.value || '').trim(),
        agents: selAgents,
        integrations: selInts,
        agentProfiles: uniq(selAgents.map(function (a) { return a.profile })),
        explicitOptionalIntegrationPaths: uniq(selInts.filter(function (i) { return i.group === 'extra' && i.path }).map(function (i) { return i.path })),
        docker: !!byKey['docker'],
        kubectl: !!byKey['kubectl'],
        electron: electron,
        macosGui: macosGui,
        ssh: !!byKey['ssh'],
        spotlight: !!byKey['spotlight'],
        cleanshot: !!byKey['cleanshot'],
        clipboard: !!byKey['clipboard'],
        env: !!byKey['env'],
        onepassword: !!byKey['1password'],
        cloudCredentials: !!byKey['cloud-credentials'],
        browserNativeMessaging: !!byKey['browser-native-messaging'],
        shellStartup: !!byKey['shell-init'],
        wideRead: !!byKey['wide-read'],
        errors: errors,
      }
    }

    function collect() {
      var state = buildLiveState()
      if (state.errors.length) throw new Error(state.errors[0])
      assertAbs(state.home, 'HOME_DIR value')
      if (state.work) assertAbs(state.work, 'Workdir')
      return {
        home: state.home,
        work: state.work,
        ro: parseList(el.ro.value, state.home, 'Read-only path'),
        rw: parseList(el.rw.value, state.home, 'Read/write path'),
        append: state.append,
        agents: state.agents,
        tools: TOOLCHAINS.slice(),
        agentProfiles: state.agentProfiles,
        toolProfiles: ORD.toolchains.slice(),
        explicitOptionalIntegrationPaths: state.explicitOptionalIntegrationPaths,
        docker: state.docker,
        kubectl: state.kubectl,
        electron: state.electron,
        macosGui: state.macosGui,
        ssh: state.ssh,
        spotlight: state.spotlight,
        cleanshot: state.cleanshot,
        clipboard: state.clipboard,
        env: state.env,
        onepassword: state.onepassword,
        cloudCredentials: state.cloudCredentials,
        browserNativeMessaging: state.browserNativeMessaging,
        shellStartup: state.shellStartup,
        wideRead: state.wideRead,
      }
    }

    function cmdSnippet(s: any) {
      var l = ['# Save generated policy to my-safehouse.sb', '# Run selected agents under that policy:']
      if (s.agents.length) s.agents.forEach(function (a: any) { l.push('sandbox-exec -f my-safehouse.sb -- ' + a.command) })
      else l.push('sandbox-exec -f my-safehouse.sb -- claude --dangerously-skip-permissions')
      l.push(''); l.push('# Closest safehouse CLI equivalent for grants/integrations:')
      var feats: string[] = []
      if (s.docker) feats.push('docker'); if (s.kubectl) feats.push('kubectl')
      if (s.electron) feats.push('electron'); if (!s.electron && s.macosGui) feats.push('macos-gui')
      if (s.ssh) feats.push('ssh'); if (s.spotlight) feats.push('spotlight')
      if (s.cleanshot) feats.push('cleanshot'); if (s.clipboard) feats.push('clipboard'); if (s.onepassword) feats.push('1password')
      if (s.cloudCredentials) feats.push('cloud-credentials'); if (s.browserNativeMessaging) feats.push('browser-native-messaging')
      if (s.shellStartup) feats.push('shell-init')
      if (s.wideRead) feats.push('wide-read')
      var flags: string[] = []
      if (feats.length) flags.push('--enable=' + feats.join(','))
      if (s.env) flags.push('--env')
      if (s.work) flags.push('--workdir="' + s.work.replace(/"/g, '\\"') + '"')
      if (s.ro.length) flags.push('--add-dirs-ro="' + s.ro.join(':').replace(/"/g, '\\"') + '"')
      if (s.rw.length) flags.push('--add-dirs="' + s.rw.join(':').replace(/"/g, '\\"') + '"')
      l.push('safehouse ' + (flags.length ? flags.join(' ') + ' ' : '') + '--stdout -- <agent-command>')
      l.push('# Select agents above to include matching 60-agents profiles.')
      return l.join('\n')
    }

    function buildSafehouseCommand(state: any) {
      var feats: string[] = []
      if (state.docker) feats.push('docker')
      if (state.kubectl) feats.push('kubectl')
      if (state.electron) feats.push('electron')
      else if (state.macosGui) feats.push('macos-gui')
      if (state.ssh) feats.push('ssh')
      if (state.spotlight) feats.push('spotlight')
      if (state.cleanshot) feats.push('cleanshot')
      if (state.clipboard) feats.push('clipboard')
      if (state.onepassword) feats.push('1password')
      if (state.cloudCredentials) feats.push('cloud-credentials')
      if (state.browserNativeMessaging) feats.push('browser-native-messaging')
      if (state.shellStartup) feats.push('shell-init')
      if (state.wideRead) feats.push('wide-read')

      var flags: string[] = []
      if (feats.length) flags.push('--enable=' + feats.join(','))
      if (state.env) flags.push('--env')
      if (state.work && state.work.charAt(0) === '/') flags.push('--workdir="' + state.work.replace(/"/g, '\\"') + '"')
      if (state.roInfo.values.length) flags.push('--add-dirs-ro="' + state.roInfo.values.join(':').replace(/"/g, '\\"') + '"')
      if (state.rwInfo.values.length) flags.push('--add-dirs="' + state.rwInfo.values.join(':').replace(/"/g, '\\"') + '"')

      return 'safehouse ' + (flags.length ? flags.join(' ') + ' ' : '') + '--stdout -- <agent-command>'
    }

    function summarizeLabels(labels: string[], emptyText: string, maxItems: number) {
      if (!labels.length) return emptyText
      if (labels.length <= maxItems) return labels.join(', ')
      return labels.slice(0, maxItems).join(', ') + ' +' + String(labels.length - maxItems) + ' more'
    }

    function setFeedback(node: HTMLElement, message: string, kind?: 'ok' | 'warn' | 'error') {
      node.textContent = message
      node.classList.remove('is-ok', 'is-warn', 'is-error')
      if (kind) node.classList.add('is-' + kind)
    }

    function setIssues(errors: string[]) {
      el.summaryIssues.innerHTML = ''
      if (!errors.length) {
        var ok = document.createElement('li')
        ok.textContent = 'Ready to generate.'
        el.summaryIssues.appendChild(ok)
        return
      }
      errors.slice(0, 3).forEach(function (msg) {
        var li = document.createElement('li')
        li.textContent = msg
        el.summaryIssues.appendChild(li)
      })
      if (errors.length > 3) {
        var more = document.createElement('li')
        more.textContent = '+' + String(errors.length - 3) + ' more validation issue(s)'
        el.summaryIssues.appendChild(more)
      }
    }

    function setStepDone(stepNumber: number, done: boolean) {
      var step = stepNodes[stepNumber - 1]
      if (!step) return
      step.classList.toggle('is-done', done)
    }

    function markStepConfirmed(stepNumber: number) {
      confirmedSteps[stepNumber] = true
      setStepDone(stepNumber, true)
    }

    function markStepNeedsReview(stepNumber: number) {
      if (!confirmedSteps[stepNumber]) return
      confirmedSteps[stepNumber] = false
      setStepDone(stepNumber, false)
    }

    function markSectionChanged(stepNumber: number) {
      markStepNeedsReview(stepNumber)
      if (stepNumber >= 1 && stepNumber <= 4) markStepNeedsReview(5)
    }

    function validateStepBeforeConfirm(stepNumber: number) {
      if (stepNumber !== 4) return { ok: true, message: '' }
      var state = buildLiveState()
      var firstError =
        state.homeErrors[0] ||
        state.workErrors[0] ||
        state.roInfo.errors[0] ||
        state.rwInfo.errors[0]
      if (firstError) return { ok: false, message: firstError }
      return { ok: true, message: '' }
    }

    function initStepAccordion() {
      stepNodes = Array.prototype.slice.call(document.querySelectorAll('.pb-step')) as HTMLElement[]
      if (!stepNodes.length) return

      confirmedSteps = {}
      stepNodes.forEach(function (_, idx) {
        confirmedSteps[idx + 1] = false
        setStepDone(idx + 1, false)
      })

      openStepByIndex = function (idx: number, scroll?: boolean) {
        if (idx < 0 || idx >= stepNodes.length) return
        stepNodes.forEach(function (step, curIdx) {
          var open = curIdx === idx
          step.classList.toggle('is-open', open)
          var btn = step.querySelector('.pb-step-head') as HTMLButtonElement | null
          if (btn) btn.setAttribute('aria-expanded', open ? 'true' : 'false')
        })
        if (scroll) stepNodes[idx].scrollIntoView({ behavior: 'smooth', block: 'start' })
      }

      stepNodes.forEach(function (step, idx) {
        var btn = step.querySelector('.pb-step-head') as HTMLButtonElement | null
        if (!btn) return
        btn.addEventListener('click', function () {
          if (openStepByIndex) openStepByIndex(idx, false)
        })
        var nextBtn = step.querySelector('.pb-next') as HTMLButtonElement | null
        if (nextBtn) {
          nextBtn.addEventListener('click', function () {
            var stepNumber = idx + 1
            var check = validateStepBeforeConfirm(stepNumber)
            if (!check.ok) {
              setStatus('Fix this section before confirming: ' + check.message, 'error')
              if (openStepByIndex) openStepByIndex(idx, true)
              return
            }
            markStepConfirmed(stepNumber)
            if (openStepByIndex) openStepByIndex(idx + 1, true)
          })
        }
      })

      if (openStepByIndex) openStepByIndex(0, false)
    }

    function updateLiveUi() {
      var state = buildLiveState()

      if (state.homeErrors.length) setFeedback(el.homeFeedback, state.homeErrors[0], 'error')
      else if (state.home && state.home !== state.homeRaw) setFeedback(el.homeFeedback, 'Using: ' + state.home + ' (normalized from input)', 'ok')
      else setFeedback(el.homeFeedback, state.home ? 'Using: ' + state.home : 'Required field.', state.home ? 'ok' : 'error')

      if (state.workErrors.length) setFeedback(el.workdirFeedback, state.workErrors[0], 'error')
      else if (!state.work) setFeedback(el.workdirFeedback, 'Optional. Leave blank to avoid automatic workdir write access.', 'warn')
      else if (state.work !== state.workRaw) setFeedback(el.workdirFeedback, 'Using: ' + state.work + ' (normalized from input)', 'ok')
      else setFeedback(el.workdirFeedback, 'Using: ' + state.work, 'ok')

      if (state.roInfo.errors.length) {
        setFeedback(el.roFeedback, state.roInfo.errors[0], 'error')
      } else {
        var roMsg = String(state.roInfo.values.length) + ' read-only path(s)'
        if (state.roInfo.duplicateCount) roMsg += '; ignored ' + String(state.roInfo.duplicateCount) + ' duplicate line(s)'
        if (state.roInfo.normalized.length) roMsg += '; ' + state.roInfo.normalized[0]
        setFeedback(el.roFeedback, roMsg, state.roInfo.values.length ? 'ok' : 'warn')
      }

      if (state.rwInfo.errors.length) {
        setFeedback(el.rwFeedback, state.rwInfo.errors[0], 'error')
      } else {
        var rwMsg = String(state.rwInfo.values.length) + ' read/write path(s)'
        if (state.rwInfo.duplicateCount) rwMsg += '; ignored ' + String(state.rwInfo.duplicateCount) + ' duplicate line(s)'
        if (state.rwInfo.normalized.length) rwMsg += '; ' + state.rwInfo.normalized[0]
        setFeedback(el.rwFeedback, rwMsg, state.rwInfo.values.length ? 'ok' : 'warn')
      }

      if (state.append) setFeedback(el.appendFeedback, 'Advanced overlay will be appended at the end of the generated policy.', 'warn')
      else setFeedback(el.appendFeedback, 'No overlay set.', 'ok')

      var agentNames = state.agents.map(function (a: any) { return a.label })
      el.summaryAgents.textContent = agentNames.length
        ? String(agentNames.length) + ' selected: ' + summarizeLabels(agentNames, '', 3)
        : 'No agents selected yet.'

      var optionalLabels = state.integrations
        .filter(function (i: any) { return i.group === 'extra' })
        .map(function (i: any) { return i.label })
      el.summaryIntegrations.textContent = optionalLabels.length
        ? String(optionalLabels.length) + ' enabled: ' + summarizeLabels(optionalLabels, '', 3)
        : 'No optional integrations enabled.'

      var pathBits: string[] = []
      pathBits.push(state.home && state.home.charAt(0) === '/' ? 'Home: ' + state.home : 'Home: not valid yet')
      pathBits.push(state.work ? 'Workdir: ' + state.work : 'Workdir: not set')
      pathBits.push('Extra RO: ' + String(state.roInfo.values.length))
      pathBits.push('Extra RW: ' + String(state.rwInfo.values.length))
      pathBits.push(state.append ? 'Overlay: on' : 'Overlay: off')
      el.summaryPaths.textContent = pathBits.join(' | ')

      setIssues(state.errors)
      el.summaryCommand.textContent = buildSafehouseCommand(state)
    }

    async function buildPolicy(s: any) {
      var toolPaths = ordered('profiles/30-toolchains/', s.toolProfiles, ORD.toolchains)
      var agentPaths = ordered('profiles/60-agents/', s.agentProfiles, ORD.agents)
      var selectedProfilePaths = agentPaths.slice()
      var integrationPaths = await resolveOptionalIntegrationPaths(s.explicitOptionalIntegrationPaths, selectedProfilePaths)
      var fetches = uniq(BASE_MODULES.concat(toolPaths).concat(SHARED_MODULES).concat(CORE_INTEGRATION_MODULES).concat(integrationPaths).concat(agentPaths))
      var texts = await Promise.all(fetches.map(getProfile))
      var by: Record<string, string> = {}; fetches.forEach(function (p, i) { by[p] = texts[i] })
      var parts: string[] = []; var included: string[] = []
      function add(path: string, replaceHome: boolean) {
        var c = by[path]; if (typeof c !== 'string') throw new Error('Missing loaded profile content: ' + path)
        if (replaceHome) c = c.split(HOME_TOKEN).join(esc(s.home)); c = c.replace(/\n+$/, ''); parts.push(c); parts.push(''); included.push(path)
      }
      add(BASE_MODULES[0], true); add(BASE_MODULES[1], false); add(BASE_MODULES[2], false)
      toolPaths.forEach(function (p) { add(p, false) })
      SHARED_MODULES.forEach(function (p) { add(p, false) })
      parts.push(emitIntPreamble(s))
      CORE_INTEGRATION_MODULES.forEach(function (p) { add(p, false) })
      integrationPaths.forEach(function (p) { add(p, false) })
      if (!agentPaths.length) { parts.push(';; No agent profile selected; skipping 60-agents modules.'); parts.push('') }
      else agentPaths.forEach(function (p) { add(p, false) })
      if (s.ro.length || s.rw.length) {
        parts.push(';; #safehouse-test-id:dynamic-cli-grants# Additional dynamic path grants from wizard input.'); parts.push('')
        s.ro.forEach(function (p: string) { parts.push(emitGrant(p, 'extra read-only path', 'ro')) })
        s.rw.forEach(function (p: string) { parts.push(emitGrant(p, 'extra read/write path', 'rw')) })
      }
      if (s.wideRead) { parts.push('(allow file-read* (subpath "/"))'); parts.push('') }
      if (s.work) { parts.push(';; #safehouse-test-id:workdir-grant# Allow read/write access to the selected workdir.'); parts.push(emitGrant(s.work, 'selected workdir', 'rw')) }
      if (s.append) { parts.push(';; #safehouse-test-id:append-profile# Appended policy from wizard overlay.'); parts.push(''); parts.push(s.append.replace(/\n+$/, '')); parts.push('') }
      return { policy: parts.join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n', included }
    }

    function iconNode(item: any) {
      var i = document.createElement('span'); i.className = 'pb-icon'
      if (item.logo) { var img = document.createElement('img'); img.src = item.logo; img.alt = item.label + ' icon'; img.loading = 'lazy'; i.appendChild(img) }
      else i.textContent = item.glyph || item.label.charAt(0).toUpperCase()
      return i
    }

    function makeAgent(agent: any) {
      var label = document.createElement('label'); label.className = 'pb-agent'
      var input = document.createElement('input'); input.type = 'checkbox'; input.className = 'pb-hidden'; input.id = 'agent-' + agent.key; input.checked = !!agent.on
      var box = document.createElement('span'); box.className = 'pb-agent-box'
      var wrap = document.createElement('span'); wrap.className = 'pb-avatar-wrap'
      var img = document.createElement('img'); img.className = 'pb-avatar'; img.src = agent.logo; img.alt = agent.label + ' logo'; img.loading = 'lazy'
      var chk = document.createElement('span'); chk.className = 'pb-check'; chk.textContent = '\u2713'
      wrap.appendChild(img); wrap.appendChild(chk)
      var name = document.createElement('span'); name.className = 'pb-agent-name'; name.textContent = agent.label
      box.appendChild(wrap); box.appendChild(name); label.appendChild(input); label.appendChild(box)
      return label
    }

    function makeCard(item: any, prefix: string, checked: boolean, disabled: boolean) {
      var label = document.createElement('label'); label.className = 'pb-card'
      var input = document.createElement('input'); input.type = 'checkbox'; input.className = 'pb-hidden'; input.id = prefix + item.key; input.checked = !!checked
      if (disabled) input.disabled = true
      var box = document.createElement('span'); box.className = 'pb-card-box'
      var body = document.createElement('span')
      var title = document.createElement('span'); title.className = 'pb-label'; title.textContent = item.label; body.appendChild(title)
      if (item.desc) { var meta = document.createElement('span'); meta.className = 'pb-meta'; meta.textContent = item.desc; body.appendChild(meta) }
      box.appendChild(iconNode(item)); box.appendChild(body); label.appendChild(input); label.appendChild(box)
      return label
    }

    function render() {
      AGENTS.forEach(function (a) { el.agentsGrid.appendChild(makeAgent(a)) })
      TOOLCHAINS.forEach(function (t) { el.toolchainsGrid.appendChild(makeCard({ key: t.key, label: t.label, logo: t.logo }, 'toolchain-', !!t.on, true)) })
      INTEGRATIONS.forEach(function (i: any) { (i.group === 'default' ? el.integrationsDefaultGrid : el.integrationsExtraGrid).appendChild(makeCard(i, 'integration-', !!i.on, !!i.locked)) })
    }

    function setGroup(items: any[], prefix: string, val: boolean) { items.forEach(function (x) { var i = document.getElementById(prefix + x.key) as HTMLInputElement | null; if (i && !i.disabled) i.checked = val }) }

    function syncElectron() {
      var e = document.getElementById('integration-electron') as HTMLInputElement | null
      var m = document.getElementById('integration-macos-gui') as HTMLInputElement | null
      if (!e || !m) return; if (e.checked) { m.checked = true; m.disabled = true } else { m.disabled = false }
    }

    async function generate() {
      syncElectron(); var old = el.gen.textContent; el.gen.disabled = true; el.copy.disabled = true; el.dl.disabled = true; el.launchers.disabled = true; el.gen.textContent = 'Generating...'
      setStatus('Loading and composing profile modules...')
      try {
        var s = collect(); var out = await buildPolicy(s)
        lastPolicy = out.policy; el.policy.textContent = out.policy; el.command.textContent = cmdSnippet(s)
        el.moduleCount.textContent = 'Included modules: ' + out.included.length
        el.copy.disabled = false; el.dl.disabled = false; el.launchers.disabled = false
        setStatus('Generated policy from ' + out.included.length + ' modules.', 'success')
        markStepConfirmed(5)
        if (openStepByIndex) openStepByIndex(4, true)
      } catch (err: any) { console.error(err); setStatus(err?.message || String(err), 'error'); el.moduleCount.textContent = 'Included modules: \u2014'; markStepNeedsReview(5) }
      finally { el.gen.disabled = false; el.gen.textContent = old; updateLiveUi() }
    }

    function downloadTextFile(filename: string, text: string, mimeType?: string) {
      var blob = new Blob([text], { type: mimeType || 'text/plain;charset=utf-8' }); var url = URL.createObjectURL(blob)
      var a = document.createElement('a'); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); document.body.removeChild(a); URL.revokeObjectURL(url)
    }

    function buildLauncherSetupScript(policyText: string) {
      var policyBody = String(policyText || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n+$/, '')
      var marker = 'SAFEHOUSE_POLICY_' + Date.now().toString(36).toUpperCase()
      while (policyBody.indexOf(marker) !== -1) marker += '_X'
      var l = [
        '#!/usr/bin/env bash', 'set -euo pipefail', '', 'output_dir="${SAFEHOUSE_LAUNCHER_OUTPUT_DIR:-$HOME/Desktop}"', '',
        'write_policy_file() {', '  local target="$1"', "  cat > \"$target\" <<'" + marker + "'", policyBody, marker, '}', '',
        'copy_native_icon() {', '  local app_bundle="$1"', '  local out_icns="$2"', '  local icon_name=""', '',
        '  icon_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$app_bundle/Contents/Info.plist" 2>/dev/null || true)',
        '  [[ -n "$icon_name" ]] || icon_name="AppIcon"', '  [[ "$icon_name" == *.icns ]] || icon_name="${icon_name}.icns"', '',
        '  if [[ -f "$app_bundle/Contents/Resources/$icon_name" ]]; then', '    cp "$app_bundle/Contents/Resources/$icon_name" "$out_icns"', '    return 0', '  fi', '',
        '  local first_icns', '  first_icns=$(/bin/ls "$app_bundle/Contents/Resources"/*.icns 2>/dev/null | head -n 1 || true)',
        '  if [[ -n "$first_icns" ]]; then', '    cp "$first_icns" "$out_icns"', '  fi', '}', '',
        'resolve_app_bundle() {', '  local app_name="$1"', '  local candidate', '',
        '  for candidate in "/Applications/$app_name" "$HOME/Applications/$app_name"; do', '    if [[ -d "$candidate" ]]; then',
        '      printf "%s\\n" "$candidate"', '      return 0', '    fi', '  done', '', '  return 1', '}', '',
        'make_launcher_app() {', '  local display_name="$1"', '  local bundle_id="$2"', '  local app_name="$3"',
        '  local app_rel_binary="$4"', '  local app_bundle app_binary launcher', '',
        '  if ! app_bundle="$(resolve_app_bundle "$app_name")"; then', '    echo "Skipping ${display_name}: ${app_name} not found in /Applications or ~/Applications."',
        '    return 0', '  fi', '', '  app_binary="$app_bundle/$app_rel_binary"',
        '  if [[ ! -x "$app_binary" ]]; then', '    echo "Skipping ${display_name}: binary missing at ${app_binary}"', '    return 0', '  fi', '',
        '  launcher="$output_dir/${display_name}.app"', '  rm -rf "$launcher"', '  mkdir -p "$launcher/Contents/MacOS" "$launcher/Contents/Resources"', '',
        '  write_policy_file "$launcher/Contents/Resources/policy.sb"', '',
        '  cat > "$launcher/Contents/MacOS/launch" <<LAUNCH', '#!/usr/bin/env bash', 'set -euo pipefail',
        'exec /usr/bin/sandbox-exec -f "\\${BASH_SOURCE[0]%/*}/../Resources/policy.sb" -- "$app_binary" --no-sandbox "\\$@"',
        'LAUNCH', '  chmod 0755 "$launcher/Contents/MacOS/launch"', '',
        '  cat > "$launcher/Contents/Info.plist" <<PLIST', '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
        '<plist version="1.0">', '<dict>', '  <key>CFBundleName</key><string>${display_name}</string>',
        '  <key>CFBundleDisplayName</key><string>${display_name}</string>', '  <key>CFBundleIdentifier</key><string>${bundle_id}</string>',
        '  <key>CFBundleExecutable</key><string>launch</string>', '  <key>CFBundlePackageType</key><string>APPL</string>',
        '  <key>CFBundleIconFile</key><string>AppIcon</string>', '  <key>CFBundleVersion</key><string>1</string>',
        '  <key>CFBundleShortVersionString</key><string>1.0</string>', '</dict>', '</plist>', 'PLIST', '',
        '  copy_native_icon "$app_bundle" "$launcher/Contents/Resources/AppIcon.icns" || true',
        '  /usr/bin/touch "$launcher"', '  echo "Created: $launcher"', '}', '',
        'main() {', '  if ! command -v sandbox-exec >/dev/null 2>&1; then', '    echo "sandbox-exec was not found in PATH." >&2', '    exit 1', '  fi', '',
        '  mkdir -p "$output_dir"', '',
        '  make_launcher_app "Claude (Sandboxed)" "dev.agent-safehouse.launcher.claude" "Claude.app" "Contents/MacOS/Claude"',
        '  make_launcher_app "VS Code (Sandboxed)" "dev.agent-safehouse.launcher.vscode" "Visual Studio Code.app" "Contents/MacOS/Electron"', '',
        '  echo ""', '  echo "Done. Desktop launchers are in: $output_dir"', '  echo "Tip: drag them to your Dock."', '}', '', 'main "$@"',
      ]
      return l.join('\n') + '\n'
    }

    render()
    syncElectron()
    initStepAccordion()
    updateLiveUi()

    document.getElementById('pb-agents-all')!.addEventListener('click', function () { setGroup(AGENTS, 'agent-', true); markSectionChanged(1); updateLiveUi() })
    document.getElementById('pb-agents-none')!.addEventListener('click', function () { setGroup(AGENTS, 'agent-', false); markSectionChanged(1); updateLiveUi() })
    document.querySelector('.pb-flow')!.addEventListener('change', function (ev) {
      var t = ev.target as HTMLInputElement | null
      if (!t) return
      if (t.id.indexOf('agent-') === 0) markSectionChanged(1)
      else if (t.id.indexOf('integration-') === 0) markSectionChanged(3)
      if (t.type === 'checkbox') { syncElectron(); updateLiveUi() }
    })
    ;[el.home, el.workdir, el.ro, el.rw, el.append].forEach(function (node) {
      node.addEventListener('input', function () { markSectionChanged(4); updateLiveUi() })
      node.addEventListener('blur', updateLiveUi)
    })

    el.gen.addEventListener('click', generate)
    el.copy.addEventListener('click', async function () {
      if (!lastPolicy) { setStatus('Generate a policy first.', 'error'); return }
      try { await navigator.clipboard.writeText(lastPolicy); setStatus('Policy copied to clipboard.', 'success') }
      catch (_) { setStatus('Copy failed. Use Download instead.', 'error') }
    })
    el.dl.addEventListener('click', function () {
      if (!lastPolicy) { setStatus('Generate a policy first.', 'error'); return }
      downloadTextFile('safehouse.custom.generated.sb', lastPolicy); setStatus('Downloaded safehouse.custom.generated.sb.', 'success')
    })
    el.launchers.addEventListener('click', function () {
      if (!lastPolicy) { setStatus('Generate a policy first.', 'error'); return }
      var fn = 'create-safehouse-desktop-launchers.command'
      downloadTextFile(fn, buildLauncherSetupScript(lastPolicy), 'text/x-shellscript;charset=utf-8')
      setStatus('Downloaded ' + fn + '.', 'success')
    })
  })()
})
</script>

<template>
  <div class="pb">
    <div class="pb-eyebrow">Interactive wizard</div>
    <h1 class="pb-h1">Build your own Safehouse policy</h1>
    <p class="pb-intro">
      Pick your coding agents, optional capabilities, and file system access in plain language. The builder creates a sandbox policy you
      can copy or download without hand-editing policy files.
      <a href="https://github.com/eugene1g/agent-safehouse/tree/main/profiles" target="_blank" rel="noopener noreferrer">View policy modules on GitHub</a>.
    </p>

    <div class="pb-shell">
      <div class="pb-flow">
        <section class="pb-step is-open">
          <button type="button" class="pb-step-head" aria-expanded="true">
            <span class="pb-step-number">1</span>
            <span class="pb-step-head-copy">
              <span class="pb-step-title">Choose your agents</span>
              <span class="pb-step-subtitle">Pick which coding assistants this policy should support.</span>
            </span>
            <span class="pb-step-done-indicator" aria-hidden="true">✓</span>
            <span class="pb-step-chevron" aria-hidden="true"></span>
          </button>
          <div class="pb-step-content">
            <div class="pb-bulk">
              <button id="pb-agents-all" type="button">Select all</button>
              <button id="pb-agents-none" type="button">Clear all</button>
            </div>
            <div id="pb-agents-grid" class="pb-agent-grid"></div>
            <div class="pb-step-nav">
              <button type="button" class="pb-next">Confirm &amp; Continue</button>
            </div>
          </div>
        </section>

        <section class="pb-step">
          <button type="button" class="pb-step-head" aria-expanded="false">
            <span class="pb-step-number">2</span>
            <span class="pb-step-head-copy">
              <span class="pb-step-title">Runtime toolchains</span>
              <span class="pb-step-subtitle">These are included for compatibility. Java, Perl, and PHP are shown last.</span>
            </span>
            <span class="pb-step-done-indicator" aria-hidden="true">✓</span>
            <span class="pb-step-chevron" aria-hidden="true"></span>
          </button>
          <div class="pb-step-content">
            <div id="pb-toolchains-grid" class="pb-grid pb-grid-tight"></div>
            <div class="pb-step-nav">
              <button type="button" class="pb-next">Confirm &amp; Continue</button>
            </div>
          </div>
        </section>

        <section class="pb-step">
          <button type="button" class="pb-step-head" aria-expanded="false">
            <span class="pb-step-number">3</span>
            <span class="pb-step-head-copy">
              <span class="pb-step-title">Access outside your project</span>
              <span class="pb-step-subtitle">Enable only the optional capabilities your agents actually need.</span>
            </span>
            <span class="pb-step-done-indicator" aria-hidden="true">✓</span>
            <span class="pb-step-chevron" aria-hidden="true"></span>
          </button>
          <div class="pb-step-content">
            <p class="pb-group-title">Always on</p>
            <div id="pb-integrations-default-grid" class="pb-grid"></div>
            <p class="pb-group-title">Optional</p>
            <div id="pb-integrations-extra-grid" class="pb-grid"></div>
            <div class="pb-step-nav">
              <button type="button" class="pb-next">Confirm &amp; Continue</button>
            </div>
          </div>
        </section>

        <section class="pb-step">
          <button type="button" class="pb-step-head" aria-expanded="false">
            <span class="pb-step-number">4</span>
            <span class="pb-step-head-copy">
              <span class="pb-step-title">File system access</span>
              <span class="pb-step-subtitle">Start with baseline paths, then add the smallest extra grants you need.</span>
            </span>
            <span class="pb-step-done-indicator" aria-hidden="true">✓</span>
            <span class="pb-step-chevron" aria-hidden="true"></span>
          </button>
          <div class="pb-step-content">
            <div class="pb-fs-guide">
              <p><strong>Absolute paths only:</strong> <code>~</code> is supported and expands to your HOME_DIR value.</p>
              <p><strong>Principle of least privilege:</strong> keep write access narrow to reduce accidental damage.</p>
            </div>

            <div class="pb-fs-group">
              <h3 class="pb-subhead">Baseline paths</h3>
              <div class="pb-fields">
                <div class="pb-field">
                  <label for="pb-home-dir">HOME_DIR value</label>
                  <input id="pb-home-dir" type="text" value="/Users/you">
                  <p id="pb-home-feedback" class="pb-field-feedback">Required field.</p>
                </div>
                <div class="pb-field">
                  <label for="pb-workdir">Workdir (read/write; optional)</label>
                  <input id="pb-workdir" type="text" value="/Users/you/projects/my-app">
                  <p id="pb-workdir-feedback" class="pb-field-feedback">Optional. Leave blank to avoid automatic workdir write access.</p>
                </div>
              </div>
            </div>

            <div class="pb-fs-group">
              <h3 class="pb-subhead">Extra grants</h3>
              <div class="pb-fields pb-fields-fs">
                <div class="pb-field">
                  <label for="pb-add-ro">Extra read-only directories (one per line)</label>
                  <textarea id="pb-add-ro" placeholder="/Users/you/mywork&#10;/Users/you/docs"></textarea>
                  <p id="pb-ro-feedback" class="pb-field-feedback">0 read-only paths</p>
                </div>
                <div class="pb-field">
                  <label for="pb-add-rw">Extra read/write directories (one per line)</label>
                  <textarea id="pb-add-rw" placeholder="/Users/you/scratch"></textarea>
                  <p id="pb-rw-feedback" class="pb-field-feedback">0 read/write paths</p>
                </div>
              </div>
            </div>

            <div class="pb-fs-group pb-fs-group-advanced">
              <h3 class="pb-subhead">Advanced override (optional)</h3>
              <p class="pb-hint">This text is appended last and can override earlier rules. Use only if you know exactly what you need.</p>
              <div class="pb-field pb-full">
                <label for="pb-append-profile">Appended profile text</label>
                <textarea id="pb-append-profile" placeholder=";; Example deny overlay&#10;(deny file-read* (home-subpath &quot;/.aws&quot;))"></textarea>
                <p id="pb-append-feedback" class="pb-field-feedback">No overlay set.</p>
              </div>
            </div>
            <div class="pb-step-nav">
              <button type="button" class="pb-next">Confirm &amp; Continue</button>
            </div>
          </div>
        </section>

        <section class="pb-step">
          <button type="button" class="pb-step-head" aria-expanded="false">
            <span class="pb-step-number">5</span>
            <span class="pb-step-head-copy">
              <span class="pb-step-title">Generate and copy policy</span>
              <span class="pb-step-subtitle">Create your policy file, inspect it, and copy or download.</span>
            </span>
            <span class="pb-step-done-indicator" aria-hidden="true">✓</span>
            <span class="pb-step-chevron" aria-hidden="true"></span>
          </button>
          <div class="pb-step-content">
            <div class="pb-actions">
              <button id="pb-generate" type="button" class="pb-btn pb-primary">Generate policy</button>
              <button id="pb-copy" type="button" class="pb-btn pb-secondary" disabled>Copy policy</button>
              <button id="pb-download" type="button" class="pb-btn pb-secondary" disabled>Download .sb</button>
              <button id="pb-download-launchers" type="button" class="pb-btn pb-secondary" disabled>Download desktop launcher setup (.command)</button>
            </div>

            <ul class="pb-notes">
              <li>Save the output as <code>my-safehouse.sb</code>.</li>
              <li>Run: <code>sandbox-exec -f my-safehouse.sb -- &lt;command&gt;</code>.</li>
              <li>macOS app shortcuts: run the downloaded launcher setup script with <code>bash /path/to/create-safehouse-desktop-launchers.command</code>.</li>
              <li>Compare with CLI output via <code>safehouse --stdout</code> if needed.</li>
            </ul>

            <p id="pb-status" class="pb-status">Ready. Select options and click "Generate policy".</p>
            <p id="pb-module-count" class="pb-module-count">Included modules: —</p>

            <h3 class="pb-out-title">Command helper snippet</h3>
            <pre><code id="pb-command-output"># Choose options, then click "Generate policy".</code></pre>

            <h3 class="pb-out-title">Generated policy preview</h3>
            <pre><code id="pb-policy-output">;; Policy output will appear here.</code></pre>
          </div>
        </section>
      </div>

      <aside class="pb-summary" aria-live="polite">
        <div class="pb-summary-eyebrow">Live summary</div>
        <h2 class="pb-summary-title">Policy at a glance</h2>
        <p class="pb-summary-hint">Updates as you make changes.</p>

        <div class="pb-summary-block">
          <h3>Agents</h3>
          <p id="pb-summary-agents">No agents selected yet.</p>
        </div>

        <div class="pb-summary-block">
          <h3>Optional access</h3>
          <p id="pb-summary-integrations">No optional integrations enabled.</p>
        </div>

        <div class="pb-summary-block">
          <h3>File system</h3>
          <p id="pb-summary-paths">Home: not valid yet.</p>
        </div>

        <div class="pb-summary-block">
          <h3>Ready check</h3>
          <ul id="pb-summary-issues" class="pb-summary-issues">
            <li>Ready to generate.</li>
          </ul>
        </div>

        <div class="pb-summary-block">
          <h3>Command preview</h3>
          <pre class="pb-summary-pre"><code id="pb-summary-command">safehouse --stdout -- &lt;agent-command&gt;</code></pre>
        </div>
      </aside>
    </div>
  </div>
</template>

<style>
.pb { padding: 20px 0 48px; max-width: 1180px; margin: 0 auto; padding-left: 24px; padding-right: 24px; }

.pb-eyebrow { font-family: var(--vp-font-family-mono); font-size: 0.625rem; letter-spacing: 2px; text-transform: uppercase; color: #a67c00; font-weight: 700; margin-bottom: 8px; }
.pb-h1 { font-size: 2.4rem; font-weight: 700; color: var(--vp-c-text-1); line-height: 1.1; margin-bottom: 10px; }
.pb-intro { max-width: 920px; color: var(--vp-c-text-2); font-size: 0.96rem; line-height: 1.7; margin-bottom: 22px; }
.pb-intro code, .pb-hint code, .pb-notes code { font-family: var(--vp-font-family-mono); font-size: 0.75rem; color: var(--vp-c-brand-1); background: rgba(212,160,23,0.09); border: 1px solid rgba(212,160,23,0.18); border-radius: 4px; padding: 1px 6px; }

.pb-shell { display: grid; grid-template-columns: minmax(0, 1fr) minmax(260px, 300px); gap: 20px; align-items: start; }
.pb-flow { display: grid; gap: 14px; }

.pb-step { border: 1px solid var(--vp-c-border); border-radius: 12px; background: var(--vp-c-bg); overflow: hidden; }
.pb-step-head { width: 100%; display: grid; grid-template-columns: 32px minmax(0, 1fr) auto 16px; gap: 12px; align-items: center; text-align: left; background: transparent; border: 0; cursor: pointer; padding: 13px 14px; }
.pb-step-head:hover { background: var(--vp-c-bg-alt); }
.pb-step-number { width: 32px; height: 32px; border-radius: 8px; border: 1px solid var(--vp-c-brand-1); color: var(--vp-c-brand-1); background: transparent; font-family: var(--vp-font-family-mono); font-size: 0.875rem; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; user-select: none; }
.pb-step-head-copy { min-width: 0; display: grid; gap: 3px; }
.pb-step-title { color: var(--vp-c-text-1); font-size: 1rem; font-weight: 700; line-height: 1.25; }
.pb-step-subtitle { color: var(--vp-c-text-2); font-size: 0.81rem; line-height: 1.45; }
.pb-step-done-indicator { width: 20px; height: 20px; border-radius: 999px; border: 1px solid rgba(74, 222, 128, 0.55); color: #4ade80; font-size: 0.72rem; line-height: 1; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; opacity: 0; transform: scale(0.85); transition: opacity 0.18s ease, transform 0.18s ease; }
.pb-step-chevron { width: 10px; height: 10px; border-right: 2px solid var(--vp-c-text-2); border-bottom: 2px solid var(--vp-c-text-2); transform: rotate(45deg); transition: transform 0.16s ease; justify-self: end; }
.pb-step.is-open .pb-step-chevron { transform: rotate(225deg); margin-top: 4px; }
.pb-step.is-done .pb-step-done-indicator { opacity: 1; transform: scale(1); }
.pb-step.is-done .pb-step-number { border-color: rgba(74, 222, 128, 0.7); color: #4ade80; }
.pb-step-content { display: none; border-top: 1px solid var(--vp-c-border); padding: 14px 16px 16px; }
.pb-step.is-open .pb-step-content { display: block; }

.pb-hint { font-size: 0.84rem; color: var(--vp-c-text-2); margin-bottom: 10px; line-height: 1.65; }

.pb-bulk { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 10px; }
.pb-bulk button { background: var(--vp-c-bg); border: 1px solid var(--vp-c-border); color: var(--vp-c-text-1); font-family: var(--vp-font-family-mono); font-size: 0.68rem; padding: 6px 9px; border-radius: 6px; cursor: pointer; }
.pb-bulk button:hover { border-color: #a67c00; color: var(--vp-c-brand-1); }

.pb-hidden { position: absolute; opacity: 0; pointer-events: none; }

/* Agents grid */
.pb-agent-grid { display: grid; grid-template-columns: repeat(7, 72px); justify-content: space-between; gap: 18px 0; }
.pb-agent { width: 72px; display: block; cursor: pointer; }
.pb-agent-box { display: flex; flex-direction: column; align-items: center; gap: 10px; position: relative; transition: transform 0.16s; }
.pb-agent:hover .pb-agent-box { transform: translateY(-2px); }
.pb-avatar-wrap { position: relative; width: 72px; height: 72px; border-radius: 16px; border: 1px solid transparent; background: var(--vp-c-bg-elv); overflow: hidden; transition: all 0.16s; }
.pb-avatar { width: 72px; height: 72px; display: block; object-fit: cover; border-radius: 16px; background: var(--vp-c-bg-elv); }
.pb-agent-name { font-size: 0.75rem; font-weight: 600; color: var(--vp-c-text-2); text-align: center; line-height: 1.35; }
.pb-check { position: absolute; top: 5px; right: 5px; width: 18px; height: 18px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 0.72rem; font-weight: 700; color: transparent; background: rgba(10,14,26,0.88); border: 1px solid var(--vp-c-border); transition: all 0.16s; }
.pb-agent .pb-hidden:checked + .pb-agent-box .pb-avatar-wrap { border-color: var(--vp-c-brand-1); box-shadow: 0 0 0 2px rgba(212,160,23,0.15); }
.pb-agent .pb-hidden:checked + .pb-agent-box .pb-agent-name { color: var(--vp-c-text-1); }
.pb-agent .pb-hidden:checked + .pb-agent-box .pb-check { color: #0a0e1a; background: var(--vp-c-brand-1); border-color: var(--vp-c-brand-1); }

/* Cards grid */
.pb-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(138px, 1fr)); gap: 8px; }
.pb-grid-tight { grid-template-columns: repeat(auto-fit, minmax(118px, 1fr)); }
.pb-card { display: block; position: relative; cursor: pointer; }
.pb-card-box { display: grid; grid-template-columns: 24px 1fr; gap: 8px; align-items: center; min-height: 52px; background: var(--vp-c-bg); border: 1px solid var(--vp-c-border); border-radius: 10px; padding: 7px 8px; transition: 0.16s; }
.pb-card:hover .pb-card-box { border-color: var(--vp-c-border); transform: translateY(-1px); }
.pb-icon { width: 24px; height: 24px; border-radius: 6px; display: flex; align-items: center; justify-content: center; font-size: 0.75rem; font-weight: 700; color: var(--vp-c-brand-1); font-family: var(--vp-font-family-mono); overflow: hidden; background: transparent; border: none; }
.pb-icon img { width: 100%; height: 100%; object-fit: contain; background: transparent; }
.pb-label { display: block; font-size: 0.8rem; font-weight: 600; color: var(--vp-c-text-1); line-height: 1.3; }
.pb-meta { display: block; font-size: 0.69rem; color: var(--vp-c-text-2); line-height: 1.35; margin-top: 1px; }
.pb-card .pb-hidden:checked + .pb-card-box { border-color: var(--vp-c-brand-1); box-shadow: 0 0 0 2px rgba(212,160,23,0.13); background: var(--vp-c-bg-elv); }
.pb-card .pb-hidden:disabled + .pb-card-box { cursor: default; }

.pb-group-title { margin-top: 4px; margin-bottom: 8px; font-size: 0.8rem; color: var(--vp-c-text-2); font-weight: 600; letter-spacing: 0.2px; line-height: 1.5; }
.pb-fs-guide { margin: 0 0 12px; padding: 12px 14px; border-radius: 10px; border: 1px solid var(--vp-c-border); background: var(--vp-c-bg-alt); display: grid; gap: 6px; }
.pb-fs-guide p { margin: 0; color: var(--vp-c-text-2); font-size: 0.8rem; line-height: 1.55; }
.pb-fs-guide strong { color: var(--vp-c-text-1); font-weight: 600; }
.pb-fs-group { border: 1px solid var(--vp-c-border); border-radius: 10px; padding: 12px; background: var(--vp-c-bg); margin-bottom: 10px; }
.pb-fs-group-advanced { border-color: rgba(239, 83, 80, 0.42); background: rgba(239, 83, 80, 0.08); }
.pb-subhead { margin: 0 0 8px; color: var(--vp-c-text-1); font-size: 0.9rem; font-weight: 700; border: 0; padding: 0; }

/* Fields */
.pb-fields { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.pb-field { display: flex; flex-direction: column; gap: 6px; }
.pb-field.pb-full { grid-column: 1 / -1; }
.pb-field label { font-family: var(--vp-font-family-mono); font-size: 0.62rem; letter-spacing: 1.2px; text-transform: uppercase; color: var(--vp-c-text-2); font-weight: 700; }
.pb-field input, .pb-field textarea { width: 100%; background: var(--vp-c-bg); border: 1px solid var(--vp-c-border); border-radius: 8px; color: var(--vp-c-text-1); font-family: var(--vp-font-family-mono); font-size: 0.78rem; padding: 10px 12px; line-height: 1.5; }
.pb-field textarea { min-height: 92px; resize: vertical; }
.pb-field input:focus, .pb-field textarea:focus { outline: none; border-color: #a67c00; box-shadow: 0 0 0 2px rgba(212,160,23,0.12); }
.pb-fields-fs .pb-field textarea { min-height: 120px; }
.pb-field-feedback { margin: 0; color: var(--vp-c-text-2); font-size: 0.72rem; line-height: 1.45; }
.pb-field-feedback.is-ok { color: #4ade80; }
.pb-field-feedback.is-warn { color: #f5c842; }
.pb-field-feedback.is-error { color: #ef5350; }

.pb-step-nav { margin-top: 12px; display: flex; justify-content: flex-end; }
.pb-next { background: var(--vp-c-bg); border: 1px solid var(--vp-c-border); color: var(--vp-c-text-1); font-family: var(--vp-font-family-mono); font-size: 0.68rem; letter-spacing: 0.5px; padding: 7px 10px; border-radius: 7px; cursor: pointer; }
.pb-next:hover { border-color: #a67c00; color: var(--vp-c-brand-1); }

.pb-summary { position: sticky; top: 84px; width: 100%; max-width: 300px; min-width: 0; justify-self: end; border: 1px solid var(--vp-c-border); border-radius: 12px; background: var(--vp-c-bg-alt); padding: 12px; display: grid; gap: 10px; overflow: hidden; }
.pb-summary-eyebrow { font-family: var(--vp-font-family-mono); font-size: 0.62rem; letter-spacing: 1.4px; text-transform: uppercase; color: #a67c00; font-weight: 700; }
.pb-summary-title { margin: 0; color: var(--vp-c-text-1); font-size: 1.05rem; line-height: 1.2; border: 0; padding: 0; }
.pb-summary-hint { margin: 0; color: var(--vp-c-text-2); font-size: 0.78rem; line-height: 1.45; }
.pb-summary-block { min-width: 0; border: 1px solid var(--vp-c-border); border-radius: 9px; background: var(--vp-c-bg); padding: 10px; }
.pb-summary-block h3 { margin: 0 0 6px; font-size: 0.72rem; line-height: 1.2; text-transform: uppercase; letter-spacing: 1px; color: var(--vp-c-text-2); border: 0; padding: 0; font-family: var(--vp-font-family-mono); }
.pb-summary-block p { margin: 0; color: var(--vp-c-text-1); font-size: 0.76rem; line-height: 1.45; overflow-wrap: anywhere; }
.pb-summary-issues { margin: 0; padding-left: 16px; display: grid; gap: 4px; }
.pb-summary-issues li { color: var(--vp-c-text-1); font-size: 0.75rem; line-height: 1.35; overflow-wrap: anywhere; }

/* Buttons */
.pb-actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 6px; }
.pb-btn { display: inline-flex; align-items: center; justify-content: center; padding: 11px 18px; border-radius: 8px; font-size: 0.84rem; font-weight: 600; border: 1px solid transparent; cursor: pointer; transition: 0.16s; }
.pb-btn.pb-primary { background: var(--vp-c-brand-1); color: #0a0e1a; }
.pb-btn.pb-primary:hover { background: #f5c842; transform: translateY(-1px); }
.pb-btn.pb-secondary { background: var(--vp-c-bg); color: var(--vp-c-text-1); border-color: var(--vp-c-border); }
.pb-btn.pb-secondary:hover { border-color: #a67c00; color: var(--vp-c-text-1); }
.pb-btn:disabled { opacity: 0.55; cursor: not-allowed; transform: none; }

.pb-notes { margin: 12px 0 0 18px; display: grid; gap: 4px; color: var(--vp-c-text-2); font-size: 0.81rem; }
.pb-status { margin-top: 10px; min-height: 1.2rem; font-size: 0.81rem; color: var(--vp-c-text-2); }
.pb-status.success { color: #4ade80; }
.pb-status.error { color: #ef5350; }
.pb-module-count { margin-top: 6px; font-size: 0.74rem; color: var(--vp-c-text-2); font-family: var(--vp-font-family-mono); }
.pb-out-title { margin: 16px 0 8px; color: var(--vp-c-text-1); font-size: 0.93rem; font-weight: 600; border: none; padding: 0; }

.pb pre { margin: 0; background: var(--vp-c-bg-alt); border: 1px solid var(--vp-c-border); border-radius: 10px; padding: 14px 15px; max-height: 350px; overflow: auto; font-family: var(--vp-font-family-mono); font-size: 0.74rem; line-height: 1.65; }
.pb .pb-summary-pre { margin: 0; background: var(--vp-c-bg-alt); border: 1px solid var(--vp-c-border); border-radius: 8px; padding: 10px; max-height: 180px; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere; word-break: break-word; font-family: var(--vp-font-family-mono); font-size: 0.69rem; line-height: 1.45; }

/* Responsive */
@media (max-width: 1100px) {
  .pb-shell { grid-template-columns: 1fr; }
  .pb-summary { position: static; max-width: none; justify-self: stretch; }
}
@media (max-width: 1024px) { .pb-agent-grid { grid-template-columns: repeat(6, 72px); justify-content: space-around; } }
@media (max-width: 920px) {
  .pb-fields { grid-template-columns: 1fr; }
  .pb-grid { grid-template-columns: repeat(auto-fit, minmax(132px, 1fr)); }
}
@media (max-width: 760px) {
  .pb-h1 { font-size: 2rem; }
  .pb-step-head { grid-template-columns: 28px minmax(0, 1fr) auto 14px; gap: 10px; padding: 12px; }
  .pb-step-number { width: 28px; height: 28px; font-size: 0.8rem; }
  .pb-step-done-indicator { width: 18px; height: 18px; font-size: 0.66rem; }
  .pb-step-title { font-size: 0.95rem; }
  .pb-step-subtitle { font-size: 0.75rem; }
  .pb-agent-grid { grid-template-columns: repeat(4, 72px); justify-content: space-between; }
  .pb-actions { flex-direction: column; }
  .pb-btn { width: 100%; }
}
@media (max-width: 520px) { .pb-agent-grid { grid-template-columns: repeat(3, 72px); justify-content: space-around; } }
</style>
