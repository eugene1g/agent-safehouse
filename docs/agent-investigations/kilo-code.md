# Kilo Code -- Sandbox Analysis Report

**Analysis Date:** 2025-07-01
**Repository:** https://github.com/Kilo-Org/kilocode
**Git Commit:** `7dace4a790cbaa80cdf812cab229a88f531e19ae`
**Latest Version:** 5.7.0
**License:** Open source
**Source Availability:** Open source

---

## 1. Overview

Kilo Code is a VS Code extension and a fork of Cline/Roo Code. It retains much of the Roo Code architecture but adds Kilo-specific branding, cloud services, an agent manager, autocomplete, STT (speech-to-text), contribution tracking, managed code indexing, and a device auth flow. Changes from the upstream are marked throughout the codebase with `// kilocode_change` comments.

The extension is built with TypeScript and runs inside VS Code's extension host (Node.js). It provides an agentic coding assistant via sidebar webview, tab panel, agent manager panel, and browser session panel. The publisher is `kilocode`, and it requires VS Code `^1.84.0` and Node.js `20.20.0`.

## 2. UI & Execution Modes

### Webview Architecture

Kilo Code uses **React** for its webview UI, built with **Vite**. The webview-ui package is a full React application using:

- **React 18** with `react-dom`
- **Radix UI** components (dialog, dropdown, select, tabs, tooltip, etc.)
- **Tailwind CSS 4** for styling
- **Jotai** for state management
- **TanStack React Query** for async state
- **Mermaid** for diagram rendering
- **KaTeX** for math rendering
- **React Markdown** with remark-gfm and rehype plugins
- **Shiki** for syntax highlighting
- **React Virtuoso** for virtualized lists
- **PostHog JS** for webview-side analytics

Source: `webview-ui/package.json`

### Webview Panels

The extension creates multiple webview surfaces:

1. **Sidebar Webview** (`kilo-code.SidebarProvider`) -- The primary UI, registered as a `WebviewView` in the activity bar.
2. **Tab/Editor Panel** (`kilo-code.TabPanelProvider`) -- A `WebviewPanel` opened via the "Open in New Tab" command.
3. **Agent Manager Panel** -- A separate webview for multi-agent orchestration (`agent-manager.html`).
4. **Browser Session Panel** -- Managed via `BrowserSessionPanelManager.ts` for displaying browser automation screenshots.

```typescript
// src/core/webview/ClineProvider.ts
public static readonly sideBarId = `${Package.name}.SidebarProvider`
public static readonly tabPanelId = `${Package.name}.TabPanelProvider`
```

The webview HTML entry points are:
- `webview-ui/index.html` (main chat UI)
- `webview-ui/agent-manager.html` (agent manager)
- `webview-ui/browser-panel.html` (browser panel)

### Execution Modes

- **IDE Extension** -- Primary mode, running as a VS Code extension with sidebar and tab panels.
- **CLI Mode** -- Indicated by `process.env.KILO_CLI_MODE` flag, with session data stored in `{globalStorage}/sessions/`.

## 3. Authentication & Credentials

### 3.1 Credential Storage (VS Code SecretStorage)

Kilo Code uses VS Code's `SecretStorage` API (which wraps macOS Keychain on macOS) as its **primary credential store** for all API keys. The `ContextProxy` class initializes by loading all secret keys from `context.secrets`:

```typescript
// src/core/config/ContextProxy.ts
const promises = [
    ...SECRET_STATE_KEYS.map(async (key) => {
        try {
            this.secretCache[key] = await this.originalContext.secrets.get(key)
        } catch (error) { ... }
    }),
    ...GLOBAL_SECRET_KEYS.map(async (key) => {
        try {
            this.secretCache[key] = await this.originalContext.secrets.get(key)
        } catch (error) { ... }
    }),
]
```

### 3.2 API Key Sources and Priority Order

From `packages/types/src/global-settings.ts`:

```typescript
export const SECRET_STATE_KEYS = [
    "apiKey",              // Anthropic API key
    "glamaApiKey",
    "openRouterApiKey",
    "awsAccessKey", "awsApiKey", "awsSecretKey", "awsSessionToken",
    "openAiApiKey",
    "ollamaApiKey",
    "geminiApiKey",
    "openAiNativeApiKey",
    "cerebrasApiKey",
    "deepSeekApiKey",
    "doubaoApiKey",
    "moonshotApiKey",
    "mistralApiKey",
    "minimaxApiKey",
    "unboundApiKey",
    "requestyApiKey",
    "xaiApiKey",
    "groqApiKey",
    "chutesApiKey",
    "litellmApiKey",
    "deepInfraApiKey",
    "codeIndexOpenAiKey",
    "codeIndexQdrantApiKey",
    "kilocodeToken",
    "syntheticApiKey",
    "ovhCloudAiEndpointsApiKey",
    "inceptionLabsApiKey",
    "codebaseIndexOpenAiCompatibleApiKey",
    "codebaseIndexGeminiApiKey",
    "codebaseIndexMistralApiKey",
    "codebaseIndexVercelAiGatewayApiKey",
    "codebaseIndexOpenRouterApiKey",
    "huggingFaceApiKey",
    "sambaNovaApiKey",
    "zaiApiKey",
    "fireworksApiKey",
    "featherlessApiKey",
    "ioIntelligenceApiKey",
    "vercelAiGatewayApiKey",
    "sapAiCoreServiceKey",
    "basetenApiKey",
    "corethinkApiKey",
] as const

export const GLOBAL_SECRET_KEYS = [
    "openRouterImageApiKey",
    "kiloCodeImageApiKey",
] as const
```

### 3.3 OAuth Flows

Separate OAuth credential stores exist for:

- **Claude Code OAuth** -- Stored in VS Code secrets under key `claude-code-oauth-credentials` (access/refresh tokens for Anthropic OAuth). Opens browser for authorization, binds local callback server on port `54545`.
- **OpenAI Codex OAuth** -- Similar pattern for OpenAI Codex.
- **MCP OAuth** -- `McpOAuthTokenStorage` uses VS Code's `SecretStorage` for MCP server OAuth tokens. Binds local callback on port `33418`.

```typescript
// src/integrations/claude-code/oauth.ts
const CLAUDE_CODE_CREDENTIALS_KEY = "claude-code-oauth-credentials"
```

### 3.4 Credential File Locations and Formats

**Per-Profile Secret Storage:** The `ProviderSettingsManager` stores provider profiles in VS Code's `globalState` under a scoped key prefix (`roo_cline_config_`), but secret fields within profiles are stored via `context.secrets` with the profile ID as part of the key.

**GlobalState Usage:** VS Code's `globalState` is used extensively for non-secret settings (mode preferences, custom instructions, task history, telemetry settings, provider profiles, etc.). Settings sync registers specific keys:

```typescript
// src/services/settings-sync/SettingsSyncService.ts
private static readonly SYNC_KEYS = [
    "allowedCommands", "deniedCommands", "autoApprovalEnabled",
    "fuzzyMatchThreshold", "diffEnabled", "directoryContextAddedContext",
    "language", "customModes", "firstInstallCompleted", "telemetrySetting",
]
```

**.env File Reading:** The extension entry point reads `.env` files from the extension's dist directory at startup:

```typescript
// src/extension.ts
import * as dotenvx from "@dotenvx/dotenvx"
const envPath = path.join(__dirname, "..", ".env")
dotenvx.config({ path: envPath })
```

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

| Path | Description |
|---|---|
| `~/.kilocode/` | Global config directory |
| `~/.kilocode/skills/` | Global skills |
| `~/.kilocode/rules/` | Global rules |
| `~/.kilocode/mcp/` | Fallback MCP servers directory |
| `~/.roo/` | Legacy global config (fallback) |

```typescript
// src/services/roo-config/index.ts
export function getGlobalRooDirectory(): string {
    const homeDir = os.homedir()
    const kiloDir = path.join(homeDir, ".kilocode")
    const rooDir = path.join(homeDir, ".roo")  // legacy fallback
    if (fsSync.existsSync(rooDir) && !fsSync.existsSync(kiloDir)) {
        return rooDir
    }
    return kiloDir
}
```

### 4.2 Project-Level Config Paths

| Path | Description |
|---|---|
| `{workspace}/.kilocode/rules/` | Agent rules (instructions) |
| `{workspace}/.kilocode/workflows/` | Workflow definitions |
| `{workspace}/.kilocode/mcp.json` | Project-level MCP server config |
| `{workspace}/.kilocode/skills/` | Project-level skills |
| `{workspace}/.kilocodemodes` | Project-level custom mode definitions |
| `{workspace}/.kilocodeignore` | Ignore patterns (like .gitignore for LLM access) |
| `{workspace}/.roo/commands/` | Slash command definitions (legacy path) |

### 4.3 System/Enterprise Config Paths (MDM)

```typescript
// src/services/mdm/MdmService.ts
case "darwin":
    return `/Library/Application Support/RooCode/${configFileName}`  // mdm.json or mdm.dev.json
case "linux":
    return `/etc/roo-code/${configFileName}`
case "win32":
    return path.join(process.env.PROGRAMDATA || "C:\\ProgramData", "RooCode", configFileName)
```

### 4.4 Data & State Directories

The extension uses VS Code's `globalStorageUri` as its primary data root. On macOS, this resolves to:

```
~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/
```

Users can configure `kilo-code.customStoragePath` in VS Code settings to redirect all storage to a custom location.

```typescript
// src/utils/storage.ts
export async function getTaskDirectoryPath(globalStoragePath: string, taskId: string): Promise<string> {
    const basePath = await getStorageBasePath(globalStoragePath)
    const taskDir = path.join(basePath, "tasks", taskId)
    await fs.mkdir(taskDir, { recursive: true })
    return taskDir
}

export async function getSettingsDirectoryPath(globalStoragePath: string): Promise<string> {
    const basePath = await getStorageBasePath(globalStoragePath)
    const settingsDir = path.join(basePath, "settings")
    ...
}

export async function getCacheDirectoryPath(globalStoragePath: string): Promise<string> {
    const basePath = await getStorageBasePath(globalStoragePath)
    const cacheDir = path.join(basePath, "cache")
    ...
}

export function getLancedbVectorStoreDirectoryPath(globalStoragePath: string): string {
    const basePath = getStorageBasePathSync(globalStoragePath)
    const cacheDir = path.join(basePath, "vector")
    ...
}
```

| Path | Description |
|---|---|
| `{globalStorage}/tasks/{taskId}/` | Task conversation histories |
| `{globalStorage}/settings/` | Extension settings directory |
| `{globalStorage}/settings/mcp_settings.json` | MCP server configuration |
| `{globalStorage}/settings/custom_modes.yaml` | Custom mode definitions |
| `{globalStorage}/cache/` | Cache directory |
| `{globalStorage}/vector/` | LanceDB vector store for code indexing |
| `{globalStorage}/puppeteer/` | Chromium browser download + snapshots |
| `{globalStorage}/sessions/` | CLI session data (per workspace hash) |

Per-task files (`tasks/{taskId}/`):

| File | Description |
|---|---|
| `api_conversation_history.json` | Full API message history |
| `ui_messages.json` | UI-facing chat messages |
| `task_metadata.json` | Task metadata |

### 4.5 Workspace Files Read

| Path | Description |
|---|---|
| `{workspace}/.kilocode/rules/` | Agent rules/instructions |
| `{workspace}/.kilocode/workflows/` | Workflow definitions |
| `{workspace}/.kilocodemodes` | Custom mode definitions |
| `{workspace}/.kilocodeignore` | Ignore patterns |
| `{workspace}/.roo/commands/` | Slash commands (legacy) |

### 4.6 Temp Directory Usage

**Shell Integration Temp Directories:** The `ShellIntegrationManager` creates temporary directories in `os.tmpdir()` for zsh ZDOTDIR overrides:

```typescript
// src/integrations/terminal/ShellIntegrationManager.ts
const tmpDir = path.join(os.tmpdir(), `roo-zdotdir-${Math.random().toString(36).substring(2, 15)}`)
```

These are cleaned up on terminal close or when shell integration becomes available.

**tmp Module:** The `tmp` npm package (`^0.2.3`) is listed as a dependency, used for various temporary file operations throughout the codebase.

**Contribution Tracking Formatter:**

```typescript
// src/services/contribution-tracking/FormatterService.ts
const tempFileName = `.kilo-format-temp-${uniqueId}${ext}`
```

This creates temporary files in the workspace for formatting operations.

**Storage Write Test:**

```typescript
// src/utils/storage.ts (getStorageBasePathSync)
const testFile = path.join(customStoragePath, ".write_test")
fsSync.writeFileSync(testFile, "test")
fsSync.rmSync(testFile)
```

### MCP Server Directories (Platform-Specific)

```typescript
// src/core/webview/ClineProvider.ts
if (process.platform === "win32") {
    mcpServersDir = path.join(os.homedir(), "AppData", "Roaming", "Kilo-Code", "MCP")
} else if (process.platform === "darwin") {
    mcpServersDir = path.join(os.homedir(), "Documents", "Kilo-Code", "MCP")
} else {
    mcpServersDir = path.join(os.homedir(), ".local", "share", "Kilo-Code", "MCP")
}
// Fallback:
path.join(os.homedir(), ".kilocode", "mcp")
```

### Kilo Config File

The `getKilocodeConfig()` utility reads a Kilo-specific configuration file (referenced in `src/utils/kilo-config-file.ts`).

## 5. Tools Available to the LLM

The following tools are exposed to the LLM for use during agentic sessions:

| Tool | Description |
|---|---|
| `ExecuteCommandTool` | Runs arbitrary shell commands via VS Code Terminal API with shell integration |
| `WriteToFileTool` | Writes entire files to the workspace |
| `ApplyDiffTool` | Applies unified diffs to existing files |
| `SearchAndReplaceTool` / `SearchReplaceTool` | Search and replace operations in files |
| `editFileTool` (Kilo-specific) | Kilo's custom file editing tool |
| Ripgrep search | File content searching via bundled `rg` binary |
| File search | File name searching |
| `BrowserSession` (Puppeteer) | LLM-driven browser automation (navigate, click, type, screenshot) via headless Chromium |
| `UrlContentFetcher` | Fetches and renders web page content |
| Git operations (via simple-git) | Checkpoint operations, worktree management |
| MCP tools | Any tools provided by configured MCP servers |

The `DiffViewProvider` shows diffs in VS Code editor using virtual document scheme `kilo-code-diff`.

## 6. Host System Interactions

### 6.1 Subprocess Execution

**Terminal Command Execution (Primary):** The `ExecuteCommandTool` runs commands via VS Code Terminal API with shell integration:

```typescript
// src/integrations/terminal/Terminal.ts
this.terminal = terminal ?? vscode.window.createTerminal({ cwd, name: "Kilo Code", iconPath, env })
```

**Ripgrep (Search):** Spawns the bundled VS Code ripgrep binary:

```typescript
// src/services/ripgrep/index.ts
import * as childProcess from "child_process"
// Executes the rg binary from vscode.env.appRoot
```

**FFmpeg (Speech-to-Text):**

```typescript
// src/services/stt/FFmpegCaptureService.ts
import { spawn, ChildProcess } from "child_process"
// Spawns ffmpeg for audio capture from microphone
```

**Agent Runtime Process (Agent Manager):** Forks Node.js child processes for agent-runtime:

```typescript
// src/core/kilocode/agent-manager/RuntimeProcessHandler.ts
import { fork, type ChildProcess } from "node:child_process"
// Forks agent-runtime-process.js for each agent session
```

**Git Operations (via simple-git):**

```typescript
// src/services/checkpoints/ShadowCheckpointService.ts
import simpleGit, { SimpleGit } from "simple-git"
// Used for checkpoint operations (shadow git repositories)
```

Also used in:
- `src/core/kilocode/agent-manager/WorktreeManager.ts` -- Git worktree management
- `src/core/kilocode/agent-manager/AgentTaskRunner.ts` -- Git operations for agent tasks
- `src/shared/kilocode/cli-sessions/core/GitStateService.ts` -- Git state tracking

**Other subprocess users:**
- `src/services/search/file-search.ts` -- Uses child_process to run ripgrep
- `src/utils/lancedb-manager.ts` -- Uses child_process for lancedb operations
- `src/utils/countTokens.ts`, `src/workers/countTokens.ts` -- Uses workerpool for token counting in separate threads
- `src/services/commit-message/GitExtensionService.ts` -- Uses child_process for git diff operations

### 6.2 Network Requests

**API Provider Endpoints:**

| Provider | Endpoint Pattern |
|---|---|
| **Kilo Code API** | `https://api.kilo.ai/api/...` |
| **OpenRouter** | `https://openrouter.ai/api/v1/...` |
| **Anthropic** | `https://api.anthropic.com/...` |
| **OpenAI** | `https://api.openai.com/v1/...` |
| **Google Vertex AI** | `https://aiplatform.googleapis.com/v1/...` |
| **AWS Bedrock** | AWS SDK endpoints |
| **Ollama** | Local `http://localhost:11434/...` |
| **LM Studio** | Local endpoints |
| **Cerebras** | Cerebras cloud SDK |
| **Mistral** | Mistral AI SDK |
| **DeepSeek** | DeepSeek API |
| **Google Gemini** | Google GenAI SDK |

**Kilo Code Services:**

| Endpoint | Purpose |
|---|---|
| `https://api.kilo.ai/api/profile` | User profile |
| `https://api.kilo.ai/api/profile/balance` | Balance check |
| `https://api.kilo.ai/api/openrouter/...` | Proxied OpenRouter |
| `https://api.kilo.ai/api/organizations/...` | Organization management |
| `https://api.kilo.ai/api/users/notifications` | Notifications |
| `https://api.kilo.ai/payments/topup` | Payment top-up |
| `https://app.kilo.ai/share/...` | Share URLs |
| `https://ai-attribution.kiloapps.io/attributions/track` | Contribution tracking |

**OAuth Endpoints:**

| Service | Endpoints |
|---|---|
| **Claude Code OAuth** | `https://claude.ai/oauth/authorize`, `https://console.anthropic.com/v1/oauth/token` |
| **OpenAI Codex OAuth** | OpenAI auth endpoints |
| **MCP OAuth** | Dynamic per-server |

**Telemetry:**

| Service | Endpoint |
|---|---|
| **PostHog** | `https://us.i.posthog.com` |

**Browser Discovery:**

```typescript
// src/services/browser/browserDiscovery.ts
await axios.get(`${chromeHostUrl}/json/version`, { timeout: 1000 })
```

Probes local Chrome DevTools Protocol endpoints.

### 6.3 Port Binding

| OAuth Flow | Default Port |
|---|---|
| Claude Code OAuth | `54545` |
| MCP OAuth | `33418` |
| OpenAI Codex OAuth | Configured per flow |

```typescript
// src/services/mcp/oauth/McpOAuthBrowserFlow.ts
server.listen(DEFAULT_AUTH_FLOW_PORT, "127.0.0.1")  // 33418

// src/integrations/claude-code/oauth.ts
server.listen(CLAUDE_CODE_OAUTH_CONFIG.callbackPort, () => { ... })  // 54545
```

### 6.4 Browser Launching

**External Browser (Links):**

```typescript
// src/activate/registerCommands.ts
vscode.env.openExternal(vscode.Uri.parse(getAppUrl()))

// src/core/mentions/index.ts
vscode.env.openExternal(vscode.Uri.parse(mention))  // URL mentions

// src/core/checkpoints/index.ts
await vscode.env.openExternal(vscode.Uri.parse("https://git-scm.com/downloads"))

// OAuth flows open browser for authorization
await vscode.env.openExternal(vscode.Uri.parse(authUrl))
```

**Headless Chromium (Puppeteer):**

Two services download and launch Chromium via `puppeteer-chromium-resolver`:

1. **BrowserSession** -- For LLM-driven browser automation (navigate, click, type, screenshot)
2. **UrlContentFetcher** -- For fetching and rendering web page content

```typescript
// src/services/browser/BrowserSession.ts
const puppeteerDir = path.join(globalStoragePath, "puppeteer")
// Downloads Chromium to {globalStorage}/puppeteer/.chromium-browser-snapshots/
const stats: PCRStats = await PCR({ downloadPath: puppeteerDir })
this.browser = await stats.puppeteer.launch({
    args: ["--user-agent=...", "--disable-gpu", ...],
    headless: true,
    executablePath: stats.executablePath,
})
```

### 6.5 Clipboard Access

Used for reading terminal contents (fallback when shell integration is unavailable):

```typescript
// src/integrations/terminal/Terminal.ts
const tempCopyBuffer = await vscode.env.clipboard.readText()
// ... copies terminal content via clipboard ...
let terminalContents = (await vscode.env.clipboard.readText()).trim()
await vscode.env.clipboard.writeText(tempCopyBuffer)  // restore original
```

Also used for:
- Copying content to clipboard from webview
- GitHub URL handling fallback

### 6.6 File System Watchers

| Watcher | Pattern | Source |
|---|---|---|
| Workspace files | `**` (all files) | `WorkspaceTracker.ts` |
| `.kilocodeignore` | `.kilocodeignore` | `RooIgnoreController.ts` |
| MCP settings (global) | `mcp_settings.json` | `McpHub.ts` (via chokidar) |
| MCP settings (project) | `.kilocode/mcp.json` | `McpHub.ts` (via VS Code watcher) |
| Custom modes | `custom_modes.yaml` | `CustomModesManager.ts` |
| Skills directories | `.kilocode/skills/` | `SkillsManager.ts` |
| Code index files | Various patterns | `file-watcher.ts` (code-index) |
| Workspace folders | Workspace folder changes | `McpHub.ts` |
| Network proxy config | VS Code config changes | `networkProxy.ts` |

### 6.7 Other

**IPC (Inter-Process Communication):**

- **node-ipc** -- Used for the extension API (allows external processes to communicate with the extension)
- **Node.js fork() IPC** -- Agent Manager communicates with agent-runtime child processes via `process.send()` / `process.on('message')`
- **socket.io-client** -- Used in some provider implementations and the STT service

```typescript
// src/extension/api.ts
ipc.listen()  // node-ipc server for external API access
```

**Text-to-Speech:** Uses the `say` npm package which invokes system TTS:

```typescript
// src/utils/tts.ts
// Uses the 'say' package which calls macOS 'say' command, Windows SAPI, or Linux espeak
```

**Speech-to-Text:** The `FFmpegCaptureService` spawns FFmpeg for microphone capture, and `OpenAIWhisperClient` sends audio to OpenAI's Whisper API.

**Machine ID / Telemetry Identifiers:**

```typescript
// src/core/webview/ClineProvider.ts
const machineId = vscode.env.machineId  // VS Code's machine identifier

// packages/telemetry/src/PostHogTelemetryClient.ts
private distinctId: string = vscode.env.machineId
```

The `node-machine-id` package is also a dependency, though usage appears limited.

**Global Agent (Network Proxy):**

```typescript
// src/utils/networkProxy.ts
// Uses global-agent to globally route all HTTP/HTTPS traffic through a debug proxy
```

**Terminal Creation (VS Code Terminal API):**

- **Kilo Code Terminal** -- Created per-task via `vscode.window.createTerminal()` with custom environment
- **Session Terminal Manager** -- `SessionTerminalManager.ts` manages terminals for agent manager sessions
- **Setup Script Runner** -- `SetupScriptRunner.ts` runs setup scripts in terminals

The terminal creation injects custom environment variables:

```typescript
// src/integrations/terminal/Terminal.ts
const env = Terminal.getEnv()  // Customized environment for shell integration
```

**MCP Server Launching:**

The `McpHub` launches MCP servers as child processes:

```typescript
// src/services/mcp/McpHub.ts
// StdioClientTransport spawns MCP server processes
// SSEClientTransport connects to HTTP-based MCP servers
// StreamableHTTPClientTransport for newer HTTP protocol
```

Environment variables from the config and `process.env` are passed to spawned MCP servers.

## 7. Extension Points

### 7.1 Hook/Lifecycle System

No explicit hook/lifecycle system beyond VS Code extension lifecycle (`activate`/`deactivate`).

### 7.2 Plugin/Extension Architecture

Kilo Code is itself a VS Code extension. It does not have its own plugin system, but supports:

- **Custom modes** -- User-defined operating modes via `custom_modes.yaml` or `.kilocodemodes`
- **Skills** -- Project-level (`.kilocode/skills/`) and global (`~/.kilocode/skills/`) skills
- **Slash commands** -- `.roo/commands/` for command definitions
- **Workflows** -- `.kilocode/workflows/`

### 7.3 MCP Integration

The `McpHub` acts as an MCP client and supports:

- **Stdio transport** -- Spawns MCP server processes
- **SSE transport** -- Connects to HTTP-based MCP servers
- **Streamable HTTP transport** -- For newer HTTP protocol

Configuration sources:
- `{globalStorage}/settings/mcp_settings.json` (global)
- `{workspace}/.kilocode/mcp.json` (project-level)

OAuth support for MCP servers via `McpOAuthBrowserFlow` and `McpOAuthTokenStorage`.

### 7.4 Custom Commands/Skills/Agents

- **Agent Manager** -- Multi-agent orchestration with `RuntimeProcessHandler` forking agent-runtime processes, worktree management for parallel agent sessions
- **Custom Modes** -- Cloud-synced organization-managed modes
- **Autocomplete** -- Full inline code completion system with Continue.dev-derived autocomplete engine

### 7.5 SDK/API Surface

- **node-ipc** -- External API access for programmatic control of the extension from other processes
- **Extension API** -- `src/extension/api.ts` provides IPC-based API

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

No built-in sandboxing. The extension runs with the full privileges of the VS Code extension host process.

### 8.2 Permission System

- **Command approval** -- `allowedCommands` and `deniedCommands` lists for shell command execution
- **Auto-approval** -- `autoApprovalEnabled` setting with `fuzzyMatchThreshold`
- **Diff-based review** -- `diffEnabled` for file change review before applying

### 8.3 Safety Mechanisms

- `.kilocodeignore` for restricting LLM file access
- MDM enterprise configuration for managed environments

### 8.4 Known Vulnerabilities

None identified.

### 8.5 Enterprise/Managed Security Controls

**MDM Support:** `MdmService` reads enterprise MDM config from system paths (`/Library/Application Support/RooCode/mdm.json` on macOS, `/etc/roo-code/` on Linux, `%PROGRAMDATA%\RooCode\` on Windows).

## 9. Key Dependencies

| Dependency | Impact |
|---|---|
| `puppeteer-core` + `puppeteer-chromium-resolver` | Downloads and launches Chromium binary |
| `simple-git` | Spawns git subprocesses for checkpoint/worktree operations |
| `@vscode/ripgrep` | Bundled ripgrep binary for file searching |
| `chokidar` | Native filesystem watching (uses fsevents on macOS) |
| `default-shell` | Detects user's default shell |
| `node-machine-id` | Reads machine identifier (accesses system hardware IDs) |
| `say` | Invokes system TTS commands (`say` on macOS, `espeak` on Linux, SAPI on Windows) |
| `sound-play` | Plays audio files using system audio |
| `global-agent` | Globally intercepts HTTP/HTTPS for proxy routing |
| `@lancedb/lancedb` | Native database for vector embeddings (writes to disk) |
| `@qdrant/js-client-rest` | Qdrant vector DB client (network) |
| `node-ipc` | Unix/Windows IPC socket for external API |
| `workerpool` | Creates worker threads for token counting |
| `ps-list` | Lists system processes |
| `is-wsl` | Detects WSL environment |
| `tar-fs` | Extracts tar archives (marketplace skill installation) |
| `ws` | WebSocket client (used for various streaming connections) |
| `socket.io-client` | Socket.IO client for real-time connections |
| `pdf-parse` + `mammoth` + `xlsx` | File content extraction (PDF, DOCX, XLSX) |
| `web-tree-sitter` + `tree-sitter-wasms` | Code parsing via WASM tree-sitter |
| `tiktoken` + `js-tiktoken` | Token counting (may use native bindings) |
| `proper-lockfile` | File locking for concurrent access |
| `undici` | HTTP client (used for proxy-aware fetch) |
| `google-auth-library` | Google Cloud authentication (reads service account keys) |
| `@aws-sdk/*` | AWS SDK for Bedrock (reads AWS credentials from environment/files) |

## 10. Environment Variables

| Variable | Purpose |
|---|---|
| `KILOCODE_POSTHOG_API_KEY` | PostHog telemetry key (baked in at build) |
| `KILOCODE_DEV_AGENT_RUNTIME_PATH` | Dev override for agent-runtime |
| `KILO_CLI_MODE` | CLI mode flag |
| `ZDOTDIR` | Shell integration |
| `PATH` | FFmpeg discovery |
| `PROGRAMDATA` | Windows MDM path |
| `NODE_ENV` | Test detection |

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|---|---|---|---|
| `~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/` | R/W | Primary data storage root | Yes |
| `{globalStorage}/tasks/{taskId}/` | R/W | Task conversation histories | Yes |
| `{globalStorage}/settings/` | R/W | Extension settings | Yes |
| `{globalStorage}/settings/mcp_settings.json` | R/W | MCP server configuration | Yes |
| `{globalStorage}/settings/custom_modes.yaml` | R/W | Custom mode definitions | Yes |
| `{globalStorage}/cache/` | R/W | Cache directory | Yes |
| `{globalStorage}/vector/` | R/W | LanceDB vector store | Yes |
| `{globalStorage}/puppeteer/` | R/W | Chromium download/cache | Yes |
| `{globalStorage}/sessions/` | R/W | CLI session data | Yes |
| `~/.kilocode/` | R/W | Global config directory | Yes |
| `~/.kilocode/skills/` | R | Global skills | No |
| `~/.kilocode/rules/` | R | Global rules | No |
| `~/.kilocode/mcp/` | R/W | Fallback MCP dir | Yes |
| `~/.roo/` | R | Legacy global config (fallback) | No |
| `~/Documents/Kilo-Code/MCP/` (macOS) | R/W | MCP servers directory | Yes |
| `/Library/Application Support/RooCode/mdm.json` | R | MDM enterprise config | No |
| `{workspace}/.kilocode/` | R/W | Project config directory | No |
| `{workspace}/.kilocode/mcp.json` | R/W | Project MCP config | No |
| `{workspace}/.kilocode/rules/` | R | Project rules | No |
| `{workspace}/.kilocode/skills/` | R | Project skills | No |
| `{workspace}/.kilocode/workflows/` | R | Project workflows | No |
| `{workspace}/.kilocodemodes` | R/W | Project custom modes | No |
| `{workspace}/.kilocodeignore` | R | Ignore patterns | No |
| `{workspace}/.roo/commands/` | R | Slash commands (legacy) | No |
| `{workspace}/**` | R/W | Any workspace file (via LLM tools) | Yes (LLM) |
| `os.tmpdir()/roo-zdotdir-*` | R/W | Temporary shell integration dirs | Yes |
| `{workspace}/.kilo-format-temp-*` | R/W | Temporary formatting files | Yes |
| `{extensionPath}/dist/` | R | Extension bundle | No |
| `{extensionPath}/../.env` | R | Environment variables | No |
| Custom path via `kilo-code.customStoragePath` | R/W | User-configured storage | Yes |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|---|---|---|
| `https://api.kilo.ai/api/profile` | User profile | On auth |
| `https://api.kilo.ai/api/profile/balance` | Balance check | On usage |
| `https://api.kilo.ai/api/openrouter/...` | Proxied OpenRouter | LLM requests |
| `https://api.kilo.ai/api/organizations/...` | Organization management | On org access |
| `https://api.kilo.ai/api/users/notifications` | Notifications | Periodic |
| `https://api.kilo.ai/payments/topup` | Payment top-up | User action |
| `https://app.kilo.ai/share/...` | Share URLs | User action |
| `https://ai-attribution.kiloapps.io/attributions/track` | Contribution tracking | On code generation |
| `https://openrouter.ai/api/v1/...` | OpenRouter API | LLM requests |
| `https://api.anthropic.com/...` | Anthropic API | LLM requests |
| `https://api.openai.com/v1/...` | OpenAI API | LLM requests |
| `https://aiplatform.googleapis.com/v1/...` | Google Vertex AI | LLM requests |
| AWS SDK endpoints | AWS Bedrock | LLM requests |
| `http://localhost:11434/...` | Ollama (local) | LLM requests |
| `https://claude.ai/oauth/authorize` | Claude Code OAuth | OAuth flow |
| `https://console.anthropic.com/v1/oauth/token` | Claude Code token exchange | OAuth flow |
| `https://us.i.posthog.com` | PostHog telemetry | Telemetry events |
| Chrome DevTools Protocol (local) | Browser discovery | Puppeteer setup |
| MCP server URLs | MCP transports (SSE/HTTP) | MCP communication |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|---|---|---|
| Shell Commands | VS Code Terminal API | LLM-driven arbitrary command execution (user-approved) |
| File Search (ripgrep) | child_process.spawn | Bundled `rg` binary |
| Git Operations | simple-git (child_process) | Checkpoints, worktrees, commit info |
| Agent Processes | child_process.fork | Agent-runtime for parallel agents |
| MCP Servers | child_process (via MCP SDK) | Spawns configured MCP server processes |
| Chromium Browser | puppeteer-core (child_process) | Downloads + launches headless Chromium |
| FFmpeg | child_process.spawn | Audio capture for STT |
| TTS | `say` package (child_process) | System text-to-speech |
| Network: LLM APIs | HTTP/HTTPS | 30+ API providers |
| Network: Kilo Cloud | HTTPS | `api.kilo.ai`, `kiloapps.io` |
| Network: Telemetry | HTTPS | PostHog (`us.i.posthog.com`) |
| Network: OAuth | HTTPS + local HTTP server | Claude, OpenAI, MCP OAuth flows |
| Local Servers | `http.createServer` | OAuth callbacks on ports 54545, 33418 |
| IPC | node-ipc (Unix socket) | External API access |
| File Watching | VS Code FSWatcher + chokidar | Workspace, config files, ignore files |
| Clipboard | VS Code clipboard API | Terminal content reading (fallback) |
| Browser Launch | `vscode.env.openExternal` | Opens URLs in default browser |
| Worker Threads | workerpool | Token counting |
| Machine Identity | `vscode.env.machineId` | Telemetry distinct ID |
| Proxy | global-agent + undici | Debug proxy routing |
| Keychain (macOS) | VS Code SecretStorage | All API keys and OAuth tokens |
| Vector Database | LanceDB (native) | Code index embeddings (disk I/O) |

## 12. Sandboxing Recommendations

### Differences from Cline/Roo Code

Key Kilo Code additions beyond the Cline/Roo Code base that affect sandboxing:

| Feature | Description |
|---|---|
| **Kilo Code Cloud** | Integration with `api.kilo.ai` for auth, billing, organizations, model proxying |
| **Device Auth Flow** | Device-based authentication via `DeviceAuthHandler` |
| **Agent Manager** | Multi-agent orchestration with `RuntimeProcessHandler` forking agent-runtime processes |
| **Managed Code Indexing** | `ManagedIndexer` with Kilo cloud token for embedding |
| **Autocomplete** | Full inline code completion system with Continue.dev-derived autocomplete engine |
| **Speech-to-Text** | FFmpeg-based audio capture + OpenAI Whisper integration |
| **Contribution Tracking** | `ContributionTrackingService` tracking AI code attribution to `kiloapps.io` |
| **Settings Sync** | `SettingsSyncService` for VS Code Settings Sync integration |
| **Auto-Purge** | `AutoPurgeScheduler` / `AutoPurgeService` for automatic task history cleanup |
| **MDM Support** | `MdmService` reads enterprise MDM config from system paths |
| **Rebranded Paths** | `.kilocode/` instead of `.roo/`, `.kilocodemodes` instead of `.roomodes`, `.kilocodeignore` instead of `.rooignore` |
| **Default Provider** | Default provider is `kilocode` with `minimax/minimax-m2.1:free` model |
| **PostHog Telemetry** | PostHog-based analytics (vs Cline's approach) |
| **Notifications** | Server-driven notifications from `api.kilo.ai` |
| **Organization Modes** | Cloud-synced organization-managed modes |
| **Worktree Support** | Git worktree management for parallel agent sessions |
| **i18n** | Full internationalization with 20+ languages |
| **Claude Code OAuth** | Direct OAuth with Anthropic's Claude platform |
| **OpenAI Codex OAuth** | OAuth integration with OpenAI Codex |
| **Formatter Service** | AI code attribution formatting |

### Recommendations

1. **Restrict network access** -- Allow only required LLM API endpoints and Kilo cloud services; block arbitrary outbound connections from spawned processes.
2. **Sandbox shell execution** -- The `ExecuteCommandTool` allows LLM-driven arbitrary commands; wrap in seatbelt or container.
3. **Limit filesystem scope** -- Restrict access to workspace and extension storage paths; deny access to `~/.ssh`, `~/.aws`, `~/.git-credentials`, etc.
4. **Control port binding** -- Allow only OAuth callback ports (54545, 33418) on localhost.
5. **Restrict Chromium downloads** -- The Puppeteer integration downloads a full Chromium binary; consider pre-provisioning or blocking.
6. **Protect credentials** -- VS Code SecretStorage (macOS Keychain) contains all API keys; ensure spawned subprocesses cannot access the keychain.
7. **Monitor IPC** -- The node-ipc server allows external process control; restrict socket access.
8. **Limit agent forking** -- The Agent Manager forks multiple agent-runtime processes; apply process count limits.
9. **Control MCP servers** -- MCP servers are spawned as child processes with inherited environment; sanitize env vars passed to them.
10. **Telemetry** -- PostHog telemetry sends data to `us.i.posthog.com`; block if not desired.
