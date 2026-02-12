# Claude Code -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/anthropics/claude-code
**Git Commit:** `76a2154fd5e7e6db75119593bd68d84b0eb7e154`
**Latest Version:** 2.1.39
**License:** Proprietary (Anthropic Commercial Terms of Service)
**Source Availability:** Docs-only repo

---

## Disclaimer

**This repository is a documentation/examples/plugins-only repository.** The actual Claude Code agent binary is closed-source and compiled. It is distributed via:
- Native installer: `curl -fsSL https://claude.ai/install.sh | bash` (macOS/Linux)
- Homebrew: `brew install --cask claude-code`
- Windows installer: `irm https://claude.ai/install.ps1 | iex`
- WinGet: `winget install Anthropic.ClaudeCode`
- npm (deprecated): `npm install -g @anthropic-ai/claude-code`

The npm package name is `@anthropic-ai/claude-code`. The repository contains **no source code** for the CLI itself. Everything documented below is inferred from publicly available documentation, CHANGELOG entries, example configurations, plugin interfaces, and scripts.

---

## 1. Overview

[INFERRED] Claude Code is Anthropic's proprietary AI coding agent distributed as a compiled binary (Node.js-based). It operates primarily as a **CLI/TUI** application that runs in the user's terminal, with additional integration as a **VS Code extension** (`anthropic.claude-code`) and a **Desktop application** (Claude Code for Desktop, v2.0.51). It supports headless/non-interactive mode via `--print` / `-p`, SDK-driven automation via the TypeScript SDK (`@anthropic-ai/claude-agent-sdk`) and Python SDK (`claude-code-sdk`), and remote sessions from `claude.ai`.

The repository itself contains documentation, examples, plugin definitions, DevContainer configuration, and CI scripts -- but no agent source code. It hosts 14 official plugins providing commands, agents, hooks, and skills.

### Repository Contents

| Path | Description |
|------|-------------|
| `README.md` | Installation instructions and basic overview |
| `CHANGELOG.md` | Detailed release notes from v0.2.21 through v2.1.39 (1677 lines) |
| `SECURITY.md` | Vulnerability disclosure via HackerOne |
| `LICENSE.md` | Proprietary -- Anthropic Commercial Terms |
| `examples/` | Settings examples and hook examples |
| `plugins/` | 14 official plugins (commands, agents, hooks, skills) |
| `.devcontainer/` | DevContainer configuration with network firewall |
| `scripts/` | GitHub issue management scripts (TypeScript/Bash) |
| `Script/` | PowerShell script for Windows DevContainer setup |
| `.claude/` | Custom slash commands for the repo itself |
| `.github/` | CI workflows and issue templates |
| `.claude-plugin/` | Marketplace manifest for bundled plugins |
| `demo.gif` | Demo animation (~11 MB) |

### Version Timeline (from CHANGELOG)

| Version | Milestone |
|---------|-----------|
| 0.2.x | Early development: MCP support, file suggestions, image paste, web fetch |
| 0.2.96 | Claude Max subscription support |
| 1.0.0 | General availability; Sonnet 4 and Opus 4 models |
| 1.0.23 | TypeScript SDK released (`@anthropic-ai/claude-code`), Python SDK (`claude-code-sdk`) |
| 1.0.38 | Hooks system released |
| 1.0.60 | Custom subagents |
| 2.0.0 | Native VS Code extension, `/rewind`, UI overhaul, Agent SDK rename |
| 2.0.12 | Plugin system released |
| 2.0.20 | Claude Skills introduced |
| 2.0.24 | Sandbox mode for BashTool (Linux & Mac) |
| 2.0.45 | Microsoft Foundry support; `PermissionRequest` hook |
| 2.0.51 | Opus 4.5; Claude Code for Desktop |
| 2.0.60 | Background agents |
| 2.1.0 | Automatic skill hot-reload; hooks in agent/skill frontmatter |
| 2.1.16 | Task management system |
| 2.1.32 | Opus 4.6; Agent Teams (multi-agent collaboration, experimental) |
| 2.1.36 | Fast mode for Opus 4.6 |
| 2.1.39 | Current version |

## 2. UI & Execution Modes

[INFERRED] Claude Code renders its TUI in the terminal (Node.js-based). It supports the following execution modes:

- **Interactive TUI**: Full terminal UI with alternate-screen-like rendering, syntax highlighting (native engine, v2.0.71), vim bindings (v0.2.34), emacs/readline keybindings, external editor support (Ctrl+G), image paste (Ctrl+V/Cmd+V), themes (`/theme`), reduced motion mode, CJK/IME support, and custom keyboard shortcuts (`/keybindings`, v2.1.18). iTerm2 progress bar via OSC 9;4. Clickable hyperlinks for file paths via OSC 8 (v2.1.2).
- **Non-interactive/print mode**: `--print` / `-p` flag bypasses the TUI and outputs directly to stdout. Supports structured output formats (`--output-format stream-json`).
- **VS Code extension**: Native VS Code extension (`anthropic.claude-code`) with sidebar support (primary and secondary), IDE diff tabs for file changes, LSP integration (v2.0.74), auto Python virtual environment activation.
- **Desktop application**: Claude Code for Desktop (v2.0.51).
- **SDK/headless mode**: Programmatic use via TypeScript SDK (`@anthropic-ai/claude-agent-sdk`) and Python SDK (`claude-code-sdk`). Supports session management, custom tools as callbacks, partial message streaming, structured outputs, and auto-exit after idle (`CLAUDE_CODE_EXIT_AFTER_STOP_DELAY`).
- **Remote sessions**: Sessions from `claude.ai` (v2.1.33) with "Teleport" between web and CLI (v2.0.24, v2.1.0).
- **Background agents**: Autonomous background execution (v2.0.60) with background command execution (Ctrl+B, v1.0.71).
- **Agent Teams**: Multi-agent collaboration mode (experimental, v2.1.32, requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).

### Output Styles

- Built-in styles: "Explanatory", "Learning" (v1.0.81, deprecated v2.0.30, un-deprecated v2.0.32)
- Custom output styles via `--system-prompt`, `--system-prompt-file`, `--append-system-prompt`, CLAUDE.md, or plugins
- Plugin-based output styles (v2.0.41)

### Slash Commands (built-in, selected)

`/bug`, `/clear`, `/compact`, `/config`, `/context`, `/copy`, `/debug`, `/doctor`, `/export`, `/fast`, `/feedback`, `/help`, `/hooks`, `/keybindings`, `/login`, `/memory`, `/mcp`, `/model`, `/permissions`, `/plan`, `/plugin`, `/remote-env`, `/rename`, `/resume`, `/rewind`, `/sandbox`, `/settings`, `/skills`, `/stats`, `/status`, `/tasks`, `/teleport`, `/terminal-setup`, `/theme`, `/usage`, `/vim`

## 3. Authentication & Credentials

[INFERRED] All authentication details below are inferred from CHANGELOG and public documentation.

### 3.1 Credential Storage

On macOS, API keys are stored in the system Keychain (v0.2.30). A `security unlock-keychain` hint is provided when the keychain is locked (v2.0.30). OAuth tokens are managed by Claude Code, cached, and proactively refreshed before expiration (v1.0.110).

### 3.2 API Key Sources and Priority Order

1. **API Key** (`ANTHROPIC_API_KEY`): Direct Anthropic API key.
2. **API Key Helper**: Dynamic key generation via `apiKeyHelper` setting with configurable TTL (`CLAUDE_CODE_API_KEY_HELPER_TTL_MS`). 5-minute default TTL (v0.2.74). Ability to set `Proxy-Authorization` via `ANTHROPIC_AUTH_TOKEN` was removed in v1.0.37.
3. **AWS Bedrock**: `AWS_BEARER_TOKEN_BEDROCK` (v1.0.51), `aws login` credentials (v2.0.64), `awsAuthRefresh` / `awsCredentialExport` helper settings (v1.0.53), cross-region inference model configuration.
4. **Google Vertex AI**: `CLOUD_ML_REGION` with fallback (v1.0.8). Configuration via `settings.json` (v2.0.47).
5. **Microsoft Foundry**: Added in v2.0.45.
6. **Claude Pro/Max/Subscription**: OAuth-based authentication for claude.ai subscribers. Includes `/upgrade` command (v1.0.11), `/usage` for plan limits (v2.0.0).

### 3.3 OAuth Flows

- Browser-based OAuth flow. URLs moved from `console.anthropic.com` to `platform.claude.com` (v2.1.7).
- On Windows, OAuth uses port 45454 (v1.0.54).
- Keyboard shortcut 'c' to copy OAuth URL when browser does not open (v2.1.10).
- MCP OAuth: SSE and HTTP MCP servers support OAuth with automatic browser flow (v1.0.27). Includes pre-configured OAuth client credentials for servers like Slack (v2.1.30). OAuth Authorization Server discovery (v1.0.35), Dynamic Client Registration (v2.1.30).

### 3.4 Credential File Locations and Formats

- macOS Keychain for API keys
- OAuth tokens cached internally by the agent
- `forceLoginMethod` setting: Bypass login selection screen (v1.0.32)
- `CLAUDE_CODE_AUTO_CONNECT_IDE=false`: Disable IDE auto-connection (v1.0.61)

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

The main configuration directory is `~/.claude/` (customizable via `CLAUDE_CONFIG_DIR`). On XDG-compliant systems, `XDG_CONFIG_HOME` is also supported (v1.0.28).

| Path | Purpose |
|------|---------|
| `~/.claude/` | Primary config directory |
| `~/.claude.json` | Legacy global user config (pre-1.0.7 settings) |
| `~/.claude/settings.json` | User-level settings |
| `~/.claude/settings.local.json` | User-level local settings |
| `~/.claude/skills/` | User-level skills (auto-reloaded, v2.1.0) |
| `~/.claude/commands/` | User-level custom slash commands |
| `~/.claude/rules/` | User-level rules (v2.0.64) |
| `~/.claude/security_warnings_state_*.json` | Per-session state for security plugin |

### 4.2 Project-Level Config Paths

| Path | Purpose |
|------|---------|
| `.claude/settings.json` | Shared project settings (committable) |
| `.claude/settings.local.json` | Local project settings (gitignored) |
| `.claude/commands/` | Project slash commands |
| `.claude/skills/` | Project skills |
| `.claude/rules/` | Project rules |
| `.claude/*.local.md` | Plugin state files (gitignored) |
| `.mcp.json` | Project-scope MCP server configuration |
| `CLAUDE.md` | Project instruction file (supports `@path/to/file.md` imports) |

### 4.3 System/Enterprise Config Paths

| Path | Purpose |
|------|---------|
| `managed-settings.json` | Organization-managed settings |
| (Windows, deprecated) `C:\ProgramData\ClaudeCode\managed-settings.json` | Old Windows managed path |
| (Windows, current) `C:\Program Files\ClaudeCode\managed-settings.json` | Current Windows managed path |

#### Settings Hierarchy (highest to lowest priority)

1. Enterprise managed settings (`managed-settings.json`)
2. User settings (`~/.claude/settings.json`)
3. User local settings (`~/.claude/settings.local.json`)
4. Project settings (`.claude/settings.json`)
5. Project local settings (`.claude/settings.local.json`)
6. CLI flags and environment variables

### 4.4 Data & State Directories

| Path/Variable | Purpose |
|---------------|---------|
| `CLAUDE_CODE_TMPDIR` | Override temp directory for internal temp files (v2.1.5) |
| `/tmp/security-warnings-log.txt` | Debug log for security hook plugin |
| Per-user temp directory | Isolated temp dirs to prevent permission conflicts (v2.1.23) |
| Shell snapshots | Moved from `/tmp` to `~/.claude` for reliability (v1.0.48) |
| Transcript files | Session transcript JSONL files (path provided to hooks) |
| Plan files | Customizable via `plansDirectory` setting (v2.1.9) |
| Config backups | Timestamped, rotated (5 most recent), in home directory (v2.1.20) |

#### Session Management

- Session persistence and resume (`--continue`, `--resume`)
- Named sessions (`/rename`, v2.0.64)
- Session forking with custom IDs
- Transcript files (JSONL format)
- Automatic context compaction
- 5-hour session time limit
- Session linking to PRs (v2.1.27)
- Remote sessions from claude.ai (v2.1.33)

### 4.5 Workspace Files Read

- `CLAUDE.md` (project root, `.claude/CLAUDE.md`, nested directories)
- Additional directories via `--add-dir` (when `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`)
- `@path/to/file.md` import syntax (v0.2.107), binary file exclusion from imports (v2.1.2)
- `.claude/rules/` directories (v2.0.64), auto-discovered from nested directories
- `.gitignore` respected by default (configurable via `respectGitignore`)

### 4.6 Temp Directory Usage

- `CLAUDE_CODE_TMPDIR` overrides the temp directory for internal temp files (v2.1.5)
- Per-user temp directory isolation to prevent permission conflicts (v2.1.23)
- Shell snapshots moved from `/tmp` to `~/.claude` for reliability (v1.0.48)

#### DevContainer Paths

The included DevContainer configuration mounts:
- `/workspace` -- bind-mount of the local workspace
- `/commandhistory` -- persistent bash history volume
- `/home/node/.claude` -- persistent Claude config volume
- `CLAUDE_CONFIG_DIR=/home/node/.claude`

#### Key Settings Fields (inferred from examples and CHANGELOG)

```json
{
  "permissions": {
    "allow": [],
    "ask": [],
    "deny": [],
    "disableBypassPermissionsMode": "disable"
  },
  "allowManagedPermissionRulesOnly": false,
  "allowManagedHooksOnly": false,
  "strictKnownMarketplaces": [],
  "sandbox": { "..." },
  "disallowedTools": [],
  "disableAllHooks": false,
  "language": "english",
  "spinnerVerbs": [],
  "spinnerTipsEnabled": true,
  "showTurnDuration": true,
  "attribution": {},
  "respectGitignore": true,
  "fileSuggestion": {},
  "plansDirectory": "./plans",
  "companyAnnouncements": "",
  "temperatureOverride": null,
  "cleanupPeriodDays": 30,
  "forceLoginMethod": null,
  "reducedMotionMode": false,
  "extraKnownMarketplaces": [],
  "env": {}
}
```

#### Example Settings Profiles

**Strict (enterprise):**
- Disable `--dangerously-skip-permissions`
- Block all plugin marketplaces
- Block user/project permission rules and hooks
- Deny web tools
- Require approval for Bash
- Full network isolation in sandbox

**Lax (enterprise):**
- Disable `--dangerously-skip-permissions`
- Block plugin marketplaces
- All other defaults

**Bash sandbox:**
- Block user/project permission rules
- Enable sandbox for all Bash
- No auto-allow, no unsandboxed commands
- Full network isolation

## 5. Tools Available to the LLM

[INFERRED] The following tools are provided to the LLM for autonomous use, inferred from CHANGELOG and hook system documentation:

| Tool | Purpose |
|------|---------|
| `Bash` | Execute shell commands (with sandbox support) |
| `Read` | Read files (supports PDFs with `pages` parameter, Jupyter notebooks, images) |
| `Write` | Write files (respects umask, not hardcoded 0o600 since v2.1.0) |
| `Edit` | Edit files (exact string replacement) |
| `MultiEdit` | Multiple edits in one file |
| `Glob` | File pattern matching |
| `Grep` / Search | Ripgrep-based content search (built-in ripgrep, v1.0.84) |
| `WebSearch` | Web search |
| `WebFetch` | Fetch URLs |
| `Task` | Spawn subagents |
| `TaskOutput` | Read subagent output (unified, replaced AgentOutputTool/BashOutputTool v2.0.64) |
| `TaskUpdate` | Update/delete tasks (v2.1.20) |
| `TaskStop` | Stop tasks |
| `NotebookEdit` | Edit Jupyter notebooks |
| `SlashCommand` | Invoke slash commands (v1.0.123) |
| `Skill` | Invoke skills |
| `AskUserQuestion` | Interactive questions (v2.0.21) |
| `TodoWrite` | Todo list management (v0.2.93, v2.1.16 task management) |
| `LS` | List directories (renamed from LSTool, v0.2.82) |
| `LSP` | Language Server Protocol integration (v2.0.74) |
| `MCPSearch` | Deferred MCP tool discovery (v2.1.7) |
| `ToolSearch` | Search for available tools |
| `SendMessage` | Agent team messaging (v2.1.32) |

### Tool Permissions Configuration

Settings files support per-tool permission rules:

```json
{
  "permissions": {
    "allow": ["Read", "Glob", "Grep", "Bash(git log:*)"],
    "ask": ["Bash"],
    "deny": ["WebSearch", "WebFetch"]
  }
}
```

## 6. Host System Interactions

### 6.1 Subprocess Execution

- Spawns child processes for Bash commands
- Background command execution (Ctrl+B, v1.0.71)
- Auto-background long-running commands instead of killing them (v2.0.19)
- Shell environment snapshots (in-memory since v1.0.54)
- Persistent shell session management
- Process cleanup on exit (SIGKILL fallback, v2.1.19)
- Built-in ripgrep binary for Grep/Search tool (v1.0.84)
- Git operations: log, show, diff, status, fetch, rebase, etc.
- GitHub CLI (`gh`) commands for PR creation and review

### 6.2 Network Requests

#### LLM API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `api.anthropic.com` | Primary Anthropic API |
| `platform.claude.com` | OAuth and API Console (formerly `console.anthropic.com`) |
| `claude.ai` | Installation scripts, web sessions |

#### Telemetry & Infrastructure

| Endpoint | Purpose |
|----------|---------|
| `sentry.io` | Error reporting/telemetry |
| `statsig.anthropic.com` | Feature flags / analytics |
| `statsig.com` | Feature flags |
| `registry.npmjs.org` | npm package resolution (for npm installs) |

#### IDE Marketplace

| Endpoint | Purpose |
|----------|---------|
| `marketplace.visualstudio.com` | VS Code extension marketplace |
| `vscode.blob.core.windows.net` | VS Code extension binaries |
| `update.code.visualstudio.com` | VS Code updates |

#### GitHub Integration

| Endpoint | Purpose |
|----------|---------|
| `api.github.com` | GitHub integration (meta IP ranges) |
| GitHub web/API/git ranges | Full GitHub connectivity |

#### Proxy Support

- `HTTP_PROXY` and `HTTPS_PROXY` environment variables respected for OTEL (v2.0.17)
- `NO_PROXY` for bypassing proxy for specific hosts (v1.0.93)
- `CLAUDE_CODE_PROXY_RESOLVES_HOSTS=true` for proxy DNS resolution (opt-in, v2.0.55)
- mTLS and proxy connectivity fixes for corporate proxies (v2.1.23)
- Proxy settings from `settings.json` applied to WebFetch and HTTP requests (v2.1.33)

#### Telemetry / Observability

- OpenTelemetry (OTEL) support with configurable export interval (default 5s, v1.0.8)
- OTEL resource attributes: `os.type`, `os.version`, `host.arch`, `wsl.version`, `terminal.type`, `language` (v1.0.51, v1.0.28)
- mTLS support for HTTP-based OTEL exporters (v1.0.126)
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` disables release notes fetching and other non-essential network calls (v2.0.17)
- `Active Time` metric in OTEL (v1.0.39)
- `speed` attribute for fast mode visibility in OTEL spans (v2.1.39)

### 6.3 Port Binding

- OAuth callback on Windows uses port 45454 (v1.0.54)
- MCP servers may bind ports (user-configured)

### 6.4 Browser Launching

- OAuth browser flows (automatic)
- Keyboard shortcut 'c' to copy OAuth URL when browser does not open (v2.1.10)
- MCP OAuth: SSE and HTTP MCP servers support OAuth with automatic browser flow (v1.0.27)

### 6.5 Clipboard Access

- Image paste from clipboard (platform-specific: xclip, wl-paste, Ctrl+V/Cmd+V)

### 6.6 File System Watchers

- File watching for modification detection
- Symlink support in suggestions and skill directories

### 6.7 Other

- Per-user temp directory isolation
- File read capabilities: images, PDFs up to 100 pages/20MB, Jupyter notebooks
- Git operations: extensive command support (log, show, diff, status, fetch, rebase, etc.), PR creation and review, commit co-authoring (`Co-Authored-By:`), branch management, GitHub App installation (`/install-github-app`), git worktree support
- IDE integration: VS Code extension, LSP, IDE diff tabs, multiple terminal client support, auto Python virtual environment activation
- "Teleport" between web and CLI

## 7. Extension Points

### 7.1 Hook/Lifecycle System

#### Hook Events

| Event | When | Capabilities |
|-------|------|-------------|
| `PreToolUse` | Before tool execution | Approve/deny/ask/modify tool input |
| `PostToolUse` | After tool execution | React to results, provide feedback |
| `Stop` | Main agent stopping | Block stop, force continuation |
| `SubagentStop` | Subagent stopping | Validate subagent completion (v1.0.41) |
| `SessionStart` | Session begins | Load context, set env vars via `$CLAUDE_ENV_FILE` |
| `SessionEnd` | Session ends | Cleanup, logging (v1.0.85) |
| `UserPromptSubmit` | User submits prompt | Add context, validate, block (v1.0.54) |
| `PreCompact` | Before context compaction | Preserve critical information (v1.0.48) |
| `Notification` | User notification | React to notifications (v2.0.37) |
| `PermissionRequest` | Permission requested | Auto-approve/deny with custom logic (v2.0.45, v2.0.54) |
| `Setup` | CLI init/maintenance | Triggered by `--init`, `--init-only`, `--maintenance` (v2.1.10) |
| `TeammateIdle` | Agent team member idle | Multi-agent coordination (v2.1.33) |
| `TaskCompleted` | Task completed | Multi-agent coordination (v2.1.33) |

#### Hook Types

1. **Command hooks**: Execute shell commands, receive JSON on stdin, output JSON on stdout
2. **Prompt hooks**: LLM-driven evaluation (supported for Stop, SubagentStop, UserPromptSubmit, PreToolUse)

#### Hook Input (JSON via stdin)

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask|allow",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {"command": "..."},
  "tool_use_id": "...",
  "tool_result": "..."
}
```

#### Hook Output

- **Exit code 0**: Success (stdout shown in transcript)
- **Exit code 2**: Blocking error (stderr fed back to Claude)
- **Other exit codes**: Non-blocking error
- JSON output supports: `systemMessage`, `hookSpecificOutput`, `decision`, `continue`, `suppressOutput`, `additionalContext` (v2.1.9), `updatedInput` (v2.1.0)

#### Hook Environment Variables

| Variable | Purpose |
|----------|---------|
| `CLAUDE_PROJECT_DIR` | Project root path (v1.0.58) |
| `CLAUDE_PLUGIN_ROOT` | Plugin directory (for portable paths) |
| `CLAUDE_ENV_FILE` | SessionStart only: write env vars here to persist |
| `CLAUDE_CODE_REMOTE` | Set if running in remote context |
| `CLAUDE_SESSION_ID` | Current session ID (v2.1.9) |

#### Hook Configuration

Hooks are defined in:
- `.claude/settings.json` (user-level, direct format)
- `.claude/settings.local.json` (project-level)
- `hooks/hooks.json` (plugin-level, wrapped in `{"hooks": {...}}`)
- Agent/skill frontmatter (v2.1.0)

Hooks load at session start and run in parallel. Timeout: 60s default for commands (changed to 10 minutes in v2.1.3), 30s for prompts. Configurable per-hook via `timeout` field. `once: true` for single-execution hooks (v2.1.0). `disableAllHooks` setting to turn off all hooks (v1.0.68).

### 7.2 Plugin/Extension Architecture

#### Plugin Structure

```
plugin-name/
  .claude-plugin/
    plugin.json          # Required manifest
  commands/              # Slash commands (.md with YAML frontmatter)
  agents/                # Subagent definitions (.md)
  skills/                # Skills (subdirs with SKILL.md)
    skill-name/
      SKILL.md
      references/
      examples/
      scripts/
  hooks/
    hooks.json           # Hook configuration
    scripts/             # Hook scripts
  .mcp.json              # MCP server definitions
  scripts/               # Helper utilities
  README.md
```

#### Plugin Manifest (`.claude-plugin/plugin.json`)

```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "...",
  "author": {"name": "...", "email": "..."},
  "mcpServers": {}
}
```

#### Plugin Discovery and Installation

- Install via `/plugin install`, `/plugin marketplace`
- Repository-level config via `extraKnownMarketplaces`
- Plugins pinnable to specific git commit SHAs (v2.1.14)
- Git branch/tag support via fragment syntax `owner/repo#branch` (v2.0.28)
- Auto-update toggle per marketplace (v2.0.70)
- `FORCE_AUTOUPDATE_PLUGINS` env var (v2.1.2)
- Skills from plugins visible in `/skills` menu (v2.1.0)

#### Marketplace Schema

The repository itself is a marketplace with schema `https://anthropic.com/claude-code/marketplace.schema.json`:

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "claude-code-plugins",
  "plugins": [...]
}
```

#### Bundled Plugins (14 total)

| Plugin | Category | Components |
|--------|----------|------------|
| `agent-sdk-dev` | development | Commands, agents |
| `claude-opus-4-5-migration` | development | Skill |
| `code-review` | productivity | Command, 5 parallel agents |
| `commit-commands` | productivity | 3 git commands |
| `explanatory-output-style` | learning | SessionStart hook |
| `feature-dev` | development | Command, 3 agents |
| `frontend-design` | development | Skill |
| `hookify` | productivity | 4 hooks, commands, agent, skill, Python rule engine |
| `learning-output-style` | learning | SessionStart hook |
| `plugin-dev` | development | 7 skills, command, 3 agents |
| `pr-review-toolkit` | productivity | Command, 6 agents |
| `ralph-wiggum` | development | Stop hook, commands (self-referential loop) |
| `security-guidance` | security | PreToolUse hook (9 security patterns) |
| `commit-commands` | productivity | 3 git workflow commands |

### 7.3 MCP Integration

#### MCP Server Types

| Type | Transport | Authentication |
|------|-----------|---------------|
| `stdio` | Child process (stdin/stdout) | Environment variables |
| `sse` | Server-Sent Events (HTTP) | OAuth (automatic) |
| `http` | REST (Streamable HTTP) | Bearer tokens, headers |
| `ws` | WebSocket | Bearer tokens, headers |

#### MCP Configuration Sources

- `.mcp.json` in project root (project scope, committable, v0.2.50)
- `~/.mcp.json` or equivalent (user scope, renamed from "global" in v0.2.49)
- Plugin `.mcp.json` or inline in `plugin.json`
- CLI: `claude mcp add`, `claude mcp add-json`, `claude mcp add-from-claude-desktop`
- `--mcp-config` flag for runtime override (supports multiple files, v1.0.73)

#### MCP Tool Naming Convention

Format: `mcp__<server-name>__<tool-name>` (or `mcp__plugin_<plugin-name>_<server-name>__<tool-name>` for plugins)

#### MCP Features

- OAuth Authorization Server discovery (v1.0.35)
- OAuth token proactive refresh (v1.0.110)
- Dynamic Client Registration (v2.1.30)
- `headersHelper` for dynamic headers (v1.0.119)
- `list_changed` notifications for dynamic tool updates (v2.1.0)
- `structuredContent` in tool responses (v2.0.21)
- `resource_link` tool results (v1.0.44)
- Tool annotations and titles (v1.0.44)
- MCP tool search auto mode: deferred discovery when tools exceed 10% context (v2.1.7)
- Auto-reconnection for SSE on disconnect (v1.0.18)
- Server instructions support (v1.0.52)
- `MCP_TIMEOUT` and `MCP_TOOL_TIMEOUT` env vars (v1.0.8)

### 7.4 Custom Commands/Skills/Agents

#### Custom Agents

Defined as markdown files in `.claude/agents/` or plugin `agents/` directories. Agent frontmatter supports:

```yaml
---
description: Agent role
model: claude-sonnet-4-5-20250929
permissionMode: ask|allow
disallowedTools: [...]
tools: [Task(AgentName)]  # Restrict sub-agent spawning
hooks:
  PreToolUse: [...]
memory: user|project|local
---
```

Features:
- Custom model per agent (v1.0.64)
- `permissionMode` (v2.0.43)
- `disallowedTools` (v2.0.30)
- Scoped hooks in agent frontmatter (v2.1.0)
- Memory support with scope (v2.1.33)
- Background agents (v2.0.60)
- Agent Teams (experimental, multi-agent collaboration, v2.1.32, requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- Agents invocable via `@agent-name` mention (v1.0.62)

#### Skills

Skills are auto-activating capabilities defined in `skills/*/SKILL.md`. Features:
- Auto-discovery from `.claude/skills/` directories (v2.1.6)
- Hot-reload without restart (v2.1.0)
- Token budget scales with context window (2% of context, v2.1.32)
- `context: fork` for forked sub-agent execution (v2.1.0)
- `user-invocable: false` to hide from menu (v2.1.0)
- `allowed-tools` in frontmatter (YAML-style lists supported, v2.1.0)
- `${CLAUDE_SESSION_ID}` substitution (v2.1.9)

#### Memory System

**CLAUDE.md Files** -- primary mechanism for project-level instructions. Loaded from:
- Project root `CLAUDE.md`
- `.claude/CLAUDE.md`
- Nested directories `.claude/CLAUDE.md`
- Additional directories via `--add-dir` (when `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`)

**Rules** -- stored in `.claude/rules/` directories (v2.0.64), auto-discovered from nested directories.

**Automatic Memory** -- Claude automatically records and recalls memories as it works (v2.1.32). Memory can be scoped to `user`, `project`, or `local` in agent frontmatter.

**Memory Management** -- `/memory` command for editing imported files (v1.0.94). `#` shortcut for quick memory entry (removed in v2.0.70, replaced with Claude direct editing).

### 7.5 SDK/API Surface

#### SDK Distribution (closed-source, inferred from CHANGELOG)

- **TypeScript SDK**: `@anthropic-ai/claude-code` (released v1.0.23), migrated to `@anthropic-ai/claude-agent-sdk` (v2.0.25)
- **Python SDK**: `claude-code-sdk` (released v1.0.23)
- Minimum zod peer dependency: `^4.0.0` (v2.1.2)

#### SDK Features

- Session support
- Custom tools as callbacks
- `canUseTool` callback for tool confirmation
- `--max-budget-usd` flag
- Partial message streaming (`--include-partial-messages`)
- `--replay-user-messages` flag
- Custom environment for spawned processes
- `SDKUserMessageReplay` events
- `queued_command` attachment messages
- Request cancellation
- Custom timeouts for hooks
- `--tools` flag to restrict available tools
- Structured outputs for non-interactive mode

#### CLI Flags (selected)

```
claude [options] [prompt]
  --print, -p           Non-interactive mode
  --continue, -c        Continue last conversation
  --resume              Resume specific session
  --resume <name>       Resume by name
  --from-pr             Resume PR-linked session
  --fork-session        Fork a session
  --session-id          Custom session ID
  --model               Override model
  --agent               Override agent
  --agents              Dynamic agents
  --add-dir             Additional working directories
  --mcp-config          MCP configuration files
  --system-prompt       Override system prompt
  --system-prompt-file  System prompt from file
  --append-system-prompt Append to system prompt
  --settings            Load settings from JSON
  --tools               Restrict built-in tools
  --disallowedTools     Disallow specific tools
  --dangerously-skip-permissions  Skip all permission checks
  --disable-slash-commands  Disable slash commands
  --output-format       Output format (stream-json)
  --debug               Debug mode
  --mcp-debug           MCP debug mode
  --init / --init-only / --maintenance  Setup hooks
  --setting-sources     Control settings sources
```

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

#### Bash Sandbox (v2.0.24+)

Released as a sandbox mode for BashTool on Linux and Mac. The sandbox configuration is controlled through `settings.json`:

```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": false,
    "allowUnsandboxedCommands": false,
    "excludedCommands": [],
    "network": {
      "allowUnixSockets": [],
      "allowAllUnixSockets": false,
      "allowLocalBinding": false,
      "allowedDomains": [],
      "httpProxyPort": null,
      "socksProxyPort": null
    },
    "enableWeakerNestedSandbox": false
  }
}
```

Key sandbox properties:
- `enabled`: Enable sandbox for Bash tool
- `autoAllowBashIfSandboxed`: Auto-approve Bash commands when sandboxed (bug fix in v2.1.34 for exclusion bypass)
- `allowUnsandboxedCommands`: Disable the `dangerouslyDisableSandbox` escape hatch (v2.0.30)
- `excludedCommands`: Commands that run outside sandbox
- `network.*`: Network isolation controls for sandboxed commands
- `enableWeakerNestedSandbox`: Allow weaker nested sandbox
- Sandbox blocks writes to `.claude/skills` directory (v2.1.38)

**Important:** The sandbox applies **only** to the `Bash` tool. It does NOT apply to Read, Write, Edit, WebSearch, WebFetch, MCP tools, hooks, or internal commands.

#### DevContainer Network Firewall

The included `.devcontainer/init-firewall.sh` implements strict network isolation using iptables:

- Default policy: `DROP` for INPUT, FORWARD, OUTPUT
- Allows: DNS (UDP 53), SSH (TCP 22), localhost, Docker DNS
- Explicitly allowed domains: `registry.npmjs.org`, `api.anthropic.com`, `sentry.io`, `statsig.anthropic.com`, `statsig.com`, `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com`
- GitHub IP ranges fetched dynamically from `api.github.com/meta`
- Host network allowed (for Docker bridge)
- All other outbound traffic explicitly REJECTED
- Verification: confirms `example.com` is blocked and `api.github.com` is reachable
- Requires `NET_ADMIN` and `NET_RAW` capabilities

### 8.2 Permission System

Three levels of permission control:

1. **allow**: Auto-approved tools/commands
2. **ask**: Require user confirmation
3. **deny**: Block entirely

Permission rules support:
- Tool-specific rules: `Bash`, `Read`, `Write`, `Edit`, `WebSearch`, `WebFetch`
- Bash command patterns: `Bash(npm *)`, `Bash(* install)`, `Bash(git * main)` (v2.1.0)
- Wildcard MCP tools: `mcp__server__*` (v2.0.70)
- `Bash(*)` treated as equivalent to `Bash` (v2.1.20)
- Output redirections in patterns: `Bash(python:*)` matches `python script.py > output.txt` (v1.0.123)

### 8.3 Safety Mechanisms

- `disableBypassPermissionsMode`: Prevent `--dangerously-skip-permissions`
- `allowManagedPermissionRulesOnly`: Block user/project-defined permission rules
- `allowManagedHooksOnly`: Block user/project-defined hooks
- `strictKnownMarketplaces`: Restrict plugin marketplace sources
- `disallowedTools`: Explicit tool blocking
- Managed MCP allowlist/denylist (v2.0.22)

### 8.4 Known Vulnerabilities (selected from CHANGELOG)

- v2.1.7: Wildcard permission rules matching compound commands with shell operators
- v2.1.6: Permission bypass via shell line continuation
- v2.1.2: Command injection in bash command processing
- v2.1.38: Heredoc delimiter parsing to prevent command smuggling
- v2.1.0: OAuth tokens, API keys, passwords exposed in debug logs
- v1.0.124: Security vulnerability in Bash tool permission checks
- v1.0.120: Bash tool permission checks bypass using prefix matching
- v2.0.10: PreToolUse hooks can modify tool inputs (intentional feature but security-relevant)

### 8.5 Enterprise/Managed Security Controls

Enterprise/managed settings support:
- `disableBypassPermissionsMode`: Prevent `--dangerously-skip-permissions`
- `allowManagedPermissionRulesOnly`: Block user/project-defined permission rules
- `allowManagedHooksOnly`: Block user/project-defined hooks
- `strictKnownMarketplaces`: Restrict plugin marketplace sources
- `disallowedTools`: Explicit tool blocking
- Managed MCP allowlist/denylist (v2.0.22)

## 9. Key Dependencies

[INFERRED] The binary is compiled and closed-source; exact dependencies cannot be determined. Known from documentation:

| Dependency | Impact |
|-----------|--------|
| Node.js runtime | Core execution environment |
| Built-in ripgrep | File content searching (bundled, v1.0.84) |
| macOS Keychain (`security` CLI) | API key storage on macOS |
| Sentry SDK | Error reporting/telemetry |
| Statsig SDK | Feature flags / analytics |
| OpenTelemetry | Observability export |

## 10. Environment Variables

### Core Configuration

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | API key for direct Anthropic API |
| `CLAUDE_CONFIG_DIR` | Override config directory |
| `CLAUDE_CODE_TMPDIR` | Override temp directory (v2.1.5) |
| `CLAUDE_CODE_SHELL` | Override shell detection (v2.0.65) |
| `CLAUDE_CODE_SHELL_PREFIX` | Wrap shell commands (v1.0.61) |
| `CLAUDE_BASH_NO_LOGIN` | Skip login shell for BashTool (v1.0.124) |
| `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` | Freeze working directory for bash (v1.0.18) |

### Feature Toggles

| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enable agent teams (v2.1.32) |
| `CLAUDE_CODE_ENABLE_TASKS` | Enable/disable task system (v2.1.19) |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | Disable background tasks (v2.1.4) |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Disable telemetry/release notes (v2.0.17) |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | Disable beta features (v2.1.25) |
| `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | Load CLAUDE.md from `--add-dir` dirs (v2.1.20) |
| `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | Override file read token limit (v2.1.0) |
| `DISABLE_INTERLEAVED_THINKING` | Opt out of interleaved thinking (v1.0.1) |
| `DISABLE_AUTOUPDATER` | Disable auto-update (v2.0.36) |
| `IS_DEMO` | Hide email/org from UI (v2.1.0) |
| `ENABLE_SECURITY_REMINDER` | Toggle security hook plugin (default: 1) |
| `FORCE_AUTOUPDATE_PLUGINS` | Force plugin auto-update (v2.1.2) |

### API/Provider Configuration

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Override default Sonnet model (v1.0.88) |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Override default Opus model (v1.0.88) |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Override default Haiku model (v2.0.17) |
| `ANTHROPIC_BEDROCK_BASE_URL` | Bedrock base URL (v2.0.71) |
| `AWS_BEARER_TOKEN_BEDROCK` | Bedrock API key (v1.0.51) |
| `CLOUD_ML_REGION` | Google Vertex AI region (v1.0.8) |
| `ANTHROPIC_LOG=debug` | Debug logging (replaces `DEBUG=true`, v0.2.125) |

### Timeout/Performance

| Variable | Purpose |
|----------|---------|
| `BASH_DEFAULT_TIMEOUT_MS` | Default bash command timeout (v0.2.108) |
| `BASH_MAX_TIMEOUT_MS` | Maximum bash command timeout (v0.2.108) |
| `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` | API key helper TTL (v0.2.117) |
| `CLAUDE_CODE_EXIT_AFTER_STOP_DELAY` | Auto-exit SDK mode after idle (v2.0.35) |
| `MCP_TIMEOUT` | MCP server startup timeout (v0.2.41) |
| `MCP_TOOL_TIMEOUT` | MCP tool call timeout (v1.0.8) |

### Proxy

| Variable | Purpose |
|----------|---------|
| `HTTP_PROXY` | HTTP proxy |
| `HTTPS_PROXY` | HTTPS proxy |
| `NO_PROXY` | Proxy bypass list (v1.0.93) |
| `CLAUDE_CODE_PROXY_RESOLVES_HOSTS` | Proxy DNS resolution (v2.0.55) |
| `NODE_EXTRA_CA_CERTS` | Custom CA certificates (v1.0.40) |

### Hook Environment Variables

| Variable | Purpose |
|----------|---------|
| `CLAUDE_PROJECT_DIR` | Project root path (v1.0.58) |
| `CLAUDE_PLUGIN_ROOT` | Plugin directory (for portable paths) |
| `CLAUDE_ENV_FILE` | SessionStart only: write env vars here to persist |
| `CLAUDE_CODE_REMOTE` | Set if running in remote context |
| `CLAUDE_SESSION_ID` | Current session ID (v2.1.9) |

### IDE Integration

| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_AUTO_CONNECT_IDE` | Disable IDE auto-connection (set to `false`, v1.0.61) |

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `~/.claude/` | Read/Write | Primary config directory | Yes (on first run) |
| `~/.claude.json` | Read | Legacy global user config | No |
| `~/.claude/settings.json` | Read/Write | User-level settings | Yes |
| `~/.claude/settings.local.json` | Read/Write | User-level local settings | Yes |
| `~/.claude/skills/` | Read/Write | User-level skills | Yes |
| `~/.claude/commands/` | Read | User-level custom slash commands | No (user-created) |
| `~/.claude/rules/` | Read | User-level rules | No (user-created) |
| `~/.claude/security_warnings_state_*.json` | Read/Write | Security plugin state | Yes |
| `.claude/settings.json` | Read | Shared project settings | No |
| `.claude/settings.local.json` | Read/Write | Local project settings | Yes |
| `.claude/commands/` | Read | Project slash commands | No |
| `.claude/skills/` | Read/Write | Project skills | Yes |
| `.claude/rules/` | Read | Project rules | No |
| `.claude/*.local.md` | Read/Write | Plugin state files | Yes |
| `.claude/agents/` | Read | Custom agent definitions | No |
| `.mcp.json` | Read | Project MCP server config | No |
| `~/.mcp.json` | Read | User MCP server config | No |
| `CLAUDE.md` | Read | Project instructions | No |
| `managed-settings.json` | Read | Enterprise managed settings | No |
| `C:\ProgramData\ClaudeCode\managed-settings.json` | Read | Windows managed settings (deprecated) | No |
| `C:\Program Files\ClaudeCode\managed-settings.json` | Read | Windows managed settings (current) | No |
| `$CLAUDE_CODE_TMPDIR` or system temp | Read/Write | Temp files | Yes |
| `/tmp/security-warnings-log.txt` | Write | Security hook debug log | Yes |
| Transcript files (JSONL) | Write | Session transcripts | Yes |
| Plan files (`plansDirectory`) | Read/Write | Plans | Yes |
| Config backups (home directory) | Write | Settings backups | Yes |
| Working directory files | Read/Write | Via Read/Write/Edit tools | Yes |
| macOS Keychain | Read/Write | API key storage | Yes |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `api.anthropic.com` | Primary Anthropic API | Every LLM request |
| `platform.claude.com` | OAuth and API Console | OAuth flow |
| `claude.ai` | Installation scripts, web sessions | Install, remote sessions |
| `sentry.io` | Error reporting | On errors |
| `statsig.anthropic.com` | Feature flags / analytics | Startup and periodically |
| `statsig.com` | Feature flags | Startup and periodically |
| `registry.npmjs.org` | npm package resolution | npm installs |
| `api.github.com` | GitHub integration | GitHub operations |
| GitHub web/API/git ranges | Full GitHub connectivity | Git operations |
| `marketplace.visualstudio.com` | VS Code extension marketplace | Extension install/update |
| `vscode.blob.core.windows.net` | VS Code extension binaries | Extension download |
| `update.code.visualstudio.com` | VS Code updates | Update checks |
| MCP server endpoints (user-configured) | MCP tool calls | MCP tool use |
| Any URL (via WebFetch) | Web content retrieval | WebFetch tool use |
| Any URL (via WebSearch) | Web search | WebSearch tool use |
| OTEL exporter endpoint (user-configured) | Observability export | Periodically (5s default) |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Shell command execution | Child process (`Bash` tool) | Persistent shell session, sandbox-aware |
| File read | Internal (`Read` tool) | Any file: text, images, PDFs, Jupyter notebooks |
| File write/edit | Internal (`Write`/`Edit`/`MultiEdit` tools) | Respects umask |
| File search | Built-in ripgrep (`Grep` tool) | Bundled binary |
| File pattern matching | Internal (`Glob` tool) | Respects `.gitignore` |
| Directory listing | Internal (`LS` tool) | N/A |
| Web fetch | Internal (`WebFetch` tool) | Arbitrary URL retrieval |
| Web search | Internal (`WebSearch` tool) | N/A |
| OAuth browser launch | Browser opening | OAuth authentication flows |
| Clipboard read | Platform-specific (xclip, wl-paste) | Image paste |
| File watching | Internal mechanism | Modification detection |
| Keychain access | macOS `security` CLI | API key storage/retrieval |
| MCP subprocess spawn | Child process (stdio transport) | MCP server management |
| MCP HTTP/SSE/WS | HTTP client | MCP server connections |
| LSP integration | Language Server Protocol | Code analysis (v2.0.74) |
| Process management | SIGKILL fallback | Cleanup on exit (v2.1.19) |
| Temp directory isolation | OS-level per-user dirs | Permission conflict prevention |
| Git operations | `git` CLI | Extensive VCS support |
| GitHub operations | `gh` CLI | PR creation, issue management |
| Telemetry | Sentry SDK, Statsig SDK | Error reporting, feature flags |
| OTEL export | OpenTelemetry SDK | Observability metrics |

## 12. Sandboxing Recommendations

### What Can Be Controlled via Settings

1. **Bash sandbox**: Network isolation, command exclusions, domain allowlisting
2. **Permission rules**: Per-tool allow/ask/deny with patterns
3. **Hook blocking**: `allowManagedHooksOnly`, `disableAllHooks`
4. **Plugin restrictions**: `strictKnownMarketplaces`, managed-only rules
5. **Tool restrictions**: `disallowedTools`
6. **Permission bypass prevention**: `disableBypassPermissionsMode`

### What Cannot Be Controlled via Settings

1. **Read/Write/Edit tools are not sandboxed** -- only Bash is sandbox-aware
2. **MCP tools operate outside the sandbox** -- they can make arbitrary network calls
3. **Hooks execute arbitrary code** -- managed hooks only partially addresses this
4. **WebFetch/WebSearch are deny-only** -- no URL-level allowlisting
5. **The binary itself is opaque** -- no source auditing possible
6. **Telemetry connections** (Sentry, Statsig) are hardcoded

### Recommended Sandboxing Strategy

For maximum isolation, use the DevContainer approach:
1. Run in a container with network firewall (`init-firewall.sh`)
2. Use managed settings with `allowManagedPermissionRulesOnly` and `allowManagedHooksOnly`
3. Enable bash sandbox with strict network isolation
4. Deny WebSearch and WebFetch
5. Restrict MCP servers to known, trusted ones
6. Use `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
7. Disable `--dangerously-skip-permissions`

### Attack Surface Summary

| Surface | Risk | Mitigation |
|---------|------|------------|
| Bash commands | High | Sandbox mode, permission rules, hooks |
| File read/write | Medium | Permission rules (no sandbox) |
| Network (WebFetch) | Medium | Deny rule, firewall |
| MCP servers | Medium | Managed allowlist, HTTPS only |
| Hooks/Plugins | Medium | `allowManagedHooksOnly`, trust model |
| API keys | High | Keychain storage, env vars, no debug logging |
| Telemetry | Low | `DISABLE_NONESSENTIAL_TRAFFIC` |
| Session data | Low | Per-user temp dirs, cleanup period |
| OAuth tokens | Medium | Token refresh, secure storage |

### CI/CD Scripts

The repository includes GitHub Actions workflows for managing the `anthropics/claude-code` issue tracker:

| Workflow | Purpose |
|----------|---------|
| `claude.yml` | Run Claude Code on `@claude` mentions in issues/PRs |
| `claude-dedupe-issues.yml` | Automated duplicate issue detection |
| `auto-close-duplicates.yml` | Auto-close duplicate issues after 3 days |
| `backfill-duplicate-comments.yml` | Backfill duplicate comments |
| `claude-issue-triage.yml` | Issue triage |
| `oncall-triage.yml` | Oncall issue labeling |
| `lock-closed-issues.yml` | Lock closed issues |
| `stale-issue-manager.yml` | Stale issue management |
| `issue-opened-dispatch.yml` | Issue open dispatch |
| `remove-autoclose-label.yml` | Remove autoclose labels |
| `log-issue-events.yml` | Log issue events |

The `claude.yml` workflow uses `anthropics/claude-code-action@v1` with `--model claude-sonnet-4-5-20250929`.

Scripts in `scripts/`:
- `auto-close-duplicates.ts` (Bun/TypeScript): Closes issues marked as duplicates after 3 days with no author objection
- `backfill-duplicate-comments.ts` (Bun/TypeScript): Backfills duplicate comments on issues
- `comment-on-duplicates.sh` (Bash): Posts duplicate comment with up to 3 potential duplicates

### Files Analyzed

All files in the repository were examined. Key files:

- `README.md`
- `CHANGELOG.md` (1677 lines, exhaustively analyzed)
- `SECURITY.md`
- `LICENSE.md`
- `examples/settings/settings-strict.json`
- `examples/settings/settings-lax.json`
- `examples/settings/settings-bash-sandbox.json`
- `examples/settings/README.md`
- `examples/hooks/bash_command_validator_example.py`
- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile`
- `.devcontainer/init-firewall.sh`
- `Script/run_devcontainer_claude_code.ps1`
- `.claude-plugin/marketplace.json`
- `plugins/README.md`
- `plugins/plugin-dev/skills/hook-development/SKILL.md`
- `plugins/plugin-dev/skills/mcp-integration/SKILL.md`
- `plugins/plugin-dev/skills/plugin-structure/SKILL.md`
- `plugins/plugin-dev/skills/plugin-settings/SKILL.md`
- `plugins/hookify/hooks/hooks.json`
- `plugins/hookify/hooks/pretooluse.py`
- `plugins/hookify/core/rule_engine.py`
- `plugins/hookify/core/config_loader.py`
- `plugins/security-guidance/hooks/hooks.json`
- `plugins/security-guidance/hooks/security_reminder_hook.py`
- `plugins/ralph-wiggum/hooks/hooks.json`
- `plugins/ralph-wiggum/hooks/stop-hook.sh`
- `.claude/commands/oncall-triage.md`
- `.claude/commands/commit-push-pr.md`
- `.claude/commands/dedupe.md`
- `.github/workflows/claude.yml`
- `scripts/auto-close-duplicates.ts`
- `scripts/comment-on-duplicates.sh`
