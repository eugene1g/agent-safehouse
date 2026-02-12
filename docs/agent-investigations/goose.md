# Goose -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/block/goose
**Git Commit:** `ac0ceddf88d3b8eb993825147b0b308cb81318fd`
**Latest Version:** 1.23.0
**License:** Apache-2.0
**Source Availability:** Open source

---

## 1. Overview

Goose is an open-source AI coding agent built in Rust. It is published as a workspace containing multiple crates: `goose` (core library with agents, providers, config, session management, OAuth, security, telemetry), `goose-cli` (CLI binary `goose`), `goose-server` (server binary `goosed` with REST/WebSocket API), `goose-mcp` (MCP extension servers for developer tools, computer controller, memory, tutorial), `goose-acp` (Agent Communication Protocol server), and test infrastructure crates. It also ships a desktop UI (Electron app, version 1.23.0) in `ui/desktop/`.

Goose supports many LLM providers including OpenAI, Anthropic, Google/Gemini, Databricks, Ollama, OpenRouter, Azure OpenAI, AWS Bedrock, AWS SageMaker, GCP Vertex AI, GitHub Copilot, Venice, xAI, LiteLLM, Snowflake, Tetrate, and more. It can also delegate to external CLI agents (Claude Code, Gemini CLI, Cursor Agent, Codex).

---

## 2. UI & Execution Modes

### CLI Interface (Interactive Terminal)

Goose has an interactive terminal CLI using these libraries:
- **`rustyline`** (`15.0.0`) -- line editing and input history
- **`cliclack`** (`0.3.5`) -- interactive prompts (confirm, select, multi-select)
- **`console`** (`0.16.1`) -- terminal colors and styling
- **`bat`** (`0.26.1`) -- syntax-highlighted code output
- **`indicatif`** (`0.18.1`) -- progress bars
- **`anstream`** (`0.6.18`) -- ANSI stream handling

There is **no TUI framework** (no ratatui, tui-rs, crossterm widget layers). The CLI is a traditional REPL-style interface with syntax-highlighted output.

The CLI stores readline history:
```rust
// crates/goose-cli/src/session/mod.rs:116
history_file: Paths::state_dir().join("history.txt"),
old_history_file: Paths::config_dir().join("history.txt"),
```

### Desktop Application (Electron)

The desktop app is in `ui/desktop/` and is a full **Electron** application:
- **Electron** `40.1.0`
- **React** `19.2.4` with React Router
- **Vite** as build tool
- **Tailwind CSS** `4.1.18` for styling
- **Electron Forge** for packaging and distribution
- Uses `electron-updater` for auto-updates
- Has `react-markdown`, `react-syntax-highlighter`, `katex` for rich content rendering

The desktop app communicates with the Rust backend (`goosed`) via HTTP/WebSocket.

### Web UI Mode (`goose web`)

The CLI can launch a web server mode that serves a bundled frontend:
```rust
// crates/goose-cli/src/commands/web.rs:283
let listener = tokio::net::TcpListener::bind(addr).await?;
```

Uses:
- **`axum`** (`0.8`) with WebSocket support for real-time communication
- **`tower-http`** for CORS, static file serving, and auth middleware
- Opens the browser automatically: `webbrowser::open(&url)`

### Server Mode (`goosed`)

The `goose-server` crate (`goosed` binary) runs a standalone HTTP/WebSocket server:
- Default bind: `127.0.0.1:3000`
- Configurable via `GOOSE_HOST` and `GOOSE_PORT` environment variables
- Full REST API with OpenAPI spec (via `utoipa`)
- WebSocket support for streaming agent responses

---

## 3. Authentication & Credentials

### 3.1 Credential Storage (System Keyring)

Goose uses the **`keyring`** crate (`3.6.2`) with the `apple-native` feature for macOS Keychain integration:

```rust
// crates/goose/src/config/base.rs:4
use keyring::Entry;

// crates/goose/src/config/base.rs:17-18
const KEYRING_SERVICE: &str = "goose";
const KEYRING_USERNAME: &str = "secrets";
```

**Keyring features enabled**:
```toml
keyring = { version = "3.6.2", features = [
    "apple-native",       # macOS Keychain via Security.framework
    "windows-native",     # Windows Credential Manager
    "sync-secret-service", # Linux Secret Service (D-Bus)
    "vendored",
] }
```

All secrets (API keys, OAuth tokens) are stored as a single JSON blob in the keychain under service `goose`, username `secrets`.

### 3.2 API Key Sources and Priority Order

All config and secrets check environment variables first (uppercase):
```rust
// crates/goose/src/config/base.rs:666
let env_key = key.to_uppercase();
if let Ok(val) = env::var(&env_key) { ... }
```

Fallback to file-based secrets if keyring unavailable or explicitly disabled:
```rust
// crates/goose/src/config/base.rs:124
let secrets = match env::var("GOOSE_DISABLE_KEYRING") {
    Ok(_) => SecretStorage::File {
        path: config_dir.join("secrets.yaml"),
    },
    Err(_) => SecretStorage::Keyring {
        service: KEYRING_SERVICE.to_string(),
    },
};
```

Fallback file: `~/.config/goose/secrets.yaml` (plaintext YAML)

The system auto-detects keyring availability errors and falls back:
```rust
// crates/goose/src/config/base.rs:900
fn is_keyring_availability_error(&self, error_str: &str) -> bool {
    error_str.contains("keyring")
        || error_str.contains("DBus error")
        || error_str.contains("org.freedesktop.secrets")
        || error_str.contains("couldn't access platform secure storage")
}
```

Provider-specific credentials read from environment or keyring:
- `OPENAI_API_KEY`, `OPENAI_HOST`
- `ANTHROPIC_API_KEY`
- `DATABRICKS_HOST`, `DATABRICKS_TOKEN`
- `OPENROUTER_API_KEY`, `OPENROUTER_HOST`
- `OLLAMA_HOST`, `OLLAMA_TIMEOUT`
- `SNOWFLAKE_HOST`, `SNOWFLAKE_TOKEN`
- `GOOGLE_API_KEY`
- GitHub Copilot token cache: `Paths::in_config_dir("githubcopilot/info.json")`
- AWS credentials (via `aws-config` crate for Bedrock/SageMaker)
- GCP credentials (via `jsonwebtoken` for Vertex AI)
- Azure credentials (via `az` CLI: `tokio::process::Command::new("az")`)

### 3.3 OAuth Flows

Goose implements OAuth for multiple providers:

1. **MCP OAuth** (`crates/goose/src/oauth/mod.rs`):
   - Starts local callback server on `127.0.0.1:0` (random port)
   - Opens browser for authorization
   - Stores credentials via `GooseCredentialStore` (which uses the Config secret system -> keychain)

2. **Databricks OAuth** (`crates/goose/src/providers/oauth.rs`):
   - Binds to `127.0.0.1:<bind_port>`
   - Opens browser for authorization
   - Stores tokens at `Paths::in_config_dir("databricks/oauth")`

3. **ChatGPT/Codex OAuth** (`crates/goose/src/providers/chatgpt_codex.rs`):
   - Binds to `127.0.0.1:16372` (fixed port)
   - PKCE flow
   - Stores tokens at `Paths::in_config_dir("chatgpt_codex/tokens.json")`

4. **OpenRouter signup** (`crates/goose/src/config/signup_openrouter/`):
   - Binds to `127.0.0.1:3000`
   - Opens browser for authentication

5. **Tetrate Agent Router** (`crates/goose/src/config/signup_tetrate/`):
   - Binds to `127.0.0.1:3000`
   - Opens browser for authentication

### 3.4 Credential File Locations and Formats

| Path | Purpose |
|------|---------|
| System keyring (service: `goose`, user: `secrets`) | Primary secret storage (JSON blob) |
| `{config_dir}/secrets.yaml` | Fallback plaintext secret storage |
| `{config_dir}/githubcopilot/info.json` | GitHub Copilot token cache |
| `{config_dir}/chatgpt_codex/tokens.json` | ChatGPT/Codex OAuth tokens |
| `{config_dir}/databricks/oauth/` | Databricks OAuth token storage |

---

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

Goose uses the **`etcetera`** crate for XDG-compliant path resolution:

```rust
// crates/goose/src/config/paths.rs
let strategy = choose_app_strategy(AppStrategyArgs {
    top_level_domain: "Block".to_string(),
    author: "Block".to_string(),
    app_name: "goose".to_string(),
})
```

On macOS:
| Directory Type | macOS Path |
|---|---|
| Config | `~/Library/Application Support/Block.goose/` |
| Data | `~/Library/Application Support/Block.goose/` |
| State | `~/Library/Application Support/Block.goose/` |

On Linux (XDG):
| Directory Type | Linux Path |
|---|---|
| Config | `~/.config/goose/` |
| Data | `~/.local/share/goose/` |
| State | `~/.local/state/goose/` |

Can be overridden with `GOOSE_PATH_ROOT` environment variable.

#### Config Files

| Path | Purpose |
|---|---|
| `{config_dir}/config.yaml` | Main configuration file |
| `{config_dir}/config.yaml.bak` | Config backup (rotated up to `.bak.5`) |
| `{config_dir}/config.yaml.tmp` | Atomic write temp file |
| `{config_dir}/secrets.yaml` | Fallback secret storage (when keyring disabled) |
| `{config_dir}/.bash_env` | Bash environment file (server mode) |
| `{config_dir}/custom_providers/` | Declarative provider definitions |
| `{config_dir}/prompts/` | Custom prompt templates |
| `{config_dir}/permissions/tool_permissions.json` | Tool permission records |
| `{config_dir}/recipes/` | Global recipe library |
| `{config_dir}/memory/` | Global memory store (category files) |
| `{config_dir}/tunnel.lock` | Tunnel lock file |
| `{config_dir}/.gooseignore` | Global ignore patterns |
| `{config_dir}/.goosehints` | Global hints file |

### 4.2 Project-Level Config Paths

| Path | Purpose |
|---|---|
| `.goosehints` | Project-specific hints (read from CWD and parent dirs) |
| `.gooseignore` | Project-specific ignore patterns |
| `.goose/memory/` | Project-local memory storage |
| `.goose/recipes/` | Project-local recipe library |
| `AGENTS.md` | Agent instructions file (read from CWD) |
| `recipe.yaml` | Default recipe save location |
| `init-config.yaml` | Initial config (in workspace root) |

### 4.3 System/Enterprise Config Paths

N/A

### 4.4 Data & State Directories

| Path | Purpose |
|---|---|
| `{data_dir}/sessions/sessions.db` | SQLite database for session storage |
| `{data_dir}/sessions/*.jsonl` | Legacy session files (migrated to SQLite) |
| `{data_dir}/schedule.json` | Scheduled jobs storage |
| `{data_dir}/scheduled_recipes/` | Scheduled recipe YAML files |
| `{data_dir}/models/` | Downloaded Whisper model files |
| `{data_dir}/projects.json` | Project tracking data |
| `{data_dir}/goose_apps/` | Goose apps directory |
| `{state_dir}/logs/cli/{date}/` | CLI log files (JSON, date-rotated) |
| `{state_dir}/logs/server/{date}/` | Server log files |
| `{state_dir}/logs/debug/` | Debug log files |
| `{state_dir}/history.txt` | Readline history |
| `{state_dir}/telemetry_installation.json` | Telemetry installation ID |
| `{state_dir}/codex/images/` | Codex image storage |

Log cleanup: files older than 14 days are automatically removed.

### 4.5 Workspace Files Read

| Path | Purpose |
|---|---|
| `.goosehints` | Project-specific hints (read from CWD and parent dirs) |
| `.gooseignore` | Project-specific ignore patterns |
| `AGENTS.md` | Agent instructions file |
| `.env`, `.env.*` | Ignored by default |
| `.gitignore` | Respected for file operations |

### 4.6 Temp Directory Usage

#### tempfile Crate Usage

Goose uses the `tempfile` crate (`3`) extensively, primarily in test code. The `tempfile` crate uses `std::env::temp_dir()` which respects the `TMPDIR` environment variable on macOS/Linux.

#### Explicit /tmp Usage

The computer controller macOS platform uses a hardcoded `/tmp`:
```rust
// crates/goose-mcp/src/computercontroller/platform/macos.rs:19
fn get_temp_path(&self) -> PathBuf {
    PathBuf::from("/tmp")
}
```

#### Atomic Config Writes

Config file saves use a `.tmp` extension sibling file for atomic writes:
```rust
// crates/goose/src/config/base.rs:452
let temp_path = self.config_path.with_extension("tmp");
```

---

## 5. Tools Available to the LLM

Goose provides tools to the LLM through its built-in MCP extension servers:

**Developer Extension** (`goose-mcp/src/developer/`):
- `text_editor` -- File reading and editing
- `write_file` -- File writing/creation
- `patch_file` -- Fuzzy patch application
- Shell execution via user's `$SHELL` (defaults to `bash`)
- Screen capture (`xcap` crate for screenshots)
- Memory storage (project-local and global)

**Computer Controller Extension** (`goose-mcp/src/computercontroller/`):
- AppleScript execution (macOS automation via `osascript`)
- Shell automation
- Platform-specific automation (X11/Wayland on Linux, PowerShell on Windows)

**Memory Extension**:
- Project-local and global memory storage and retrieval

**Document Processing**:
- PDF reading (`lopdf` crate)
- DOCX reading (`docx-rs` crate)
- Excel reading (`umya-spreadsheet` crate)
- Image processing (`image` crate)

Tools respect `.gooseignore` and `.gitignore` patterns. The developer extension uses `tree-sitter` for code parsing (Python, Rust, JavaScript, Go, Java, Kotlin, Swift, Ruby). Files matching `.env` and `.env.*` are ignored by default.

---

## 6. Host System Interactions

### 6.1 Subprocess Execution

#### Shell Execution (Developer Extension)

The primary mechanism for the agent to interact with the system:
```rust
// crates/goose-mcp/src/developer/shell.rs:114
let mut command_builder = tokio::process::Command::new(&shell_config.executable);
```
- Uses user's `$SHELL` (defaults to `bash`)
- Sets `GOOSE_TERMINAL=1`, `AGENT=goose`
- Disables interactive Git: `GIT_TERMINAL_PROMPT=0`, `GIT_EDITOR=<error script>`
- Creates new process group on Unix for proper cleanup
- **This is the primary way the agent runs arbitrary commands**

#### Specific External Commands

| Command | Location | Purpose |
|---|---|---|
| `osascript` | `computercontroller/platform/macos.rs` | Execute AppleScript for macOS automation |
| `bash -c` | Multiple | Shell command execution |
| `sh -c` | Multiple | Shell command execution |
| `powershell` / `cmd` | Windows paths | Windows shell execution |
| `gh` (GitHub CLI) | `recipes/github_recipe.rs` | GitHub operations (auth, repos, PRs) |
| `git` | `recipes/github_recipe.rs` | Git operations |
| `curl` | `commands/update.rs` | Download update script |
| `docker exec` | `agents/extension_manager.rs` | Run extensions in Docker containers |
| `docker run` | `agents/extension_manager.rs` | Start containerized extensions |
| `uvx` | `agents/extension_manager.rs` | Run Python MCP servers via uv |
| `az` | `providers/azureauth.rs` | Azure CLI for authentication |
| `sw_vers` | `posthog.rs` | Get macOS version (telemetry) |
| `goose` | `commands/project.rs` | Self-invocation for project management |
| `claude` | Provider: claude_code | Claude Code CLI invocation |
| `gemini` | Provider: gemini_cli | Gemini CLI invocation |
| `cursor-agent` | Provider: cursor_agent | Cursor Agent CLI invocation |
| `codex` | Provider: codex | Codex CLI invocation |
| `python3` | `computercontroller/platform/linux.rs` | Linux automation scripts |
| `xdotool` / `wmctrl` | `computercontroller/platform/linux.rs` | X11 automation |
| `wtype` / `wl-paste` / `wl-copy` | `computercontroller/platform/linux.rs` | Wayland automation |
| `xclip` | `computercontroller/platform/linux.rs` | X11 clipboard |
| `taskkill` | Windows paths | Process termination |
| `which` | `computercontroller/platform/linux.rs` | Check for dependencies |

#### Extension Launching

MCP extensions are started as child processes:
```rust
// crates/goose/src/agents/extension_manager.rs:571
Command::new(cmd).configure(|command| {
    command.args(args).envs(all_envs);
})
```

Extensions can be launched via:
- Direct command execution (stdio MCP)
- `uvx` for Python-based MCP servers
- `docker exec` for containerized extensions
- Built-in extensions (in-process via `tokio::io::duplex`)
- HTTP-based MCP connections

### 6.2 Network Requests

#### LLM Provider API Endpoints

| Provider | Default Endpoint |
|---|---|
| OpenAI | `https://api.openai.com` |
| Anthropic | Anthropic API |
| Google/Gemini | Google Generative Language API |
| Databricks | User-configured `DATABRICKS_HOST` |
| Ollama | `localhost:11434` |
| OpenRouter | `https://openrouter.ai/api` |
| Azure OpenAI | User-configured |
| AWS Bedrock | Via AWS SDK |
| AWS SageMaker | Via AWS SDK |
| GCP Vertex AI | `{location}-aiplatform.googleapis.com` |
| GitHub Copilot | `https://api.github.com/copilot_internal/v2/token` |
| Venice | User-configured |
| xAI | User-configured |
| LiteLLM | User-configured |
| Snowflake | User-configured `SNOWFLAKE_HOST` |
| Tetrate | User-configured |

#### Telemetry

PostHog analytics (opt-in):
```rust
// crates/goose/src/posthog.rs:17
const POSTHOG_API_KEY: &str = "phc_RyX5CaY01VtZJCQyhSR5KFh6qimUy81YwxsEpotAftT";
```
- Sends to PostHog cloud API
- Controlled by `GOOSE_TELEMETRY_ENABLED` config or `GOOSE_TELEMETRY_OFF` env var
- Currently only `session_started` events are active (error/other events disabled)
- Sanitizes PII (paths, emails, tokens) before sending

#### Observability

- **Langfuse** integration (optional, via `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY`)
  - Default URL: `http://localhost:3000`
- **OpenTelemetry OTLP** export (optional)

#### Whisper Model Downloads

Downloads from HuggingFace:
```rust
// crates/goose/src/dictation/whisper.rs:61-79
url: "https://huggingface.co/oxide-lab/whisper-tiny-GGUF/resolve/main/model-tiny-q80.gguf"
url: "https://huggingface.co/oxide-lab/whisper-base-GGUF/resolve/main/whisper-base-q8_0.gguf"
url: "https://huggingface.co/oxide-lab/whisper-small-GGUF/resolve/main/whisper-small-q8_0.gguf"
url: "https://huggingface.co/oxide-lab/whisper-medium-GGUF/resolve/main/whisper-medium-q8_0.gguf"
```

#### Tunnel (Remote Access)

Cloudflare tunnel proxy for remote access:
```rust
// crates/goose-server/src/tunnel/lapstone.rs:32
const WORKER_URL: &str = "https://cloudflare-tunnel-proxy.michael-neale.workers.dev";
```

#### Update Mechanism

Self-update via download script:
```rust
// crates/goose-cli/src/commands/update.rs:13-14
Command::new("curl")
    .args(["-fsSL", "https://github.com/block/goose/raw/main/download_cli.sh"])
```

### 6.3 Port Binding

| Port | Context | Purpose |
|---|---|---|
| `3000` | `goosed` default | HTTP/WebSocket API server |
| `3000` | OpenRouter/Tetrate signup | OAuth callback server |
| `0` (random) | MCP OAuth | OAuth callback server |
| `0` (random) | Databricks OAuth | OAuth callback server |
| `16372` | ChatGPT/Codex OAuth | Fixed OAuth callback port |
| Configurable | `goose web` | Web UI server |
| `0` (random) | Tests | Test servers |

### 6.4 Browser Launching

Multiple locations open the system browser:
```rust
webbrowser::open(authorization_url)  // OAuth flows
webbrowser::open(&url)               // Web UI auto-open
open::that(url)                      // Recipe deep links
```

### 6.5 Clipboard Access

- **Linux X11**: `xclip -selection clipboard`
- **Linux Wayland**: `wl-paste` / `wl-copy`
- **macOS**: Via AppleScript (`osascript`)
- **Windows**: Via PowerShell
- Desktop app requests `clipboard-write` permission

### 6.6 File System Watchers

None identified.

### 6.7 Other

- **Screen Capture** via **`xcap`** crate (`0.4.0`):
  ```rust
  // crates/goose-mcp/src/developer/rmcp_developer.rs:52
  use xcap::{Monitor, Window};
  ```
  - Captures full display screenshots
  - Captures specific window screenshots
  - Lists available windows

- **macOS AppleScript**: The computer controller can execute arbitrary AppleScript:
  ```rust
  // crates/goose-mcp/src/computercontroller/platform/macos.rs:9
  Command::new("osascript").arg("-e").arg(script).output()?;
  ```
  This provides deep system integration: window management, application control, file operations, browser automation, etc.

- **SQLite Database**: Session data stored in SQLite (`{data_dir}/sessions/sessions.db`) using `sqlx` with WAL journal mode. Stores sessions, messages, metadata with schema migrations.

- **Document Processing**: Can read PDF (`lopdf`), DOCX (`docx-rs`), Excel (`umya-spreadsheet`), and images (`image` crate).

---

## 7. Extension Points

### 7.1 Hook/Lifecycle System

None identified (no hook/lifecycle events system).

### 7.2 Plugin/Extension Architecture

Extensions are managed through the Extension Manager:
- **Builtin extensions**: Run in-process via duplex streams
  - Developer (file editing, shell, screen capture, memory)
  - Computer Controller (AppleScript, shell automation)
  - Memory (project-local and global memory storage)
  - Tutorial
  - Auto-visualiser
- **Stdio extensions**: Launched as child processes
- **HTTP extensions**: Connected via HTTP/SSE
- **Docker extensions**: Launched inside Docker containers
- **Platform extensions**: Pre-registered definitions

### 7.3 MCP Integration

Goose is deeply integrated with MCP (Model Context Protocol):
- Acts as both an MCP client (connecting to external MCP servers) and hosts built-in MCP servers (developer, computer controller, memory, tutorial)
- Supports stdio, HTTP, and Docker transport types
- Extension configuration in `config.yaml`
- `uvx` support for Python-based MCP servers
- Docker-based MCP server isolation

### 7.4 Custom Commands/Skills/Agents

- **Recipes**: Reusable task definitions stored in `{config_dir}/recipes/` (global) and `.goose/recipes/` (project-local)
- **Scheduled recipes**: `{data_dir}/scheduled_recipes/`
- **Custom prompt templates**: `{config_dir}/prompts/`
- **Custom providers**: `{config_dir}/custom_providers/` for declarative provider definitions

### 7.5 SDK/API Surface

- **REST API** with OpenAPI spec (via `utoipa`) on `goosed`
- **WebSocket** support for streaming agent responses
- **ACP (Agent Communication Protocol)** server (`goose-acp` crate)

---

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

None. The agent runs directly on the host with the user's full permissions.

### 8.2 Permission System

- Tool permission records stored at `{config_dir}/permissions/tool_permissions.json`
- No tiered autonomy system like some other agents

### 8.3 Safety Mechanisms

- Disables interactive Git prompts: `GIT_TERMINAL_PROMPT=0`, `GIT_EDITOR=<error script>`
- Respects `.gooseignore` and `.gitignore` patterns
- Ignores `.env`, `.env.*` files by default
- Telemetry sanitizes PII before sending

### 8.4 Known Vulnerabilities

None identified.

### 8.5 Enterprise/Managed Security Controls

N/A

---

## 9. Key Dependencies

| Dependency | Version | Impact |
|---|---|---|
| `keyring` | 3.6.2 | macOS Keychain, Windows Credential Manager, Linux Secret Service |
| `xcap` | 0.4.0 | Screen capture (uses platform-specific APIs) |
| `reqwest` | 0.12.28 | HTTP client with system proxy support, rustls TLS |
| `sqlx` | 0.8 | SQLite database (runtime-tokio-rustls) |
| `candle-core/nn/transformers` | 0.9 | Local ML inference (Metal on macOS, CUDA optional) |
| `tokio` | 1.49 | Async runtime (full features) |
| `axum` | 0.8 | HTTP server framework |
| `webbrowser` | 1.0 | System browser launching |
| `open` | 5.3.2 | Open URLs/files with default handler |
| `libc` | 0.2 | Direct Unix system calls (process group kill) |
| `socket2` | 0.6.1 | Low-level socket options (TCP keepalive) |
| `fs2` | 0.4 | File locking (exclusive locks for config) |
| `which` | 8.0.0 | Command resolution on PATH |
| `shellexpand` | 3.1 | Tilde expansion in paths |
| `ignore` | 0.4.25 | Gitignore-style pattern matching |
| `tree-sitter` + parsers | Various | Code parsing (7+ languages) |
| `lopdf` | 0.36.0 | PDF reading |
| `docx-rs` | 0.4.7 | DOCX reading |
| `umya-spreadsheet` | 2.2.3 | Excel reading |
| `aws-config`/`aws-sdk-*` | Various | AWS service access |
| `posthog-rs` | 0.3.7 | Telemetry (PostHog) |
| `mpatch` | 0.2.0 | Fuzzy patch application |
| `sys-info` | 0.9 | System information |
| `rustls` | 0.23 | TLS (ring backend) |
| `hf-hub` | 0.4.3 | HuggingFace model downloads |
| `winapi` | 0.3 | Windows credential access (wincred) |

---

## 10. Environment Variables

### Configuration Variables (via `GOOSE_` prefix)

| Variable | Purpose |
|---|---|
| `GOOSE_PROVIDER` | Active LLM provider |
| `GOOSE_MODEL` | Active model name |
| `GOOSE_MODE` | Operating mode |
| `GOOSE_HOST` / `GOOSE_PORT` | Server bind address |
| `GOOSE_DISABLE_KEYRING` | Disable keychain, use file-based secrets |
| `GOOSE_TELEMETRY_ENABLED` | Telemetry opt-in config key |
| `GOOSE_TELEMETRY_OFF` | Environment-level telemetry disable |
| `GOOSE_PATH_ROOT` | Override all base directories |
| `GOOSE_SEARCH_PATHS` | Additional PATH entries for commands |
| `GOOSE_MAX_TOKENS` | Max tokens for responses |
| `GOOSE_TEMPERATURE` | LLM temperature |
| `GOOSE_CONTEXT_LIMIT` | Context window limit |
| `GOOSE_TOOLSHIM` | Enable tool shim |
| `GOOSE_TOOLSHIM_OLLAMA_MODEL` | Ollama model for tool shim |
| `GOOSE_PREDEFINED_MODELS` | Predefined model list |
| `GOOSE_EMBEDDING_MODEL` | Embedding model name |
| `GOOSE_AUTO_COMPACT_THRESHOLD` | Auto-compaction threshold |
| `GOOSE_DESKTOP` | Indicates desktop app context |
| `GOOSE_TERMINAL` | Set in spawned shells to indicate agent context |
| `GOOSE_RECIPE_PATH` | Additional recipe search paths |
| `GOOSE_RECIPE_RETRY_TIMEOUT_SECONDS` | Recipe retry timeout |
| `GOOSE_RECIPE_ON_FAILURE_TIMEOUT_SECONDS` | Recipe failure timeout |
| `GOOSE_PROVIDER_SKIP_BACKOFF` | Skip provider backoff |
| `GOOSE_MCP_CLIENT_VERSION` | MCP client version |
| `GOOSE_DISABLE_SESSION_NAMING` | Disable auto session naming |
| `GOOSE_MAX_ACTIVE_AGENTS` | Max concurrent agents |
| `GOOSE_CLAUDE_CODE_DEBUG` | Debug logging for Claude Code provider |
| `GOOSE_CODEX_DEBUG` | Debug logging for Codex provider |
| `GOOSE_CURSOR_AGENT_DEBUG` | Debug logging for Cursor Agent provider |
| `GOOSE_LEAD_MODEL` / `GOOSE_LEAD_PROVIDER` / etc. | Lead-worker agent config |

### Provider API Key Variables

| Variable | Provider |
|---|---|
| `OPENAI_API_KEY` | OpenAI |
| `ANTHROPIC_API_KEY` | Anthropic |
| `DATABRICKS_HOST` / `DATABRICKS_TOKEN` | Databricks |
| `OPENROUTER_API_KEY` | OpenRouter |
| `OLLAMA_HOST` | Ollama |
| `SNOWFLAKE_HOST` / `SNOWFLAKE_TOKEN` | Snowflake |
| `GOOGLE_API_KEY` | Google |
| Various AWS vars | AWS Bedrock/SageMaker |
| Various GCP vars | GCP Vertex AI |

### Tracing/Observability Variables

| Variable | Purpose |
|---|---|
| `LANGFUSE_PUBLIC_KEY` | Langfuse tracing |
| `LANGFUSE_SECRET_KEY` | Langfuse tracing |
| `LANGFUSE_URL` | Langfuse endpoint |
| `RUST_LOG` | Log level filter |

---

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|---|---|---|---|
| `~/Library/Application Support/Block.goose/` (macOS) | R/W | Config, data, state root | Yes |
| `~/.config/goose/` (Linux) | R/W | Config root | Yes |
| `~/.local/share/goose/` (Linux) | R/W | Data root | Yes |
| `~/.local/state/goose/` (Linux) | R/W | State root | Yes |
| `{config}/config.yaml` | R/W | Main config | Yes |
| `{config}/config.yaml.bak*` | R/W | Config backups (up to 6) | Yes |
| `{config}/secrets.yaml` | R/W | Fallback secret storage | Yes |
| `{config}/custom_providers/` | R | Custom provider definitions | No (user-created) |
| `{config}/prompts/` | R | Custom prompt templates | No (user-created) |
| `{config}/permissions/tool_permissions.json` | R/W | Tool permissions | Yes |
| `{config}/recipes/` | R/W | Global recipe library | Yes |
| `{config}/memory/` | R/W | Global memory categories | Yes |
| `{config}/githubcopilot/info.json` | R/W | GitHub Copilot cache | Yes |
| `{config}/chatgpt_codex/tokens.json` | R/W | ChatGPT/Codex OAuth tokens | Yes |
| `{config}/databricks/oauth/` | R/W | Databricks OAuth tokens | Yes |
| `{config}/tunnel.lock` | R/W | Tunnel lock file | Yes |
| `{config}/.gooseignore` | R | Global ignore patterns | No (user-created) |
| `{config}/.goosehints` | R | Global hints | No (user-created) |
| `{config}/.bash_env` | R | Bash environment (server) | No (user-created) |
| `{data}/sessions/sessions.db` | R/W | SQLite session database | Yes |
| `{data}/schedule.json` | R/W | Scheduled jobs | Yes |
| `{data}/scheduled_recipes/` | R/W | Scheduled recipe files | Yes |
| `{data}/models/` | R/W | Downloaded ML models | Yes |
| `{data}/projects.json` | R/W | Project tracking | Yes |
| `{data}/goose_apps/` | R/W | Goose apps | Yes |
| `{state}/logs/cli/{date}/*.log` | W | CLI log files | Yes |
| `{state}/logs/server/{date}/*.log` | W | Server log files | Yes |
| `{state}/history.txt` | R/W | Readline history | Yes |
| `{state}/telemetry_installation.json` | R/W | Telemetry ID | Yes |
| `{state}/codex/images/` | R/W | Codex images | Yes |
| `{cwd}/.goosehints` | R | Project hints | No (user-created) |
| `{cwd}/.gooseignore` | R | Project ignore patterns | No (user-created) |
| `{cwd}/.goose/memory/` | R/W | Project-local memory | Yes |
| `{cwd}/.goose/recipes/` | R | Project-local recipes | No (user-created) |
| `{cwd}/AGENTS.md` | R | Agent instructions | No (user-created) |
| `{cwd}/recipe.yaml` | R/W | Default recipe file | Yes |
| `/tmp` | R/W | macOS temp (computer controller) | Yes |
| System keychain | R/W | macOS Keychain via Security.framework | Yes |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|---|---|---|
| `https://api.openai.com` | LLM inference | When OpenAI provider selected |
| Anthropic API | LLM inference | When Anthropic provider selected |
| Google Generative Language API | LLM inference | When Gemini provider selected |
| `DATABRICKS_HOST` | LLM inference | When Databricks configured |
| `localhost:11434` | LLM inference | When Ollama configured |
| `https://openrouter.ai/api` | LLM inference | When OpenRouter configured |
| Azure OpenAI | LLM inference | When Azure configured |
| AWS Bedrock/SageMaker | LLM inference | When AWS configured |
| `{location}-aiplatform.googleapis.com` | LLM inference | When Vertex AI configured |
| `https://api.github.com/copilot_internal/v2/token` | LLM inference | When GitHub Copilot configured |
| PostHog cloud API | Telemetry (opt-in) | Session start |
| Langfuse endpoint | Observability (optional) | When Langfuse configured |
| `https://huggingface.co/oxide-lab/whisper-*` | Whisper model downloads | When dictation enabled |
| `https://cloudflare-tunnel-proxy.michael-neale.workers.dev` | Tunnel proxy | When remote access enabled |
| `https://github.com/block/goose/raw/main/download_cli.sh` | Self-update | On `goose update` command |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|---|---|---|
| Arbitrary shell execution | `tokio::process::Command` via user's `$SHELL` | **Critical** -- agent can run any command |
| File read/write | `std::fs` / `tokio::fs` in working directory | **Critical** -- agent reads/writes project files |
| AppleScript execution | `osascript -e` | **Critical** -- full macOS automation |
| Screen capture | `xcap` crate | **High** -- captures screen contents |
| Browser launch | `webbrowser::open` / `open::that` | **Medium** -- opens URLs |
| HTTP port binding | `tokio::net::TcpListener` | **Medium** -- binds local ports (3000, random) |
| Clipboard access | Platform-specific CLI tools | **Medium** -- read/write clipboard |
| Keychain access | `keyring` crate (Security.framework) | **Medium** -- stores/reads secrets |
| Docker control | `docker exec/run` | **High** -- container management |
| Network HTTP requests | `reqwest` | **Medium** -- API calls to LLM providers |
| Telemetry | `posthog-rs` | **Low** -- opt-in analytics |
| Git operations | `git` CLI via shell | **Medium** -- repository access |
| GitHub CLI | `gh` CLI | **Medium** -- GitHub API access |
| Azure CLI | `az` CLI | **Medium** -- Azure auth |
| System version query | `sw_vers` / `/etc/os-release` | **Low** -- system info |
| ML model download | `reqwest` to HuggingFace | **Low** -- model files |
| SQLite database | `sqlx` | **Low** -- local DB file |
| File locking | `fs2` | **Low** -- config atomicity |
| Process group management | `libc::kill` with process groups | **Medium** -- signal handling |
| MCP extension spawning | Child process or Docker | **High** -- runs arbitrary MCP servers |
| UV package execution | `uvx` | **High** -- runs arbitrary Python packages |
| Self-update | `curl` + `bash` | **High** -- downloads and executes scripts |

---

## 12. Sandboxing Recommendations

**Critical restrictions needed:**
1. **Shell execution** -- The agent can run arbitrary commands via the user's shell. This is the primary attack surface and should be sandboxed.
2. **AppleScript** -- `osascript` provides full macOS automation capabilities (window management, app control, file operations).
3. **Screen capture** -- The `xcap` crate can capture full display and individual window screenshots.
4. **File system access** -- The agent reads/writes files in the working directory with no OS-level restriction.

**What to allow:**
- Network access to configured LLM provider endpoints
- Read/write access to the working directory (scoped)
- Read/write access to `~/Library/Application Support/Block.goose/` (macOS) for config/state
- Keychain access for secret storage
- Localhost port binding for OAuth callbacks and server mode

**Known gaps:**
- No built-in sandboxing whatsoever -- the agent runs with full user permissions
- `osascript` provides essentially unrestricted macOS automation
- MCP stdio extensions run as child processes with full user permissions
- `uvx` can install and execute arbitrary Python packages
- Self-update mechanism (`curl | bash`) downloads and runs scripts from GitHub
- Docker extensions can manage containers on the host

**Recommended isolation strategy:**
- Container-based isolation (Docker/Podman) with restricted filesystem mounts
- Network egress filtering to only allow configured LLM endpoints
- Disable `osascript` and screen capture in sandboxed environments
- Use HTTP-based MCP servers instead of stdio to maintain isolation boundaries
