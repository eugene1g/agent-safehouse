# Cline -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/cline/cline
**Git Commit:** `d3918dd7dfbc4d353b60f52b80e57d3eb7be0231`
**Latest Version:** 3.58.0
**License:** Apache-2.0
**Source Availability:** Open source

---

## 1. Overview

Cline is an AI coding assistant that runs as a **VS Code extension** (and optionally as a standalone CLI). The extension is published under the name `claude-dev` by publisher `saoudrizwan`, with display name `Cline`. It requires VS Code engine `^1.84.0`.

The extension renders its UI as a sidebar webview built with React, communicates with multiple LLM providers, and executes arbitrary shell commands on behalf of the AI agent. It also has a standalone/CLI mode that runs outside VS Code using a gRPC-based ProtoBus server.

**Latest Tag:** `cli-build-024bb65`
**package.json name:** `claude-dev`

---

## 2. UI & Execution Modes

### Webview Architecture

Cline renders its UI as a **VS Code sidebar webview** using **React** (not Svelte or Vue). The webview is a single-page React application built with Vite and served inside VS Code's webview panel.

**Sidebar webview registration** in `package.json`:
```json
"views": {
    "claude-dev-ActivityBar": [
        {
            "type": "webview",
            "id": "claude-dev.SidebarProvider",
            "name": ""
        }
    ]
}
```

**Webview Provider** (`src/hosts/vscode/VscodeWebviewProvider.ts`):
```typescript
export class VscodeWebviewProvider extends WebviewProvider implements vscode.WebviewViewProvider {
    public static readonly SIDEBAR_ID = ExtensionRegistryInfo.views.Sidebar
    private webview?: vscode.WebviewView

    public async resolveWebviewView(webviewView: vscode.WebviewView): Promise<void> {
        this.webview = webviewView
        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [vscode.Uri.file(HostProvider.get().extensionFsPath)],
        }
        webviewView.webview.html =
            this.context.extensionMode === vscode.ExtensionMode.Development
                ? await this.getHMRHtmlContent()
                : this.getHtmlContent()
    }
}
```

**Webview UI stack** (`webview-ui/package.json`):
- React (via `@heroui/react`, `@radix-ui/*` components)
- Vite for bundling
- Tailwind CSS for styling
- Communication with extension host via VS Code `postMessage` API, wrapped in a gRPC-like protobuf protocol

**No external browser windows are launched for the main UI.** The extension does launch the system browser via `vscode.env.openExternal()` for:
- OAuth authentication flows (OpenRouter, Requesty, OpenAI Codex, Hicap, OCA)
- Opening URLs from mention links
- Bug report URLs
- Documentation links

### Webview Panels

Only a **single sidebar webview** is created (`claude-dev.SidebarProvider`). No `createWebviewPanel` calls exist in the production code -- the extension exclusively uses the sidebar `WebviewView`.

### Execution Modes

- **VS Code extension** (primary): Sidebar webview with integrated terminal
- **Standalone/CLI mode**: Uses gRPC ProtoBus server on port 26040, stores data in `~/.cline/data/`

---

## 3. Authentication & Credentials

### 3.1 Credential Storage

#### VS Code SecretStorage (Primary Mechanism)

Cline uses **VS Code's `context.secrets` API** as its primary secret storage backend. On macOS, this wraps the system **Keychain**.

**Initialization** (`src/core/storage/StateManager.ts`):
```typescript
secretStorage.init(context.secrets)
```

**ClineSecretStorage wrapper** (`src/shared/storage/ClineSecretStorage.ts`):
```typescript
export class ClineSecretStorage extends ClineStorage {
    override readonly name = "ClineSecretStorage"
    private secretStorage: SecretStores | null = null

    public init(store: SecretStores) {
        if (!this.secretStorage) {
            this.secretStorage = store
            Logger.info("[ClineSecretStorage] initialized")
        }
    }

    protected async _store(key: string, value: string): Promise<void> {
        if (value && value.length > 0) {
            await this.storage.store(key, value)
        } else {
            await this.storage.delete(key)
        }
    }
}
```

#### Standalone Mode

When running outside VS Code (CLI/standalone mode), secrets are stored in a **plain JSON file** on disk:

**File:** `~/.cline/data/secrets.json`

(`src/standalone/vscode-context.ts`):
```typescript
const extensionContext: ExtensionContext = {
    globalState: new MementoStore(path.join(DATA_DIR, "globalState.json")),
    secrets: new SecretStore(path.join(DATA_DIR, "secrets.json")),
}
```

#### No keytar / Keychain Direct Usage

No direct `keytar` or macOS Keychain API usage was found. All keychain access goes through VS Code's `context.secrets` abstraction.

#### Secret Keys Stored

All API keys and credentials are stored via SecretStorage. The complete list of secret keys (`src/shared/storage/state-keys.ts`):

```
apiKey, clineApiKey, clineAccountId, cline:clineAccountId,
openRouterApiKey, awsAccessKey, awsSecretKey, awsSessionToken,
awsBedrockApiKey, openAiApiKey, geminiApiKey, openAiNativeApiKey,
ollamaApiKey, deepSeekApiKey, requestyApiKey, togetherApiKey,
fireworksApiKey, qwenApiKey, doubaoApiKey, mistralApiKey,
liteLlmApiKey, authNonce, asksageApiKey, xaiApiKey,
moonshotApiKey, zaiApiKey, huggingFaceApiKey, nebiusApiKey,
sambanovaApiKey, cerebrasApiKey, sapAiCoreClientId,
sapAiCoreClientSecret, groqApiKey, huaweiCloudMaasApiKey,
basetenApiKey, vercelAiGatewayApiKey, difyApiKey, minimaxApiKey,
hicapApiKey, aihubmixApiKey, nousResearchApiKey,
remoteLiteLlmApiKey, ocaApiKey, ocaRefreshToken,
mcpOAuthSecrets, openai-codex-oauth-credentials
```

### 3.2 API Key Sources and Priority Order

API keys are configured through the VS Code extension UI (sidebar webview) and stored in SecretStorage. They can also be read from environment variables in standalone mode.

### 3.3 OAuth Flows

Multiple OAuth flows are supported:
- **OpenRouter OAuth** (browser redirect)
- **OpenAI Codex OAuth** with PKCE (local HTTP server on dynamic port for callback)
- **OCA OAuth** (browser redirect)
- **Requesty OAuth** (browser redirect)
- **Hicap OAuth** (browser redirect)

### 3.4 Credential File Locations and Formats

| Location | Format | Purpose |
|----------|--------|---------|
| VS Code SecretStorage (macOS Keychain) | Encrypted | Primary credential storage |
| `~/.cline/data/secrets.json` | Plain JSON | Standalone mode secrets |
| `~/.qwen/oauth_creds.json` | JSON | Qwen Code OAuth credentials |
| `~/.oca/config.json` | JSON | Oracle Cloud config |

**External Credential Files Read:**

1. **Qwen Code OAuth credentials**: `~/.qwen/oauth_creds.json` (or custom path)
   ```typescript
   // src/core/api/providers/qwen-code.ts
   return path.join(os.homedir(), QWEN_DIR, QWEN_CREDENTIAL_FILENAME)
   ```

2. **OCA (Oracle Cloud) config**: `~/.oca/config.json`
   ```typescript
   // src/services/auth/oca/utils/constants.ts
   export const OCA_CONFIG_PATH = path.join(os.homedir(), ".oca", "config.json")
   ```

---

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

| Path | Purpose |
|---|---|
| `~/.cline/` | Cline home directory (config, data) |
| `~/.cline/endpoints.json` | On-premise/self-hosted endpoint configuration |
| `~/.cline/data/` | Standalone mode data storage |
| `~/.cline/data/globalState.json` | Standalone global state |
| `~/.cline/data/secrets.json` | Standalone secrets (plain JSON) |
| `~/.cline/data/workspaceState.json` | Standalone workspace state |
| `~/.cline/skills/` | Global skills directory |
| `~/Documents/Cline/Rules/` | Global Cline rules |
| `~/Documents/Cline/Workflows/` | Global workflows |
| `~/Documents/Cline/MCP/` | MCP server files |
| `~/Documents/Cline/Hooks/` | Global hooks scripts |
| `~/.oca/config.json` | OCA provider config (read only) |
| `~/.qwen/oauth_creds.json` | Qwen OAuth credentials |

(`src/core/storage/disk.ts`)

### 4.2 Project-Level Config Paths

| File/Dir | Purpose |
|---|---|
| `.clineignore` | File access control patterns (gitignore syntax) |
| `.clinerules` | Project-specific rules |
| `.clinerules/hooks/` | Project-specific hook scripts |
| `.clinerules/workflows/` | Project-specific workflows |
| `.clinerules/skills/` | Project-specific skills |
| `.cline/skills/` | Alternative skills location |
| `.claude/skills/` | Claude skills directory |
| `.cursor/rules/` | Cursor rules (compatibility) |
| `.cursorrules` | Cursor rules file (compatibility) |
| `.windsurfrules` | Windsurf rules (compatibility) |
| `AGENTS.md` | Agents rules file (compatibility) |

### 4.3 System/Enterprise Config Paths

N/A

### 4.4 Data & State Directories

#### VS Code Extension Storage (globalStorageFsPath)

The primary data storage location is VS Code's extension global storage directory. On macOS, this is typically:
`~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/`

Subdirectories created within globalStorage:

| Subpath | Purpose |
|---|---|
| `tasks/{taskId}/` | Per-task conversation history and metadata |
| `tasks/{taskId}/api_conversation_history.json` | API conversation history |
| `tasks/{taskId}/ui_messages.json` | UI messages |
| `tasks/{taskId}/task_metadata.json` | Task metadata (files, model usage, environment) |
| `tasks/{taskId}/context_history.json` | Context tracking history |
| `tasks/{taskId}/settings.json` | Per-task settings snapshot |
| `state/taskHistory.json` | Global task history index |
| `settings/cline_mcp_settings.json` | MCP server configuration |
| `cache/mcp_marketplace_catalog.json` | MCP marketplace catalog cache |
| `cache/remote_config_{orgId}.json` | Remote configuration cache |
| `checkpoints/{cwdHash}/.git/` | Shadow git repos for checkpoints |
| `puppeteer/` | Downloaded Chromium browser |
| `puppeteer/.chromium-browser-snapshots/` | Chromium binary cache |

#### globalState Usage

VS Code's `globalState` (Memento) is used extensively for non-sensitive settings and state. It stores model configurations, UI preferences, task history, workspace roots, feature flags, and more. See the `GLOBAL_STATE_FIELDS` and `SETTINGS_FIELDS` definitions in `src/shared/storage/state-keys.ts`.

#### SQLite Database

Cline uses `better-sqlite3` for lock management:

(`src/core/locks/SqliteLockManager.ts`):
```typescript
export class SqliteLockManager {
    private db!: Database.Database
    private dbPath: string
    // Creates .db file and .db.lock file at the configured path
}
```

The lock database is created within the globalStorage path for coordinating task and checkpoint locks.

### 4.5 Workspace Files Read

| File/Dir | Purpose |
|---|---|
| `.clineignore` | File access control patterns (gitignore syntax) |
| `.clinerules` | Project-specific rules |
| `.clinerules/hooks/` | Project-specific hook scripts |
| `.clinerules/workflows/` | Project-specific workflows |
| `.clinerules/skills/` | Project-specific skills |
| `.cline/skills/` | Alternative skills location |
| `.claude/skills/` | Claude skills directory |
| `.cursor/rules/` | Cursor rules (compatibility) |
| `.cursorrules` | Cursor rules file (compatibility) |
| `.windsurfrules` | Windsurf rules (compatibility) |
| `AGENTS.md` | Agents rules file (compatibility) |

### 4.6 Temp Directory Usage

#### ClineTempManager (Primary)

(`src/services/temp/ClineTempManager.ts`):

```typescript
class ClineTempManagerImpl {
    constructor() {
        // macOS: /var/folders/xx/.../T/cline
        // Windows: C:\Users\{user}\AppData\Local\Temp\cline
        // Linux: /tmp/cline
        const baseTempDir = os.tmpdir()
        const clineTempDir = path.join(baseTempDir, "cline")
        fs.mkdirSync(clineTempDir, { recursive: true })
        this.tempDir = clineTempDir
    }
}
```

- Creates `<os.tmpdir()>/cline/` subdirectory
- 50-hour max file age
- 2GB total size cap
- Periodic cleanup every 24 hours
- Files prefixed with descriptive names (e.g., `large-output-`, `background-`)

#### Other Temp File Usage

| Location | Purpose | Source |
|---|---|---|
| `os.tmpdir()/chrome-debug-profile/` | Chrome debug user data directory | `BrowserSession.ts` |
| `os.tmpdir()/cline_recording_*.webm` | Audio recording temp files | `AudioRecordingService.ts` |
| `os.tmpdir()/cline-system-prompt-*.txt` | Claude Code system prompt temp files | `integrations/claude-code/run.ts` |
| `os.tmpdir()/temp_image_*.{format}` | Temporary image files | `integrations/misc/open-file.ts` |
| `os.tmpdir()/cline-remote-*.md` | Remote file viewing | `core/controller/file/openFile.ts` |
| VS Code temp via `NotebookDiffView` | Notebook diff temp files | `hosts/vscode/NotebookDiffView.ts` |

---

## 5. Tools Available to the LLM

Cline provides the AI agent with the following tool capabilities:

1. **Shell command execution**: The most significant tool -- Cline executes arbitrary shell commands on behalf of the AI agent, using either VS Code's integrated terminal (with shell integration for output capture) or direct `child_process.spawn()` in standalone mode.

2. **File read/write/edit**: The AI can read, create, and modify files in the workspace.

3. **Browser automation**: Via puppeteer-core + Chromium, the AI can take screenshots of web pages, interact with web page elements, navigate URLs, and fetch URL content.

4. **Search tools**:
   - File content search via ripgrep (`rg`)
   - File name search via ripgrep
   - Code parsing via tree-sitter (WASM)

5. **MCP tools**: External tools provided by MCP servers (connected via stdio, SSE, or StreamableHTTP transports).

6. **Git operations**: Commit message generation, checkpoint management via shadow git repos.

7. **Claude Code subprocess**: Can invoke the `claude` CLI as a subprocess for delegated tasks.

---

## 6. Host System Interactions

### 6.1 Subprocess Execution

Cline spawns subprocesses in multiple contexts:

#### Terminal Command Execution
The most significant subprocess interaction -- Cline executes arbitrary shell commands on behalf of the AI agent.

**VS Code terminal mode** (`src/hosts/vscode/terminal/VscodeTerminalProcess.ts`):
- Uses VS Code's `Terminal.shellIntegration.executeCommand()` API
- Falls back to clipboard-based output capture when shell integration is unavailable

**Standalone/background terminal mode** (`src/integrations/terminal/standalone/StandaloneTerminalProcess.ts`):
- Uses `child_process.spawn()` directly
- Runs commands in the configured shell (bash, zsh, PowerShell, etc.)

#### Hook Script Execution
(`src/core/hooks/HookProcess.ts`):
```typescript
export class HookProcess extends EventEmitter {
    async run(inputJson: string): Promise<void> {
        // Spawns hook scripts via child_process.spawn()
        // 30-second timeout, 1MB output limit
    }
}
```

#### Other Subprocess Usage

| File | Subprocess | Purpose |
|---|---|---|
| `services/ripgrep/index.ts` | `rg` (ripgrep binary) | File content search |
| `services/browser/BrowserSession.ts` | Chrome/Chromium | Browser automation (detached process) |
| `services/dictation/AudioRecordingService.ts` | Audio recording program (platform-specific) | Voice dictation |
| `integrations/claude-code/run.ts` | `claude` CLI | Claude Code subprocess invocation |
| `services/search/file-search.ts` | `rg` (ripgrep) | File name search |
| `core/storage/disk.ts` | `powershell`, `xdg-user-dir` | Documents path detection |
| `utils/git.ts` | `git` | Git operations |
| `utils/process-termination.ts` | Process kill utilities | Cleanup |
| `core/task/utils.ts` | Various | Task utility subprocesses |

#### Ripgrep Binary
(`src/services/ripgrep/index.ts`):
```typescript
async function execRipgrep(args: string[]): Promise<string> {
    const binPath: string = await getBinaryLocation("rg")
    const rgProcess = childProcess.spawn(binPath, args)
    // ...
}
```

### 6.2 Network Requests

#### AI Provider APIs
| Provider | Endpoint | SDK/Client |
|---|---|---|
| Anthropic | `api.anthropic.com` | `@anthropic-ai/sdk` |
| OpenAI | `api.openai.com` | `openai` SDK |
| Google Gemini / Vertex | `generativelanguage.googleapis.com`, Vertex AI endpoints | `@google/genai`, `@google-cloud/vertexai` |
| AWS Bedrock | AWS regional endpoints | `@aws-sdk/client-bedrock-runtime` |
| Azure OpenAI | Azure endpoints | `@azure/identity` |
| OpenRouter | `openrouter.ai/api` | Custom via OpenAI SDK |
| Ollama | `localhost:11434` (default) | `ollama` SDK |
| Mistral | `api.mistral.ai` | `@mistralai/mistralai` |
| Cerebras | Cerebras endpoints | `@cerebras/cerebras_cloud_sdk` |
| DeepSeek | `api.deepseek.com` | OpenAI-compatible |
| Together AI | `api.together.xyz` | OpenAI-compatible |
| Qwen | `chat.qwen.ai` | Custom OAuth + OpenAI-compatible |
| SAP AI Core | SAP endpoints | `@sap-ai-sdk/*` |
| LM Studio | `localhost:1234` (default) | OpenAI-compatible |
| LiteLLM | Configurable | OpenAI-compatible |
| Many others... | Various | OpenAI-compatible |

#### Cline Backend Services
| Endpoint | Purpose |
|---|---|
| `https://app.cline.bot` | Cline web application |
| `https://api.cline.bot` | Cline API (auth, account, config) |
| `https://api.cline.bot/v1/mcp` | MCP marketplace/remote servers |
| Staging variants | `staging-app.cline.bot`, `core-api.staging.int.cline.bot` |

#### Telemetry and Analytics
| Service | Purpose |
|---|---|
| PostHog | Analytics, feature flags, error tracking |
| OpenTelemetry (configurable) | Metrics, logs, traces export |

#### MCP (Model Context Protocol) Servers
- Connects to local MCP servers via **stdio** (spawning subprocess)
- Connects to remote MCP servers via **SSE** or **StreamableHTTP** transports
- Server configs read from `cline_mcp_settings.json`

### 6.3 Port Binding

| Port | Service | Context |
|---|---|---|
| 9222 | Chrome Remote Debugging | Browser automation (connects to or launches) |
| 26040 | gRPC ProtoBus | Standalone/CLI mode server |
| Dynamic | OAuth callback server | OpenAI Codex OAuth flow |
| Dynamic | Auth callback server | External host authentication |
| Dynamic | Test server | E2E test HTTP server |

Standalone/CLI gRPC server (`src/standalone/protobus-service.ts`):
```typescript
export const PROTOBUS_PORT = 26040
const host = process.env.PROTOBUS_ADDRESS || `127.0.0.1:${PROTOBUS_PORT}`
server.bindAsync(host, grpc.ServerCredentials.createInsecure(), ...)
```

### 6.4 Browser Launching

#### System Browser
- `vscode.env.openExternal()` for OAuth URLs, documentation links, bug reports
- Fallback to `open` npm package when VS Code API unavailable

#### Chromium/Puppeteer (Browser Automation)
(`src/services/browser/BrowserSession.ts`):
```typescript
// Uses puppeteer-core + puppeteer-chromium-resolver
// Downloads Chromium to: globalStorage/puppeteer/.chromium-browser-snapshots/
// Chrome debug port: 9222
const DEBUG_PORT = 9222

// Can also launch system Chrome in debug mode:
const chromeProcess = spawn(installation, [
    `--remote-debugging-port=${DEBUG_PORT}`,
    `--user-data-dir=${userDataDir}`,
    "--disable-notifications",
    ...userArgs,
    "chrome://newtab",
], { detached: true, stdio: "ignore" })
```

Features:
- Screenshots of web pages
- Web page interaction/navigation
- URL content fetching (`UrlContentFetcher`)
- Port 9222 for Chrome DevTools Protocol

### 6.5 Clipboard Access

(`src/utils/env.ts`):
```typescript
export async function writeTextToClipboard(text: string): Promise<void> {
    await HostProvider.env.clipboardWriteText(StringRequest.create({ value: text }))
}

export async function readTextFromClipboard(): Promise<string> {
    const response = await HostProvider.env.clipboardReadText(EmptyRequest.create({}))
    return response.value
}
```

Uses:
- Terminal output capture fallback (reads/writes clipboard to get terminal content)
- Copying installation commands
- Copying URLs when browser launch fails
- "Add to Cline" command (reads selected text from clipboard)

### 6.6 File System Watchers

| File Watched | Library | Purpose |
|---|---|---|
| `.clineignore` | chokidar | Reload ignore patterns on change |
| `cline_mcp_settings.json` | chokidar | Reload MCP server config on change |
| MCP server source files | chokidar | Restart MCP servers when their files change |
| Hook directories | VS Code `FileSystemWatcher` | Cache invalidation for hook discovery |
| Test mode files | VS Code `FileSystemWatcher` | Test/eval file watching |
| `FileContextTracker` | VS Code `FileSystemWatcher` | Track file context changes |

### 6.7 Other

#### Audio/Dictation
(`src/services/dictation/AudioRecordingService.ts`):
- Spawns audio recording processes (platform-dependent)
- Searches `PATH` for recording binaries
- Records to `os.tmpdir()/cline_recording_*.webm`
- Sends audio to voice transcription service

#### Machine Identification
(`src/services/logging/distinctId.ts`):
```typescript
import { machineId } from "node-machine-id"
// On macOS: reads IOPlatformSerialNumber from IOService
// Falls back to UUID stored in globalState
const id = await machineId()
```

#### Git Integration
- `simple-git` library for checkpoint operations (shadow git repos)
- Git executable for various operations
- Commit message generation feature
- Worktree management

#### VS Code Terminal API
(`src/hosts/vscode/terminal/VscodeTerminalManager.ts`):
- Creates terminals via `vscode.window.createTerminal()`
- Supports terminal reuse across commands
- Uses shell integration for output capture
- Falls back to clipboard-based output when shell integration unavailable

**Terminal profiles** (`src/utils/shell.ts`):
- Detects available shells (bash, zsh, PowerShell, cmd, fish, etc.)
- Reads `SHELL`, `COMSPEC` environment variables
- Supports custom shell configuration

#### URI Handler
(`src/services/uri/SharedUriHandler.ts`):
- Registers a custom URI handler for `vscode://saoudrizwan.claude-dev/`
- Used for OAuth callback redirects

#### VS Code Extension APIs Used

| API | Usage |
|---|---|
| `vscode.window.createTerminal` | Terminal creation |
| `vscode.workspace.createFileSystemWatcher` | File change monitoring |
| `vscode.env.openExternal` | Browser launching |
| `vscode.env.clipboard` | Clipboard read/write |
| `context.secrets` | Secret/credential storage |
| `context.globalState` | Persistent state storage |
| `context.workspaceState` | Workspace-scoped state |
| `WebviewViewProvider` | Sidebar UI rendering |
| `vscode.languages` | Language features |
| `vscode.comments` | Code review comments |
| `vscode.workspace.registerTextDocumentContentProvider` | Diff view |
| `vscode.window.registerUriHandler` | URI scheme handling |
| `vscode.scm` | Source control integration |
| `vscode.notebooks` | Jupyter notebook integration |
| `Terminal.shellIntegration` | Shell integration for output capture |
| `vscode.workspace.fs` | File system access |

---

## 7. Extension Points

### 7.1 Hook/Lifecycle System

(`src/core/hooks/HookProcess.ts`):
- Hook scripts can be defined in `.clinerules/hooks/` (project) and `~/Documents/Cline/Hooks/` (global)
- Spawned via `child_process.spawn()` with 30-second timeout and 1MB output limit
- Hooks are triggered on various lifecycle events
- `DEBUG_HOOKS` environment variable enables hook debugging

### 7.2 Plugin/Extension Architecture

None beyond MCP and hooks.

### 7.3 MCP Integration

Cline integrates with the **Model Context Protocol (MCP)** as a client:
- Connects to local MCP servers via **stdio** (spawning subprocess)
- Connects to remote MCP servers via **SSE** or **StreamableHTTP** transports
- Server configs stored in `<globalStorage>/settings/cline_mcp_settings.json`
- MCP marketplace catalog cached at `<globalStorage>/cache/mcp_marketplace_catalog.json`
- File watchers restart MCP servers when their source files change
- MCP OAuth secrets stored in SecretStorage under `mcpOAuthSecrets` key
- Uses `@modelcontextprotocol/sdk`

### 7.4 Custom Commands/Skills/Agents

- **Skills**: `~/.cline/skills/` (global), `.clinerules/skills/` and `.cline/skills/` (project), `.claude/skills/` (Claude compat)
- **Workflows**: `~/Documents/Cline/Workflows/` (global), `.clinerules/workflows/` (project)
- **Rules**: `~/Documents/Cline/Rules/` (global), `.clinerules` (project), plus compatibility with `.cursorrules`, `.cursor/rules/`, `.windsurfrules`, `AGENTS.md`

### 7.5 SDK/API Surface

- **gRPC ProtoBus** (`standalone/protobus-service.ts`): Port 26040, provides programmatic access in standalone/CLI mode
- **Custom URI handler**: `vscode://saoudrizwan.claude-dev/` for OAuth callbacks

---

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

Cline has **no built-in sandboxing mechanism**. All shell commands, file operations, and browser automation run with the full privileges of the VS Code process (or the standalone Node.js process).

### 8.2 Permission System

None at the process level. The AI agent has unrestricted access to the filesystem and can execute arbitrary shell commands.

### 8.3 Safety Mechanisms

- `.clineignore` file provides gitignore-style patterns to restrict which files the AI can access
- Hook scripts have a 30-second timeout and 1MB output limit
- Browser automation uses a separate Chrome profile (`chrome-debug-profile`)

### 8.4 Known Vulnerabilities

- **Standalone mode stores secrets in plain JSON** (`~/.cline/data/secrets.json`) without encryption
- **gRPC ProtoBus uses insecure credentials** (`grpc.ServerCredentials.createInsecure()`) on port 26040

### 8.5 Enterprise/Managed Security Controls

- On-premise endpoint configuration via `~/.cline/endpoints.json`
- Remote configuration cache per organization (`cache/remote_config_{orgId}.json`)

---

## 9. Key Dependencies

| Dependency | Impact |
|---|---|
| `better-sqlite3` | **Native module** -- SQLite3 compiled for the platform. Creates .db files for lock management. |
| `web-tree-sitter` / `tree-sitter-wasms` | **WASM modules** -- Code parsing via tree-sitter. Loads `.wasm` files at runtime. |
| `puppeteer-core` + `puppeteer-chromium-resolver` | **Downloads Chromium** binary (~150MB) to extension storage. Launches Chrome processes. |
| `chrome-launcher` | Finds and launches system Chrome installations. |
| `node-machine-id` | Reads hardware/platform identifier (IOPlatformSerialNumber on macOS). |
| `chokidar` | File system watching (uses native fsevents on macOS). |
| `simple-git` | Git operations via subprocess. |
| `execa` | Enhanced subprocess execution. |
| `default-shell` | Detects system default shell. |
| `@anthropic-ai/sdk` | Anthropic API client (network). |
| `openai` | OpenAI API client (network). |
| `@aws-sdk/*` | AWS Bedrock client (network, potentially reads `~/.aws/credentials`). |
| `@azure/identity` | Azure authentication (may access system credential stores). |
| `@google-cloud/vertexai` | Google Cloud Vertex AI (may use application default credentials). |
| `@grpc/grpc-js` | gRPC server/client for standalone mode. |
| `posthog-node` | Analytics/telemetry (network). |
| `@opentelemetry/*` | Observability framework (network, metrics, traces). |
| `@modelcontextprotocol/sdk` | MCP server communication (subprocess/network). |
| `archiver` | ZIP archive creation. |
| `open` | Cross-platform `open` command (launches browser/files). |
| `os-name` | OS name detection. |

---

## 10. Environment Variables

### Read by Cline

| Variable | Purpose |
|---|---|
| `CLINE_ENVIRONMENT` / `CLINE_ENVIRONMENT_OVERRIDE` | Environment selection (production/staging/local) |
| `CLINE_DIR` | Override for `~/.cline` data directory |
| `IS_DEV` | Development mode flag |
| `E2E_TEST` | End-to-end test mode |
| `PROTOBUS_ADDRESS` | gRPC server address override |
| `INSTALL_DIR` | Standalone installation directory |
| `WORKSPACE_STORAGE_DIR` | Workspace storage override |
| `SHELL` / `COMSPEC` | Shell detection |
| `PATH` | Binary lookup (audio recording, ripgrep) |
| `DEBUG_HOOKS` | Hook debugging |
| `OTEL_EXPORTER_OTLP_HEADERS` | OpenTelemetry headers |
| `CLINE_OTEL_*` | OpenTelemetry configuration (multiple) |
| `CLINE_STORAGE_SYNC_*` | Storage sync worker configuration |
| `TEL_DEBUG_DIAGNOSTICS` | Telemetry debug mode |
| `IS_STANDALONE` | Standalone mode flag (compile-time replacement) |
| `NODE_ENV` | Node environment |

---

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|---|---|---|---|
| `~/.cline/` | R/W | Cline home directory | Yes |
| `~/.cline/endpoints.json` | R | On-premise endpoint configuration | No (user-created) |
| `~/.cline/data/` | R/W | Standalone data storage | Yes |
| `~/.cline/data/globalState.json` | R/W | Standalone global state | Yes |
| `~/.cline/data/secrets.json` | R/W | Standalone secrets (PLAIN TEXT) | Yes |
| `~/.cline/data/workspace/` | R/W | Standalone workspace storage | Yes |
| `~/.cline/skills/` | R/W | Global skills | Yes |
| `~/.oca/config.json` | R | OCA provider config | No (external) |
| `~/.qwen/oauth_creds.json` | R/W | Qwen OAuth credentials | Cline writes |
| `~/Documents/Cline/Rules/` | R/W | Global rules | Yes |
| `~/Documents/Cline/Workflows/` | R/W | Global workflows | Yes |
| `~/Documents/Cline/MCP/` | R/W | MCP server files | Yes |
| `~/Documents/Cline/Hooks/` | R/W | Global hook scripts | Yes |
| `<globalStorage>/tasks/` | R/W | Task history and conversations | Yes |
| `<globalStorage>/settings/` | R/W | Extension settings | Yes |
| `<globalStorage>/state/` | R/W | State files (taskHistory.json) | Yes |
| `<globalStorage>/cache/` | R/W | Cached data (MCP catalog, remote config) | Yes |
| `<globalStorage>/checkpoints/` | R/W | Shadow git repositories | Yes |
| `<globalStorage>/puppeteer/` | R/W | Downloaded Chromium browser | Yes |
| `<os.tmpdir()>/cline/` | R/W | Temp files (logs, outputs) | Yes |
| `<os.tmpdir()>/chrome-debug-profile/` | R/W | Chrome debug user data | Yes |
| `<os.tmpdir()>/cline_recording_*.webm` | R/W | Audio recordings | Yes |
| `<os.tmpdir()>/cline-system-prompt-*.txt` | R/W | Claude Code prompts | Yes |
| `<os.tmpdir()>/temp_image_*` | R/W | Temp images | Yes |
| `<os.tmpdir()>/cline-remote-*` | R/W | Remote file viewing | Yes |
| `<workspace>/.clineignore` | R | File access patterns | No (user-created) |
| `<workspace>/.clinerules/` | R | Project rules, hooks, workflows, skills | No (user-created) |
| `<workspace>/.cline/skills/` | R | Project skills | No (user-created) |
| `<workspace>/.claude/skills/` | R | Claude skills | No (user-created) |
| `<workspace>/.cursorrules` | R | Cursor rules (compat) | No (user-created) |
| `<workspace>/.cursor/rules/` | R | Cursor rules dir (compat) | No (user-created) |
| `<workspace>/.windsurfrules` | R | Windsurf rules (compat) | No (user-created) |
| `<workspace>/AGENTS.md` | R | Agents rules (compat) | No (user-created) |
| `<workspace>/**/*` | R/W | Arbitrary workspace file access (AI-directed) | Modified by agent |
| AWS credentials (`~/.aws/`) | R | AWS SDK credential chain | No (external) |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|---|---|---|
| `api.anthropic.com` | Anthropic API requests | When using Anthropic provider |
| `api.openai.com` | OpenAI API requests | When using OpenAI provider |
| `generativelanguage.googleapis.com` | Google Gemini API | When using Gemini provider |
| Google Vertex AI endpoints | Vertex AI requests | When using Vertex provider |
| AWS Bedrock regional endpoints | Bedrock API requests | When using Bedrock provider |
| Azure OpenAI endpoints | Azure API requests | When using Azure provider |
| `openrouter.ai/api` | OpenRouter API | When using OpenRouter provider |
| `localhost:11434` | Ollama local server | When using Ollama provider |
| `api.mistral.ai` | Mistral API | When using Mistral provider |
| `api.deepseek.com` | DeepSeek API | When using DeepSeek provider |
| `api.together.xyz` | Together AI API | When using Together provider |
| `chat.qwen.ai` | Qwen API | When using Qwen provider |
| `localhost:1234` | LM Studio local server | When using LM Studio provider |
| `app.cline.bot` / `api.cline.bot` | Cline backend (auth, config, MCP) | Account management, remote config |
| PostHog | Analytics, feature flags | During operation |
| OpenTelemetry collector | Metrics, logs, traces | When configured |
| MCP server URLs (stdio/SSE/HTTP) | MCP tool server communication | When using MCP tools |
| OAuth callback servers (dynamic, inbound) | OAuth flows | During auth flows |
| `localhost:9222` (inbound) | Chrome Remote Debugging | Browser automation |
| `localhost:26040` (inbound) | gRPC ProtoBus | Standalone/CLI mode |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|---|---|---|
| Shell command execution | VS Code Terminal API / `child_process.spawn()` | Arbitrary commands (AI-directed) |
| Terminal creation | `vscode.window.createTerminal()` | VS Code integrated terminals |
| Ripgrep search | `child_process.spawn("rg")` | File content and name search |
| Git operations | `simple-git` / `git` CLI | Checkpoints, commits, worktree management |
| Chrome/Chromium | `puppeteer-core` / `chrome-launcher` | Browser automation, screenshots, web interaction |
| Audio recording | Platform-specific spawned process | Voice dictation |
| Claude Code CLI | `child_process.spawn("claude")` | Delegated AI tasks |
| Hook scripts | `child_process.spawn()` | Lifecycle hooks (30s timeout, 1MB limit) |
| File system watchers | `chokidar` / VS Code `FileSystemWatcher` | .clineignore, MCP settings, hooks, context tracking |
| Clipboard | VS Code `env.clipboard` API | Terminal output capture, URL copying |
| Browser launching | `vscode.env.openExternal()` / `open` npm | OAuth, docs, URLs |
| Machine identification | `node-machine-id` | Hardware serial reading (IOPlatformSerialNumber on macOS) |
| Secret storage | VS Code `context.secrets` (macOS Keychain) | Credential storage |
| SQLite | `better-sqlite3` | Lock management |
| Tree-sitter | `web-tree-sitter` (WASM) | Code parsing |
| URI handling | `vscode.window.registerUriHandler` | `vscode://` URI scheme for OAuth |
| gRPC server | `@grpc/grpc-js` | Standalone mode ProtoBus on port 26040 |
| Telemetry | PostHog + OpenTelemetry | Analytics, metrics, traces |

---

## 12. Sandboxing Recommendations

1. **No built-in sandboxing**: Cline runs with full privileges of the VS Code process. All shell commands, file operations, and browser automation are unrestricted.

2. **Arbitrary shell command execution**: The AI agent can execute any shell command through the VS Code terminal or direct subprocess spawning. This is the primary attack surface.

3. **Chromium download and execution**: Cline downloads and manages its own Chromium binary (~150MB) and launches it with remote debugging enabled on port 9222. Consider restricting this.

4. **Standalone mode security gaps**: In standalone mode, secrets are stored in plain JSON (`~/.cline/data/secrets.json`) and the gRPC server uses insecure credentials.

5. **Machine identification**: `node-machine-id` reads hardware serial numbers, which could be used for fingerprinting.

6. **File access**: The AI has unrestricted workspace file access. `.clineignore` provides advisory control but is not enforced by a sandbox.

7. **MCP servers**: MCP servers are spawned as subprocesses or connected via network, potentially expanding the attack surface.

8. **Recommended isolation**: Run VS Code / Cline inside a container or sandbox. On macOS, use seatbelt profiles to restrict filesystem access, network endpoints, and subprocess execution. Protect `.git/hooks/` and sensitive config directories from modification.

9. **Network access**: Cline connects to 20+ AI provider APIs, its own backend services, PostHog analytics, and arbitrary MCP server endpoints. Consider restricting to known-good endpoints.

10. **Clipboard access**: Used as a fallback for terminal output capture, which means the clipboard may be read/written during normal operation.
