# Gemini CLI -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/google-gemini/gemini-cli
**Git Commit:** `099aa9621c530885fd69687953f5b1fe4bf006df`
**Latest Version:** 0.30.0-nightly.20260210.a2174751d (monorepo), latest tag v0.1.12
**License:** Open source
**Source Availability:** Open source

---

## 1. Overview

Gemini CLI is a terminal-based agentic coding assistant from Google that uses the Gemini family of AI models. It is a TypeScript/Node.js monorepo (Node.js >= 20.0.0) consisting of multiple packages: the CLI itself (`@google/gemini-cli`), a core library (`@google/gemini-cli-core`), an A2A server (`@google/gemini-cli-a2a-server`), a VS Code IDE companion (`gemini-cli-vscode-ide-companion`), and test utilities.

The CLI provides an interactive terminal UI for agentic coding tasks, supporting file editing, shell command execution, web fetching, code search, and browser automation. It includes built-in sandbox mechanisms (macOS Seatbelt, Docker, Podman) for isolating AI-driven tool execution.

## 2. UI & Execution Modes

### Primary Framework: Ink (React for the terminal)

Gemini CLI uses **Ink** (`@jrichman/ink@6.4.10`, a fork of React-Ink) to render its terminal user interface. The entire interactive UI is built with React components (`.tsx` files) rendered to the terminal via Ink.

**Evidence** from `packages/cli/src/gemini.tsx`:
```typescript
import React from 'react';
import { render } from 'ink';
import { AppContainer } from './ui/AppContainer.js';
```

The CLI contains approximately **270 `.tsx` component files** in `packages/cli/src/ui/`, including:
- Layout components (`DefaultAppLayout.tsx`, `ScreenReaderAppLayout.tsx`)
- Message renderers (`GeminiMessage.tsx`, `ToolMessage.tsx`, `UserMessage.tsx`)
- Dialog components (`SettingsDialog.tsx`, `ModelDialog.tsx`, `AuthDialog.tsx`)
- Code display (`CodeColorizer.tsx`, `DiffRenderer.tsx`, `MarkdownDisplay.tsx`)
- Input components (`Composer.tsx`, `TextInput.tsx`, `InputPrompt.tsx`)

Additional UI elements:
- **ink-gradient** and **tinygradient** for colored gradient effects
- **ink-spinner** for loading indicators
- **highlight.js / lowlight** for syntax highlighting

### Execution Modes

- **Interactive TUI** -- Primary mode using Ink-based React terminal UI.
- **Non-interactive/print** -- For scripted/CI usage.
- **DevTools service** -- Optionally connects to `gemini-cli-devtools` via WebSocket on port 25417.
- **VSCode IDE Companion** -- Separate package using Express to serve a local HTTP server for IDE integration.
- **A2A Server** -- Separate package using Express for its HTTP server (default port 41242).

The CLI does **not** serve a web UI in its core package.

## 3. Authentication & Credentials

### 3.1 Credential Storage

**Keychain Storage (macOS Keychain via keytar):**

Uses the **keytar** npm package (optional dependency) for macOS Keychain / Linux Secret Service / Windows Credential Manager integration:

```typescript
// packages/core/src/mcp/token-storage/keychain-token-storage.ts
export class KeychainTokenStorage extends BaseTokenStorage implements SecretStorage {
  private keychainAvailable: boolean | null = null;
  private keytarModule: Keytar | null = null;

  async getKeytar(): Promise<Keytar | null> {
    const moduleName = 'keytar';
    const module = await import(moduleName);
    this.keytarModule = module.default || module;
  }
}
```

Keytar service names used:
- `gemini-cli-oauth` -- for main OAuth credential storage
- MCP server-specific service names -- for MCP OAuth tokens

**Hybrid Token Storage (Keychain with file fallback):**

The `HybridTokenStorage` class first attempts to use the Keychain. If that fails (keytar not available, or keychain not working), it falls back to **encrypted file storage**:

```typescript
// packages/core/src/mcp/token-storage/hybrid-token-storage.ts
private async initializeStorage(): Promise<TokenStorage> {
  const forceFileStorage = process.env[FORCE_FILE_STORAGE_ENV_VAR] === 'true';
  if (!forceFileStorage) {
    const keychainStorage = new KeychainTokenStorage(this.serviceName);
    if (await keychainStorage.isAvailable()) {
      return keychainStorage;
    }
  }
  return new FileTokenStorage(this.serviceName);
}
```

**Encrypted File Token Storage:**

When keychain is unavailable, tokens are stored in an encrypted JSON file:
```typescript
// packages/core/src/mcp/token-storage/file-token-storage.ts
this.tokenFilePath = path.join(configDir, 'mcp-oauth-tokens-v2.json');
const salt = `${os.hostname()}-${os.userInfo().username}-gemini-cli`;
this.encryptionKey = crypto.scryptSync('gemini-cli-oauth', salt, 32);
// Uses AES-256-GCM encryption
```

### 3.2 API Key Sources and Priority Order

Gemini CLI supports **four** authentication methods, configured via the `authType` setting:

1. **OAuth2 with Google (Login with Google)** -- Primary method
2. **Gemini API Key** -- Via `GEMINI_API_KEY` environment variable
3. **Vertex AI** -- Via `GOOGLE_CLOUD_PROJECT` + `GOOGLE_CLOUD_LOCATION` or `GOOGLE_API_KEY`
4. **Compute ADC (Application Default Credentials)** -- Via Google metadata server for Cloud Shell / GCE

### 3.3 OAuth Flows

**Browser-based OAuth flow** (default):
- Uses hardcoded OAuth2 client credentials (public client for "installed applications"):
  ```typescript
  // packages/core/src/code_assist/oauth2.ts
  const OAUTH_CLIENT_ID = '<REDACTED_GOOGLE_OAUTH_CLIENT_ID>';
  const OAUTH_CLIENT_SECRET = '<REDACTED_GOOGLE_OAUTH_CLIENT_SECRET>';

  const OAUTH_SCOPE = [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];
  ```
- Starts a local HTTP server on a random port (`http://127.0.0.1:<port>/oauth2callback`)
- Opens the browser with the `open` npm package
- Receives the auth code via the callback server
- 5-minute timeout, with SIGINT cancellation support

**User code flow** (when `NO_BROWSER=true` or browser suppressed):
- Prints an auth URL to the terminal
- User manually visits URL and pastes back the authorization code via readline

After auth, fetches user info from `https://www.googleapis.com/oauth2/v2/userinfo`. Token refresh is automatic via the `OAuth2Client`.

### 3.4 Credential File Locations and Formats

| Path | Purpose |
|------|---------|
| `~/.gemini/oauth_creds.json` | OAuth credentials (legacy, migrated) |
| `~/.gemini/mcp-oauth-tokens.json` | MCP OAuth tokens (legacy) |
| `~/.gemini/mcp-oauth-tokens-v2.json` | MCP OAuth tokens (encrypted, current) |
| `~/.gemini/google_accounts.json` | Google account info cache |
| macOS Keychain (`gemini-cli-oauth`) | OAuth tokens (primary) |
| `~/.config/gcloud/` | Google Cloud SDK config (read-only) |
| Path from `GOOGLE_APPLICATION_CREDENTIALS` | ADC key file |

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths (`~/.gemini/`)

The constant `GEMINI_DIR = '.gemini'` is defined in `packages/core/src/utils/paths.ts`. The home directory can be overridden with `GEMINI_CLI_HOME`.

```typescript
// packages/core/src/config/storage.ts
static getGlobalGeminiDir(): string {
  const homeDir = homedir();
  if (!homeDir) {
    return path.join(os.tmpdir(), GEMINI_DIR);
  }
  return path.join(homeDir, GEMINI_DIR);
}
```

| Path | Purpose | R/W |
|------|---------|-----|
| `~/.gemini/settings.json` | User settings | R/W |
| `~/.gemini/memory.md` | Global memory file | R/W |
| `~/.gemini/commands/` | User-defined commands | R |
| `~/.gemini/skills/` | User-defined skills | R |
| `~/.gemini/agents/` | User agent definitions | R |
| `~/.gemini/policies/` | User policies (TOML) | R |
| `~/.gemini/acknowledgments/agents.json` | Acknowledged agents | R/W |
| `~/.gemini/projects.json` | Project registry (maps project paths to short IDs) | R/W |
| `~/.gemini/installation_id` | Installation identifier | R/W |
| `~/.agents/` | Global agents directory | R |
| `~/.agents/skills/` | Agent skills | R |

### 4.2 Project-Level Config Paths

| Path | Purpose | R/W |
|------|---------|-----|
| `.gemini/settings.json` | Workspace settings | R |
| `.gemini/memory.md` | Workspace memory | R |
| `.gemini/system.md` | Custom system prompt | R |
| `.gemini/commands/` | Project commands | R |
| `.gemini/skills/` | Project skills | R |
| `.gemini/agents/` | Project agent definitions | R |
| `.gemini/extensions/` | Extensions directory | R/W |
| `.gemini/extensions/gemini-extension.json` | Extensions config | R/W |
| `.gemini/sandbox.Dockerfile` | Custom sandbox Dockerfile | R |
| `.gemini/sandbox.venv/` | Sandbox Python venv | R/W |
| `.gemini/.env` | Environment variables (preferred) | R |
| `.geminiignore` | File ignore patterns | R |
| `.env` | Environment variables (fallback) | R |
| `.agents/skills/` | Project agent skills | R |

### 4.3 System/Enterprise Config Paths

| Path | Platform | Purpose |
|------|----------|---------|
| `/Library/Application Support/GeminiCli/settings.json` | macOS | System settings |
| `/Library/Application Support/GeminiCli/policies/` | macOS | System policies |
| `C:\ProgramData\gemini-cli\settings.json` | Windows | System settings |
| `/etc/gemini-cli/settings.json` | Linux | System settings |
| `/etc/gemini-cli/policies/` | Linux | System policies |

Overridable via:
- `GEMINI_CLI_SYSTEM_SETTINGS_PATH`
- `GEMINI_CLI_SYSTEM_DEFAULTS_PATH`

### 4.4 Data & State Directories

| Path | Purpose | R/W |
|------|---------|-----|
| `~/.gemini/tmp/` | Global temp directory | R/W |
| `~/.gemini/tmp/bin/` | Downloaded binaries (e.g., ripgrep) | R/W |
| `~/.gemini/tmp/<project-id>/` | Per-project temp directory | R/W |
| `~/.gemini/tmp/<project-id>/checkpoints/` | Git checkpoints | R/W |
| `~/.gemini/tmp/<project-id>/logs/` | Project logs | R/W |
| `~/.gemini/tmp/<project-id>/plans/` | Plans | R/W |
| `~/.gemini/tmp/<project-id>/images/` | Clipboard images temp storage | R/W |
| `~/.gemini/tmp/<project-id>/shell_history` | Shell history | R/W |
| `~/.gemini/history/` | Session history directory | R/W |
| `~/.gemini/history/<project-id>/` | Per-project session history | R/W |

### 4.5 Workspace Files Read

| Path | Purpose |
|------|---------|
| `.gemini/settings.json` | Workspace settings |
| `.gemini/memory.md` | Workspace memory |
| `.gemini/system.md` | Custom system prompt |
| `.geminiignore` | File ignore patterns |
| `.gitignore` | Git ignore patterns (also used for file exclusion) |
| `.git/logs/HEAD` | Watched for branch name changes |

### 4.6 Temp Directory Usage

**Primary temp directory strategy:**

```typescript
// packages/core/src/utils/paths.ts
export function tmpdir(): string {
  return os.tmpdir();
}
```

The system temp directory (`os.tmpdir()`) is used for:
- Test-related temp directories (via `fs.mkdtemp(path.join(os.tmpdir(), ...))`)
- The macOS Seatbelt sandbox passes `TMP_DIR` as `os.tmpdir()` resolved path

Most persistent temp files go into `~/.gemini/tmp/` (NOT `os.tmpdir()`):
- Per-project temp directories: `~/.gemini/tmp/<project-short-id>/`
- Downloaded binaries: `~/.gemini/tmp/bin/`
- Clipboard images, logs, plans, checkpoints

**IDE server port file:**

```typescript
const portDir = path.join(tmpdir(), 'gemini', 'ide');
// File: gemini-ide-server-<ppid>-<port>.json
```

**Podman auth file:**

```typescript
const emptyAuthFilePath = path.join(os.tmpdir(), 'empty_auth.json');
fs.writeFileSync(emptyAuthFilePath, '{}', 'utf-8');
```

**.env File Search Order:**

The `.env` file search walks up from `cwd`:
1. `<dir>/.gemini/.env` (preferred)
2. `<dir>/.env`
3. Walks up to parent directories
4. Falls back to `~/.gemini/.env`
5. Falls back to `~/.env`

## 5. Tools Available to the LLM

The following tools/capabilities are available to the AI during agentic sessions:

| Tool | Description |
|------|-------------|
| Shell command execution | Executes shell commands via PTY or child_process spawn |
| File read/write/edit | Reads, writes, and edits files in the workspace via Node.js `fs` module |
| Ripgrep search | File content searching via downloaded `rg` binary (cached in `~/.gemini/tmp/bin/rg`) |
| Git operations | Repository detection, branch info, diff, status, checkpoint creation via `simple-git` and `git` spawn |
| Web fetch | Fetches arbitrary HTTP/HTTPS URLs (with private IP blocking) via `web-fetch.ts` |
| MCP tools | Any tools provided by configured MCP servers (stdio, SSE, HTTP transports) |
| Editor launching | Can spawn external editors (code, vim, emacs, etc.) for diff viewing |

## 6. Host System Interactions

### 6.1 Subprocess Execution

**Shell command execution (primary tool interaction):**

The `ShellExecutionService` is the main mechanism for executing AI-requested shell commands. It supports two execution methods:

1. **PTY-based execution** (preferred): Uses `@lydell/node-pty` or `node-pty` (optional dependencies) to spawn commands in a pseudo-terminal
2. **child_process fallback**: Uses `spawn()` with `['bash', '-c', command]` or equivalent

```typescript
// packages/core/src/services/shellExecutionService.ts
const child = cpSpawn(executable, spawnArgs, {
  cwd,
  stdio: ['ignore', 'pipe', 'pipe'],
  shell: false,
  detached: !isWindows,
  env: {
    ...sanitizeEnvironment(process.env, sanitizationConfig),
    GEMINI_CLI: '1',
    TERM: 'xterm-256color',
    PAGER: 'cat',
    GIT_PAGER: 'cat',
  },
});
```

All shell executions set `GEMINI_CLI=1` in the environment.

**Ripgrep:** Downloads and caches ripgrep binary to `~/.gemini/tmp/bin/rg`. Falls back to system `rg` if available.

**Git operations:** Uses `simple-git` library and direct `spawnAsync('git', ...)` calls for repository detection, branch info, diff, status, and checkpoint creation (shadow git repos).

**Editor launching:** Can spawn external editors for diff viewing: GUI editors (`code`, `vscodium`, `windsurf`, `cursor`, `zed`, `antigravity`) and terminal editors (`vim`, `neovim`, `emacs`, `hx`).

**Sandbox execution:** Spawns one of: `sandbox-exec` (macOS Seatbelt) with `.sb` profile files, `docker run ...` (Docker container), or `podman run ...` (Podman container).

**MCP Server launching:** Uses `StdioClientTransport` from the MCP SDK to spawn MCP servers as child processes via their configured `command` and `args`.

**Clipboard operations:** On macOS, spawns `osascript -e 'clipboard info'` to check clipboard type and `osascript -e '...'` to save clipboard images. On Linux, spawns `wl-paste` or `xclip` depending on display server.

**Browser launching:** Uses the `open` npm package to launch URLs in the default browser for OAuth, documentation, bug reporting, extensions page, and DevTools UI. Also has a secure browser launcher that uses `execFile` (not `exec`) to avoid shell interpretation.

**Process relaunch:** Uses `spawn(process.execPath, nodeArgs, ...)` to relaunch itself.

**Safety checker:** Spawns safety checker processes via `spawn(checkerPath, [], {...})`.

### 6.2 Network Requests

**Gemini API / Google AI endpoints:**

The primary API interaction is through the `@google/genai` SDK (version `1.30.0`):
- Gemini API: `generativelanguage.googleapis.com`
- Vertex AI: `aiplatform.googleapis.com`
- Configurable via `GOOGLE_GEMINI_BASE_URL` and `GOOGLE_VERTEX_BASE_URL`

**Code Assist endpoint:**

```typescript
// packages/core/src/code_assist/server.ts
export const CODE_ASSIST_ENDPOINT = 'https://cloudcode-pa.googleapis.com';
```

Overridable via `CODE_ASSIST_ENDPOINT` environment variable.

**Telemetry endpoints:**

1. **Clearcut logging**: `https://play.googleapis.com/log?format=json&hasfast=true`
2. **OpenTelemetry OTLP**: Configurable via `GEMINI_TELEMETRY_OTLP_ENDPOINT` or `OTEL_EXPORTER_OTLP_ENDPOINT`
3. **Google Cloud Monitoring/Trace exporters** (when using GCP telemetry target)

**OAuth / User info:**

- Google OAuth2 authorization endpoint
- `https://www.googleapis.com/oauth2/v2/userinfo` for user profile
- `https://codeassist.google.com/authcode` for user-code auth redirect
- `https://developers.google.com/gemini-code-assist/auth_success_gemini` (success redirect)
- `https://developers.google.com/gemini-code-assist/auth_failure_gemini` (failure redirect)

**Web fetch tool:** The AI can fetch arbitrary HTTP/HTTPS URLs (with private IP blocking).

**Update checks:** Uses `latest-version` npm package to check for updates.

**MCP server connections:** Supports SSE, Streamable HTTP, and stdio transports for connecting to MCP servers.

**Proxy support:** HTTP proxy support via `https-proxy-agent` and environment variables: `HTTPS_PROXY` / `https_proxy`, `HTTP_PROXY` / `http_proxy`, `NO_PROXY` / `no_proxy`.

### 6.3 Port Binding

| Port | Purpose | Bound to |
|------|---------|----------|
| Random ephemeral | OAuth callback server | `127.0.0.1` (or `OAUTH_CALLBACK_HOST`) |
| 25417 (default) | DevTools WebSocket server | `127.0.0.1` |
| Random ephemeral | VSCode IDE Companion HTTP server | `127.0.0.1` |
| 8877 | Sandbox proxy (when `GEMINI_SANDBOX_PROXY_COMMAND` set) | localhost |
| 41242 | A2A server (default from config) | localhost |

### 6.4 Browser Launching

Uses the `open` npm package to launch URLs in the default browser for:
- OAuth authentication
- Documentation (`/docs` command)
- Bug reporting (`/bug` command)
- Extensions page (`/extensions` command)
- DevTools UI

Also has a secure browser launcher at `packages/core/src/utils/secure-browser-launcher.ts` that uses `execFile` (not `exec`) to avoid shell interpretation.

### 6.5 Clipboard Access

Full clipboard integration:
- **Text read/write**: via `clipboardy` npm package (or OSC 52 sequence for remote sessions)
- **Image read**: platform-specific (osascript on macOS, PowerShell on Windows, wl-paste/xclip on Linux)
- **Image save**: Saves clipboard images to `~/.gemini/tmp/<project-id>/images/`

### 6.6 File System Watchers

```typescript
// packages/cli/src/ui/hooks/useGitBranchName.ts
watcher = fs.watch(gitLogsHeadPath, (eventType: string) => { ... });
```

Watches `.git/logs/HEAD` to detect branch name changes in real-time.

### 6.7 Other

**System information:** Uses `systeminformation` package for system info gathering.

**Process signal handling:** Handles SIGINT/SIGTERM for graceful shutdown.

**DNS resolution:** Standard Node.js dns module (implicit).

## 7. Extension Points

### 7.1 Hook/Lifecycle System

None identified.

### 7.2 Plugin/Extension Architecture

- **Extensions directory**: `.gemini/extensions/` with `gemini-extension.json` config
- **Custom commands**: User-defined commands in `~/.gemini/commands/` and `.gemini/commands/`
- **Skills**: User-defined skills in `~/.gemini/skills/` and `.gemini/skills/`
- **Agents**: User agent definitions in `~/.gemini/agents/` and `.gemini/agents/`
- **Policies**: User policies (TOML) in `~/.gemini/policies/` and system-level policies

### 7.3 MCP Integration

Uses `@modelcontextprotocol/sdk` for MCP server connections:
- **Stdio transport** -- Spawns MCP server processes as child processes
- **SSE transport** -- Connects to HTTP-based MCP servers
- **Streamable HTTP transport** -- For newer HTTP protocol
- **MCP OAuth** -- Token storage via keychain or encrypted file

### 7.4 Custom Commands/Skills/Agents

- Custom commands in `~/.gemini/commands/` and `.gemini/commands/`
- Custom skills in `~/.gemini/skills/` and `.gemini/skills/`
- Agent definitions in `~/.gemini/agents/`, `.gemini/agents/`, `~/.agents/`
- Custom system prompt via `.gemini/system.md`
- Memory files: `~/.gemini/memory.md` and `.gemini/memory.md`

### 7.5 SDK/API Surface

- **A2A Server** (`@google/gemini-cli-a2a-server`) -- HTTP server for Agent-to-Agent protocol
- **VSCode IDE Companion** (`gemini-cli-vscode-ide-companion`) -- Local HTTP server for IDE integration
- **DevTools service** -- WebSocket server for development tools integration

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

Gemini CLI has **three built-in sandbox mechanisms**:

**a. macOS Seatbelt (sandbox-exec):**

On macOS, Seatbelt is the **default** sandbox when `sandbox-exec` is available. Six built-in profiles:

| Profile | Description |
|---------|-------------|
| `permissive-open` | Default. Permissive with network access |
| `permissive-closed` | Permissive without network access |
| `permissive-proxied` | Permissive with proxy-only network |
| `restrictive-open` | Restrictive with network access |
| `restrictive-closed` | Restrictive without network access |
| `restrictive-proxied` | Restrictive with proxy-only network |

Profile files: `packages/cli/src/utils/sandbox-macos-*.sb`

Variables passed to sandbox profiles:
- `TARGET_DIR` - current working directory
- `TMP_DIR` - system temp directory
- `HOME_DIR` - user home directory
- `CACHE_DIR` - Darwin user cache directory
- `INCLUDE_DIR_0` through `INCLUDE_DIR_4` - additional workspace directories

Configurable via:
- `SEATBELT_PROFILE` env var
- Custom `.sb` files in `.gemini/` directory

**b. Docker:**

Container sandbox using Docker. Mounts:
- Working directory
- `~/.gemini/` settings directory
- `os.tmpdir()` temp directory
- Home directory
- `~/.config/gcloud/` (read-only, if exists)
- `GOOGLE_APPLICATION_CREDENTIALS` file (read-only)
- Additional mounts from `SANDBOX_MOUNTS` env var

**c. Podman:**

Same as Docker but using Podman runtime.

The root `package.json` references a sandbox Docker image:
```json
"config": {
  "sandboxImageUri": "us-docker.pkg.dev/gemini-code-dev/gemini-cli/sandbox:0.30.0-nightly.20260210.a2174751d"
}
```

### 8.2 Permission System

N/A -- Gemini CLI relies on its sandbox mechanisms rather than a granular permission system for individual tool calls.

### 8.3 Safety Mechanisms

**Environment Variable Sanitization:**

Shell commands spawned by the AI have their environment sanitized to prevent credential leakage:
- Always allowed: `PATH`, `HOME`, `SHELL`, `TMPDIR`, `USER`, `LANG`, etc.
- Always blocked: Variables matching patterns like `TOKEN`, `SECRET`, `PASSWORD`, `KEY`, `AUTH`, `CREDENTIAL`
- Value-pattern blocked: PEM keys, JWT tokens, GitHub PATs, AWS keys, etc.

**Safety checker:** Spawns safety checker processes for content moderation.

**Private IP blocking:** Web fetch tool blocks access to private IP addresses.

### 8.4 Known Vulnerabilities

None identified.

### 8.5 Enterprise/Managed Security Controls

System-level settings and policies:
- `/Library/Application Support/GeminiCli/settings.json` (macOS)
- `/Library/Application Support/GeminiCli/policies/` (macOS)
- `/etc/gemini-cli/settings.json` (Linux)
- `/etc/gemini-cli/policies/` (Linux)
- `C:\ProgramData\gemini-cli\settings.json` (Windows)

## 9. Key Dependencies

### From `packages/cli/package.json`:

| Dependency | System Impact |
|------------|--------------|
| `ink` (`@jrichman/ink@6.4.10`) | Terminal UI rendering (raw mode, alternate screen buffer) |
| `clipboardy` | System clipboard read/write |
| `open` | Launches default browser |
| `ws` | WebSocket client (DevTools) |
| `dotenv` | Reads `.env` files |
| `shell-quote` | Shell command parsing/quoting |
| `command-exists` | Checks if commands exist on PATH |
| `extract-zip` | Zip extraction (for ripgrep download) |
| `tar` | Tar extraction |
| `undici` | HTTP client |

### From `packages/core/package.json`:

| Dependency | System Impact |
|------------|--------------|
| `google-auth-library` | Google OAuth2, ADC, Compute auth |
| `@google/genai` | Gemini API SDK (network requests) |
| `@modelcontextprotocol/sdk` | MCP server stdio/SSE/HTTP transport (spawns processes) |
| `keytar` (optional) | macOS Keychain / Linux Secret Service / Windows Credential Manager |
| `@lydell/node-pty` (optional) | Pseudo-terminal for shell commands |
| `node-pty` (optional) | Alternative PTY implementation |
| `simple-git` | Git operations |
| `@joshua.litt/get-ripgrep` | Downloads ripgrep binary |
| `systeminformation` | System info gathering |
| `web-tree-sitter` | Code parsing (may access WASM files) |
| `@xterm/headless` | Terminal emulation for command output |
| `open` | Browser launching |
| `https-proxy-agent` | HTTP proxy support |
| `@google-cloud/logging` | GCP logging |
| `@opentelemetry/*` | Telemetry collection and export |
| `fdir` | Fast directory traversal |

## 10. Environment Variables

### Auth & API

| Variable | Usage |
|----------|-------|
| `GEMINI_API_KEY` | Gemini API key |
| `GOOGLE_API_KEY` | Google API key (Vertex express) |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID |
| `GOOGLE_CLOUD_LOCATION` | GCP location |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to ADC key file |
| `GOOGLE_CLOUD_ACCESS_TOKEN` | Direct access token |
| `GOOGLE_GENAI_USE_GCA` | Use Google Code Assist |
| `GOOGLE_GENAI_USE_VERTEXAI` | Use Vertex AI |
| `GOOGLE_GEMINI_BASE_URL` | Custom Gemini API base URL |
| `GOOGLE_VERTEX_BASE_URL` | Custom Vertex AI base URL |
| `CODE_ASSIST_ENDPOINT` | Custom Code Assist endpoint |

### Sandbox

| Variable | Usage |
|----------|-------|
| `GEMINI_SANDBOX` | Sandbox mode: `false`, `true`, `docker`, `podman`, `sandbox-exec` |
| `SANDBOX` | Set inside sandbox to container name (sentinel: if set, don't re-sandbox) |
| `SEATBELT_PROFILE` | macOS Seatbelt profile name |
| `GEMINI_SANDBOX_IMAGE` | Custom sandbox Docker image |
| `GEMINI_SANDBOX_PROXY_COMMAND` | Proxy command for sandbox |
| `SANDBOX_FLAGS` | Additional Docker/Podman flags |
| `SANDBOX_MOUNTS` | Additional volume mounts (comma-separated `from:to:opts`) |
| `SANDBOX_ENV` | Additional env vars for sandbox (comma-separated `key=value`) |
| `SANDBOX_SET_UID_GID` | Force UID/GID mapping in container |
| `BUILD_SANDBOX` | Build sandbox image from source |

### Telemetry

| Variable | Usage |
|----------|-------|
| `GEMINI_TELEMETRY_ENABLED` | Enable/disable telemetry |
| `GEMINI_TELEMETRY_TARGET` | Telemetry target (e.g., `gcp`) |
| `GEMINI_TELEMETRY_OTLP_ENDPOINT` | OTLP endpoint URL |
| `GEMINI_TELEMETRY_OTLP_PROTOCOL` | OTLP protocol |
| `GEMINI_TELEMETRY_LOG_PROMPTS` | Log prompt content |
| `GEMINI_TELEMETRY_OUTFILE` | Telemetry output file path |
| `GEMINI_TELEMETRY_USE_COLLECTOR` | Use collector |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Standard OTLP endpoint fallback |

### Configuration

| Variable | Usage |
|----------|-------|
| `GEMINI_CLI_HOME` | Override home directory |
| `GEMINI_CLI_SYSTEM_SETTINGS_PATH` | Override system settings path |
| `GEMINI_CLI_SYSTEM_DEFAULTS_PATH` | Override system defaults path |
| `GEMINI_MODEL` | Override model selection |
| `GEMINI_FOLDER_TRUST` | Trust current folder |
| `GEMINI_YOLO_MODE` | Auto-approve all tool calls |
| `GEMINI_FORCE_FILE_STORAGE` | Force file-based token storage |
| `FORCE_ENCRYPTED_FILE` | Use encrypted storage for OAuth credentials |

### OAuth

| Variable | Usage |
|----------|-------|
| `NO_BROWSER` | Suppress browser launch for OAuth |
| `OAUTH_CALLBACK_HOST` | Override OAuth callback bind address (default `127.0.0.1`) |
| `OAUTH_CALLBACK_PORT` | Override OAuth callback port |

### IDE Integration

| Variable | Usage |
|----------|-------|
| `GEMINI_CLI_IDE_SERVER_PORT` | IDE companion server port |
| `GEMINI_CLI_IDE_WORKSPACE_PATH` | IDE workspace path |
| `GEMINI_CLI_IDE_AUTH_TOKEN` | IDE auth token |
| `TERM_PROGRAM` | Terminal program detection |

### Proxy

| Variable | Usage |
|----------|-------|
| `HTTPS_PROXY` / `https_proxy` | HTTPS proxy URL |
| `HTTP_PROXY` / `http_proxy` | HTTP proxy URL |
| `NO_PROXY` / `no_proxy` | Proxy bypass list |

### Misc

| Variable | Usage |
|----------|-------|
| `DEBUG` | Enable debug mode |
| `DEBUG_PORT` | Debug port for Node.js inspector |
| `BROWSER` | Browser override (blocklist check) |
| `CLOUD_SHELL` | Google Cloud Shell detection |
| `GEMINI_CLI_ACTIVITY_LOG_TARGET` | Activity logging output path |
| `GEMINI_CLI_INTEGRATION_TEST` | Integration test mode |

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `~/.gemini/` | R/W | Main config directory | Yes |
| `~/.gemini/settings.json` | R/W | User settings | Yes |
| `~/.gemini/oauth_creds.json` | R/W | OAuth credentials (legacy) | Yes |
| `~/.gemini/mcp-oauth-tokens-v2.json` | R/W | Encrypted MCP tokens | Yes |
| `~/.gemini/google_accounts.json` | R/W | Google account cache | Yes |
| `~/.gemini/installation_id` | R/W | Installation ID | Yes |
| `~/.gemini/memory.md` | R/W | Global memory | Yes |
| `~/.gemini/projects.json` | R/W | Project registry | Yes |
| `~/.gemini/tmp/**` | R/W | Temp data, downloaded binaries | Yes |
| `~/.gemini/history/**` | R/W | Session history | Yes |
| `~/.gemini/commands/` | R | Custom commands | No |
| `~/.gemini/skills/` | R | Custom skills | No |
| `~/.gemini/agents/` | R | Custom agents | No |
| `~/.gemini/policies/` | R | Custom policies | No |
| `~/.agents/` | R | Agent definitions | No |
| `<cwd>/.gemini/` | R/W | Workspace config | No |
| `<cwd>/.geminiignore` | R | Ignore patterns | No |
| `<cwd>/.env` | R | Environment variables | No |
| `/Library/Application Support/GeminiCli/` | R | System settings (macOS) | No |
| `/etc/gemini-cli/` | R | System settings (Linux) | No |
| `/tmp/gemini/ide/` | R/W | IDE server port files | Yes |
| `~/.config/gcloud/` | R | GCloud config | No |
| macOS Keychain | R/W | OAuth tokens (via keytar) | Yes |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `generativelanguage.googleapis.com` | Gemini API | LLM requests (configurable via `GOOGLE_GEMINI_BASE_URL`) |
| `aiplatform.googleapis.com` | Vertex AI | LLM requests (configurable via `GOOGLE_VERTEX_BASE_URL`) |
| `cloudcode-pa.googleapis.com` | Code Assist | Code Assist requests (configurable via `CODE_ASSIST_ENDPOINT`) |
| `accounts.google.com` | OAuth2 authorization | OAuth flow |
| `oauth2.googleapis.com` | OAuth2 token exchange | OAuth flow |
| `www.googleapis.com/oauth2/v2/userinfo` | User info | After OAuth |
| `play.googleapis.com/log` | Clearcut telemetry | Telemetry events |
| Configurable OTLP endpoint | OpenTelemetry | Telemetry events (configurable via `GEMINI_TELEMETRY_OTLP_ENDPOINT`) |
| `developers.google.com/gemini-code-assist/auth_*` | Auth redirect | OAuth flow |
| `codeassist.google.com/authcode` | User-code auth | OAuth flow |
| `registry.npmjs.org` | Update checks | On startup |
| Arbitrary HTTP/HTTPS URLs | Web fetch tool | AI-driven web fetch |
| MCP server URLs | SSE/HTTP MCP transports | MCP communication |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Shell command execution | node-pty / child_process spawn | AI-triggered, env sanitized, `GEMINI_CLI=1` set |
| File read/write/edit | Node.js `fs` module | AI-triggered |
| Git operations | simple-git / spawn git | AI-triggered |
| Gemini API calls | @google/genai SDK | Implicit on every prompt |
| Code Assist API calls | google-auth-library HTTP | Implicit |
| Web page fetching | undici/fetch | AI-triggered, private IPs blocked |
| MCP server launch | @modelcontextprotocol/sdk stdio | Config-driven |
| Browser launch (OAuth) | `open` npm package | User-triggered |
| Browser launch (docs/bug) | `open` npm package | User-triggered |
| Clipboard read/write | clipboardy / osascript | User-triggered |
| Keychain access | keytar | Implicit on auth |
| Telemetry HTTP POST | Clearcut / OTLP | Implicit |
| DevTools WebSocket | ws | Opt-in |
| Sandbox container launch | docker/podman/sandbox-exec | Config-driven |
| Ripgrep download | HTTP fetch | On first grep |
| Editor launch | spawn (code/vim/etc) | AI-triggered (diff review) |
| Port binding | net.createServer | OAuth, IDE companion, A2A server |
| fs.watch | Node.js fs | `.git/logs/HEAD` monitoring |
| System info | systeminformation | Implicit |
| Process signal handling | process.kill, SIGINT/SIGTERM | Implicit |
| DNS resolution | Node.js dns | Implicit |

## 12. Sandboxing Recommendations

1. **Use built-in sandboxing** -- Gemini CLI already provides macOS Seatbelt, Docker, and Podman sandboxes. Enable the appropriate one for the deployment environment.
2. **Prefer restrictive profiles** -- Use `restrictive-closed` or `restrictive-proxied` Seatbelt profiles instead of the default `permissive-open` for higher security.
3. **Network restrictions** -- The `permissive-open` default allows all network access. Use `*-closed` or `*-proxied` profiles to restrict AI-driven network requests.
4. **Protect credentials** -- Keychain/encrypted file tokens and OAuth credentials are accessible; ensure sandbox restricts access to `~/.gemini/oauth_creds.json` and keychain from AI-spawned processes.
5. **Environment sanitization is good but not perfect** -- The built-in env sanitization blocks many credential patterns but relies on pattern matching; custom credentials with non-standard names may leak.
6. **Control web fetch** -- The web fetch tool blocks private IPs but allows arbitrary public URLs; consider restricting further in sensitive environments.
7. **MCP server audit** -- MCP servers are spawned as child processes with their own environment; audit configured servers and their permissions.
8. **Restrict clipboard access** -- Clipboard operations use platform-specific tools (osascript, xclip); sandbox should control access to these.
9. **Limit port binding** -- OAuth callback, DevTools, IDE companion, and A2A server all bind ports; restrict to only what is needed.
10. **Telemetry** -- Clearcut and OTLP telemetry send data to Google endpoints; block if not desired with `GEMINI_TELEMETRY_ENABLED=false`.
