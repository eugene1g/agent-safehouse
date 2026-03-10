# GitHub Copilot CLI -- Sandbox Analysis Report

**Analysis Date:** 2026-03-09
**Repository:** https://github.com/github/copilot-cli
**Git Commit:** `6c50fd21d4fdb34470828bd86403babd7f2429b1`
**Latest Version:** 1.0.2
**License:** Proprietary (source-available client, custom license)
**Source Availability:** Source-available (client code visible on GitHub; AI models and backend services are closed-source)

---

## 1. Overview

GitHub Copilot CLI is a **terminal-native AI coding agent** from GitHub. It brings the same agentic capabilities as the GitHub Copilot coding agent directly into the command line. The tool is built on Node.js and distributed as the npm package `@github/copilot`.

The repository at `github/copilot-cli` contains only a `README.md`, `LICENSE.md`, `changelog.md`, and an `install.sh` script. The actual CLI binary is a prebuilt Node.js application distributed via npm, Homebrew, or direct install script -- the implementation source code is not publicly available.

Entry point:
```bash
copilot
```

Installation methods:
- **npm:** `npm install -g @github/copilot`
- **Homebrew:** `brew install copilot-cli`
- **Install script:** `curl -fsSL https://gh.io/copilot-install | bash`
- **WinGet (Windows):** `winget install GitHub.Copilot`

The CLI requires an active GitHub Copilot subscription (Individual, Pro, Business, or Enterprise). Each prompt consumes one premium request from the user's monthly quota.

---

## 2. UI & Execution Modes

### Primary UI: Interactive Terminal (TUI)

Copilot CLI is a **terminal-based interactive agent**. On launch, it presents a conversational interface where users type natural-language prompts. The agent responds with explanations, code suggestions, file edits, and shell commands.

Key UI features:
- **Animated banner** on first launch (re-show with `--banner`)
- **Slash commands** for control (`/login`, `/model`, `/feedback`, `/mcp`, `/lsp`, `/experimental`, etc.)
- **`@` references** to attach files or directories to context
- **`!` prefix** for direct shell execution
- **Streaming output** with markdown rendering
- **Mode cycling** via `Shift+Tab`

### Execution Modes

- **Interactive mode (default):** The user approves every tool call (file edit, shell command) before execution. Maximum control.
- **Plan mode:** Copilot builds a step-by-step plan before executing. User reviews and approves the plan.
- **Autopilot mode (experimental):** Copilot proceeds autonomously, handling tool calls and iteration without user interrupts. Activated via `--experimental` flag or `/experimental` command.

### Non-Interactive Mode

Copilot CLI can be invoked with a prompt argument for one-shot, non-interactive usage:
```bash
copilot "explain this error" < error.log
```

### VS Code Integration

Copilot CLI sessions can also run within Visual Studio Code's Chat view, supporting multiple parallel sessions with workspace isolation.

### Browser Launching

The CLI launches a browser in two scenarios:
1. **OAuth login flow** (`/login`): Opens `github.com/login/device` for device code authentication
2. **MCP OAuth**: Opens browser for MCP server authorization when required

---

## 3. Authentication & Credentials

### Credential Storage

Authentication tokens are stored via **macOS Keychain** (via the system's native secure credential storage). If the keychain is unavailable, tokens may fall back to storage in `~/.copilot/config.json`.

The CLI can also piggyback on credentials from the **GitHub CLI** (`gh`), reading tokens from `~/.config/gh/hosts.yml`.

### Authentication Methods

1. **OAuth device flow (primary):** `/login` triggers a browser-based device code flow via `github.com/login/device`. The user authorizes in the browser and the CLI receives a token.
2. **Personal Access Token (PAT):** A fine-grained PAT with "Copilot Requests" permission can be set via environment variables.
3. **GitHub CLI credentials:** If `gh` is authenticated, Copilot CLI can use its stored tokens.

### Token Precedence

| Priority | Source | Variable / Location |
|----------|--------|---------------------|
| 1 (highest) | Environment variable | `COPILOT_GITHUB_TOKEN` |
| 2 | Environment variable | `GH_TOKEN` |
| 3 | Environment variable | `GITHUB_TOKEN` |
| 4 | GitHub CLI | `~/.config/gh/hosts.yml` |
| 5 (lowest) | Interactive login | OAuth device flow → Keychain |

### Keychain Usage

On macOS, the OAuth token obtained via `/login` is stored in the system Keychain. This is the reason the Safehouse profile for Copilot CLI declares a `$$require=55-integrations-optional/keychain.sb$$` dependency.

---

## 4. Configuration & Filesystem

### Configuration Hierarchy

Copilot CLI merges configuration from multiple sources (highest priority first):

1. **CLI arguments** (e.g., `--model`, `--experimental`)
2. **Environment variables** (`COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, etc.)
3. **User-level config** (`~/.copilot/config.json`)
4. **Repository-level config** (`.github/copilot-instructions.md`, `.github/hooks/`, `.github/lsp.json`)
5. **Built-in defaults**

### User-Level Configuration (`~/.copilot/`)

| File / Directory | Purpose |
|------------------|---------|
| `config.json` | Core settings (model, editor, theme, trusted folders) |
| `mcp-config.json` | MCP server definitions |
| `lsp-config.json` | Language Server Protocol server configuration |
| `copilot-instructions.md` | Global custom instructions for the agent |
| `command-history-state.json` | Command history |
| `session-state/` | Active session data |
| `history-session-state/` | Historical session data |
| `agents/` | Custom agent definitions (`.agent.md` files) |
| `hooks/` | Personal hooks (apply across all repositories) |
| `logs/` | Debug and error logs |

### Repository-Level Configuration

| File / Directory | Purpose |
|------------------|---------|
| `.github/copilot-instructions.md` | Repository-wide agent instructions |
| `.github/instructions/**/*.instructions.md` | Modular per-topic instructions |
| `.github/hooks/` | Repository hooks (`preToolUse.json`, etc.) |
| `.github/lsp.json` | Repository-level LSP server configuration |
| `AGENTS.md`, `Copilot.md` | Agent behavior instructions (read by convention) |
| `.copilot/` | Project-level Copilot config (if present) |

### Trusted Directories

Copilot CLI prompts the user to trust a directory on first use. Trusted directories are persisted in `config.json` under `trusted_folders`. Only trusted directories (and subdirectories) are accessible for read/write/exec operations.

---

## 5. Tools Available to LLM

Copilot CLI exposes a set of tools that the underlying LLM can invoke during agentic operation. Each tool call requires user approval unless permissions have been pre-granted.

### Built-in Tools

| Tool | Description |
|------|-------------|
| **Shell execution** | Execute arbitrary shell commands in the user's terminal |
| **File read** | Read file contents and attach to context |
| **File write/edit** | Create or modify files in the workspace |
| **Web fetch** | Retrieve content from URLs |
| **Git operations** | Interact with git (status, diff, commit, etc.) via shell |
| **GitHub API** | Access repositories, issues, PRs via built-in GitHub MCP server |

### Tool Permission Controls

- **`--allow-tool TOOL`**: Pre-approve a specific tool (e.g., `shell(git status)`)
- **`--deny-tool TOOL`**: Block a specific tool permanently
- **`--allow-all-tools`** / `/allow-all`: Skip all individual tool prompts (autopilot)
- **`--dangerously-skip-permissions`**: Skip all permission checks entirely (tool, path, URL)
- **`/add-dir PATH`**: Grant access to an additional directory

### MCP Tools

Copilot CLI ships with **GitHub's MCP server** built in, providing tools for repository, issue, and PR management. Additional MCP servers can be added via `mcp-config.json` or `/mcp add`.

---

## 6. Host System Interactions

### Process Spawning

Copilot CLI spawns child processes for:
- Shell command execution (user-approved tool calls)
- Git operations
- MCP server processes (stdio-based or HTTP)
- LSP server processes
- Browser launch for OAuth flows

### Network Activity

All LLM inference happens server-side via GitHub's API. The CLI makes HTTPS requests to:
- `api.github.com` -- GitHub API and Copilot completions
- `mcp.github.com` -- Built-in GitHub MCP server
- Custom MCP server URLs (if configured)

### Filesystem Access

The CLI reads and writes files within:
- `~/.copilot/` -- Configuration, state, logs, and session data
- The current working directory (trusted) -- Project files being edited
- `~/.config/gh/` -- GitHub CLI credentials (read-only)
- `$TMPDIR` -- Temporary files

### LSP Integration

Copilot CLI supports Language Server Protocol for enhanced code intelligence. LSP servers are external processes configured via `lsp-config.json` and spawned as needed.

---

## 7. Extensions & Plugins

### Custom Agents

Users can define custom agent behaviors via `.agent.md` files placed in `~/.copilot/agents/` (global) or the repository root. These provide specialized instructions and tool access for specific workflows.

### MCP Servers

MCP (Model Context Protocol) servers extend Copilot CLI's capabilities:
- **Built-in:** GitHub MCP server (repository, issues, PRs)
- **User-configured:** Added via `~/.copilot/mcp-config.json` or `/mcp add`
- **Types:** stdio-based (local process) or HTTP/SSE (remote)

### Hooks System

Copilot CLI supports lifecycle hooks for workflow automation:

| Hook Event | Trigger |
|------------|---------|
| `sessionStart` | New session begins or resumes |
| `sessionEnd` | Session ends or is terminated |
| `userPromptSubmitted` | User submits a prompt |
| `preToolUse` | Before a tool executes (can allow/deny) |
| `postToolUse` | After a tool executes |
| `errorOccurred` | On error |

Hooks are configured in:
- `.github/hooks/*.json` (repository-level)
- `~/.copilot/hooks/` (personal, all repositories)

The `preToolUse` hook is particularly powerful -- it can output a `permissionDecision` of `allow` or `deny` to programmatically control tool execution.

---

## 8. Sandbox Model

### No Built-in OS-Level Sandbox

Copilot CLI **does not implement OS-level sandboxing** (no `sandbox-exec`, no seccomp, no containers). All operations run with the full privileges of the invoking user.

### Application-Level Permission System

Instead of OS sandboxing, Copilot CLI relies on an **application-level permission model**:

1. **Trusted directories:** Only directories explicitly trusted by the user are accessible
2. **Per-tool approval:** Each tool call requires user confirmation (unless pre-approved)
3. **Tool allowlists/denylists:** Fine-grained control over which tools can execute
4. **Hooks:** Programmatic allow/deny decisions via `preToolUse` hooks

### Permission Escalation Flags

| Flag | Effect | Risk |
|------|--------|------|
| (default) | Prompt for every tool call | Lowest |
| `--allow-tool TOOL` | Pre-approve specific tools | Low |
| `--allow-all-tools` | Skip all tool prompts | Medium |
| `--dangerously-skip-permissions` | Skip ALL permission checks | Highest |

### Key Limitation

The permission system is **advisory, not enforced by the OS kernel**. A bug or exploit in the CLI itself could bypass these checks. This is the primary reason external sandboxing (like Agent Safehouse) is valuable.

---

## 9. Dependencies

### Runtime Requirements

| Dependency | Purpose |
|------------|---------|
| Node.js (bundled) | Runtime for the CLI binary |
| npm / Homebrew / install script | Installation |
| System Keychain (macOS) | Credential storage |
| Git | Version control operations |
| Browser | OAuth login flow |

### npm Package

The CLI is distributed as `@github/copilot` on npm. The package bundles the prebuilt application -- it does not compile from source during installation.

---

## 10. Environment Variables

| Variable | Purpose |
|----------|---------|
| `COPILOT_GITHUB_TOKEN` | Authentication token (highest priority) |
| `GH_TOKEN` | Authentication token (second priority) |
| `GITHUB_TOKEN` | Authentication token (third priority) |
| `HTTPS_PROXY` / `HTTP_PROXY` | Proxy configuration |
| `NO_PROXY` | Proxy bypass list |
| `NO_BROWSER` | Disable automatic browser opening |
| `XDG_CONFIG_HOME` | Override config directory base path |

---

## 11. Summary Tables

### 11.1 All Filesystem Paths

| Path | Access | Purpose | Created by Agent |
|------|--------|---------|------------------|
| `~/.copilot/` | R/W | Main config and state directory | Yes |
| `~/.copilot/config.json` | R/W | Core settings (model, theme, trusted folders) | Yes |
| `~/.copilot/mcp-config.json` | R/W | MCP server configuration | Yes |
| `~/.copilot/lsp-config.json` | R/W | LSP server configuration | Yes |
| `~/.copilot/copilot-instructions.md` | R | Global custom instructions | No (user-created) |
| `~/.copilot/command-history-state.json` | R/W | Command history | Yes |
| `~/.copilot/session-state/` | R/W | Active session data | Yes |
| `~/.copilot/history-session-state/` | R/W | Historical session data | Yes |
| `~/.copilot/agents/` | R | Custom agent definitions | No (user-created) |
| `~/.copilot/hooks/` | R | Personal hooks | No (user-created) |
| `~/.copilot/logs/` | R/W | Debug and error logs | Yes |
| `~/.config/gh/hosts.yml` | R | GitHub CLI credentials (fallback auth) | No |
| `~/.local/bin/copilot` | R | CLI binary (npm/local install) | No (installer) |
| `~/bin/copilot` | R | CLI binary (alternative location) | No (installer) |
| `/opt/homebrew/bin/copilot` | R | CLI binary (Homebrew install) | No (installer) |
| `.github/copilot-instructions.md` | R | Repository agent instructions | No (user-created) |
| `.github/instructions/**/*.instructions.md` | R | Modular repo instructions | No (user-created) |
| `.github/hooks/*.json` | R | Repository hooks config | No (user-created) |
| `.github/lsp.json` | R | Repository LSP config | No (user-created) |
| `AGENTS.md` / `Copilot.md` | R | Agent behavior instructions | No (user-created) |
| `$TMPDIR` | R/W | Temporary files | Yes |
| macOS Keychain | R/W | OAuth token storage | N/A |
| User project files | R/W | Code files being edited | Modified by agent |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `api.github.com` (HTTPS) | GitHub API, Copilot completions | Every LLM call, GitHub operations |
| `mcp.github.com` (HTTPS) | Built-in GitHub MCP server | GitHub context queries (issues, PRs, repos) |
| `github.com/login/device` (HTTPS) | OAuth device code flow | During `/login` |
| Custom MCP server URLs (HTTPS/stdio) | User-configured MCP servers | When MCP tools are invoked |
| LSP server processes (stdio) | Language server communication | During code intelligence operations |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Process spawning | `child_process` (Node.js) | Shell commands, git, MCP servers, LSP servers |
| Keychain access (macOS) | Security framework | Store/retrieve OAuth tokens |
| Browser launch | System default browser | OAuth login flow, MCP OAuth |
| Filesystem access | Node.js `fs` | Config, state, project files, logs |
| Network requests | HTTPS | GitHub API, MCP servers |
| Terminal I/O | stdin/stdout | Interactive TUI, streaming output |
| DNS | System resolver | Name resolution for API endpoints |

---

## 12. Sandboxing Recommendations

1. **No built-in OS sandboxing**: Copilot CLI relies entirely on application-level permission checks. All file and network operations run with full user privileges. External sandboxing is strongly recommended.

2. **`~/.copilot/` is the primary data directory**: All config, state, session data, logs, and MCP config live here. The Safehouse profile grants read/write access to this entire subtree.

3. **Keychain access is required for authentication**: The CLI stores OAuth tokens in macOS Keychain. The Safehouse profile correctly declares a dependency on the keychain integration (`$$require=55-integrations-optional/keychain.sb$$`).

4. **GitHub CLI credential fallback**: If the user authenticates via `gh` CLI, Copilot CLI reads `~/.config/gh/hosts.yml`. Consider whether read access to this path should be granted based on your auth strategy.

5. **`--dangerously-skip-permissions` is the key flag for sandboxed use**: When running inside Agent Safehouse, use this flag to disable the redundant application-level permission prompts -- the OS sandbox provides the real enforcement layer.

6. **MCP servers are spawned as child processes**: Custom MCP servers run within the sandbox. Ensure their required paths and network access are covered by your policy.

7. **LSP servers are spawned as child processes**: Language servers need access to project files and potentially to toolchain binaries. Ensure relevant toolchain profiles are enabled.

8. **Shell command execution**: The agent's most powerful tool. In autopilot mode or with `--allow-all-tools`, commands run without user confirmation. The external sandbox is the critical safety net.

9. **Network access**: All traffic goes to `*.github.com` domains by default. Custom MCP servers may require additional network endpoints. The baseline network profile should cover GitHub API access.

10. **Trusted directory prompts are bypassed in non-interactive mode**: When piping input or running headless, ensure the sandbox constrains filesystem access appropriately since the interactive trust prompt may not appear.
