# Pi Coding Agent -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/badlogic/pi-mono
**Git Commit:** `34878e7cc8074f42edff6c2cdcc9828aa9b6afde`
**Latest Version:** 0.52.9
**License:** MIT
**Source Availability:** Open source

---

## 1. Overview

Pi (published as `@mariozechner/pi-coding-agent`) is an interactive coding agent CLI built in TypeScript/Node.js. It is a monorepo (`pi-mono`) by Mario Zechner. The agent provides read, bash, edit, write, grep, find, and ls tools to an LLM, with support for many providers (Anthropic, OpenAI, Google, AWS Bedrock, Groq, Cerebras, xAI, OpenRouter, Mistral, GitHub Copilot, and more).

The monorepo contains these packages:

| Package | npm Name | Description |
|---------|----------|-------------|
| `packages/ai` | `@mariozechner/pi-ai` | Unified multi-provider LLM API |
| `packages/agent` | `@mariozechner/pi-agent-core` | Agent runtime with tool calling |
| `packages/coding-agent` | `@mariozechner/pi-coding-agent` | **Main CLI** -- the coding agent |
| `packages/tui` | `@mariozechner/pi-tui` | Custom terminal UI library |
| `packages/web-ui` | `@mariozechner/pi-web-ui` | Web components for chat (not used by CLI) |
| `packages/mom` | `@mariozechner/pi-mom` | Slack bot delegating to pi agent |
| `packages/pods` | `@mariozechner/pi` | vLLM GPU pod management CLI |

---

## 2. UI & Execution Modes

### Custom TUI (NOT Ink/React)

Pi uses its own custom terminal UI library (`@mariozechner/pi-tui`) with **differential rendering** -- it is NOT based on Ink, React-Ink, blessed, or any other TUI framework. The TUI renders directly to stdout using ANSI escape codes and manages its own component tree.

```typescript
// packages/tui/src/tui.ts
/**
 * Minimal TUI implementation with differential rendering
 */
export interface Component {
    render(width: number): string[];
    handleInput?(data: string): void;
    invalidate(): void;
}
```

Key TUI features:
- Direct ANSI escape code rendering to stdout
- Differential rendering (only re-renders changed lines)
- Supports Kitty keyboard protocol for key release events
- Terminal image support (Kitty protocol, iTerm2 inline images)
- OSC 8 hyperlink support
- Custom editor component with full input handling
- Overlay/modal system

### No Web UI in CLI Mode

The `packages/web-ui` package exists but is separate -- it provides web components (using `lit` / `mini-lit`) for embedding in web pages, not used by the CLI. The CLI is purely terminal-based.

### Three Execution Modes

1. **Interactive mode** (default) -- full TUI with editor, footer, conversation display
2. **Print mode** (`-p` or piped stdin) -- non-interactive, outputs to stdout
3. **RPC mode** (`--rpc`) -- headless JSON protocol on stdin/stdout for embedding in other applications

---

## 3. Authentication & Credentials

### 3.1 Credential Storage

All credentials are stored in a plain JSON file at `~/.pi/agent/auth.json`, with file permissions set to `0o600`:

```typescript
// packages/coding-agent/src/core/auth-storage.ts
private save(): void {
    const dir = dirname(this.authPath);
    if (!existsSync(dir)) {
        mkdirSync(dir, { recursive: true, mode: 0o700 });
    }
    writeFileSync(this.authPath, JSON.stringify(this.data, null, 2), "utf-8");
    chmodSync(this.authPath, 0o600);
}
```

The auth file stores two types of credentials:
- **API keys** (plain text in JSON)
- **OAuth tokens** (access token, refresh token, expiry timestamp)

File locking via `proper-lockfile` prevents race conditions when multiple pi instances refresh tokens simultaneously.

Pi does **NOT** use macOS Keychain, `keytar`, `keyring`, or any OS-level credential store.

### 3.2 API Key Sources and Priority Order

Priority: runtime override > auth.json > env var > fallback resolver.

```typescript
// packages/ai/src/env-api-keys.ts
const envMap: Record<string, string> = {
    openai: "OPENAI_API_KEY",
    "azure-openai-responses": "AZURE_OPENAI_API_KEY",
    google: "GEMINI_API_KEY",
    groq: "GROQ_API_KEY",
    cerebras: "CEREBRAS_API_KEY",
    xai: "XAI_API_KEY",
    openrouter: "OPENROUTER_API_KEY",
    "vercel-ai-gateway": "AI_GATEWAY_API_KEY",
    zai: "ZAI_API_KEY",
    mistral: "MISTRAL_API_KEY",
    minimax: "MINIMAX_API_KEY",
    "minimax-cn": "MINIMAX_CN_API_KEY",
    huggingface: "HF_TOKEN",
    opencode: "OPENCODE_API_KEY",
    "kimi-coding": "KIMI_API_KEY",
};
```

Additional provider-specific environment variables:
- `ANTHROPIC_API_KEY`, `ANTHROPIC_OAUTH_TOKEN`
- `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`
- `AWS_PROFILE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_BEARER_TOKEN_BEDROCK`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_CONTAINER_CREDENTIALS_*`
- `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`
- `AZURE_OPENAI_BASE_URL`, `AZURE_OPENAI_RESOURCE_NAME`, `AZURE_OPENAI_API_VERSION`, `AZURE_OPENAI_DEPLOYMENT_NAME_MAP`

### 3.3 OAuth Flows

Pi supports 5 OAuth providers, each with its own flow:

| Provider | Flow Type | Local HTTP Server Port | Endpoints |
|----------|-----------|------------------------|-----------|
| Anthropic | PKCE auth code (manual paste) | None | `claude.ai/oauth/authorize`, `console.anthropic.com/v1/oauth/token` |
| GitHub Copilot | Device code flow (polling) | None | `github.com/login/device/code`, `github.com/login/oauth/access_token` |
| Google Antigravity | PKCE auth code + local callback | `127.0.0.1:51121` | `accounts.google.com/o/oauth2/v2/auth`, `oauth2.googleapis.com/token` |
| Google Gemini CLI | PKCE auth code + local callback | `127.0.0.1:8085` | `accounts.google.com/o/oauth2/v2/auth`, `oauth2.googleapis.com/token` |
| OpenAI Codex | PKCE auth code + local callback | `127.0.0.1:1455` | `auth.openai.com/oauth/authorize`, `auth.openai.com/oauth/token` |

During OAuth login, pi opens the user's browser using platform-specific commands:

```typescript
// packages/coding-agent/src/modes/interactive/components/login-dialog.ts
const openCmd = process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open";
exec(`${openCmd} "${url}"`);
```

### 3.4 Credential File Locations and Formats

| Path | Purpose |
|------|---------|
| `~/.pi/agent/auth.json` | All API keys and OAuth tokens (JSON, mode 0o600) |
| `~/.config/gcloud/application_default_credentials.json` | Google ADC check (for Vertex AI) |
| `~/.aws/credentials`, `~/.aws/config` | AWS credential chain (via SDK, for Bedrock) |

---

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

The default global config directory is `~/.pi/agent/`, configurable via the `PI_CODING_AGENT_DIR` environment variable.

```typescript
// packages/coding-agent/src/config.ts
export const CONFIG_DIR_NAME: string = pkg.piConfig?.configDir || ".pi";
export function getAgentDir(): string {
    const envDir = process.env[ENV_AGENT_DIR];
    if (envDir) { /* ... */ }
    return join(homedir(), CONFIG_DIR_NAME, "agent");
}
```

| Path | Purpose |
|------|---------|
| `~/.pi/agent/auth.json` | API keys and OAuth tokens |
| `~/.pi/agent/settings.json` | User settings (default provider, theme, compaction, etc.) |
| `~/.pi/agent/models.json` | Custom model definitions |
| `~/.pi/agent/pi-debug.log` | Debug log output |
| `~/.pi/agent/sessions/` | Session history storage |
| `~/.pi/agent/sessions/<encoded-cwd>/` | Per-project session files |
| `~/.pi/agent/sessions/<encoded-cwd>/session.jsonl` | Session data (JSONL format) |
| `~/.pi/agent/themes/` | User custom themes |
| `~/.pi/agent/bin/` | Managed tool binaries (fd, rg) |
| `~/.pi/agent/tools/` | Tools directory |
| `~/.pi/agent/prompts/` | User prompt templates |
| `~/.pi/agent/git/` | Git-based package installs |
| `~/.pi/agent/npm/` | (via global npm root) |
| `~/.pi/agent/extensions/` | Global extensions |
| `~/.pi/agent/sandbox.json` | Sandbox extension config (optional) |

### 4.2 Project-Level Config Paths

| Path | Purpose |
|------|---------|
| `<cwd>/.pi/settings.json` | Project-local settings |
| `<cwd>/.pi/extensions/` | Project-local extensions |
| `<cwd>/.pi/sandbox.json` | Project-local sandbox config |
| `<cwd>/.pi/npm/` | Project-local npm packages |
| `<cwd>/.pi/git/` | Project-local git packages |

### 4.3 System/Enterprise Config Paths

N/A

### 4.4 Data & State Directories

| Path | Purpose |
|------|---------|
| `~/.pi/agent/sessions/` | Session history storage root |
| `~/.pi/agent/sessions/<encoded-cwd>/session.jsonl` | Per-project session data |
| `~/.pi/agent/pi-debug.log` | Debug log output |

### 4.5 Workspace Files Read

| File | Purpose |
|------|---------|
| `AGENTS.md` | Agent instructions (loaded from cwd and parent dirs) |
| `CLAUDE.md` | Alternative agent instructions file |
| `.gitignore` | Used by find/grep tools to respect ignore patterns |
| `.ignore` | Additional ignore patterns |
| `.fdignore` | fd-specific ignore patterns |
| `<cwd>/.git/HEAD` | Git branch detection (with worktree support) |

### 4.6 Temp Directory Usage

Pi uses `os.tmpdir()` (which reads the `TMPDIR` environment variable on macOS) for temporary files:

```typescript
// packages/coding-agent/src/core/tools/bash.ts
import { tmpdir } from "node:os";
function getTempFilePath(): string {
    const id = randomBytes(8).toString("hex");
    return join(tmpdir(), `pi-bash-${id}.log`);
}
```

Temporary file patterns:

| Pattern | Purpose | Cleanup |
|---------|---------|---------|
| `$TMPDIR/pi-bash-<hex>.log` | Bash output overflow (>30KB output) | No automatic cleanup |
| `$TMPDIR/pi-editor-<timestamp>.pi.md` | External editor temp file | Cleaned after editor closes |
| `$TMPDIR/pi-extensions/npm/<hash>/` | Temporary npm package installs | No automatic cleanup |
| `$TMPDIR/pi-extensions/git-<host>/<hash>/` | Temporary git package installs | No automatic cleanup |
| `$TMPDIR/mom-bash-<id>.log` | Mom (Slack bot) bash output | No automatic cleanup |

---

## 5. Tools Available to the LLM

Pi provides the following tools to the LLM:

- **`read`** -- File reading (any file the LLM requests in the working directory tree)
- **`bash`** -- Shell command execution (arbitrary commands via configured shell)
- **`edit`** -- File editing (diff-based, uses `diff` npm package)
- **`write`** -- File creation/writing
- **`grep`** -- Content search (uses `rg` / ripgrep, streaming)
- **`find`** -- File pattern matching (uses `fd`)
- **`ls`** -- Directory listing

The bash tool runs commands directly on the host system with the user's full permissions. Shell resolution order: user `shellPath` in settings > `/bin/bash` > bash on PATH > `sh`.

Pi auto-downloads `fd` and `rg` (ripgrep) binaries if not found on PATH, installing them to `~/.pi/agent/bin/`:
```typescript
// packages/coding-agent/src/utils/tools-manager.ts
// Downloads from GitHub releases:
// https://github.com/sharkdp/fd/releases/...
// https://github.com/BurntSushi/ripgrep/releases/...
```

Extensions can register additional custom tools (including replacing the bash tool).

---

## 6. Host System Interactions

### 6.1 Subprocess Execution

#### Shell Execution (bash tool -- primary agent capability)

```typescript
// packages/coding-agent/src/core/tools/bash.ts
const child = spawn(shell, [...args, command], {
    cwd,
    detached: true,
    env: env ?? getShellEnv(),
    stdio: ["ignore", "pipe", "pipe"],
});
```

- Runs arbitrary commands via bash (or configured shell)
- Shell resolution: user `shellPath` in settings > `/bin/bash` > bash on PATH > `sh`
- Process groups are used (`detached: true`) for tree killing
- `SIGKILL` sent to process group on cancellation
- The agent's `~/.pi/agent/bin/` directory is prepended to `PATH`

#### Tool Binary Management

Pi auto-downloads `fd` and `rg` (ripgrep) if not found on PATH:
- `spawnSync("fd", [...])` for file autocomplete
- `spawn("rg", [...])` for grep tool (ripgrep streaming)
- `spawnSync("tar", ["xzf", ...])` for extracting downloaded archives
- `spawnSync("which", ["bash"])` or `spawnSync("where", ["bash.exe"])` for shell detection

#### Clipboard Operations

```typescript
// packages/coding-agent/src/utils/clipboard.ts (macOS)
execSync("pbcopy", { input: text, timeout: 5000 });

// Also emits OSC 52 escape sequence to stdout for terminal clipboard:
process.stdout.write(`\x1b]52;c;${encoded}\x07`);
```

On macOS: `pbcopy` for text, `@mariozechner/clipboard` (optional native dependency) for image clipboard.

#### External Editor

```typescript
// packages/coding-agent/src/modes/interactive/interactive-mode.ts
const editorCmd = process.env.VISUAL || process.env.EDITOR;
const result = spawnSync(editor, [...editorArgs, tmpFile], {
    stdio: "inherit",
});
```

- Spawns `$VISUAL` or `$EDITOR` for the `/editor` command
- Uses a temp file in `$TMPDIR`

#### GitHub CLI

```typescript
// Session sharing via /share command:
spawnSync("gh", ["auth", "status"], { encoding: "utf-8" });
spawn("gh", ["gist", "create", "--public=false", tmpFile]);
```

#### Browser Opening

```typescript
// During OAuth login:
exec(`open "${url}"`);     // macOS
exec(`start "${url}"`);    // Windows
exec(`xdg-open "${url}"`); // Linux
```

#### Package Management

```typescript
// packages/coding-agent/src/core/package-manager.ts
const child = spawn(command, args, { cwd: installRoot, ... });
// Runs: npm install, npm root -g, git clone, etc.
```

- `npm install <package>` -- for installing npm extension packages
- `npm root -g` -- to find global npm root
- `git clone <url>` -- for git-based package installs
- `git fetch`, `git checkout` -- for git package updates

#### Process Tree Killing

```typescript
// packages/coding-agent/src/utils/shell.ts
// Unix:
process.kill(-pid, "SIGKILL");  // Kill entire process group
// Windows fallback:
spawn("taskkill", ["/F", "/T", "/PID", String(pid)]);
```

### 6.2 Network Requests

#### LLM API Calls

| Provider | Endpoint Pattern |
|----------|-----------------|
| Anthropic | `https://api.anthropic.com/v1/messages` (via `@anthropic-ai/sdk`) |
| OpenAI | `https://api.openai.com/v1/...` (via `openai` SDK) |
| Google Gemini | `https://generativelanguage.googleapis.com/...` (via `@google/genai`) |
| Google Vertex | `https://<location>-aiplatform.googleapis.com/...` |
| AWS Bedrock | `https://bedrock-runtime.<region>.amazonaws.com` |
| Azure OpenAI | `https://<resource>.openai.azure.com/openai/...` |
| Groq | `https://api.groq.com/...` |
| GitHub Copilot | `https://api.individual.githubcopilot.com/...` |
| Mistral | Via `@mistralai/mistralai` SDK |
| Others | Various OpenAI-compatible endpoints |

#### Other Network Requests

| URL | Purpose |
|-----|---------|
| `https://registry.npmjs.org/@mariozechner/pi-coding-agent/latest` | Version check on startup |
| `https://registry.npmjs.org/<pkg>/latest` | npm package version checks |
| `https://api.github.com/repos/<repo>/releases/latest` | fd/rg binary download version check |
| `https://github.com/<repo>/releases/download/...` | fd/rg binary downloads |
| `https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` | Antigravity project discovery |
| `https://www.googleapis.com/oauth2/v1/userinfo` | Google user email lookup |
| OAuth token endpoints (see Section 3) | Token exchange and refresh |

#### HTTP Proxy Support

Pi respects `HTTP_PROXY`, `HTTPS_PROXY`, `http_proxy`, `https_proxy`, `no_proxy`, `NO_PROXY` environment variables via `undici`'s `EnvHttpProxyAgent`:

```typescript
// packages/ai/src/utils/http-proxy.ts
import("undici").then((m) => {
    const { EnvHttpProxyAgent, setGlobalDispatcher } = m;
    setGlobalDispatcher(new EnvHttpProxyAgent());
});
```

### 6.3 Port Binding

Pi binds local HTTP servers during OAuth flows:

| Port | Provider | Bind Address |
|------|----------|--------------|
| `51121` | Google Antigravity | `127.0.0.1` |
| `8085` | Google Gemini CLI | `127.0.0.1` |
| `1455` | OpenAI Codex | `127.0.0.1` |

These servers are **temporary** -- they start when login begins and close when the callback is received or login completes.

### 6.4 Browser Launching

During OAuth login, pi opens the user's browser using platform-specific commands:
- macOS: `open "<url>"`
- Windows: `start "<url>"`
- Linux: `xdg-open "<url>"`

### 6.5 Clipboard Access

**Text clipboard (write-only):**
- macOS: `pbcopy` via `execSync`
- Also emits OSC 52 escape sequence (works over SSH)

**Image clipboard (read-only, for pasting images into conversations):**
- macOS/Windows: `@mariozechner/clipboard` native module (optional dependency)
- Linux/Wayland: `wl-paste --list-types`, `wl-paste --type <mime>`
- Linux/X11: `xclip -selection clipboard -t <mime> -o`

### 6.6 File System Watchers

Pi sets up `fs.watch()` watchers on:

1. **Git HEAD file** (`<cwd>/.git/HEAD`) -- monitors for branch changes, displayed in the footer
2. **Theme file** -- watches for live theme reloading when custom themes change

```typescript
// packages/coding-agent/src/core/footer-data-provider.ts
private gitWatcher: FSWatcher | null = null;
// Watches .git/HEAD for branch changes

// packages/coding-agent/src/modes/interactive/theme/theme.ts
themeWatcher = fs.watch(themeFile, (eventType) => { ... });
```

### 6.7 Other

- **RPC Mode**: When run with `--rpc`, pi operates as a headless JSON-over-stdio service. Reads JSON commands from stdin, writes JSON events/responses to stdout. The `RpcClient` class can spawn a pi subprocess in RPC mode.
- **Docker/Container Interaction**: The `mom` (Slack bot) package supports Docker execution (`docker exec <container> sh -c <command>`). This is only relevant to the Slack bot, not the main CLI.
- **Session Sharing**: The `/share` command creates GitHub Gists via `gh gist create` for sharing session transcripts.

---

## 7. Extension Points

### 7.1 Hook/Lifecycle System

None identified (no hook/lifecycle events system).

### 7.2 Plugin/Extension Architecture

Extensions can:
- Register custom tools (including replacing the bash tool)
- Register custom commands
- Hook into session events
- Spawn subprocesses
- Access the filesystem
- Make network requests

Extensions are loaded from:
1. CLI flag: `pi -e ./my-extension.ts`
2. Settings: `extensions` array in `settings.json`
3. Project-local: `<cwd>/.pi/extensions/`
4. Packages: npm or git packages with `pi.extensions` in their `package.json`

Extensions are loaded via `jiti` (TypeScript-in-Node.js runtime).

### 7.3 MCP Integration

None identified. Pi uses its own extension system rather than MCP.

### 7.4 Custom Commands/Skills/Agents

- Custom prompt templates: `~/.pi/agent/prompts/`
- Custom model definitions: `~/.pi/agent/models.json`

### 7.5 SDK/API Surface

- **RPC mode** (`--rpc`): Headless JSON-over-stdio protocol for embedding in other applications
- **`RpcClient`** class: Can spawn a pi subprocess in RPC mode for programmatic control

---

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

Pi does **NOT** sandbox tool execution by default. The bash tool runs commands directly on the host system with the user's full permissions.

However, there is an **optional sandbox extension** at `packages/coding-agent/examples/extensions/sandbox/` that uses `@anthropic-ai/sandbox-runtime` to enforce OS-level restrictions:

```typescript
// Uses sandbox-exec on macOS, bubblewrap on Linux
await SandboxManager.initialize({
    network: config.network,
    filesystem: config.filesystem,
});
const wrappedCommand = await SandboxManager.wrapWithSandbox(command);
```

This is opt-in and must be explicitly enabled by the user via `pi -e ./sandbox`.

### 8.2 Permission System

None. All tools run with the user's full permissions by default.

### 8.3 Safety Mechanisms

- Credential file permissions set to `0o600` (owner read/write only)
- Config directory created with `0o700` permissions
- File locking via `proper-lockfile` for auth.json

### 8.4 Known Vulnerabilities

None identified.

### 8.5 Enterprise/Managed Security Controls

N/A

---

## 9. Key Dependencies

| Dependency | Package | Impact |
|-----------|---------|--------|
| `@anthropic-ai/sdk` | ai | HTTP to Anthropic API |
| `openai` | ai | HTTP to OpenAI-compatible APIs |
| `@google/genai` | ai | HTTP to Google Gemini API |
| `@aws-sdk/client-bedrock-runtime` | ai | HTTP to AWS Bedrock |
| `@mistralai/mistralai` | ai | HTTP to Mistral API |
| `undici` | ai | HTTP proxy agent setup (modifies global fetch) |
| `proxy-agent` | ai | HTTP proxy for AWS SDK |
| `proper-lockfile` | coding-agent | File-level locking for auth.json |
| `glob` | coding-agent | Filesystem globbing |
| `@mariozechner/clipboard` | coding-agent (optional) | Native clipboard access (image read) |
| `@silvia-odwyer/photon-node` | coding-agent | WASM-based image processing (BMP-to-PNG) |
| `@mariozechner/jiti` | coding-agent | Runtime TypeScript loading for extensions |
| `chalk` | coding-agent | Terminal color output |
| `diff` | coding-agent | Diff generation for edit tool |
| `file-type` | coding-agent | File MIME type detection |
| `ignore` | coding-agent | .gitignore pattern matching |
| `hosted-git-info` | coding-agent | Git URL parsing for package manager |
| `yaml` | coding-agent | YAML parsing |
| `marked` | coding-agent, tui | Markdown parsing |
| `@slack/socket-mode`, `@slack/web-api` | mom | Slack WebSocket and API (bot only) |
| `@anthropic-ai/sandbox-runtime` | sandbox example, mom | OS-level sandboxing (optional) |

---

## 10. Environment Variables

### Pi-Specific

| Variable | Purpose |
|----------|---------|
| `PI_CODING_AGENT_DIR` | Override global config directory (default: `~/.pi/agent`) |
| `PI_PACKAGE_DIR` | Override package asset directory |
| `PI_SHARE_VIEWER_URL` | Override share viewer URL |
| `PI_SKIP_VERSION_CHECK` | Skip npm version check on startup |
| `PI_AI_ANTIGRAVITY_VERSION` | Override Antigravity User-Agent version |
| `PI_TIMING` | Enable timing instrumentation (`1`) |
| `PI_CLEAR_ON_SHRINK` | Clear empty rows when content shrinks (`1`) |
| `PI_HARDWARE_CURSOR` | Enable hardware cursor (`1`) |
| `PI_CACHE_RETENTION` | Cache retention setting (`long`) |

### Provider API Keys

| Variable | Provider |
|----------|---------|
| `OPENAI_API_KEY` | OpenAI |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI |
| `GEMINI_API_KEY` | Google Gemini |
| `GROQ_API_KEY` | Groq |
| `CEREBRAS_API_KEY` | Cerebras |
| `XAI_API_KEY` | xAI |
| `OPENROUTER_API_KEY` | OpenRouter |
| `AI_GATEWAY_API_KEY` | Vercel AI Gateway |
| `ZAI_API_KEY` | ZAI |
| `MISTRAL_API_KEY` | Mistral |
| `MINIMAX_API_KEY` | MiniMax |
| `MINIMAX_CN_API_KEY` | MiniMax CN |
| `HF_TOKEN` | HuggingFace |
| `OPENCODE_API_KEY` | OpenCode |
| `KIMI_API_KEY` | Kimi Coding |
| `ANTHROPIC_API_KEY` | Anthropic |
| `ANTHROPIC_OAUTH_TOKEN` | Anthropic OAuth |
| `COPILOT_GITHUB_TOKEN` | GitHub Copilot |
| `GH_TOKEN` / `GITHUB_TOKEN` | GitHub |
| `AWS_PROFILE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, etc. | AWS Bedrock |
| `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`, etc. | Google Vertex AI |
| `AZURE_OPENAI_BASE_URL`, `AZURE_OPENAI_RESOURCE_NAME`, etc. | Azure OpenAI |

### Editor/Shell

| Variable | Purpose |
|----------|---------|
| `VISUAL` | Preferred editor for `/editor` command |
| `EDITOR` | Fallback editor for `/editor` command |
| `SHELL` | (not used -- pi finds bash independently) |

### Terminal Detection

| Variable | Purpose |
|----------|---------|
| `COLORTERM` | True color detection |
| `TERM` | Terminal type detection |
| `TERM_PROGRAM` | Terminal program detection (Apple_Terminal) |
| `WT_SESSION` | Windows Terminal detection |
| `COLORFGBG` | Dark/light mode detection |
| `DISPLAY` | X11 display for clipboard |
| `WAYLAND_DISPLAY` | Wayland display for clipboard |
| `XDG_SESSION_TYPE` | Session type for Wayland detection |
| `TERMUX_VERSION` | Termux environment detection |

### Proxy

| Variable | Purpose |
|----------|---------|
| `HTTP_PROXY` / `http_proxy` | HTTP proxy |
| `HTTPS_PROXY` / `https_proxy` | HTTPS proxy |
| `NO_PROXY` / `no_proxy` | Proxy bypass list |

---

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `~/.pi/agent/` | R/W | Global config root | Yes |
| `~/.pi/agent/auth.json` | R/W | Credentials (API keys + OAuth) | Yes |
| `~/.pi/agent/settings.json` | R/W | User settings | Yes |
| `~/.pi/agent/models.json` | R | Custom model definitions | No (user-created) |
| `~/.pi/agent/pi-debug.log` | W | Debug output | Yes |
| `~/.pi/agent/sessions/` | R/W | Session storage root | Yes |
| `~/.pi/agent/sessions/<encoded-cwd>/session.jsonl` | R/W | Session conversation history | Yes |
| `~/.pi/agent/themes/` | R | Custom themes | No (user-created) |
| `~/.pi/agent/bin/` | R/W | Managed binaries (fd, rg) | Yes |
| `~/.pi/agent/bin/fd` | R/W | fd binary | Yes (downloaded) |
| `~/.pi/agent/bin/rg` | R/W | rg (ripgrep) binary | Yes (downloaded) |
| `~/.pi/agent/tools/` | R/W | Tools directory | Yes |
| `~/.pi/agent/prompts/` | R | Prompt templates | No (user-created) |
| `~/.pi/agent/git/<host>/<path>/` | R/W | Git package installs | Yes |
| `~/.pi/agent/extensions/` | R | Global extensions | No (user-created) |
| `~/.pi/agent/sandbox.json` | R | Sandbox config (optional ext) | No (user-created) |
| `<cwd>/.pi/settings.json` | R/W | Project settings | Yes |
| `<cwd>/.pi/extensions/` | R | Project extensions | No (user-created) |
| `<cwd>/.pi/npm/` | R/W | Project npm packages | Yes |
| `<cwd>/.pi/git/` | R/W | Project git packages | Yes |
| `<cwd>/.pi/sandbox.json` | R | Project sandbox config | No (user-created) |
| `<cwd>/.git/HEAD` | R | Git branch detection | No |
| `<cwd>/AGENTS.md` | R | Agent instructions | No |
| `<cwd>/CLAUDE.md` | R | Agent instructions (alt) | No |
| `<cwd>/.gitignore` | R | Ignore patterns | No |
| `$TMPDIR/pi-bash-<hex>.log` | R/W | Bash output overflow | Yes |
| `$TMPDIR/pi-editor-<ts>.pi.md` | R/W | External editor temp | Yes |
| `$TMPDIR/pi-extensions/` | R/W | Temp package installs | Yes |
| `~/.config/gcloud/application_default_credentials.json` | R | Google ADC check | No |
| `~/.aws/credentials`, `~/.aws/config` | R | AWS credentials (via SDK) | No |
| Any file in `<cwd>` tree | R/W | Agent read/write/edit tools | Varies |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `api.anthropic.com` | LLM inference | When Anthropic provider selected |
| `api.openai.com` | LLM inference | When OpenAI provider selected |
| `generativelanguage.googleapis.com` | LLM inference | When Gemini provider selected |
| `<loc>-aiplatform.googleapis.com` | LLM inference | When Vertex AI configured |
| `bedrock-runtime.<region>.amazonaws.com` | LLM inference | When Bedrock configured |
| `<resource>.openai.azure.com` | LLM inference | When Azure OpenAI configured |
| `api.individual.githubcopilot.com` | LLM inference | When GitHub Copilot configured |
| `api.groq.com` | LLM inference | When Groq configured |
| Various OpenAI-compatible endpoints | LLM inference | When other providers configured |
| `registry.npmjs.org` | Version check, package installs | Startup, extension install |
| `api.github.com` | fd/rg release checks | Tool binary updates |
| `github.com` | fd/rg downloads, git clones | Tool binary downloads, git packages |
| `claude.ai` | Anthropic OAuth | During Anthropic login |
| `console.anthropic.com` | Anthropic OAuth token | During Anthropic login |
| `github.com/login/*` | GitHub OAuth | During GitHub Copilot login |
| `accounts.google.com` | Google OAuth | During Google login |
| `oauth2.googleapis.com` | Google token exchange | During Google login |
| `cloudcode-pa.googleapis.com` | Antigravity project discovery | During Antigravity setup |
| `auth.openai.com` | OpenAI Codex OAuth | During OpenAI login |
| `www.googleapis.com` | Google user info | During Google login |
| `pi.dev/session/` | Session share viewer | When sharing sessions |
| `127.0.0.1:51121` | Antigravity OAuth callback | During Antigravity login |
| `127.0.0.1:8085` | Gemini CLI OAuth callback | During Gemini login |
| `127.0.0.1:1455` | OpenAI Codex OAuth callback | During OpenAI login |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Shell execution | `spawn()` via configured shell | Agent bash tool -- runs arbitrary commands |
| File read/write/edit | Node.js `fs` module | Agent tools -- reads/writes project files |
| Clipboard write (text) | `pbcopy` (macOS), OSC 52 | Copy to clipboard |
| Clipboard read (image) | `@mariozechner/clipboard` native module | Paste images into conversation |
| Browser launch | `exec("open")` / `exec("xdg-open")` | OAuth login flows |
| HTTP port binding | `http.createServer` | OAuth callback servers (temporary) |
| Tool binary download | `fetch()` to GitHub releases | fd/rg auto-install |
| Package management | `npm install`, `git clone` | Extension installation |
| External editor | `spawnSync($VISUAL/$EDITOR)` | `/editor` command |
| GitHub CLI | `spawnSync("gh")` | Session sharing |
| File watching | `fs.watch()` | Git HEAD, theme files |
| Process group kill | `process.kill(-pid, "SIGKILL")` | Bash tool cancellation |
| Archive extraction | `spawnSync("tar")` | fd/rg install |

---

## 12. Sandboxing Recommendations

**Critical restrictions needed:**
1. **Shell execution** -- The bash tool runs arbitrary commands with full user permissions. This is the primary attack surface.
2. **File system access** -- The agent reads/writes files anywhere accessible to the user. No built-in path restrictions.
3. **Network access** -- Unrestricted outbound network to LLM providers, npm registry, GitHub, and any URL the agent shell commands access.

**What to allow:**
- Network access to configured LLM provider endpoints
- Read/write access to the working directory (scoped)
- Read/write access to `~/.pi/agent/` for config/state
- Read access to `~/.config/gcloud/` and `~/.aws/` for cloud credentials
- Localhost port binding on ports 51121, 8085, 1455 for OAuth callbacks
- `$TMPDIR` access for temporary files

**Known gaps:**
- No built-in sandboxing by default -- all tools run with full user permissions
- Optional sandbox extension exists (`@anthropic-ai/sandbox-runtime`) but must be explicitly enabled
- Extensions can register arbitrary tools, spawn processes, access filesystem, and make network requests
- Package manager can `npm install` and `git clone` arbitrary packages
- Auto-downloads binaries from GitHub (fd, rg) without verification beyond HTTPS

**Recommended isolation strategy:**
- Use the built-in optional sandbox extension (`pi -e ./sandbox`) for basic OS-level restrictions
- Container-based isolation for stronger guarantees
- Network egress filtering to restrict to configured LLM endpoints
- Restrict the `~/.pi/agent/auth.json` file to prevent credential exfiltration
