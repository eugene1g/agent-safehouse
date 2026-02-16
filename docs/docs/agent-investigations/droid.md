# Droid (Factory CLI) -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/Factory-AI/factory.git
**Git Commit:** `e4074cdac14fae891e3400c1876af2684f2b50b3`
**Latest Version:** v0.57.10 (February 9, 2026)
**License:** All rights reserved (Factory AI, 2025)
**Source Availability:** Docs-only repo

---

## Disclaimer

This repository is **exclusively a documentation repository**. It contains zero source code for the Droid agent itself. The actual `droid` CLI binary is a closed-source product distributed via installer script, Homebrew, npm, or Windows installer. All findings below are derived from public documentation only -- no source code was available for analysis.

### Repository File Inventory

| Category | Count | Notes |
|----------|-------|-------|
| MDX documentation files | ~95 | Mintlify-powered docs site |
| Image/media assets | ~80+ | PNG, GIF, WEBP, MP4, SVG, JPG |
| Example workflows | 2 dirs | GitHub Actions code review, power user skills |
| GitHub workflows | 5 | CI/CD for docs repo itself |
| Scripts | 4 | Docs map generation, Reddit posting, changelog parsing |
| Config files | 3 | `.gitignore`, `docs.json` (Mintlify), `style.css` |

### Key Non-Documentation Files

- `.github/workflows/droid.yml` -- GitHub Actions workflow using `Factory-AI/droid-action@v1`
- `.github/workflows/droid-review.yml` -- Droid-based PR review
- `.github/scripts/generate-docs-map.py` -- Python script for docs
- `.github/scripts/get-reddit-token.js` / `post-to-reddit.js` / `parse-changelog.js` -- Node.js scripts
- `examples/droid-code-review-workflow/` -- Sample GitHub Actions workflow for automated code review
- `examples/power-user-skills/` -- Example SKILL.md files (prompt-refiner-claude, prompt-refiner-gpt, memory-capture)

---

## 1. Overview

**Product Name:** Droid (formerly "Factory CLI")
**Company:** Factory AI (factory.ai)
**Product Category:** AI-native software development agent/platform

Droid is a closed-source, model-agnostic AI coding agent distributed as a CLI binary. It operates in two primary modes: an interactive full-screen TUI (`droid`) and a headless non-interactive mode (`droid exec`) for CI/CD, scripting, and batch processing. [INFERRED] The runtime is built with **Bun** (JavaScript/TypeScript runtime), evidenced by `bun 1.3.3` upgrade mentions in the changelog, Bun GC hints for memory leak fixes, Bun virtual FS sound path extraction, and SEA (Single Executable Application) binary releases.

It is model-agnostic, supporting multiple LLM backends:
- **Anthropic:** Claude Opus 4.5, Claude Opus 4.6, Sonnet 4.5, Haiku 4.5
- **OpenAI:** GPT-5.1, GPT-5.1-Codex, GPT-5.1-Codex-Max, GPT-5.2
- **Google:** Gemini 3 Pro, Gemini 3 Flash
- **Open source:** GLM-4.6 ("Droid Core"), GLM-4.7
- **Custom models via BYOK** (Bring Your Own Key): Ollama, Groq, OpenRouter, Fireworks, DeepInfra, Baseten, HuggingFace

The platform extends across: CLI, Web app (`app.factory.ai`), Slack/Teams, Linear/Jira, and Mobile (via SSH).

Installation methods:
- Installer script: `curl -fsSL https://app.factory.ai/cli | sh`
- Homebrew: `brew install --cask droid`
- npm: `npm install -g droid`
- Windows: `irm https://app.factory.ai/cli/windows | iex`

---

## 2. UI & Execution Modes

[INFERRED] The TUI renders a full-screen terminal interface with chat, diff viewer, and approval workflows. The exact terminal framework is not documented (source is closed), but the agent bundles a code-signed ripgrep binary for search and supports an `agent-browser` companion CLI for Chrome DevTools Protocol automation.

### Execution Modes

1. **Interactive TUI (`droid`)** -- Full-screen terminal interface with chat, diff viewer, approval workflows
2. **Headless/Non-interactive (`droid exec`)** -- Single-shot execution for CI/CD, scripting, and batch processing
   - Supports output formats: `text`, `json`, `stream-json`, `stream-jsonrpc`
   - Supports input formats: `stream-json`, `stream-jsonrpc`
3. **ACP daemon mode** -- Persistent background sessions (added in v0.56.0)

### Main Commands

| Command | Purpose |
|---------|---------|
| `droid` | Start interactive TUI REPL |
| `droid "query"` | Start REPL with initial prompt |
| `droid exec "query"` | Non-interactive single-shot execution |
| `droid exec -f prompt.md` | Execute from file |
| `droid exec -s <id> "query"` | Resume existing session |
| `droid exec --list-tools` | List available tools |
| `droid mcp add <name> <url>` | Add MCP server |
| `droid mcp remove <name>` | Remove MCP server |
| `droid plugin marketplace add <url>` | Add plugin marketplace |
| `droid plugin install <id>` | Install plugin |
| `droid update` | Manual CLI update |
| `droid -v` / `droid --version` | Show version |

### Key CLI Flags

| Flag | Purpose |
|------|---------|
| `--auto <low\|medium\|high>` | Set autonomy level |
| `--skip-permissions-unsafe` | Bypass ALL permission checks (dangerous) |
| `-m, --model <id>` | Select model |
| `-r, --reasoning-effort <level>` | Set reasoning effort |
| `--use-spec` | Start in specification mode |
| `--cwd <path>` | Set working directory |
| `-o, --output-format <format>` | Output: text, json, stream-json, stream-jsonrpc |
| `--input-format <format>` | Input: stream-json, stream-jsonrpc |
| `--enabled-tools <ids>` | Force-enable specific tools |
| `--disabled-tools <ids>` | Disable specific tools |
| `--delegation-url <url>` | URL for delegated sessions (Slack/Linear) |
| `--no-hooks` | Disable hooks execution |
| `--allow-background-processes` | Allow background process spawning |

### Interactive Slash Commands (30+)

`/account`, `/billing`, `/bug`, `/clear`, `/commands`, `/compress`, `/cost`, `/create-skill`, `/droids`, `/favorite`, `/fork`, `/help`, `/hooks`, `/ide`, `/login`, `/logout`, `/mcp`, `/model`, `/new`, `/plugins`, `/quit`, `/readiness-report`, `/rename`, `/review`, `/rewind-conversation`, `/sessions`, `/settings`, `/share`, `/skills`, `/status`, `/statusline`, `/terminal-setup`, `/wrapped`

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General runtime error |
| `2` | Invalid CLI arguments/options |

### IDE Integration

| IDE | Integration Type |
|-----|-----------------|
| VS Code | Dedicated extension (auto-installs from terminal) |
| Cursor | VS Code extension compatible |
| Windsurf | VS Code extension compatible |
| VSCodium | VS Code extension compatible |
| IntelliJ IDEA | Factory Droid plugin OR terminal |
| PyCharm | Factory Droid plugin OR terminal |
| Android Studio | Factory Droid plugin OR terminal |
| WebStorm | Factory Droid plugin OR terminal |
| PhpStorm | Factory Droid plugin OR terminal |
| GoLand | Factory Droid plugin OR terminal |
| Zed | Custom agent configuration |
| Any terminal-capable IDE | Via `droid` command in integrated terminal |

VS Code Extension: `Factory.factory-vscode-extension` ([Marketplace](https://marketplace.visualstudio.com/items?itemName=Factory.factory-vscode-extension)). Features include quick launch, IDE diff viewer, selection context, file reference shortcuts, diagnostic sharing, and `ideAutoConnect` setting for auto-connecting from external terminals.

---

## 3. Authentication & Credentials

### 3.1 Credential Storage

- OAuth tokens stored in the system keyring (with fallback file)
- MCP OAuth tokens stored globally in system keyring (NOT per-project)
- Authentication writes use atomic operations to prevent corruption
- `FACTORY_DISABLE_KEYRING` environment variable available to disable keyring

### 3.2 API Key Sources and Priority Order

1. **Browser-based OAuth Login** (interactive):
   - On first run, `droid` displays a URL and authentication code
   - User opens URL in browser, pastes code to authenticate
   - OAuth tokens stored with OS-level file permissions
   - Tokens auto-rotate every 30 days
   - Supports SSO: SAML 2.0 / OIDC via identity providers (Okta, Azure AD, Google Workspace)

2. **API Key Authentication** (non-interactive / CI/CD):
   - Generated at `https://app.factory.ai/settings/api-keys`
   - Key format: `fk-...` prefix
   - Set via environment variable: `FACTORY_API_KEY=fk-...`
   - Used for `droid exec` headless mode and CI/CD pipelines

3. **Machine Identities**:
   - Long-lived tokens or workload identities for CI/CD runners
   - `FACTORY_TOKEN` environment variable mentioned for CI/CD contexts

### 3.3 OAuth Flows

[INFERRED] Browser-based OAuth with authentication code display. SSO support includes SAML 2.0 / OIDC with identity providers (Okta, Azure AD, Google Workspace). The exact OAuth callback ports and flow details are not documented in the public docs.

### 3.4 Credential File Locations and Formats

[INFERRED] OAuth tokens stored in system keyring with file fallback. Exact file locations for fallback storage are not documented in the public docs.

### Enterprise SSO

- SAML 2.0 / OIDC single sign-on
- SCIM provisioning for user lifecycle management
- Role-based access control: Owner, Admin, User
- IdP group mapping to Factory organizations/teams

---

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

| Path | OS | Purpose |
|------|----|---------|
| `~/.factory/settings.json` | macOS/Linux | User-level settings (model, autonomy, sounds, hooks, etc.) |
| `%USERPROFILE%\.factory\settings.json` | Windows | User-level settings |
| `~/.factory/mcp.json` | Any | User-level MCP server configurations |
| `~/.factory/AGENTS.md` | Any | Personal agent instructions override |
| `~/.factory/skills/<name>/SKILL.md` | Any | Personal skills |
| `~/.factory/droids/<name>.md` | Any | Personal custom subagent definitions |
| `~/.factory/commands/<name>.md` | Any | Personal custom slash commands (legacy, now merged into skills) |

### 4.2 Project-Level Config Paths

| Path | Purpose |
|------|---------|
| `.factory/settings.json` | Project-level settings (checked into git) |
| `.factory/settings.local.json` | Local project settings (NOT committed) |
| `.factory/mcp.json` | Project-level MCP server configurations |
| `./AGENTS.md` | Project-level agent instructions |
| `.factory/skills/<name>/SKILL.md` | Project skills |
| `.factory/droids/<name>.md` | Project custom subagent definitions |
| `.factory/commands/<name>.md` | Project custom slash commands (legacy) |

### 4.3 System/Enterprise Config Paths

[INFERRED] Hierarchical settings model: org > project > folder > user. Extension-only policy model (lower levels cannot weaken upper-level policies). Enterprise plugin registry for centralized plugin control. Maximum autonomy level enforcement per environment.

### 4.4 Data & State Directories

| Path | Purpose |
|------|---------|
| `~/.factory/logs/` | CLI log files |
| `~/.factory/logs/droid-log-single.log` | Primary log file |
| `~/.factory/logs/console.log` | Console log |
| `~/.factory/projects/<project>/<session-id>.jsonl` | Session transcripts (conversation JSON) |
| `~/.factory/bash-command-log.txt` | Example hook log destination |
| `.factory/docs/` | Default directory for spec mode outputs (when `specSaveEnabled: true`) |
| `.factory/hooks/` | Project hook scripts |

### 4.5 Workspace Files Read

| Path | Purpose |
|------|---------|
| `./AGENTS.md` | Project-level agent instructions |
| `CLAUDE.md` | Recognized alongside AGENTS.md for system reminders |
| `.agent/` | Alternative skills folder (loaded from `.agent` folders) |

#### Claude Code Compatibility Paths

Droid explicitly scans and can import from Claude Code directories:

| Path | Purpose |
|------|---------|
| `~/.claude/agents/` | Personal Claude Code agents (importable as custom droids) |
| `<repo>/.claude/agents/` | Project Claude Code agents (importable) |
| `~/.claude/skills/` | Claude Code skills (importable) |
| `CLAUDE.md` | Recognized alongside AGENTS.md for system reminders |

### 4.6 Temp Directory Usage

[INFERRED] Not explicitly documented. The agent likely respects system temp directories given the Bun runtime.

### Plugin Locations

| Path | Purpose |
|------|---------|
| `<plugin>/.factory-plugin/plugin.json` | Plugin manifest |
| `<plugin>/commands/` | Plugin slash commands |
| `<plugin>/skills/` | Plugin skills |
| `<plugin>/droids/` | Plugin subagent definitions |
| `<plugin>/hooks/hooks.json` | Plugin hook configurations |
| `<plugin>/mcp.json` | Plugin MCP configs |

---

## 5. Tools Available to the LLM

[INFERRED] The agent has access to the following tool categories (documented tool IDs):

| Tool | Purpose |
|------|---------|
| `Read` | File reading |
| `Edit` | File editing |
| `Write` / `Create` | File writing/creation |
| `ApplyPatch` | Apply code patches |
| `Bash` / `Execute` | Shell command execution |
| `Grep` | Content search (uses ripgrep) |
| `Glob` | File pattern matching |
| `LS` | Directory listing |
| `WebSearch` | Web search |
| `WebFetch` / `FetchUrl` | URL content fetching |
| `Task` | Subagent/sub-droid delegation |
| `TodoWrite` | Task tracking (always included) |
| `Skill` | Skill invocation |
| `NotebookEdit` | Jupyter notebook editing |
| MCP tools | External tools via `mcp__<server>__<tool>` naming |

Additional details:
- **Write access restriction:** Can only modify files in the project directory and subdirectories
- **Shell commands:** Local execution with risk classification
- **Git operations:** Full git support (status, diff, commit, push with appropriate autonomy)
- Bundled ripgrep binary for search (code-signed)
- Images compressed before upload
- Files > 500 KB in unsaved buffers are skipped for performance
- Tools can be force-enabled or disabled via `--enabled-tools` and `--disabled-tools` CLI flags
- `droid exec --list-tools` lists all available tools

---

## 6. Host System Interactions

### 6.1 Subprocess Execution

[INFERRED] Shell command execution with risk classification. Bundled ripgrep binary (code-signed) for search. `agent-browser` CLI for browser automations via Chrome DevTools Protocol (CDP). Orphaned browser daemon cleanup documented as a fixed bug.

- `allowBackgroundProcesses` setting (experimental) for spawning background processes

### 6.2 Network Requests

#### Factory Cloud Endpoints

| Endpoint | Purpose |
|----------|---------|
| `app.factory.ai` | Main web application, installer scripts, API keys |
| `app.factory.ai/cli` | CLI installer (macOS/Linux) |
| `app.factory.ai/cli/windows` | CLI installer (Windows) |
| `app.factory.ai/settings/api-keys` | API key management |
| `api.factory.ai` | Factory API |
| `api.factory.ai/api/v0/openapi.json` | OpenAPI specification |
| `docs.factory.ai` | Documentation site |
| `trust.factory.ai` | Trust center / compliance docs |
| `*.factory.ai` | General Factory cloud domains |
| `discord.gg/zuudFXxg69` | Community Discord |

#### LLM Provider Endpoints (configurable)

| Provider | Endpoint |
|----------|----------|
| Anthropic | Direct API (enterprise) |
| OpenAI | `api.openai.com/v1` |
| Google (Gemini) | Direct API |
| AWS Bedrock | Via customer AWS accounts |
| GCP Vertex AI | Via customer GCP accounts |
| Azure OpenAI | Via customer Azure accounts |
| Groq | `api.groq.com/openai/v1` |
| OpenRouter | `openrouter.ai/api/v1` |
| Fireworks | Custom endpoints |
| DeepInfra | Custom endpoints |
| Baseten | Custom endpoints |
| HuggingFace | Custom endpoints |
| Ollama | Local endpoints |

#### MCP Server Endpoints (from built-in registry, 40+ servers)

| Server | Endpoint |
|--------|----------|
| Sentry | `mcp.sentry.dev/mcp` |
| Notion | `mcp.notion.com/mcp` |
| Linear | `mcp.linear.app/mcp` |
| Stripe | `mcp.stripe.com` |
| Figma | `mcp.figma.com/mcp` |
| Vercel | `mcp.vercel.com/` |
| Netlify | `netlify-mcp.netlify.app/mcp` |
| PayPal | `mcp.paypal.com/mcp` |
| Canva | `mcp.canva.com/mcp` |
| HuggingFace | `huggingface.co/mcp` |
| Intercom | `mcp.intercom.com/mcp` |
| Monday | `mcp.monday.com/mcp` |
| Socket | `mcp.socket.dev/` |
| Stytch | `mcp.stytch.dev/mcp` |
| TwelveLabs | `mcp.twelvelabs.io` |

#### Telemetry and Analytics

| Endpoint | Purpose |
|----------|---------|
| OTEL collectors | OpenTelemetry metrics, traces, logs (customer-configured) |
| Mixpanel (`f2846cc5dfc8931eb2d1e98383a748e5`) | Docs site analytics (project token in docs.json) |
| Palo Alto Prisma AIRS | Droid Shield Plus AI security scanning (enterprise) |

### 6.3 Port Binding

[INFERRED] Not explicitly documented. OAuth flows likely bind local ports for callbacks.

### 6.4 Browser Launching

[INFERRED] Browser opened during OAuth login flow (user is shown a URL and authentication code).

### 6.5 Clipboard Access

None identified in documentation.

### 6.6 File System Watchers

None identified in documentation.

### 6.7 Other

- **Proxy Support:** Standard environment variables respected: `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`, `NODE_EXTRA_CA_CERTS` for custom CAs
- **GitHub Actions Integration:** Official action `Factory-AI/droid-action@v1` for GitHub-triggered Droid execution. Triggers on `@droid` mentions in issue comments, PR review comments, PR reviews, and issues. Requires permissions: `contents: write`, `pull-requests: write`, `issues: write`, `id-token: write`, `actions: read`.
- **Code Review Workflow:** Full automated code review via `droid exec --auto high`. Triggers on PR events (opened, synchronize, reopened, ready_for_review). Generates inline review comments via GitHub API. Installs CLI to `$HOME/.local/bin/droid`.
- **CI/CD permissions example (GitHub Actions):**
  ```yaml
  permissions:
    contents: write      # Read/write repo files
    pull-requests: write # Post review comments
    issues: write        # Write to issues
    id-token: write      # OIDC authentication
    actions: read        # Read workflow info
  ```

### Enterprise Data Flows

- **Code/files:** Local only; never uploaded to a remote datastore
- **LLM traffic:** Sent to configured model providers; Factory does not proxy through third-party services
- **Telemetry:** OTLP signals to customer-configured collectors
- **Factory cloud (optional):** Limited operational logs, authentication events, anonymized usage metrics

---

## 7. Extension Points

### 7.1 Hook/Lifecycle System

#### Available Hook Events

| Event | When | Can Block? |
|-------|------|-----------|
| `PreToolUse` | Before tool execution | Yes (exit code 2 or JSON deny) |
| `PostToolUse` | After tool completion | Feedback only |
| `UserPromptSubmit` | Before prompt processing | Yes (erases prompt) |
| `Notification` | When droid sends notifications | No |
| `Stop` | When droid finishes responding | Yes (forces continuation) |
| `SubagentStop` | When sub-droid completes | Yes (forces continuation) |
| `PreCompact` | Before context compaction | No |
| `SessionStart` | Session start/resume | Context injection |
| `SessionEnd` | Session termination | No (cleanup only) |

#### Hook Configuration Locations

1. `~/.factory/settings.json` -- User hooks
2. `.factory/settings.json` -- Project hooks
3. `.factory/settings.local.json` -- Local project hooks
4. Plugin `hooks/hooks.json` -- Plugin hooks
5. Enterprise managed policy settings

#### Hook Input (via stdin JSON)

```json
{
  "session_id": "string",
  "transcript_path": "path/to/session.jsonl",
  "cwd": "string",
  "permission_mode": "default|plan|acceptEdits|bypassPermissions",
  "hook_event_name": "string",
  "tool_name": "string",
  "tool_input": {},
  "tool_response": {}
}
```

#### Hook Execution Details

- **Timeout:** 60 seconds default, configurable per command
- **Parallelization:** All matching hooks run in parallel
- **Deduplication:** Identical commands are deduplicated
- **Security:** Hooks snapshot captured at startup; external modifications require review
- **Environment:** `FACTORY_PROJECT_DIR` and `DROID_PLUGIN_ROOT` available

### 7.2 Plugin/Extension Architecture

Plugins are managed via marketplace or direct install:
- `droid plugin marketplace add <url>` -- Add plugin marketplace
- `droid plugin install <id>` -- Install plugin
- Enterprise plugin registry for centralized plugin control

Plugin structure:
| Path | Purpose |
|------|---------|
| `<plugin>/.factory-plugin/plugin.json` | Plugin manifest |
| `<plugin>/commands/` | Plugin slash commands |
| `<plugin>/skills/` | Plugin skills |
| `<plugin>/droids/` | Plugin subagent definitions |
| `<plugin>/hooks/hooks.json` | Plugin hook configurations |
| `<plugin>/mcp.json` | Plugin MCP configs |

### 7.3 MCP Integration

#### Transport Types

1. **HTTP** -- Remote MCP endpoints (recommended for cloud services)
2. **stdio** -- Local processes (for direct system access)

#### Configuration Schema

```json
{
  "mcpServers": {
    "server-name": {
      "type": "http|stdio",
      "url": "https://...",
      "headers": {},
      "command": "npx ...",
      "args": [],
      "env": {},
      "disabled": false
    }
  }
}
```

#### Layering

- User config (`~/.factory/mcp.json`) takes priority over project config (`.factory/mcp.json`)
- Project servers cannot be removed via CLI/UI (must edit file directly)
- OAuth tokens stored globally in system keyring
- Droid auto-reloads when config changes

### 7.4 Custom Commands/Skills/Agents

- **Skills:** `~/.factory/skills/<name>/SKILL.md` (personal) and `.factory/skills/<name>/SKILL.md` (project)
- **Custom Droids (subagents):** `~/.factory/droids/<name>.md` (personal) and `.factory/droids/<name>.md` (project)
- **Custom Slash Commands (legacy):** `~/.factory/commands/<name>.md` (personal) and `.factory/commands/<name>.md` (project). Now merged into skills.
- **`/create-skill` command** for creating skills interactively

### 7.5 SDK/API Surface

- `stream-jsonrpc` input/output format for SDK integration
- `stream-json` for real-time execution monitoring
- OTLP (OpenTelemetry) for metrics, traces, logs
- Cloud session sync to `app.factory.ai`
- [INFERRED] ACP (Agent Control Protocol) daemon mode for persistent background sessions

---

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

[INFERRED] No built-in OS-level container isolation. The docs explicitly recommend but do not enforce running in containers/VMs. The agent itself runs directly on the host. The "project directory only" write restriction is enforced by the agent, not by OS-level sandboxing.

### 8.2 Permission System -- Autonomy Levels (Risk-Tiered)

| Level | Capabilities | Restrictions |
|-------|-------------|--------------|
| **Default (no flags)** | Read-only: file reads, git diffs, `ls`, `git status`, env inspection | No modifications |
| **Auto Low** | + File creation/editing, formatters, read-only commands from allowlist | No system mods, no package installs |
| **Auto Medium** | + Package installs, build/test, local git commits, `npm install`, `mv`, `cp` | No `git push`, no `sudo`, no production changes |
| **Auto High** | + Git push, deploy scripts, long-running ops, docker, migrations | Still blocks destructive patterns |
| **`--skip-permissions-unsafe`** | ALL operations without confirmation | **No guardrails** -- only for disposable containers |

#### Command Risk Classification

Every shell command is classified by risk level:
- **Low risk:** read-only operations (`ls`, `cat`, `git status`)
- **Medium risk:** workspace modifications (`npm install`, `go test`, local git)
- **High risk:** destructive/security-sensitive (`rm -rf`, `kubectl delete`, `psql` against production)

### 8.3 Safety Mechanisms

#### Safety Interlocks (Always Active)

Even at Auto High, these always require confirmation:
- Dangerous patterns: `rm -rf /`, `dd of=/dev/*`
- Command substitution: `$(...)`, backticks
- CLI security check flagged commands

#### Command Allowlists and Denylists

Configured in `settings.json`:
```json
{
  "commandAllowlist": ["ls", "pwd", "dir"],
  "commandDenylist": ["rm -rf /", "mkfs", "shutdown"]
}
```
- Org-level deny/allow lists cannot be removed by projects or users
- Commands in both lists default to denylist behavior
- Extension-only policy hierarchy (can only get stricter, never looser)

#### Droid Shield (Secret Scanning)

**Standard (all users):**
- Pattern-based detection of API keys, tokens, passwords, private keys
- Scans `git commit` and `git push` diffs (only lines being added)
- Blocks git operations if secrets detected
- Enabled by default (`enableDroidShield: true`)
- Randomness validation to reduce false positives

**Shield Plus (enterprise):**
- Powered by Palo Alto Networks Prisma AIRS
- AI-powered prompt injection detection
- Advanced secrets/DLP scanning (PII, financial data)
- Toxic content and malicious code detection
- Scans prompts before they reach LLMs
- Scans git operations with AI analysis

#### Built-in Protections

- **Write access restriction:** Can only modify files in project directory and subdirectories
- **Command approval:** Risky operations require explicit user confirmation
- **Prompt injection detection:** Analyzes requests for potentially harmful instructions
- **Network request controls:** Web-fetching tools require approval by default
- **Input sanitization:** Prevents command injection attacks
- **Session isolation:** Each conversation maintains separate, secure context

#### Hook-Based Security Extensions

Hooks provide programmable enforcement points:
- **PreToolUse:** Block or modify tool calls before execution
- **PostToolUse:** Validate outputs after execution
- **UserPromptSubmit:** Filter/block prompts with sensitive content
- **Before file reads/writes:** Block access to sensitive files
- **Before git operations:** Prevent unauthorized pushes
- Exit code 2 from hooks blocks the operation and feeds stderr to the agent

### 8.4 Known Vulnerabilities

None identified in public documentation.

### 8.5 Enterprise/Managed Security Controls

- SOC 2 Type II certified
- GDPR compliant
- SAML 2.0 / OIDC SSO with SCIM provisioning
- Role-based access control (RBAC)
- Zero data retention mode
- Customer-managed encryption keys (BYOK)
- Private cloud deployments
- AES-256 encryption at rest (AWS KMS)
- TLS 1.3 encryption in transit
- Complete session logging
- OpenTelemetry metrics/traces/logs
- Hierarchical settings (org > project > folder > user)
- Extension-only policy model (lower levels cannot weaken upper-level policies)
- Enterprise plugin registry for centralized plugin control
- Maximum autonomy level enforcement per environment

#### Deployment Patterns

1. **Cloud-managed:** Droid on laptops/CI, Factory cloud for orchestration
2. **Hybrid:** Droid in customer infrastructure, selective Factory cloud access
3. **Fully airgapped:** No internet; models served on-premises; no Factory cloud dependency

---

## 9. Key Dependencies

[INFERRED] Since no source code is available, dependencies are inferred from documentation:

| Dependency | Purpose |
|------------|---------|
| Bun runtime | JavaScript/TypeScript runtime (inferred from changelog references) |
| Bundled ripgrep binary | Code search (code-signed) |
| `agent-browser` CLI | Chrome DevTools Protocol automation |
| System keyring | OAuth token storage |

---

## 10. Environment Variables

| Variable | Purpose |
|----------|---------|
| `FACTORY_API_KEY` | API key authentication |
| `FACTORY_TOKEN` | CI/CD token authentication |
| `FACTORY_PROJECT_DIR` | Project root (set by droid for hooks) |
| `FACTORY_LOG_FILE` | Custom log file output |
| `FACTORY_DISABLE_KEYRING` | Disable keyring for token storage |
| `DROID_PLUGIN_ROOT` | Plugin root directory (for plugin hooks) |
| `DROID_CWD` | Current working directory (hook context) |
| `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` | Proxy configuration |
| `NODE_EXTRA_CA_CERTS` | Custom CA certificates |
| `GH_TOKEN` | GitHub token for Actions integration |

---

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `~/.factory/settings.json` | R/W | User-level settings | Yes |
| `~/.factory/mcp.json` | R/W | User-level MCP server configurations | Yes |
| `~/.factory/AGENTS.md` | R | Personal agent instructions | No (user-created) |
| `~/.factory/skills/<name>/SKILL.md` | R | Personal skills | No (user-created) |
| `~/.factory/droids/<name>.md` | R | Personal custom subagent definitions | No (user-created) |
| `~/.factory/commands/<name>.md` | R | Personal slash commands (legacy) | No (user-created) |
| `~/.factory/logs/` | W | CLI log files | Yes |
| `~/.factory/logs/droid-log-single.log` | W | Primary log file | Yes |
| `~/.factory/logs/console.log` | W | Console log | Yes |
| `~/.factory/projects/<project>/<session-id>.jsonl` | R/W | Session transcripts | Yes |
| `~/.factory/bash-command-log.txt` | W | Hook log destination | Yes |
| `.factory/settings.json` | R/W | Project-level settings | Yes |
| `.factory/settings.local.json` | R/W | Local project settings | Yes |
| `.factory/mcp.json` | R/W | Project-level MCP configurations | Yes |
| `.factory/docs/` | W | Spec mode outputs | Yes |
| `.factory/hooks/` | R | Project hook scripts | No (user-created) |
| `.factory/skills/<name>/SKILL.md` | R | Project skills | No (user-created) |
| `.factory/droids/<name>.md` | R | Project subagent definitions | No (user-created) |
| `./AGENTS.md` | R | Project agent instructions | No (user-created) |
| `CLAUDE.md` | R | Alternative agent instructions | No (user-created) |
| `.agent/` | R | Alternative skills folder | No (user-created) |
| `~/.claude/agents/` | R | Claude Code agents (importable) | No |
| `~/.claude/skills/` | R | Claude Code skills (importable) | No |
| `<plugin>/.factory-plugin/plugin.json` | R | Plugin manifest | No (user/plugin) |
| System keyring | R/W | OAuth token storage | Yes |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `app.factory.ai` | Main web app, installers, API keys | Installation, auth, cloud sync |
| `api.factory.ai` | Factory API | API operations |
| `docs.factory.ai` | Documentation site | Documentation access |
| `trust.factory.ai` | Trust center / compliance | Compliance checks |
| Anthropic API | LLM inference | When Anthropic model selected |
| `api.openai.com/v1` | LLM inference | When OpenAI model selected |
| Google Gemini API | LLM inference | When Gemini model selected |
| AWS Bedrock | LLM inference | When Bedrock configured |
| GCP Vertex AI | LLM inference | When Vertex configured |
| Azure OpenAI | LLM inference | When Azure configured |
| `api.groq.com/openai/v1` | LLM inference | When Groq configured |
| `openrouter.ai/api/v1` | LLM inference | When OpenRouter configured |
| Ollama (local) | LLM inference | When Ollama configured |
| Fireworks / DeepInfra / Baseten / HuggingFace | LLM inference | When BYOK configured |
| MCP server endpoints (40+ in registry) | External tool integrations | When MCP servers enabled |
| OTEL collectors | Telemetry | When OpenTelemetry configured |
| Mixpanel | Docs site analytics | Docs site visits |
| Palo Alto Prisma AIRS | AI security scanning | Enterprise Shield Plus |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Shell execution | [INFERRED] Direct subprocess | Risk-classified commands with autonomy-based approval |
| File read/write | [INFERRED] Direct filesystem | Restricted to project directory |
| Git operations | [INFERRED] Git CLI | Full support: status, diff, commit, push |
| Browser automation | `agent-browser` CLI | Chrome DevTools Protocol |
| System keyring | OS keyring API | OAuth token storage with file fallback |
| Network requests | HTTP/HTTPS | LLM APIs, Factory cloud, MCP servers |
| Background processes | Experimental setting | `allowBackgroundProcesses` flag |

---

## 12. Sandboxing Recommendations

### What the Agent CAN Do (when granted appropriate autonomy)

1. Read any file accessible to the user running it
2. Write/create files within the project directory
3. Execute arbitrary shell commands (with risk classification)
4. Install packages (`npm install`, `pip install`, etc.)
5. Perform git operations including push
6. Make HTTP requests (web search, URL fetch, MCP connections)
7. Spawn background processes (experimental)
8. Automate Chrome via CDP
9. Connect to 40+ external services via MCP
10. Delegate to sub-agents with independent context windows

### What the Agent CANNOT Do (enforced)

1. Override org-level deny lists or security policies
2. Modify files outside the project directory (documented restriction)
3. Execute commands blocked by safety interlocks (even at Auto High)
4. Disable Droid Shield where enforced by org policy
5. Weaken any policy set at a higher hierarchy level

### Sandboxing Gaps / Considerations

1. **No built-in container isolation** -- The docs explicitly recommend but do not enforce running in containers/VMs. The agent itself runs directly on the host.
2. **Local execution model** -- All shell commands and file edits run locally with the user's full permissions. The autonomy system is advisory/prompt-based, not OS-enforced.
3. **`--skip-permissions-unsafe`** -- Completely removes all guardrails; documented as for "disposable containers" only.
4. **Hooks run with user credentials** -- Hooks execute in the user's environment with full access; malicious hooks can exfiltrate data.
5. **MCP stdio servers** -- Run as local processes with the user's permissions (e.g., `npx -y <package>` can install and execute arbitrary code).
6. **File content included in LLM requests** -- Code portions selected for context are sent to configured model providers.
7. **BYOK custom models** -- Users can route traffic to arbitrary HTTP endpoints when BYOK is enabled.
8. **No filesystem chroot** -- The "project directory only" restriction is enforced by the agent, not by OS-level sandboxing.

### Recommended Isolation Strategy (from Enterprise Docs)

Factory explicitly recommends container/VM sandboxing:
- Docker/Podman devcontainers with restricted filesystem mounts and network egress
- Higher autonomy ONLY inside containers/VMs without production access
- Separate credentials for sandboxed vs. production environments
- CI/CD: ephemeral jobs with short-lived credentials and minimal privileges
- Environment tagging via OTEL: `environment.type=local|ci|sandbox`

### Version History

| Version | Date | Notable Features |
|---------|------|-----------------|
| v0.57.10 | Feb 9, 2026 | Skills UX overhaul, terminal tab titles, desktop notifications |
| v0.57.9 | Feb 7, 2026 | Opus 4.6 Fast Mode |
| v0.57.7 | Feb 6, 2026 | Claude Opus 4.6 Fast, /fork command, org-managed settings |
| v0.57.5 | Feb 5, 2026 | Claude Opus 4.6, semantic diffs, plugin hooks, npm package |
| v0.56.0 | Jan 27, 2026 | ACP daemon mode, lazy session loading |
| v0.55.1 | Jan 22, 2026 | OpenTelemetry tracing |
| v0.26.0 | Nov 14, 2025 | Skills system, session favorites |
| v0.24.0 | Nov 12, 2025 | Hooks system |
| v0.22.6 | Oct 30, 2025 | MCP revamp |

### Pricing Tiers

| Plan | Standard Tokens/Month | Price/Month |
|------|----------------------|-------------|
| Free | BYOK only | $0 |
| Pro | 10M (+10M bonus) | $20 |
| Max | 100M (+100M bonus) | $200 |

Overage: $2.70 per million Standard Tokens.
