# OpenCode -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/opencode-ai/opencode
**Git Commit:** `73ee493265acf15fcd8caab2bc8cd3bd375b63cb`
**Latest Version:** 0.0.55
**License:** MIT (Go module: `github.com/opencode-ai/opencode`)
**Source Availability:** Open source

---

## 1. Overview

OpenCode is an open-source AI coding agent written in Go (version 1.24.0). It operates primarily as a **terminal TUI application** using Charmbracelet's Bubble Tea framework. It does NOT have a web UI and does NOT listen on any HTTP/TCP ports for its own interface.

The version is defined in `internal/version/version.go` and set via build-time `-ldflags` (falls back to `debug.ReadBuildInfo()` for `go install` builds):

```go
var Version = "unknown"

func init() {
    info, ok := debug.ReadBuildInfo()
    if !ok { return }
    mainVersion := info.Main.Version
    if mainVersion == "" || mainVersion == "(devel)" { return }
    Version = mainVersion
}
```

## 2. UI & Execution Modes

OpenCode uses **Charmbracelet's Bubble Tea** (`bubbletea`) as its terminal TUI framework.

### Key TUI Dependencies

| Package | Purpose |
|---------|---------|
| `github.com/charmbracelet/bubbletea v1.3.5` | Core TUI framework (Elm-architecture terminal app) |
| `github.com/charmbracelet/bubbles v0.21.0` | TUI components (textarea, etc.) |
| `github.com/charmbracelet/lipgloss v1.1.0` | Terminal styling/layout |
| `github.com/charmbracelet/glamour v0.9.1` | Markdown rendering in terminal |
| `github.com/charmbracelet/x/ansi v0.8.0` | ANSI escape code handling |
| `github.com/lrstanley/bubblezone` | Mouse zone support for bubbletea |
| `github.com/catppuccin/go v0.3.0` | Catppuccin color theme |
| `github.com/alecthomas/chroma/v2 v2.15.0` | Syntax highlighting |

Evidence from `cmd/root.go`:

```go
import tea "github.com/charmbracelet/bubbletea"
// ...
zone.NewGlobal()
program := tea.NewProgram(
    tui.New(app),
    tea.WithAltScreen(),
)
```

The TUI uses alternate screen mode (`tea.WithAltScreen()`), meaning it takes over the entire terminal.

### Non-Interactive Mode

OpenCode also supports a non-interactive CLI mode via `-p` flag:

```go
rootCmd.Flags().StringP("prompt", "p", "", "Prompt to run in non-interactive mode")
```

In this mode, it bypasses the TUI entirely and runs a spinner to stdout.

## 3. Authentication & Credentials

### 3.1 Credential Storage

OpenCode does **NOT** use macOS Keychain, `go-keyring`, or any OS-level credential storage. It does **NOT** use OAuth flows. All authentication is via environment variables and config files.

### 3.2 API Key Sources and Priority Order

API keys can be provided via environment variables or stored in JSON config files. The config struct includes:

```go
type Provider struct {
    APIKey   string `json:"apiKey"`
    Disabled bool   `json:"disabled"`
}
```

#### Environment Variables Read for API Keys

| Environment Variable | Provider |
|---------------------|----------|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) |
| `OPENAI_API_KEY` | OpenAI |
| `GEMINI_API_KEY` | Google Gemini |
| `GROQ_API_KEY` | Groq |
| `OPENROUTER_API_KEY` | OpenRouter |
| `XAI_API_KEY` | xAI (Grok) |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI |
| `AZURE_OPENAI_API_VERSION` | Azure OpenAI |
| `GITHUB_TOKEN` | GitHub Copilot |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock |
| `AWS_PROFILE` | AWS Bedrock |
| `AWS_DEFAULT_PROFILE` | AWS Bedrock |
| `AWS_REGION` | AWS Bedrock |
| `AWS_DEFAULT_REGION` | AWS Bedrock |
| `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` | AWS Bedrock (EC2) |
| `AWS_CONTAINER_CREDENTIALS_FULL_URI` | AWS Bedrock (EC2) |
| `VERTEXAI_PROJECT` | Google VertexAI |
| `VERTEXAI_LOCATION` | Google VertexAI |
| `GOOGLE_CLOUD_PROJECT` | Google VertexAI |
| `GOOGLE_CLOUD_REGION` | Google VertexAI |
| `GOOGLE_CLOUD_LOCATION` | Google VertexAI |
| `LOCAL_ENDPOINT` | Local LLM (LM Studio, etc.) |

#### Viper Environment Variable Binding

Viper is configured with `OPENCODE` prefix and `AutomaticEnv()`:

```go
viper.SetEnvPrefix(strings.ToUpper(appName))  // "OPENCODE"
viper.AutomaticEnv()
```

This means any config key can be overridden with `OPENCODE_*` environment variables.

### 3.3 OAuth Flows

None. OpenCode does not use OAuth.

### 3.4 Credential File Locations and Formats

#### GitHub Copilot Token Loading

OpenCode reads GitHub Copilot tokens from the filesystem. From `internal/config/config.go`:

```go
func LoadGitHubToken() (string, error) {
    // First check environment variable
    if token := os.Getenv("GITHUB_TOKEN"); token != "" {
        return token, nil
    }
    // ...
    filePaths := []string{
        filepath.Join(configDir, "github-copilot", "hosts.json"),
        filepath.Join(configDir, "github-copilot", "apps.json"),
    }
    // Reads oauth_token from these JSON files
}
```

On macOS, this reads:
- `~/.config/github-copilot/hosts.json`
- `~/.config/github-copilot/apps.json`

Or `$XDG_CONFIG_HOME/github-copilot/hosts.json` if XDG_CONFIG_HOME is set.

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

OpenCode uses Viper for configuration and searches these locations (in order):

```go
viper.SetConfigName(".opencode")     // filename: .opencode.json
viper.SetConfigType("json")
viper.AddConfigPath("$HOME")                           // ~/.opencode.json
viper.AddConfigPath("$XDG_CONFIG_HOME/opencode")       // $XDG_CONFIG_HOME/opencode/.opencode.json
viper.AddConfigPath("$HOME/.config/opencode")          // ~/.config/opencode/.opencode.json
```

When writing config updates (e.g., changing models), the config file is written to:
- The file Viper found, OR
- `~/.opencode.json` if none was found

### 4.2 Project-Level Config Paths

A **local config** is merged from the current working directory:

```go
local.AddConfigPath(workingDir)  // $CWD/.opencode.json
```

### 4.3 System/Enterprise Config Paths

None identified.

### 4.4 Data & State Directories

The primary data directory defaults to `.opencode` **relative to the working directory**:

```go
const defaultDataDirectory = ".opencode"
```

This means `$CWD/.opencode/` is the default data directory. It contains:

| Path | Purpose |
|------|---------|
| `.opencode/opencode.db` | SQLite database (sessions, messages, files) |
| `.opencode/init` | Flag file marking project as initialized |
| `.opencode/debug.log` | Debug log file (only if `OPENCODE_DEV_DEBUG=true`) |
| `.opencode/messages/` | Message debug logs (only if `OPENCODE_DEV_DEBUG=true`) |
| `.opencode/messages/<session-prefix>/` | Per-session message logs |
| `.opencode/commands/` | Project-specific custom commands (`.md` files) |

#### SQLite Database

The database is at `.opencode/opencode.db` (WAL mode). Schema includes:
- `sessions` -- chat sessions with token counts
- `messages` -- chat messages with parts (JSON)
- `files` -- file version history per session

Database pragmas set:
```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA page_size = 4096;
PRAGMA cache_size = -8000;
PRAGMA synchronous = NORMAL;
```

This means 3 files total for the DB:
- `.opencode/opencode.db`
- `.opencode/opencode.db-wal`
- `.opencode/opencode.db-shm`

#### Custom Commands Directories

```go
// User commands from XDG
filepath.Join(xdgConfigHome, "opencode", "commands")   // ~/.config/opencode/commands/
// User commands from home
filepath.Join(home, ".opencode", "commands")            // ~/.opencode/commands/
// Project commands
filepath.Join(cfg.Data.Directory, "commands")           // .opencode/commands/
```

#### Panic Log Files

On panic, creates files in the **current working directory**:

```go
filename := fmt.Sprintf("opencode-panic-%s-%s.log", name, timestamp)
file, err := os.Create(filename)
```

Pattern: `opencode-panic-<component>-<timestamp>.log` in CWD.

### 4.5 Workspace Files Read

OpenCode reads these project-specific instruction files from the working directory:

```go
var defaultContextPaths = []string{
    ".github/copilot-instructions.md",
    ".cursorrules",
    ".cursor/rules/",
    "CLAUDE.md",
    "CLAUDE.local.md",
    "opencode.md",
    "opencode.local.md",
    "OpenCode.md",
    "OpenCode.local.md",
    "OPENCODE.md",
    "OPENCODE.local.md",
}
```

#### GitHub Copilot Config Files (read-only, for token extraction)

```
~/.config/github-copilot/hosts.json
~/.config/github-copilot/apps.json
```

### 4.6 Temp Directory Usage

OpenCode uses `os.TempDir()` (which respects `$TMPDIR` on macOS) for temporary files.

#### Shell Command Temp Files

From `internal/llm/tools/shell/shell.go`:

```go
tempDir := os.TempDir()
stdoutFile := filepath.Join(tempDir, fmt.Sprintf("opencode-stdout-%d", time.Now().UnixNano()))
stderrFile := filepath.Join(tempDir, fmt.Sprintf("opencode-stderr-%d", time.Now().UnixNano()))
statusFile := filepath.Join(tempDir, fmt.Sprintf("opencode-status-%d", time.Now().UnixNano()))
cwdFile    := filepath.Join(tempDir, fmt.Sprintf("opencode-cwd-%d", time.Now().UnixNano()))
```

These are created and cleaned up (`os.Remove`) after each shell command execution.

Temp file pattern: `$TMPDIR/opencode-{stdout,stderr,status,cwd}-<nanosecond-timestamp>`

#### Editor Temp Files

When the user presses `ctrl+e` to open an external editor:

```go
tmpfile, err := os.CreateTemp("", "msg_*.md")
```

Pattern: `$TMPDIR/msg_<random>.md` -- cleaned up after use.

#### No Custom Temp Dir Logic

OpenCode does NOT create its own temp directories. It relies entirely on `os.TempDir()` / `os.CreateTemp()`.

## 5. Tools Available to the LLM

The following tools are provided to the LLM for autonomous use:

| Tool | Internal Name | Purpose |
|------|---------------|---------|
| File Read | `view` / `FileRead` | Reads any file by absolute path |
| Edit | `Edit` | Replaces content in existing files, creates new files |
| File Write | `write` / `FileWrite` | Overwrites or creates files |
| Patch | `Patch` | Applies multi-file patches |
| Grep | `Grep` | Searches file contents (via ripgrep) |
| Glob | `Glob` | Searches for files by pattern |
| LS | `LS` | Lists directory contents |
| Bash / Shell | Shell tool | Persistent shell for command execution |
| Fetch | Fetch tool | Web content retrieval (with permission) |
| Sourcegraph | Sourcegraph tool | Public code search via `sourcegraph.com/.api/graphql` |

### Banned Commands in Bash Tool

```go
var bannedCommands = []string{
    "alias", "curl", "curlie", "wget", "axel", "aria2c",
    "nc", "telnet", "lynx", "w3m", "links", "httpie", "xh",
    "http-prompt", "chrome", "firefox", "safari",
}
```

## 6. Host System Interactions

### 6.1 Subprocess Execution

| Command | Location | Purpose |
|---------|----------|---------|
| `$SHELL -l` (or `/bin/bash -l`) | `internal/llm/tools/shell/shell.go` | Persistent shell for bash tool |
| `rg` (ripgrep) | `internal/llm/tools/grep.go`, `internal/fileutil/fileutil.go` | File content searching |
| `fzf` | `internal/fileutil/fileutil.go` | Fuzzy file finding |
| `pgrep -P <pid>` | `internal/llm/tools/shell/shell.go` | Finding child processes to kill on timeout |
| `$EDITOR` (or `nvim`) | `internal/tui/components/chat/editor.go` | External editor for message composition |
| LSP server commands (e.g., `gopls`, `typescript-language-server`) | `internal/lsp/client.go` | Language Server Protocol integration |
| MCP server commands (user-configured) | `internal/llm/agent/mcp-tools.go` | Model Control Protocol tool servers |

#### Shell Details

The persistent shell:
- Spawns with `$SHELL -l` (login shell) or configurable via `shell.path` and `shell.args`
- Sets `GIT_EDITOR=true` in environment (to prevent interactive git editors)
- Inherits the full process environment (`os.Environ()`)
- Runs in the working directory
- Commands have a default timeout of 1 minute, max 10 minutes

### 6.2 Network Requests

#### LLM Provider API Endpoints

| Provider | Endpoint | Protocol |
|----------|----------|----------|
| Anthropic | `https://api.anthropic.com` (via SDK) | HTTPS |
| OpenAI | `https://api.openai.com` (via SDK) | HTTPS |
| Google Gemini | `https://generativelanguage.googleapis.com` (via SDK) | HTTPS |
| Groq | `https://api.groq.com/openai/v1` | HTTPS |
| OpenRouter | `https://openrouter.ai/api/v1` | HTTPS |
| xAI | `https://api.x.ai/v1` | HTTPS |
| GitHub Copilot | `https://api.githubcopilot.com` | HTTPS |
| GitHub (token exchange) | `https://api.github.com/copilot_internal/v2/token` | HTTPS |
| Azure OpenAI | `$AZURE_OPENAI_ENDPOINT` (user-configured) | HTTPS |
| AWS Bedrock | AWS Bedrock endpoint (via SDK, region-based) | HTTPS |
| Google VertexAI | Google Cloud VertexAI endpoint (via SDK) | HTTPS |
| Local LLM | `$LOCAL_ENDPOINT` (user-configured, e.g., `http://localhost:1234`) | HTTP/HTTPS |

#### Tool Network Requests

| Tool | Endpoint | Purpose |
|------|----------|---------|
| Fetch | Any user-specified URL | Web content retrieval (with permission) |
| Sourcegraph | `https://sourcegraph.com/.api/graphql` | Public code search |
| Local model discovery | `$LOCAL_ENDPOINT/v1/models` or `$LOCAL_ENDPOINT/api/v0/models` | List local models at startup |

#### MCP Server Connections

MCP servers configured by the user can connect via:
- **stdio**: Spawns a subprocess, communicates via stdin/stdout
- **SSE**: Connects to an HTTP URL with Server-Sent Events

### 6.3 Port Binding

OpenCode does **NOT** bind to any ports. It does **NOT** run an HTTP server. There are no `net.Listen` or `http.ListenAndServe` calls.

### 6.4 Browser Launching

OpenCode does **NOT** directly launch browsers. The `pkg/browser` package is listed as an **indirect dependency** in `go.mod`, pulled in by Azure Identity SDK (`azidentity`).

### 6.5 Clipboard Access

The `atotto/clipboard` package is listed as an **indirect dependency** in `go.mod`. It is pulled in by Charmbracelet's `bubbles` textarea component. There is no direct clipboard usage in OpenCode's own code.

### 6.6 File System Watchers

OpenCode uses `fsnotify` for LSP workspace watching:

```go
watcher, err := fsnotify.NewWatcher()
```

From `internal/lsp/watcher/watcher.go`:

- Recursively watches the entire working directory tree
- Excludes: `.git`, `node_modules`, `dist`, `build`, `out`, `bin`, `.idea`, `.vscode`, `.cache`, `coverage`, `target`, `vendor`
- Monitors: `Create`, `Write`, `Remove`, `Rename` events
- Notifies LSP servers of file changes
- Uses debouncing (300ms) to reduce notification spam

### 6.7 Other

#### Signal Handling

No explicit `signal.Notify` usage found. Signal handling is delegated to `bubbletea` which handles terminal signals (SIGINT, SIGTERM, SIGWINCH) internally.

#### Process Management

- Sends `SIGTERM` to child processes of the persistent shell on timeout
- Uses `pgrep -P <pid>` to find child processes
- Kills LSP server processes on shutdown (with 2-second timeout before `Kill()`)

## 7. Extension Points

### 7.1 Hook/Lifecycle System

None identified. OpenCode does not have a hook or lifecycle event system.

### 7.2 Plugin/Extension Architecture

None identified. OpenCode does not have a plugin system.

### 7.3 MCP Integration

MCP servers configured by the user can connect via:
- **stdio**: Spawns a subprocess, communicates via stdin/stdout
- **SSE**: Connects to an HTTP URL with Server-Sent Events

MCP is implemented via `github.com/mark3labs/mcp-go v0.17.0`.

### 7.4 Custom Commands/Skills/Agents

Custom commands are markdown (`.md`) files loaded from:
- `~/.config/opencode/commands/` (user commands from XDG)
- `~/.opencode/commands/` (user commands from home)
- `.opencode/commands/` (project commands)

### 7.5 SDK/API Surface

None identified. OpenCode does not expose an SDK or API for programmatic use.

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

None. OpenCode does not implement any built-in sandboxing mechanism.

### 8.2 Permission System

None identified beyond the banned commands list in the Bash tool (see Section 5).

### 8.3 Safety Mechanisms

#### Banned Commands in Bash Tool

```go
var bannedCommands = []string{
    "alias", "curl", "curlie", "wget", "axel", "aria2c",
    "nc", "telnet", "lynx", "w3m", "links", "httpie", "xh",
    "http-prompt", "chrome", "firefox", "safari",
}
```

The shell also sets `GIT_EDITOR=true` in the environment to prevent interactive git editors.

### 8.4 Known Vulnerabilities

None identified.

### 8.5 Enterprise/Managed Security Controls

None identified.

## 9. Key Dependencies

| Dependency | Impact |
|-----------|--------|
| `github.com/ncruces/go-sqlite3 v0.25.0` | SQLite database (uses Wasm via `tetratelabs/wazero` -- no CGo!) |
| `github.com/tetratelabs/wazero v1.9.0` | WebAssembly runtime for SQLite (no CGo dependency) |
| `github.com/fsnotify/fsnotify v1.8.0` | File system event watching (uses `kqueue` on macOS) |
| `github.com/charmbracelet/bubbletea v1.3.5` | Terminal TUI (raw terminal mode, alternate screen) |
| `github.com/charmbracelet/x/term v0.2.1` | Terminal capability detection |
| `github.com/atotto/clipboard v0.1.4` | Clipboard access (indirect, via bubbles textarea) |
| `github.com/pkg/browser v0.0.0-20240102092130` | Browser opening (indirect, via Azure Identity) |
| `github.com/spf13/viper v1.20.0` | Config file reading/writing |
| `github.com/subosito/gotenv v1.6.0` | .env file reading (indirect, via viper) |
| `github.com/mark3labs/mcp-go v0.17.0` | MCP client (spawns subprocesses, HTTP SSE) |
| `github.com/anthropics/anthropic-sdk-go v1.4.0` | Anthropic API client |
| `github.com/openai/openai-go v0.1.0-beta.2` | OpenAI API client |
| `google.golang.org/genai v1.3.0` | Google Generative AI client |
| `github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.7.0` | Azure credential management |
| `github.com/aws/aws-sdk-go-v2` | AWS SDK for Bedrock |
| `github.com/pressly/goose/v3 v3.24.2` | Database migration runner |
| `github.com/disintegration/imaging v1.6.2` | Image processing for attachments |
| `github.com/bmatcuk/doublestar/v4 v4.8.1` | Glob pattern matching |
| `github.com/gorilla/websocket v1.5.3` | WebSocket (indirect, used by MCP SSE client) |

### Notable: SQLite uses Wasm, not CGo

The SQLite implementation (`ncruces/go-sqlite3`) compiles SQLite to WebAssembly and runs it via `wazero`. This means:
- No CGo dependency
- No need for a C compiler
- Pure Go binary
- The Wasm runtime has its own memory sandbox

## 10. Environment Variables

### Authentication

| Environment Variable | Purpose |
|---------------------|----------|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `GEMINI_API_KEY` | Google Gemini API key |
| `GROQ_API_KEY` | Groq API key |
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `XAI_API_KEY` | xAI (Grok) API key |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI API key |
| `AZURE_OPENAI_API_VERSION` | Azure OpenAI API version |
| `GITHUB_TOKEN` | GitHub Copilot token |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock access key |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock secret key |
| `AWS_PROFILE` | AWS Bedrock profile |
| `AWS_DEFAULT_PROFILE` | AWS Bedrock default profile |
| `AWS_REGION` | AWS Bedrock region |
| `AWS_DEFAULT_REGION` | AWS Bedrock default region |
| `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` | AWS Bedrock (EC2) credentials |
| `AWS_CONTAINER_CREDENTIALS_FULL_URI` | AWS Bedrock (EC2) credentials |
| `VERTEXAI_PROJECT` | Google VertexAI project |
| `VERTEXAI_LOCATION` | Google VertexAI location |
| `GOOGLE_CLOUD_PROJECT` | Google VertexAI project |
| `GOOGLE_CLOUD_REGION` | Google VertexAI region |
| `GOOGLE_CLOUD_LOCATION` | Google VertexAI location |
| `LOCAL_ENDPOINT` | Local LLM endpoint (e.g., LM Studio) |

### Configuration

| Environment Variable | Purpose |
|---------------------|---------|
| `OPENCODE_DEV_DEBUG` | Enable development debug logging (set to `"true"`) |
| `SHELL` | Default shell path for bash tool |
| `EDITOR` | External editor for message composition (`ctrl+e`) |
| `HOME` | Home directory for config resolution |
| `XDG_CONFIG_HOME` | XDG config directory |
| `LOCALAPPDATA` | Windows AppData (Windows only) |

### Viper Auto-Binding

Any config key can be overridden with `OPENCODE_*` environment variables (prefix: `OPENCODE`).

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `$CWD/.opencode/` | Read/Write | Data directory | Yes |
| `$CWD/.opencode/opencode.db` | Read/Write | SQLite DB | Yes |
| `$CWD/.opencode/opencode.db-wal` | Read/Write | SQLite WAL | Yes |
| `$CWD/.opencode/opencode.db-shm` | Read/Write | SQLite shared memory | Yes |
| `$CWD/.opencode/init` | Read/Write | Project init flag | Yes |
| `$CWD/.opencode/debug.log` | Read/Write | Debug log (when `OPENCODE_DEV_DEBUG=true`) | Yes |
| `$CWD/.opencode/messages/` | Read/Write | Message debug logs (when `OPENCODE_DEV_DEBUG=true`) | Yes |
| `$CWD/.opencode/commands/` | Read | Project custom commands | No |
| `$CWD/.opencode.json` | Read | Local config (optional) | No |
| `~/.opencode.json` | Read/Write | Global config | Yes |
| `~/.config/opencode/.opencode.json` | Read | Global config (XDG) | No |
| `$XDG_CONFIG_HOME/opencode/.opencode.json` | Read | Global config (XDG) | No |
| `~/.config/opencode/commands/` | Read | User custom commands | No |
| `~/.opencode/commands/` | Read | User custom commands | No |
| `~/.config/github-copilot/hosts.json` | Read | GitHub Copilot token | No |
| `~/.config/github-copilot/apps.json` | Read | GitHub Copilot token | No |
| `$CWD/.github/copilot-instructions.md` | Read | Context instructions | No |
| `$CWD/.cursorrules` | Read | Context instructions | No |
| `$CWD/.cursor/rules/` | Read | Context instructions (directory) | No |
| `$CWD/CLAUDE.md` | Read | Context instructions | No |
| `$CWD/CLAUDE.local.md` | Read | Context instructions | No |
| `$CWD/opencode.md` | Read | Context instructions | No |
| `$CWD/opencode.local.md` | Read | Context instructions | No |
| `$CWD/OpenCode.md` | Read | Context instructions | No |
| `$CWD/OpenCode.local.md` | Read | Context instructions | No |
| `$CWD/OPENCODE.md` | Read | Context instructions | No |
| `$CWD/OPENCODE.local.md` | Read | Context instructions | No |
| `$TMPDIR/opencode-stdout-*` | Read/Write | Shell command temp (cleaned up) | Yes |
| `$TMPDIR/opencode-stderr-*` | Read/Write | Shell command temp (cleaned up) | Yes |
| `$TMPDIR/opencode-status-*` | Read/Write | Shell command temp (cleaned up) | Yes |
| `$TMPDIR/opencode-cwd-*` | Read/Write | Shell command temp (cleaned up) | Yes |
| `$TMPDIR/msg_*.md` | Read/Write | External editor temp (cleaned up) | Yes |
| `$CWD/opencode-panic-*.log` | Write | Panic log | Yes |
| `$CWD/**` (any file) | Read/Write | Via LLM tools (edit, write, view, etc.) | Yes |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `https://api.anthropic.com` | Anthropic LLM API | When using Anthropic provider |
| `https://api.openai.com` | OpenAI LLM API | When using OpenAI provider |
| `https://generativelanguage.googleapis.com` | Google Gemini API | When using Gemini provider |
| `https://api.groq.com/openai/v1` | Groq LLM API | When using Groq provider |
| `https://openrouter.ai/api/v1` | OpenRouter API | When using OpenRouter provider |
| `https://api.x.ai/v1` | xAI API | When using xAI provider |
| `https://api.githubcopilot.com` | GitHub Copilot LLM API | When using Copilot provider |
| `https://api.github.com/copilot_internal/v2/token` | Copilot token exchange | When using Copilot provider |
| Azure endpoint (user-configured) | Azure OpenAI API | When using Azure provider |
| AWS Bedrock (region-based) | AWS Bedrock API | When using Bedrock provider |
| VertexAI (Google Cloud) | Google VertexAI API | When using VertexAI provider |
| `$LOCAL_ENDPOINT` | Local LLM API | When using local provider |
| `https://sourcegraph.com/.api/graphql` | Code search | Sourcegraph tool use |
| Any URL | Web fetch | Fetch tool use (with permission) |
| MCP SSE URL (user-configured) | MCP tools | MCP SSE server configured |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Terminal raw mode | `bubbletea` / `x/term` | TUI takes over terminal |
| Alternate screen buffer | `bubbletea` (`tea.WithAltScreen()`) | Full-screen TUI mode |
| File system watching | `fsnotify` (uses `kqueue` on macOS) | LSP workspace watching |
| Process spawning | `os/exec` | Shell, ripgrep, fzf, editor, LSP, MCP |
| Signal sending (`SIGTERM`) | `syscall.SIGTERM` to child processes | Shell command timeout |
| Process ID lookup | `os.Getpid()` (for LSP init) | LSP initialization |
| Environment reading | `os.Getenv()`, `os.Environ()` | Config and credential loading |
| Working directory | `os.Getwd()`, `os.Chdir()` | Shell and file operations |
| Temp file creation | `os.TempDir()`, `os.CreateTemp()` | Shell output capture, editor |

## 12. Sandboxing Recommendations

Based on this analysis, a sandbox for OpenCode should:

1. **Allow filesystem access** to:
   - The working directory tree (read/write for LLM tools)
   - `$CWD/.opencode/` (data directory, SQLite DB)
   - `~/.opencode.json` and `~/.config/opencode/` (config, read-only may suffice)
   - `~/.config/github-copilot/` (read-only, for token loading)
   - `$TMPDIR/opencode-*` and `$TMPDIR/msg_*` (temp files)

2. **Allow network access** to:
   - LLM provider APIs (Anthropic, OpenAI, GitHub, Google, etc.)
   - `sourcegraph.com` (for code search tool)
   - Any URL the fetch tool targets (user-controlled with permission prompt)
   - Local endpoints (`localhost`) if using local LLM

3. **Allow process spawning** for:
   - Shell (`/bin/bash`, `/bin/zsh`, etc.)
   - `rg`, `fzf`, `pgrep`
   - `$EDITOR` (nvim, vim, etc.)
   - LSP servers (gopls, typescript-language-server, etc.)
   - MCP server commands

4. **Allow terminal access** (PTY/TTY for bubbletea TUI)

5. **No port binding** is needed (OpenCode does not listen on any ports)

6. **No keychain/keyring** access needed

7. **No browser launching** by OpenCode directly (indirect dependency only from Azure SDK)
