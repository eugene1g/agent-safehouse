# Auggie (Augment Code) -- Sandbox Analysis Report

**Analysis Date:** 2025-07-01
**Repository:** https://github.com/augmentcode/auggie.git
**Git Commit:** `87156b27e31e0de58b1f9852fa478b7ba691ef86`
**Latest Version:** 0.16.0
**License:** Custom Proprietary License (Augment Computing, Inc.)
**Source Availability:** Docs-only repo

---

## Disclaimer

**This is a documentation/SDK-examples-only repository.** The actual Auggie agent source code (`augment.mjs`) is **closed-source proprietary software** distributed exclusively through npm as `@augmentcode/auggie`. The agent binary is not included in this repository and cannot be directly analyzed. All findings below are inferred from documentation, SDK examples, changelogs, configuration patterns, and GitHub workflow definitions. Findings inferred from these indirect sources are marked with `[INFERRED]`.

---

## 1. Overview

Auggie is a **closed-source, proprietary agentic CLI** from Augment Computing with broad system access capabilities. The npm package is `@augmentcode/auggie`, with a Python SDK (`auggie-sdk` on PyPI) and a TypeScript SDK (`@augmentcode/auggie-sdk` on npm, version `^0.1.6` referenced). The runtime requires Node.js 22+ for the CLI agent and Python 3.10+ for the SDK.

The Auggie system has a layered architecture:

```
User Code (Python/TypeScript)
       |
  +----+------+--------------------+
  |           |                    |
  v           v                    v
SDK Layer    Protocol Layer      CLI (Direct Usage)
(Auggie)     (AuggieACPClient)   (auggie CLI)
  |           |                    |
  +-----+-----+                   |
        |                         |
        v                         v
   Augment CLI (augment.mjs)      Augment CLI
   (subprocess or ACP mode)       (interactive TUI)
        |
        v
   Augment Cloud API
   (hosted AI services)
```

## 2. UI & Execution Modes

### Three Interaction Modes [INFERRED]

1. **Direct CLI** (`auggie "prompt"`) - Interactive TUI or one-shot `--print` mode
2. **SDK Subprocess** (`Auggie.run()`) - Spawns a new CLI process per request
3. **ACP (Agent Client Protocol)** (`AuggieACPClient`) - Long-running CLI process via `--acp` flag, JSON-RPC over stdio

### CLI Process Spawning [INFERRED]

The SDK spawns the CLI as a subprocess:
```
node augment.mjs --acp --model <model> --workspace-root <path>
```

Key CLI flags documented:
- `--acp` - Agent Client Protocol mode (JSON-RPC over stdio)
- `--mcp` - Model Context Protocol server mode
- `--mcp-auto-workspace` - Dynamic workspace discovery in MCP mode
- `--model <model>` - Model selection (e.g., `sonnet4.5`, `haiku4.5`, `gpt5`)
- `--workspace-root <path>` - Working directory for the agent
- `--print` / `-p` - Non-interactive print mode
- `--quiet` / `-q` - Suppress output (only final result)
- `--shell` - Shell configuration
- `--startup-script` - Shell startup script
- `--max-turns` - Cap agent iterations in print mode
- `--disable-tool <tool>` - Disable specific tools
- `--permission <rule>` - Configure tool permissions
- `--image <path>` - Attach image to prompt
- `--enhance-prompt` - Enhance prompts before sending
- `--continue` / `-c` - Resume previous session
- `--resume <id>` - Resume specific session by ID
- `--allow-indexing` - Allow workspace indexing
- `--log-file <path>` - Log file for MCP mode (default: `/tmp/augment-log.txt`)
- `--augment-session-json` - Authentication JSON
- `--mcp-config <path>` - MCP server configuration file

### CLI Process Model [INFERRED]

- **Subprocess mode**: New process per `agent.run()` call (~500ms overhead each)
- **ACP mode**: Single long-running process, all messages share session (~500ms one-time overhead)
- **MCP mode**: Long-running process serving as context provider

## 3. Authentication & Credentials

### 3.1 Credential Storage [INFERRED]

| Path | Purpose |
|------|---------|
| `~/.augment/session.json` | OAuth session token (created by `auggie login`) |
| `~/.augment/settings.json` | User settings (model preferences, MCP config, tool permissions) |

### 3.2 API Key Sources and Priority Order [INFERRED]

1. **Browser-based OAuth flow** (v0.16.0+):
   ```bash
   auggie login
   ```
   Creates session file at `~/.augment/session.json` containing API token.

2. **Environment variables**:
   ```bash
   export AUGMENT_API_TOKEN=<token>
   export AUGMENT_API_URL=https://staging-shard-0.api.augmentcode.com/
   ```

3. **CLI flags**:
   - `--augment-session-json` flag
   - `AUGMENT_SESSION_AUTH` environment variable (for CI/CD)

4. **For Claude Code integration** (via ACP adapter):
   ```bash
   export ANTHROPIC_API_KEY=<key>
   ```

### 3.3 OAuth Flows [INFERRED]

Browser-based OAuth flow added in v0.16.0 via `auggie login` command. Changed from JSON paste to browser-based localhost OAuth.

### 3.4 Credential File Locations and Formats

**GitHub Actions Secrets** (for CI/CD workflows):
- `AUGMENT_SESSION_AUTH` - Augment authentication credentials
- `AUGMENT_API_TOKEN` - API token for indexing operations
- `AUGMENT_API_URL` - Tenant-specific API URL
- `GITHUB_TOKEN` - GitHub API access

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths [INFERRED]

| Path | Purpose | Notes |
|------|---------|-------|
| `~/.augment/session.json` | Authentication session | Created by `auggie login` |
| `~/.augment/settings.json` | User settings, MCP server config, model preferences, tool permissions, auto-update setting | JSON with schema validation |
| `~/.augment/rules/` | User-specific rules | Custom agent behavior rules |
| `~/.augment/commands/` | User-level custom slash commands | Markdown with frontmatter |

### 4.2 Project-Level Config Paths [INFERRED]

| Path | Purpose | Notes |
|------|---------|-------|
| `.augment/commands/` | Project-specific custom slash commands | Markdown with frontmatter |
| `.augment/` | Augment configuration directory | General project config |
| `.agents/` | Agent and skill discovery (v0.16.0+) | For agentskills.io SKILL.md files |
| `AGENTS.md` | Agent guidelines/rules | Hierarchical rules indicator in v0.16.0 |
| `CLAUDE.md` | Agent guidelines (also supported) | Compatibility with Claude Code format |
| `.augment/guidelines.md` | Agent guidelines (legacy) | Original guideline format |
| `.augmentignore` | Indexing exclusion patterns | Like `.gitignore` format |
| `.gitignore` | Also respected for indexing | Standard git ignore |

### 4.3 System/Enterprise Config Paths

None identified.

### 4.4 Data & State Directories [INFERRED]

| Path | Purpose | Notes |
|------|---------|-------|
| `/tmp/augment-log.txt` | Default MCP mode log file | Configurable via `--log-file` |
| `/tmp/direct-context-state.json` | Context state export (examples) | Used in SDK examples |
| `.augment-index-state/{branch}/state.json` | GitHub indexer state | Branch-specific, configurable via `STATE_PATH` |

### 4.5 Workspace Files Read [INFERRED]

| Path | Purpose |
|------|---------|
| `AGENTS.md` | Agent guidelines/rules |
| `CLAUDE.md` | Agent guidelines (Claude Code compatibility) |
| `.augment/guidelines.md` | Agent guidelines (legacy) |
| `.augmentignore` | Indexing exclusion patterns |
| `.gitignore` | Also respected for indexing |

### 4.6 Temp Directory Usage [INFERRED]

| Path | Purpose | Notes |
|------|---------|-------|
| `/tmp/augment-log.txt` | Default MCP mode log file | Configurable via `--log-file` |
| `/tmp/direct-context-state.json` | Context state export (examples) | Used in SDK examples |

## 5. Tools Available to the LLM

From the event listener documentation and changelog, the agent has access to these tools [INFERRED]:

| Tool Name | Kind | Purpose |
|-----------|------|---------|
| `view` | `read` | Read files and directories |
| `str-replace-editor` | `edit` | Edit files using string replacement |
| `save-file` | `create` | Create new files |
| `launch-process` | `execute` | Run shell commands |
| `apply_patch` | `edit` | Apply patches to files (enhanced in v0.9.0) |
| `codebase-retrieval` | `read` | Semantic search of indexed workspace |
| `web fetch` | `read` | Fetch web content (results truncated to 150 chars in TUI) |

### Tool Permission System [INFERRED]

- Permissions configurable via `--permission` flag, settings.json, or interactive TUI
- Permission types include: allow, deny, ask-user
- Regex-based matching for tool permission rules
- Individual tools can be disabled via `--disable-tool` flag or settings

### Sub-agents [INFERRED]

The agent supports sub-agents (v0.13.0+):
- Built-in sub-agents: `explore`, `plan`
- Sub-agents show thinking summaries
- Parallel sub-agent execution with proper interrupt handling
- Sub-agent output visible in verbose mode

## 6. Host System Interactions

### 6.1 Subprocess Execution [INFERRED]

- `launch-process` tool can execute arbitrary shell commands
- Git processes spawned for indexing operations
- MCP servers spawned as child processes (stdio transport)
- Sub-agent processes for parallel execution

### 6.2 Network Requests [INFERRED]

**Augment Cloud API:**

| URL Pattern | Purpose |
|-------------|---------|
| `https://staging-shard-0.api.augmentcode.com/` | Staging API endpoint (referenced in examples) |
| `https://your-tenant.api.augmentcode.com/` | Tenant-specific API endpoint pattern |
| Augment OAuth endpoint | Browser-based OAuth flow (v0.16.0) |

**GitHub API:** Used for PR review and description generation (via GitHub Actions), repository indexing (tarball download, commit comparison), and file content fetching.

**MCP Connections:** Connects to user-configured MCP servers (stdio, HTTP, SSE transports). MCP server OAuth authentication supported (v0.5.8+). `${augmentToken}` variable expansion for MCP server headers (v0.16.0).

**ACP (Agent Client Protocol):** JSON-RPC protocol over stdio (between SDK and CLI). Protocol operations: `initialize`, `newSession`, `prompt`, `clear`. Long-running process model with bidirectional communication.

### 6.3 Port Binding [INFERRED]

Localhost port for OAuth flow (v0.16.0). Specific port number not documented.

### 6.4 Browser Launching [INFERRED]

Browser launched for OAuth flow via `auggie login` (v0.16.0).

### 6.5 Clipboard Access

None identified.

### 6.6 File System Watchers

None identified.

### 6.7 Other

None identified.

## 7. Extension Points

### 7.1 Hook/Lifecycle System

None identified.

### 7.2 Plugin/Extension Architecture

None identified beyond custom commands and agent skills.

### 7.3 MCP Integration [INFERRED]

**As MCP Server:**
- The agent can run as an MCP server (`auggie --mcp`), providing codebase retrieval tool for external editors/clients
- Dynamic workspace discovery with `--mcp-auto-workspace`
- Log file at `/tmp/augment-log.txt` (configurable)

**As MCP Client:**
- Connects to user-configured MCP servers
- Configuration in `~/.augment/settings.json` or via `--mcp-config`
- Management: `auggie mcp add|list|remove` commands
- Transports: stdio, HTTP, SSE
- Authentication: OAuth support for MCP servers
- Token variable: `${augmentToken}` expansion in MCP server headers
- Individual toggling: Enable/disable specific MCP servers from TUI (v0.16.0)

### 7.4 Custom Commands/Skills/Agents [INFERRED]

**Custom Slash Commands:** Stored as markdown files with YAML frontmatter in `.augment/commands/` (project-level) or `~/.augment/commands/` (user-level).

Frontmatter schema:
```yaml
---
description: <string>        # Command description
argument-hint: <string>      # Hint shown for arguments (e.g., [file-path])
model: <string>              # Model override for this command (e.g., gpt5)
---
```

Variable substitution: `$ARGUMENTS` replaced with user-provided arguments.

Example commands in repository:

| Command | Description | Default Model |
|---------|-------------|---------------|
| `/code-review` | Comprehensive code review | gpt5 |
| `/security-review` | Security vulnerability analysis | gpt5 |
| `/bug-fix` | Structured bug fix approach | gpt5 |
| `/tests` | Generate comprehensive test cases | gpt5 |
| `/documentation` | Generate documentation | gpt5 |
| `/performance-optimization` | Performance analysis | gpt5 |

Nested commands supported via colon separator (e.g., `nested:command`). Commands from Claude Code are auto-detected and imported.

**Agent and Skill Discovery:** `.agents/` directory for agentskills.io SKILL.md files (v0.16.0+).

### 7.5 SDK/API Surface

**Python SDK (`auggie-sdk`):**

Core classes:
1. **`Auggie`** (main agent class): Constructor params: `workspace_root`, `model`, `listener`. Methods: `run(instruction, return_type, timeout, max_retries, functions, success_criteria, max_verification_rounds)`, `session()` context manager, `last_model_answer`, `get_available_models()`.
2. **`AuggieACPClient`** (protocol layer): Constructor params: `model`, `workspace_root`, `listener`. Methods: `start()`, `send_message(message, timeout)`, `clear_context()`, `stop()`. Context manager support.
3. **`ClaudeCodeACPClient`** (Claude Code integration): Same API as AuggieACPClient. Uses `@zed-industries/claude-code-acp` npm adapter. Requires `ANTHROPIC_API_KEY`.
4. **`AgentEventListener`** (event interface): `on_agent_message_chunk(text)`, `on_agent_message(message)`, `on_tool_call(tool_call_id, title, kind, status)`, `on_tool_response(tool_call_id, status, content)`, `on_agent_thought(text)`.
5. **`LoggingAgentListener`** -- Built-in logging listener.

**Context SDK Classes:**
1. **`DirectContext`**: `create(debug, api_key, api_url)`, `import_from_file(path, api_key, api_url)`, `add_to_index(files)`, `remove_from_index(paths)`, `search(query, max_output_length)`, `search_and_ask(search_query, question)`, `export()` / `export_to_file(path)`.
2. **`FileSystemContext`**: `create(directory, auggie_path, debug)` (spawns `auggie --mcp`), `search(query)`, `search_and_ask(search_query, question)`, `close()`.
3. **`File`** (data class): `path: str`, `contents: str`.

**Exception Classes:** `AugmentCLIError`, `AugmentParseError`, `AugmentVerificationError`.

**Function Calling:** Functions passed via `functions=[func1, func2]` parameter. Requires type hints and docstrings. Schema auto-generated from function signatures. Agent uses XML tags `<function-call>...</function-call>`. Limited to 5 rounds. Arguments and return values must be JSON-serializable.

**Supported AI Models** (from examples): `sonnet4.5` / `claude-3-5-sonnet-latest`, `sonnet4`, `haiku4.5` / `claude-3-haiku-latest`, `claude-3-opus-latest`, `gpt5`, `gpt-4o`.

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing [INFERRED]

No filesystem, network, or process execution sandboxing. The agent runs with the same privileges as the invoking user. All operations happen in the host environment. The closed-source agent binary (`augment.mjs`) cannot be audited for security.

### 8.2 Permission System [INFERRED]

- Tool permissions system: Configurable allow/deny/ask-user rules for each tool
- `--disable-tool` flag for restricting capabilities
- `--permission <rule>` flag for configuring permission rules
- Regex-based matching for tool permission rules

### 8.3 Safety Mechanisms [INFERRED]

- **File filtering**: Automatic exclusion of secret/key files from indexing (files matching: `.git`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.jks`, `*.keystore`, `*.pkcs12`, `*.crt`, `*.cer`, `id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa`)
- **Path traversal prevention**: Rejection of paths containing `..`
- **Home directory protection**: Indexing disabled when running from home directory
- **Workspace size limits**: Prevent accidental indexing of entire filesystem
- **File size limit**: Max 1 MB per file (`DEFAULT_MAX_FILE_SIZE = 1024 * 1024`)
- **UTF-8 validation**: Binary files rejected from indexing
- **MCP orphan process cleanup**: Fixed in v0.14.0
- **Process lifecycle management**: Background processes tracked and cleaned up on exit (v0.13.0)

### 8.4 Known Vulnerabilities

None identified. However, the closed-source nature prevents verification of security claims.

**Vulnerability Reporting:**
- Email: `security@augmentcode.com`
- GitHub Security Advisories
- Security details: https://www.augmentcode.com/security

### 8.5 Enterprise/Managed Security Controls

None identified.

## 9. Key Dependencies

| Dependency | Impact |
|------------|--------|
| `@augmentcode/auggie` (npm) | Closed-source CLI agent binary (`augment.mjs`) [INFERRED] |
| `auggie-sdk` (PyPI) | Python SDK for programmatic agent control |
| `@augmentcode/auggie-sdk` (npm) | TypeScript SDK |
| `@zed-industries/claude-code-acp` (npm) | Claude Code ACP adapter for ClaudeCodeACPClient |
| Node.js 22+ | Runtime for CLI agent [INFERRED] |
| Python 3.10+ | Runtime for SDK |

## 10. Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `AUGMENT_API_TOKEN` | API authentication token | For SDK/indexing |
| `AUGMENT_API_URL` | Tenant-specific API endpoint | For SDK/indexing |
| `AUGMENT_SESSION_AUTH` | Session authentication (CI/CD) | For GitHub Actions |
| `ANTHROPIC_API_KEY` | Claude Code API key | For ClaudeCodeACPClient |
| `GITHUB_TOKEN` | GitHub API access | For indexing/actions |
| `GITHUB_REPOSITORY` | `owner/repo` format | For GitHub indexer |
| `GITHUB_REF` / `GITHUB_REF_NAME` | Branch reference | For GitHub indexer |
| `GITHUB_SHA` | Commit SHA | For GitHub indexer |
| `GITHUB_OUTPUT` | Actions output file | For GitHub Actions |
| `STATE_PATH` | Custom index state path | Optional |
| `MAX_COMMITS` | Max commits before full re-index | Optional (default: 100) |
| `MAX_FILES` | Max file changes before re-index | Optional (default: 500) |
| `BRANCH` | Branch override | Optional (default: main) |
| `STORAGE_TYPE` | Index storage backend | Optional |

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `~/.augment/session.json` | R/W | OAuth session token | Yes [INFERRED] |
| `~/.augment/settings.json` | R/W | User settings, MCP config, tool permissions | Yes [INFERRED] |
| `~/.augment/rules/` | R | User-specific agent behavior rules | No [INFERRED] |
| `~/.augment/commands/` | R | User-level custom slash commands | No |
| `{workspace}/.augment/commands/` | R | Project-specific custom slash commands | No |
| `{workspace}/.augment/` | R | Augment configuration directory | No |
| `{workspace}/.augment/guidelines.md` | R | Agent guidelines (legacy) | No |
| `{workspace}/.agents/` | R | Agent and skill discovery | No |
| `{workspace}/AGENTS.md` | R | Agent guidelines/rules | No |
| `{workspace}/CLAUDE.md` | R | Agent guidelines (Claude Code compat) | No |
| `{workspace}/.augmentignore` | R | Indexing exclusion patterns | No |
| `{workspace}/.gitignore` | R | Also respected for indexing | No |
| `/tmp/augment-log.txt` | R/W | Default MCP mode log file | Yes [INFERRED] |
| `.augment-index-state/{branch}/state.json` | R/W | GitHub indexer state | Yes [INFERRED] |
| `{workspace}/**` | R/W | Any workspace file (via agent tools) | Yes [INFERRED] |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `https://<tenant>.api.augmentcode.com/` | Augment Cloud API (AI inference, indexing, search) | Every prompt [INFERRED] |
| Augment OAuth endpoint | Browser-based OAuth flow | `auggie login` [INFERRED] |
| GitHub API | PR review, description generation, indexing | GitHub Actions workflows |
| MCP server URLs | User-configured MCP server connections | MCP communication [INFERRED] |
| Arbitrary HTTP/HTTPS URLs | Web fetch tool | AI-driven web fetch [INFERRED] |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Shell command execution | `launch-process` tool | Arbitrary shell commands [INFERRED] |
| File read/write/edit | `view`, `str-replace-editor`, `save-file`, `apply_patch` tools | Workspace file operations [INFERRED] |
| Codebase search | `codebase-retrieval` tool | Semantic search of indexed workspace [INFERRED] |
| Web fetch | `web fetch` tool | Fetch arbitrary URLs [INFERRED] |
| MCP server launch | stdio/HTTP/SSE transport | Spawns configured MCP server processes [INFERRED] |
| Git operations | Spawned git processes | Indexing, worktree detection [INFERRED] |
| Browser launch | OAuth flow | `auggie login` command [INFERRED] |
| Sub-agent execution | Child processes | `explore`, `plan` sub-agents [INFERRED] |
| Process lifecycle | Background process tracking | Tracked and cleaned up on exit (v0.13.0) [INFERRED] |

## 12. Sandboxing Recommendations

Given that this is a closed-source agent with **full filesystem, network, and process execution capabilities**, the following sandboxing measures should be considered:

### High Priority

1. **Filesystem isolation** -- Mount only the target workspace directory; deny access to home directory config files (`~/.ssh`, `~/.aws`, `~/.git-credentials`, etc.)
2. **Network restrictions** -- Allowlist only Augment API endpoints; block access to internal networks
3. **Process execution limits** -- Restrict `launch-process` tool to specific commands or disable it entirely via `--disable-tool launch-process`
4. **Credential isolation** -- Ensure `~/.augment/session.json` and environment variables with tokens are not accessible to spawned processes beyond what is necessary
5. **Read-only mode** -- For analysis-only use cases, disable write tools (`str-replace-editor`, `save-file`, `apply_patch`)

### Medium Priority

6. **MCP server restrictions** -- Audit any configured MCP servers; the `${augmentToken}` variable can leak authentication tokens to MCP servers
7. **Resource limits** -- Apply cgroups or container limits for CPU, memory, and disk I/O
8. **Temp directory isolation** -- Ensure `/tmp/augment-log.txt` and other temp files are contained
9. **Git credential protection** -- The agent spawns git processes; ensure git credential helpers don't expose tokens
10. **Indexing scope** -- Use `.augmentignore` to explicitly exclude sensitive directories

### Low Priority

11. **Custom command auditing** -- Review `.augment/commands/` for prompt injection risks
12. **Session data protection** -- Session state may contain sensitive conversation content
13. **Auto-update control** -- Set `autoUpdate: false` in settings to prevent unexpected binary changes
14. **Audit logging** -- Use `AgentEventListener` to log all tool calls for review

### Key Risk Factors

- Unrestricted filesystem read/write/execute capabilities [INFERRED]
- Arbitrary shell command execution via `launch-process` tool [INFERRED]
- Network access to Augment Cloud API and potentially any MCP server [INFERRED]
- Authentication token handling across multiple configuration surfaces [INFERRED]
- Process spawning (git, shell, MCP servers) with inherited user privileges [INFERRED]
- Closed-source nature prevents verification of security claims

### Key Mitigating Features

- Tool permission system (allow/deny/ask-user) [INFERRED]
- `--disable-tool` flag for restricting capabilities [INFERRED]
- `.augmentignore` for indexing scope control [INFERRED]
- Keyish file filtering in indexer [INFERRED]
- Home directory indexing protection [INFERRED]
- Process lifecycle management and cleanup [INFERRED]

### Notable Changelog Items (Security-Relevant)

| Version | Item | Significance |
|---------|------|--------------|
| v0.16.0 | `${augmentToken}` variable for MCP headers | Token leakage vector if MCP servers are malicious |
| v0.16.0 | Localhost OAuth login | Changed auth from JSON paste to browser OAuth |
| v0.14.0 | Fixed MCP server orphan processes | Previous versions could leak processes |
| v0.13.0 | Process lifecycle management | Background processes now tracked and cleaned |
| v0.9.1 | Fixed extraneous git processes spawning after indexing | Process leak fix |
| v0.6.0 | User rules in `~/.augment/rules/` | New configuration surface for agent behavior |
| v0.6.0 | `--disable-tool` flag | Ability to restrict agent capabilities |
| v0.5.3 | Indexing disabled from home directory | Safety guard against accidental data upload |
| v0.5.2 | Workspace size limits | Prevent indexing excessively large directories |
| v0.5.1 | Tool permission system | Configurable allow/deny rules |
| v0.4.0 | Custom commands from Claude Code auto-imported | Cross-agent configuration import |

### GitHub Actions Integration

**Official GitHub Actions:**
1. `augmentcode/augment-agent` - General Augment agent action
2. `augmentcode/review-pr@v0` - AI-powered PR review
3. `augmentcode/describe-pr@v0` - AI-powered PR description generation

**Required Inputs:**

| Input | Source |
|-------|--------|
| `augment_session_auth` | `${{ secrets.AUGMENT_SESSION_AUTH }}` |
| `github_token` | `${{ secrets.GITHUB_TOKEN }}` |
| `pull_number` | `${{ github.event.pull_request.number }}` |
| `repo_name` | `${{ github.repository }}` |

**Required Permissions:**
```yaml
permissions:
  contents: read
  pull-requests: write
```

### Indexing & Context System [INFERRED]

- Indexing is enabled by default in print mode
- Safety guard: indexing is automatically disabled when running from home directory
- Workspace size limits enforced to prevent indexing excessively large directories
- Files respect `.gitignore` and `.augmentignore` patterns
- Git worktree detection supported
- Supports incremental and full re-indexing via GitHub Action indexer
- Full re-index triggered by: first run, different repository, force push, too many commits (>100), too many file changes (>500), ignore file changes
- Context state exportable/importable for persistence across CI runs

### Session Management [INFERRED]

- Sessions have unique IDs
- Sessions can be listed (`auggie session list`), resumed (`auggie session resume <id>`), shared (`/share`), and deleted
- Session state includes: workspace settings, guidelines, rules, memories
- Sessions are terminal-aware (`-c` flag prefers current terminal's session)
- Chat history summarization with visual indicator (v0.16.0)
- Session naming via `/rename` command (v0.16.0)
- Sessions persist across CLI invocations
- `-c` / `--continue` flag resumes most recent session
- `--resume <id>` resumes specific session
