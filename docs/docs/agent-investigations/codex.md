# OpenAI Codex CLI -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/openai/codex
**Git Commit:** `26d9bddc52f88d9c88f5dd3740b65f675b7eac42`
**Latest Version:** 0.2.0-alpha.2 (Rust), 0.0.0-dev (TypeScript `@openai/codex`)
**License:** Open source
**Source Availability:** Open source

---

## 1. Overview

Codex is a **dual-language** coding agent from OpenAI:

- **TypeScript (`codex-cli/`)**: A thin launcher (`bin/codex.js`) that resolves the correct platform-native Rust binary and spawns it as a child process. The Node.js component is purely a **shim** -- it does not implement any business logic.
- **Rust (`codex-rs/`)**: The full agent implementation. This is a large Cargo workspace with 60+ crates covering CLI, TUI, core logic, sandboxing, authentication, MCP, and more.

The JS shim (`codex-cli/bin/codex.js`) detects the platform/arch, finds the vendored native binary, and spawns it:

```javascript
// codex-cli/bin/codex.js
const child = spawn(binaryPath, process.argv.slice(2), {
  stdio: "inherit",
  env,
});
```

The Rust binary is the actual Codex CLI. The `codex-rs/cli` crate produces a `codex` binary; the `codex-rs/tui` crate produces a `codex-tui` binary.

**Key Rust crates and their roles:**

| Crate | Purpose |
|---|---|
| `cli` | Main CLI entry point, argument parsing, dispatch |
| `tui` | Terminal UI (ratatui/crossterm) |
| `core` | Agent logic, config, auth, exec, sandboxing |
| `exec` | Command execution and non-interactive mode |
| `exec-server` | Posix socket-based exec server |
| `app-server` | WebSocket/HTTP server for desktop app integration |
| `linux-sandbox` | Bubblewrap + Landlock + seccomp sandboxing |
| `process-hardening` | Pre-main anti-debug, anti-dump, env sanitization |
| `keyring-store` | OS keyring abstraction |
| `login` | OAuth browser flow + device code login |
| `network-proxy` | MITM proxy for sandboxed network access |
| `config` | Config validation and requirements |
| `state` | SQLite-backed session/thread persistence |
| `arg0` | Multi-binary dispatch via argv[0] trick |

**Latest Tag:** `codex-rs-2925136536b06a324551627468d17e959afa18d4-1-rust-v0.2.0-alpha.2`
**Rust Workspace Version:** `0.0.0` (edition 2024)

---

## 2. UI & Execution Modes

### Terminal TUI (Ratatui + Crossterm)

Codex uses **ratatui** (Rust TUI framework) with **crossterm** as the terminal backend. This is a pure terminal UI -- there is no web UI, Electron, or browser component for the main interface.

From `codex-rs/tui/Cargo.toml`:
```toml
ratatui = { workspace = true, features = [
    "scrolling-regions",
    "unstable-backend-writer",
    "unstable-rendered-line-info",
    "unstable-widget-ref",
] }
crossterm = { workspace = true, features = ["bracketed-paste", "event-stream"] }
```

Key UI features:
- **Alternate screen buffer** (configurable via `tui.alternate_screen` in config: `auto`/`always`/`never`)
- **Bracketed paste** support
- **Streaming output** with event-stream-based input
- **Syntax highlighting** via `tree-sitter-bash` and `tree-sitter-highlight`
- **Image support** for clipboard paste (PNG, JPEG, GIF, WebP)
- **Markdown rendering** via `pulldown-cmark`

### No Web UI for the CLI

The main CLI and TUI are purely terminal-based. However, the `app-server` crate provides a **WebSocket/HTTP server** for integration with desktop applications (like the ChatGPT desktop app). This is not a user-facing web UI but a programmatic API.

### Execution Modes

- **Interactive TUI** (`codex-tui` binary): Full ratatui terminal UI
- **CLI** (`codex` binary): Command-line dispatch
- **Non-interactive/exec mode**: Headless execution via `exec` crate
- **App server**: WebSocket/HTTP server for desktop app integration (Unix domain sockets on Unix)

### Browser Launching

The `webbrowser` crate is used in two contexts:
1. **OAuth login flow**: Opens the browser for ChatGPT authentication
2. **MCP OAuth**: Opens browser for MCP server authorization

From `codex-rs/login/src/server.rs`:
```rust
if opts.open_browser {
    let _ = webbrowser::open(&auth_url);
}
```

---

## 3. Authentication & Credentials

### 3.1 Credential Storage

From `codex-rs/core/src/auth/storage.rs`:
```rust
pub enum AuthCredentialsStoreMode {
    File,       // CODEX_HOME/auth.json
    Keyring,    // OS keyring (macOS Keychain on macOS)
    Auto,       // Keyring if available, fallback to file
    Ephemeral,  // In-memory only
}
```

#### macOS Keychain Integration

The `keyring-store` crate wraps the `keyring` crate with platform-native backends:

From `codex-rs/keyring-store/Cargo.toml`:
```toml
[target.'cfg(target_os = "macos")'.dependencies]
keyring = { workspace = true, features = ["apple-native"] }
```

On macOS, `apple-native` uses the **macOS Keychain** via Security framework. The keyring service name is `"Codex Auth"`, and keys are hashed from the `codex_home` path:

```rust
const KEYRING_SERVICE: &str = "Codex Auth";

fn compute_store_key(codex_home: &Path) -> std::io::Result<String> {
    // SHA-256 hash of canonical codex_home path, truncated to 16 hex chars
    Ok(format!("cli|{truncated}"))
}
```

#### MCP OAuth Credentials

MCP OAuth credentials are stored separately:
- **Keyring** (preferred)
- **File fallback**: `$CODEX_HOME/.credentials.json`

### 3.2 API Key Sources and Priority Order

```rust
pub const OPENAI_API_KEY_ENV_VAR: &str = "OPENAI_API_KEY";
pub const CODEX_API_KEY_ENV_VAR: &str = "CODEX_API_KEY";
```

Priority order:
1. `CODEX_API_KEY` env var (if `enable_codex_api_key_env` is true)
2. Ephemeral (in-memory) store
3. Persistent store (file or keyring)

Codex supports three authentication modes:
1. **API Key** (`OPENAI_API_KEY` / `CODEX_API_KEY` environment variables)
2. **ChatGPT login** (browser-based OAuth via `auth.openai.com`)
3. **External ChatGPT auth tokens** (for desktop app integration)

### 3.3 OAuth Flows

OAuth token refresh is sent to `https://auth.openai.com/oauth/token` (overridable via `CODEX_REFRESH_TOKEN_URL_OVERRIDE` env var).

Client ID: `app_EMoamEEZ73f0CkXaXp7hrann`

Login server (OAuth callback) binds to `localhost:1455` (default), configurable:
```rust
const DEFAULT_PORT: u16 = 1455;
```

MCP OAuth callback uses an ephemeral port.

### 3.4 Credential File Locations and Formats

**Auth file** (`$CODEX_HOME/auth.json`):
```json
{
  "auth_mode": "apiKey|chatgpt|chatgptAuthTokens",
  "OPENAI_API_KEY": "sk-...",
  "tokens": {
    "id_token": "...",
    "access_token": "...",
    "refresh_token": "...",
    "account_id": "..."
  },
  "last_refresh": "2025-01-01T00:00:00Z"
}
```

The file is written with mode `0o600` on Unix:
```rust
#[cfg(unix)]
{
    options.mode(0o600);
}
```

#### .env File Loading

From `codex-rs/arg0/src/lib.rs`:
```rust
fn load_dotenv() {
    if let Ok(codex_home) = codex_core::config::find_codex_home()
        && let Ok(iter) = dotenvy::from_path_iter(codex_home.join(".env"))
    {
        set_filtered(iter);
    }
}
```

Security: Variables starting with `CODEX_` are **filtered out** and cannot be set via `.env`:
```rust
const ILLEGAL_ENV_VAR_PREFIX: &str = "CODEX_";
```

---

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

| Path | Purpose |
|---|---|
| `~/.codex/` | Default `CODEX_HOME` (overridable via `CODEX_HOME` env var) |
| `~/.codex/config.toml` | Main configuration file |
| `~/.codex/auth.json` | Authentication credentials (file backend) |
| `~/.codex/.credentials.json` | MCP OAuth credentials (file backend) |
| `~/.codex/.env` | Environment variable overrides (loaded at startup) |
| `~/.codex/prompts/` | Custom prompts directory |
| `~/.codex/skills/` | Skills directory |

#### CODEX_HOME Resolution

From `codex-rs/utils/home-dir/src/lib.rs`:
```rust
pub fn find_codex_home() -> std::io::Result<PathBuf> {
    let codex_home_env = std::env::var("CODEX_HOME")
        .ok()
        .filter(|val| !val.is_empty());
    match codex_home_env {
        Some(val) => {
            let path = PathBuf::from(val);
            // Must exist, must be a directory, canonicalized
            path.canonicalize()
        }
        None => {
            let mut p = home_dir()?;
            p.push(".codex");
            Ok(p)
        }
    }
}
```

### 4.2 Project-Level Config Paths

| Path | Purpose |
|---|---|
| `.codex/config.toml` | Project-level config (in working directory) |
| `.codex/` | Project-level config directory |
| `AGENTS.md` | Project documentation (read at startup) |
| `.codex-agents.md` | Alternative project doc filename |

### 4.3 System/Enterprise Config Paths

| Path | Purpose |
|---|---|
| `/etc/codex/config.toml` | System-wide config (Unix) |
| `/etc/codex/requirements.toml` | System-wide requirements (Unix) |

#### macOS Managed Preferences

On macOS, Codex reads configuration from **MDM managed preferences** using Core Foundation:

From `codex-rs/core/src/config_loader/macos.rs`:
```rust
const MANAGED_PREFERENCES_APPLICATION_ID: &str = "com.openai.codex";
const MANAGED_PREFERENCES_CONFIG_KEY: &str = "config_toml_base64";
const MANAGED_PREFERENCES_REQUIREMENTS_KEY: &str = "requirements_toml_base64";
```

This allows enterprise administrators to deploy Codex configuration via MDM profiles.

#### Config Layer Precedence

Configuration is loaded from multiple layers (highest precedence first):
1. Cloud requirements
2. Managed admin preferences (MDM on macOS)
3. System config (`/etc/codex/config.toml`)
4. User config (`~/.codex/config.toml`)
5. Project config (`.codex/config.toml` in cwd)

### 4.4 Data & State Directories

| Path | Purpose |
|---|---|
| `~/.codex/log/` | Log files (configurable via `log_dir` in config) |
| `~/.codex/sessions/` | Session rollout JSONL files |
| `~/.codex/sessions/archived/` | Archived sessions |
| `~/.codex/session_index.jsonl` | Session name index |
| `~/.codex/state_4.sqlite` | SQLite state database (threads, memories) |
| `~/.codex/history.jsonl` | Command history |

#### Session Rollouts

Sessions are stored as JSONL files:
```
~/.codex/sessions/YYYY/MM/DD/rollout-YYYY-MM-DDTHH-MM-SS-<UUID>.jsonl
```

#### SQLite State Database

Thread metadata, memories, and logs are stored in:
```
~/.codex/state_4.sqlite
```

### 4.5 Workspace Files Read

| Path | Purpose |
|---|---|
| `AGENTS.md` | Project documentation |
| `.codex-agents.md` | Alternative project doc |
| `.codex/config.toml` | Project-level config |

### 4.6 Temp Directory Usage

#### Rust (`codex-rs`)

Codex uses the `tempfile` crate extensively. The primary temporary directory usage is:

1. **Arg0 dispatch symlinks**: Created under `$CODEX_HOME/tmp/arg0/` (NOT the system temp dir):

```rust
// codex-rs/arg0/src/lib.rs
let temp_root = codex_home.join("tmp").join("arg0");
std::fs::create_dir_all(&temp_root)?;
let temp_dir = tempfile::Builder::new()
    .prefix("codex-arg0")
    .tempdir_in(&temp_root)?;
```

2. **Sandbox writable roots**: The sandbox policy can include `TMPDIR` and `/tmp` as writable:

```rust
// SandboxPolicy::WorkspaceWrite includes TMPDIR and /tmp by default
// unless exclude_tmpdir_env_var or exclude_slash_tmp is set
```

3. **Test code**: Uses `tempfile::tempdir()` (which defaults to `std::env::temp_dir()` / `TMPDIR`).

4. **State database**: SQLite WAL/SHM files alongside the database.

5. **Clipboard paste**: Temporary files for clipboard image pasting:

```rust
// codex-rs/tui/src/clipboard_paste.rs
use tempfile::Builder;
```

The system temp directory (`TMPDIR`) is referenced in sandbox policies to ensure sandboxed processes can write to temp files.

#### Guard Against Temp-as-Home

In release builds, Codex guards against placing helper binaries under the system temp directory:

```rust
#[cfg(not(debug_assertions))]
{
    let temp_root = std::env::temp_dir();
    if codex_home.starts_with(&temp_root) {
        return Err(...);
    }
}
```

#### Git Repository Access

Codex reads git information from the working directory:
- `.git/` directory structure
- `git log`, `git diff`, `git branch` via `Command::new("git")`
- Git remote URLs
- Recent commits

#### File Watcher

Codex uses the `notify` crate to watch for changes to skill files in `CODEX_HOME`:

```rust
use notify::RecommendedWatcher;
// Watches skill roots for changes, broadcasts FileWatcherEvent::SkillsChanged
```

---

## 5. Tools Available to the LLM

Codex gives the LLM the following tool capabilities:

1. **Shell tool**: The core agent tool -- executes arbitrary shell commands on behalf of the AI. Commands are run via `tokio::process::Command` in sandboxed subprocesses:
```rust
// codex-rs/core/src/spawn.rs
pub(crate) async fn spawn_child_async(request: SpawnChildRequest<'_>) -> std::io::Result<Child> {
    let mut cmd = Command::new(&program);
    cmd.args(args);
    cmd.current_dir(cwd);
    cmd.env_clear();
    cmd.envs(env);
    cmd.kill_on_drop(true).spawn()
}
```

2. **apply_patch**: File editing tool dispatched via the arg0 trick -- allows the AI to apply structured patches to files without needing a full shell command.

3. **MCP tools**: External tools provided by MCP (Model Context Protocol) servers, spawned as child processes. These can provide arbitrary additional capabilities depending on user configuration.

4. **Git operations**: `git init`, `git log`, `git diff`, `git branch`, etc. are available through the shell tool.

All tool calls (except `DangerFullAccess` mode) are sandboxed via the platform-specific sandbox mechanism (Seatbelt on macOS, bubblewrap+Landlock+seccomp on Linux, restricted tokens on Windows).

---

## 6. Host System Interactions

### 6.1 Subprocess Execution

Codex spawns subprocesses extensively:

1. **Shell tool commands**: The core agent functionality -- executing shell commands on behalf of the AI
2. **Git operations**: `git init`, `git log`, `git diff`, `git branch`, etc.
3. **apply_patch**: File editing tool dispatched via arg0 trick
4. **codex-linux-sandbox**: Linux sandbox helper (bubblewrap)
5. **MCP servers**: External processes for tool integrations
6. **Notification commands**: User-configured notify commands
7. **External editor**: Opens external editor for editing
8. **Browser**: `webbrowser::open()` for OAuth flows

### 6.2 Network Requests

| Endpoint | Purpose |
|---|---|
| `https://api.openai.com/v1/` | OpenAI API (API key auth) |
| `https://chatgpt.com/backend-api/codex/` | ChatGPT backend (ChatGPT auth) |
| `https://auth.openai.com/oauth/token` | Token refresh |
| `https://auth.openai.com/` | OAuth authorization (browser) |
| OpenTelemetry endpoints | Telemetry/observability |
| MCP server URLs | MCP tool server communication |
| Ollama/LM Studio local endpoints | Local model providers |

The HTTP client is built with `reqwest`:
```rust
pub fn build_reqwest_client() -> reqwest::Client {
    let mut builder = reqwest::Client::builder()
        // ... headers, timeouts, etc.
    builder.build().unwrap_or_else(|_| reqwest::Client::new())
}
```

#### Network Proxy

Codex includes a full **MITM network proxy** (`codex-network-proxy`) built on the `rama` framework. This allows sandboxed processes to make network requests through a controlled proxy:

```toml
# codex-rs/network-proxy/Cargo.toml
rama-core = { version = "=0.3.0-alpha.4" }
rama-http = { version = "=0.3.0-alpha.4" }
rama-socks5 = { version = "=0.3.0-alpha.4" }
rama-tcp = { version = "=0.3.0-alpha.4", features = ["http"] }
rama-tls-rustls = { version = "=0.3.0-alpha.4", features = ["http"] }
```

### 6.3 Port Binding

1. **Login server** (OAuth callback): Binds to `localhost:1455` (default), configurable:
```rust
const DEFAULT_PORT: u16 = 1455;
```

2. **App server**: WebSocket/HTTP server for desktop app integration (uses Unix domain sockets on Unix)

3. **MCP OAuth callback**: Ephemeral port for MCP server OAuth

4. **Network proxy**: Binds a local proxy for sandboxed network routing

### 6.4 Browser Launching

The `webbrowser` crate is used for:
- OAuth login flow (ChatGPT authentication)
- MCP OAuth (MCP server authorization)

### 6.5 Clipboard Access

Clipboard read/write via the `arboard` crate (not available on Android):

```toml
# codex-rs/tui/Cargo.toml
[target.'cfg(not(target_os = "android"))'.dependencies]
arboard = { workspace = true }
```

Used for:
- Pasting text into the chat composer
- Pasting images from clipboard

### 6.6 File System Watchers

Codex uses the `notify` crate (FSEvents on macOS, inotify on Linux) to watch for changes to skill files in `CODEX_HOME`.

### 6.7 Other

- **Shell integration**: Reads `SHELL` environment variable; detaches child processes from TTY for shell tool calls; sets parent death signal on Linux (`prctl(PR_SET_PDEATHSIG)`); creates process groups for proper signal handling
- **PTY creation**: `openpty()` / `portable-pty` for terminal-based process execution

---

## 7. Extension Points

### 7.1 Hook/Lifecycle System

Codex supports user-configured notification commands that can be triggered on events.

### 7.2 Plugin/Extension Architecture

None identified beyond MCP integration.

### 7.3 MCP Integration

Codex integrates with the **Model Context Protocol (MCP)** as a client:
- MCP servers are spawned as child processes
- MCP OAuth flows use browser-based authorization with ephemeral callback ports
- MCP OAuth credentials stored in keyring or `$CODEX_HOME/.credentials.json`
- Uses the `rmcp` (0.15.0) crate for MCP client functionality

### 7.4 Custom Commands/Skills/Agents

- **Skills directory**: `~/.codex/skills/` -- watched for changes via `notify` crate
- **Custom prompts**: `~/.codex/prompts/`
- **Project docs**: `AGENTS.md` / `.codex-agents.md` read at startup

### 7.5 SDK/API Surface

- **App server** (`codex-rs/app-server`): WebSocket/HTTP server for desktop app integration (e.g., ChatGPT desktop app). Uses Unix domain sockets on Unix.
- **Exec server** (`codex-rs/exec-server`): Posix socket-based exec server for programmatic use.

---

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

Codex has a comprehensive, **platform-specific sandboxing system**. Codex sandboxes its own tool calls, not itself -- the main Codex process runs unsandboxed; only the shell commands it executes for the AI are sandboxed.

From `codex-rs/core/src/exec.rs` and `codex-rs/core/src/safety.rs`:
```rust
pub fn get_platform_sandbox(windows_sandbox_enabled: bool) -> Option<SandboxType> {
    if cfg!(target_os = "macos") {
        Some(SandboxType::MacosSeatbelt)
    } else if cfg!(target_os = "linux") {
        Some(SandboxType::LinuxSeccomp)
    } else if cfg!(target_os = "windows") {
        if windows_sandbox_enabled {
            Some(SandboxType::WindowsRestrictedToken)
        } else { None }
    } else { None }
}
```

#### Sandbox Policies

From the protocol definitions:
```rust
pub enum SandboxPolicy {
    ReadOnly { .. },              // Read-only filesystem, no network
    WorkspaceWrite { .. },        // Write to specific roots only
    DangerFullAccess,             // No sandboxing
    ExternalSandbox { .. },       // External sandbox manages restrictions
}
```

#### macOS: Seatbelt (`sandbox-exec`)

On macOS, Codex uses Apple's **Seatbelt** sandboxing via `/usr/bin/sandbox-exec`. Path is hardcoded for security:
```rust
pub(crate) const MACOS_PATH_TO_SEATBELT_EXECUTABLE: &str = "/usr/bin/sandbox-exec";
```

The base policy starts with **deny-all** and selectively allows:

```scheme
(version 1)

; start with closed-by-default
(deny default)

; child processes inherit the policy of their parent
(allow process-exec)
(allow process-fork)
(allow signal (target same-sandbox))

; Allow cf prefs to work.
(allow user-preference-read)

; process-info
(allow process-info* (target same-sandbox))

; Write to /dev/null only
(allow file-write-data
  (require-all
    (path "/dev/null")
    (vnode-type CHARACTER-DEVICE)))

; Allowed sysctls (hw info, kernel info)
(allow sysctl-read
  (sysctl-name "hw.activecpu")
  (sysctl-name "hw.memsize")
  (sysctl-name "hw.ncpu")
  ;; ... many more hw.* and kern.* entries
)

; Needed for python multiprocessing
(allow ipc-posix-sem)

; allow openpty()
(allow pseudo-tty)
```

For `WorkspaceWrite` mode, the policy generates **parameterized subpath rules**:

```rust
// Writable roots become sandbox-exec parameters
(allow file-write*
  (require-all
    (subpath (param "WRITABLE_ROOT_0"))
    (require-not (subpath (param "WRITABLE_ROOT_0_RO_0")))  // .git excluded
    (require-not (subpath (param "WRITABLE_ROOT_0_RO_1")))  // .codex excluded
  )
  (subpath (param "WRITABLE_ROOT_1"))  // /tmp
  (subpath (param "WRITABLE_ROOT_2"))  // TMPDIR
)
```

**Critical security feature**: `.git/` and `.codex/` directories within writable roots are automatically marked as **read-only subpaths**, preventing the AI from:
- Modifying git hooks (e.g., `.git/hooks/pre-commit`)
- Changing sandbox configuration (`.codex/config.toml`)
- Escalating privileges

When network access is enabled, additional rules are added (`seatbelt_network_policy.sbpl`):

```scheme
; Allow DNS, TLS certificate services
(allow mach-lookup
    (global-name "com.apple.bsd.dirhelper")
    (global-name "com.apple.SecurityServer")
    (global-name "com.apple.networkd")
    (global-name "com.apple.trustd.agent")
    (global-name "com.apple.SystemConfiguration.DNSConfiguration")
    (global-name "com.apple.SystemConfiguration.configd")
)

; Allow writes to Darwin user cache dir (for TLS)
(allow file-write*
  (subpath (param "DARWIN_USER_CACHE_DIR"))
)
```

When a **network proxy** is configured, network access is restricted to the proxy's loopback port only:

```rust
// Only allow outbound to specific localhost ports
(allow network-outbound (remote ip "localhost:43128"))
```

The final `sandbox-exec` invocation looks like:
```
/usr/bin/sandbox-exec -p <POLICY_TEXT> \
  -DWRITABLE_ROOT_0=/path/to/project \
  -DWRITABLE_ROOT_0_RO_0=/path/to/project/.git \
  -DWRITABLE_ROOT_0_RO_1=/path/to/project/.codex \
  -DWRITABLE_ROOT_1=/private/tmp \
  -DDARWIN_USER_CACHE_DIR=/var/folders/xx/... \
  -- bash -c "command here"
```

#### Linux: Bubblewrap + Landlock + Seccomp

On Linux, Codex uses a dedicated `codex-linux-sandbox` helper binary that combines:

1. **Bubblewrap** (vendored at `codex-rs/vendor/bubblewrap/`): Filesystem namespace isolation
2. **Landlock**: Linux security module for filesystem access control
3. **Seccomp**: System call filtering (for network restriction)

From `codex-rs/core/src/landlock.rs`:
```rust
pub(crate) fn create_linux_sandbox_command_args(
    command: Vec<String>,
    sandbox_policy: &SandboxPolicy,
    sandbox_policy_cwd: &Path,
    use_bwrap_sandbox: bool,
    allow_network_for_proxy: bool,
) -> Vec<String> {
    let mut linux_cmd: Vec<String> = vec![
        "--sandbox-policy-cwd".to_string(),
        sandbox_policy_cwd,
        "--sandbox-policy".to_string(),
        sandbox_policy_json,
    ];
    if use_bwrap_sandbox {
        linux_cmd.push("--use-bwrap-sandbox".to_string());
    }
    // ...
}
```

#### Windows: Restricted Token

On Windows, sandboxing uses a **restricted process token** via the `codex-windows-sandbox` crate.

#### Sandbox Decision Flow

1. `SandboxManager::select_initial()` determines the sandbox type based on policy and platform
2. `SandboxManager::transform()` converts a `CommandSpec` into an `ExecRequest` with sandbox wrapping
3. For `DangerFullAccess` with no managed network requirements: `SandboxType::None`
4. For `WorkspaceWrite`/`ReadOnly`: Uses platform sandbox (Seatbelt on macOS)
5. Sandbox denial detection: `is_likely_sandbox_denied()` checks if command failure was due to sandbox

### 8.2 Permission System

Sandbox policies control what the AI can do:
- `ReadOnly`: Read-only filesystem, no network
- `WorkspaceWrite`: Write to specific roots only (with `.git/` and `.codex/` protected)
- `DangerFullAccess`: No sandboxing
- `ExternalSandbox`: External sandbox manages restrictions

### 8.3 Safety Mechanisms

#### Process Hardening

The `codex-process-hardening` crate runs **before main()** via `#[ctor::ctor]`:

**macOS Hardening:**
```rust
pub(crate) fn pre_main_hardening_macos() {
    // 1. Prevent debugger attachment
    let ret_code = unsafe { libc::ptrace(libc::PT_DENY_ATTACH, 0, std::ptr::null_mut(), 0) };

    // 2. Disable core dumps
    set_core_file_size_limit_to_zero();  // setrlimit(RLIMIT_CORE, 0)

    // 3. Remove DYLD_* environment variables (library injection prevention)
    let dyld_keys = env_keys_with_prefix(std::env::vars_os(), b"DYLD_");
    for key in dyld_keys {
        unsafe { std::env::remove_var(key); }
    }
}
```

**Linux Hardening:**
```rust
pub(crate) fn pre_main_hardening_linux() {
    // 1. Mark process non-dumpable (prevents ptrace)
    libc::prctl(libc::PR_SET_DUMPABLE, 0, 0, 0, 0);

    // 2. Disable core dumps
    set_core_file_size_limit_to_zero();

    // 3. Remove LD_* environment variables (preload injection prevention)
    let ld_keys = env_keys_with_prefix(std::env::vars_os(), b"LD_");
    for key in ld_keys { unsafe { std::env::remove_var(key); } }
}
```

#### Sandbox Environment Variables

Codex sets environment variables to signal sandbox state to child processes:

```rust
pub const CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR: &str = "CODEX_SANDBOX_NETWORK_DISABLED";
pub const CODEX_SANDBOX_ENV_VAR: &str = "CODEX_SANDBOX";
// CODEX_SANDBOX is set to "seatbelt" on macOS
```

#### .env Security

The `.env` file in `~/.codex/` is loaded at startup but `CODEX_`-prefixed variables are filtered out for security.

### 8.4 Known Vulnerabilities

None identified.

### 8.5 Enterprise/Managed Security Controls

- **MDM managed preferences** on macOS (`com.openai.codex`) allow enterprise config deployment
- **System-wide requirements** (`/etc/codex/requirements.toml`) can enforce policies
- **Cloud requirements** have highest precedence in config layering

---

## 9. Key Dependencies

### Rust Dependencies (from `codex-rs/Cargo.toml`)

| Dependency | Impact |
|---|---|
| `keyring` (3.6) | OS keychain access (macOS Keychain, Windows Credential Manager, Linux Secret Service) |
| `landlock` (0.4.4) | Linux Landlock LSM |
| `seccompiler` (0.5.0) | Linux seccomp-bpf |
| `libc` (0.2.177) | Raw system calls |
| `arboard` (3) | System clipboard |
| `webbrowser` (1.0) | Browser launching |
| `notify` (8.2.0) | Filesystem watching (FSEvents on macOS, inotify on Linux) |
| `reqwest` (0.12) | HTTP client (TLS, proxies) |
| `sqlx` (0.8.6) | SQLite database |
| `tokio` (1) | Async runtime |
| `portable-pty` (0.9.0) | Pseudo-terminal creation |
| `crossterm` (0.28.1) | Terminal control |
| `ratatui` (0.29.0) | TUI framework |
| `opentelemetry` (0.31.0) | Telemetry |
| `sentry` (0.46.0) | Error reporting |
| `age` (0.11.1) | Encryption |
| `rustls` (0.23) | TLS implementation |
| `tokio-tungstenite` | WebSocket client |
| `tiny_http` (0.12) | HTTP server (for OAuth callback) |
| `tree-sitter` (0.25.10) | Code parsing |
| `image` (0.25.9) | Image processing |
| `dotenvy` (0.15.7) | .env file loading |
| `rmcp` (0.15.0) | MCP (Model Context Protocol) client |
| `rama-*` (0.3.0-alpha.4) | Network proxy framework |

### TypeScript Dependencies

Minimal -- the TypeScript side is just a launcher shim with only `prettier` as a dev dependency.

---

## 10. Environment Variables

### Read by Codex

| Variable | Purpose |
|---|---|
| `CODEX_HOME` | Override config directory (default: `~/.codex`) |
| `OPENAI_API_KEY` | API key for OpenAI API |
| `CODEX_API_KEY` | Alternative API key (higher precedence for some flows) |
| `CODEX_REFRESH_TOKEN_URL_OVERRIDE` | Override token refresh endpoint |
| `CODEX_OSS_PORT` | Port for OSS model provider |
| `CODEX_OSS_BASE_URL` | Base URL for OSS model provider |
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | Override originator header |
| `CODEX_RS_SSE_FIXTURE` | SSE fixture for testing |
| `CODEX_MANAGED_BY_NPM` / `CODEX_MANAGED_BY_BUN` | Set by JS shim |
| `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub MCP access |
| `TMPDIR` | System temp directory (used in sandbox policy) |
| `PATH` | Modified to include arg0 dispatch symlinks |
| `SHELL` | User's shell |
| `HOME` | User's home directory |
| `HTTP_PROXY`, `HTTPS_PROXY`, etc. | Network proxy configuration |

### Set by Codex (for child processes)

| Variable | Purpose |
|---|---|
| `CODEX_SANDBOX` | Sandbox type ("seatbelt" on macOS) |
| `CODEX_SANDBOX_NETWORK_DISABLED` | "1" when network is sandboxed |
| `CODEX_CI` | Set in unified exec test environments |
| `CODEX_POWERSHELL_PAYLOAD` | PowerShell script payload (Windows) |

---

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|---|---|---|---|
| `~/.codex/` | R/W | Primary config and state directory | Yes |
| `~/.codex/config.toml` | R/W | User configuration | No (user-created) |
| `~/.codex/auth.json` | R/W | Auth credentials (mode 0600) | Yes |
| `~/.codex/.credentials.json` | R/W | MCP OAuth credentials | Yes |
| `~/.codex/.env` | R | Environment variable overrides | No (user-created) |
| `~/.codex/log/` | R/W | Log files | Yes |
| `~/.codex/sessions/` | R/W | Session rollout JSONL files | Yes |
| `~/.codex/sessions/archived/` | R/W | Archived sessions | Yes |
| `~/.codex/session_index.jsonl` | R/W | Thread name index | Yes |
| `~/.codex/state_4.sqlite` | R/W | SQLite state DB | Yes |
| `~/.codex/history.jsonl` | R/W | Command history | Yes |
| `~/.codex/prompts/` | R | Custom prompts | No (user-created) |
| `~/.codex/skills/` | R | Skills | No (user-created) |
| `~/.codex/tmp/arg0/` | R/W | Temp symlinks for arg0 dispatch | Yes |
| `/etc/codex/config.toml` | R | System-wide config | No |
| `/etc/codex/requirements.toml` | R | System-wide requirements | No |
| `.codex/config.toml` | R | Project-level config | No (user-created) |
| `.codex/` | R | Project-level config directory | No (user-created) |
| `.git/` | R | Git repository metadata | No |
| `AGENTS.md` | R | Project documentation | No |
| `/usr/bin/sandbox-exec` | Exec | macOS seatbelt | No |
| `/dev/null` | W | Sandboxed output | No |
| `/dev/ptmx` | R/W | PTY master | No |
| `/dev/ttys*` | R/W | PTY slaves | No |
| `$TMPDIR` | R/W | System temp (in sandbox writable roots) | No |
| `/tmp` | R/W | Temp directory (in sandbox writable roots) | No |
| macOS Keychain | R/W | Credential storage via Security framework | N/A |
| MDM Preferences | R | `com.openai.codex` managed preferences | N/A |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|---|---|---|
| `api.openai.com` (HTTPS) | OpenAI API requests | Every LLM API call |
| `chatgpt.com` (HTTPS) | ChatGPT backend API | ChatGPT auth mode |
| `auth.openai.com` (HTTPS) | OAuth token refresh + authorization | Login and token refresh |
| `localhost:1455` (HTTP, inbound) | OAuth callback server | During login flow |
| `localhost:<ephemeral>` (HTTP, inbound) | MCP OAuth callback | MCP server auth |
| Configured MCP server URLs | MCP tool server communication | When using MCP tools |
| OpenTelemetry collector (HTTPS) | Telemetry export | During operation |
| Sentry endpoint (HTTPS) | Error reporting | On errors |
| Local proxy `localhost:*` (HTTP/SOCKS) | Network proxy for sandboxed processes | When proxy enabled |
| Ollama/LM Studio (HTTP) | Local model providers | When configured |
| WebSocket connections (WSS) | Streaming API responses | During LLM calls |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|---|---|---|
| Process spawning | `tokio::process::Command` | Shell tool execution, git, MCP servers |
| Sandbox enforcement (macOS) | `sandbox-exec` (Seatbelt) | Restrict file/network access for tool calls |
| Sandbox enforcement (Linux) | bubblewrap + Landlock + seccomp | Restrict file/network access for tool calls |
| Sandbox enforcement (Windows) | Restricted process tokens | Restrict access for tool calls |
| Anti-debug (macOS) | `ptrace(PT_DENY_ATTACH)` | Prevent debugger attachment |
| Anti-debug (Linux) | `prctl(PR_SET_DUMPABLE, 0)` | Prevent ptrace/core dumps |
| Core dump prevention | `setrlimit(RLIMIT_CORE, 0)` | Disable core dumps (all Unix) |
| Env sanitization (macOS) | Remove `DYLD_*` vars | Prevent library injection |
| Env sanitization (Linux) | Remove `LD_*` vars | Prevent preload injection |
| Keychain access (macOS) | Security framework (via keyring crate) | Store/retrieve auth credentials |
| Keychain access (Linux) | Secret Service D-Bus API | Store/retrieve auth credentials |
| Clipboard | `arboard` crate | Paste text/images (all, not Android) |
| Browser launch | `webbrowser` crate | OAuth login flows |
| Filesystem watching | `notify` crate (FSEvents/inotify/kqueue) | Watch skill file changes |
| PTY creation | `openpty()` / `portable-pty` | Terminal for process execution (Unix) |
| Process groups | `setsid()`, `setpgid()` | Signal management for child processes (Unix) |
| Parent death signal | `prctl(PR_SET_PDEATHSIG)` | Kill children when parent dies (Linux) |
| MDM preferences | Core Foundation (`CFPreferences`) | Read enterprise config (macOS) |
| File locking | `File::try_lock()` | Temp dir cleanup coordination |
| SQLite | `sqlx` (embedded SQLite) | Persistent state storage |
| TLS | `rustls` | Secure network communication |
| DNS | System resolver | Name resolution |

---

## 12. Sandboxing Recommendations

1. **Codex sandboxes its own tool calls**, not itself. The main Codex process runs unsandboxed; only the shell commands it executes for the AI are sandboxed.

2. **On macOS, `sandbox-exec` is the primary sandbox**. The seatbelt profile is deny-by-default and carefully constructed with parameterized writable roots.

3. **`.git/` and `.codex/` are protected** from writes even within writable workspace roots -- this is a security-critical feature preventing the AI from modifying git hooks or sandbox configuration.

4. **Network access can be proxy-routed**: When a network proxy is configured, sandboxed processes can only connect to the proxy's loopback port, not directly to the internet.

5. **Process hardening is aggressive**: Anti-debug (PT_DENY_ATTACH on macOS), core dump prevention, and environment sanitization (DYLD_*/LD_* removal) are applied before `main()`.

6. **Credentials use macOS Keychain** by default (via `apple-native` keyring feature), with fallback to `auth.json` file with 0600 permissions.

7. **The `.env` file in `~/.codex/`** is loaded at startup but `CODEX_`-prefixed variables are filtered out for security.

8. **The login server binds to localhost:1455** for OAuth callbacks -- this is a brief-lived HTTP server.

9. **All state is under `~/.codex/`** (or `CODEX_HOME`). This includes SQLite databases, session files, auth tokens, config, and logs.

10. **MCP server processes** are spawned as child processes and can have their own OAuth flows with browser-based authorization.
