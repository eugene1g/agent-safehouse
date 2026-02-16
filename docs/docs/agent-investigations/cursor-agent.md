# Cursor Agent -- Sandbox Analysis Report

**Analysis Date:** 2026-02-12
**Repository:** https://github.com/cursor/cursor
**Git Commit:** `53a1e5adf5b0db7a08bbe47cf8be207c3740bce5`
**Latest Version:** N/A (no tags in repository)
**License:** Proprietary (current version; original open-source version was MIT)
**Source Availability:** Docs-only repo

---

## Disclaimer

This repository is documentation-only. It contains only `README.md`, `SECURITY.md`, and a GitHub issue template. The actual Cursor agent source code is proprietary and closed-source. This analysis combines facts extracted from the repository with publicly available information. All inferred or externally sourced information is clearly marked as `[INFERRED]`.

---

## 1. Overview

**From README.md (documented fact)**:
> "Cursor is an AI code editor and coding agent."

Cursor is a proprietary AI-powered code editor built as a fork of Visual Studio Code (Electron-based). It includes multiple AI agent modes that can read, write, search, and execute code on behalf of the user. The "agent" functionality refers to Cursor's ability to autonomously perform multi-step coding tasks using LLM-powered tool calling.

**Key identity points (from repo)**:
- Website: https://cursor.com
- Features page: https://cursor.com/features
- Community forum: https://forum.cursor.com/
- Security contact: security-reports@cursor.com
- Security policy: https://cursor.com/security

### Repository Contents

The repository at `github.com/cursor/cursor` currently contains only:

```
.
├── .git/
├── .github/
│   └── ISSUE_TEMPLATE/
│       └── new-issue.md
├── README.md
└── SECURITY.md
```

#### README.md

A minimal file describing Cursor as "an AI code editor and coding agent" with links to the website, features page, and community forum. No version numbers, no technical documentation, no configuration references.

#### SECURITY.md

A vulnerability disclosure policy directing reporters to email `security-reports@cursor.com` rather than filing public GitHub issues. References https://cursor.com/security for the full security posture.

#### .github/ISSUE_TEMPLATE/new-issue.md

Redirects users to https://forum.cursor.com/ as the primary bug/feedback channel, noting that GitHub Issues are checked on a best-effort basis.

### Git History

The repository has a rich history spanning from March 2023 to January 2026:

| Period | Activity |
|--------|----------|
| **Mar 2023** (commits `a1b9dcb` to `099eec4`) | Initial commit with full open-source Electron/React/TypeScript codebase (CodeMirror-based editor) |
| **Mar-Apr 2023** (many commits) | Active open-source development: bug fixes, features, CI, PRs from community |
| **Apr 30, 2023** (commit `7815030`) | **"CM code -> own repo"** - All source code removed, repo becomes issues-only |
| **2023-2024** | README updates, issue template changes |
| **Sep 2024** | SECURITY.md added with vulnerability disclosure policy |
| **Oct 2025** | Security email updated (PR #3712) |
| **Jan 2026** | Latest README updates |

#### Key Historical Insight: Original Codebase (Now Removed)

Before commit `7815030`, the repo contained a full Electron application:

**From the original `package.json` (commit `099eec4`)**:
- **Name**: "Cursor"
- **Version**: 0.1.4
- **Description**: "Cursor is an AI-first coding environment."
- **Author**: Michael Truell (mntruell@gmail.com)
- **License**: MIT (no longer applies to current proprietary version)
- **Stack**: Electron + Electron Forge + React + TypeScript + Webpack
- **Build tool**: todesktop (desktop app packaging)

The original open-source CodeMirror-based editor was moved to `github.com/getcursor/cursor-codemirror`. The current proprietary Cursor IDE is a VS Code fork and is architecturally different from this original codebase.

#### Branch Artifacts

Several legacy branches remain from the open-source era:
- `origin/closeErrorsOnDeepLink` - Deep link error handling
- `origin/openAIVerify` - OpenAI API key validation
- `origin/patchContinue` - Bug fix for infinite loop
- `origin/pricing` - Pricing/pro plan features
- `origin/pricingBrowser` - Pricing UI in browser
- `origin/smallFixes` - Miscellaneous fixes

These branches contain historical code from the original editor but are irrelevant to the current proprietary Cursor agent.

## 2. UI & Execution Modes

[INFERRED] Cursor is built as a **fork of Visual Studio Code** (Electron-based). Its architecture includes:

### Process Model
- **Main process**: Electron main process (Node.js)
- **Renderer process**: VS Code UI (Chromium)
- **Extension host**: Runs VS Code extensions
- **AI extensions**: Cursor-specific extensions layered on top of VS Code

### Cursor-Specific Extensions
The IDE includes at least four proprietary extensions:
- **cursor-retrieval**: Codebase indexing system for semantic search
- **cursor-shadow-workspace**: AI workspace manager
- **cursor-tokenize**: Text tokenization system for LLM context
- **cursor-deeplink**: URI handling system

### Communication Protocols
- **HTTP/2 with ConnectRPC** (gRPC-Web variant) with binary protobuf encoding for AI service communication
- Standard HTTP for marketplace and telemetry
- gRPC for core AI and synchronization services

### Execution Modes

[INFERRED] Cursor provides multiple AI interaction modes:

#### Local Agent Mode (Interactive)
- Runs within the IDE process on the user's machine
- Has access to the user's filesystem (read: entire FS; write: scoped to workspace)
- Can execute terminal commands (with user approval unless in YOLO/auto-run mode)
- Uses LLM tool calling to perform multi-step coding tasks

#### Background Agent (Cloud)
- Spins up an **Ubuntu-based VM** in Cursor's **AWS cloud infrastructure**
- Clones the user's repository into the VM
- Runs against an allow-listed set of tools
- Produces pull requests asynchronously
- Each agent runs in its own **Docker container** with isolated filesystem
- Users can configure the environment via `environment.json` and `Dockerfile`

#### Tab Completion / Inline Suggestions
- Predictive code completion (not agent-based)

## 3. Authentication & Credentials

[INFERRED]

### 3.1 Credential Storage

Cursor uses account-based authentication via cursor.com. Login is required for AI features (free tier or paid plans). Deep link authentication flow (visible in historical branch `closeErrorsOnDeepLink`).

### 3.2 API Key Sources and Priority Order

- API keys can be configured for custom model providers (OpenAI, etc.)
- Background Agents API uses **Basic Auth** with base64-encoded API key (trailing colon)

### 3.3 OAuth Flows

Not explicitly documented. The historical branch `openAIVerify` shows early API key validation logic. Pro plan / pricing was added early (branch `pricing`).

### 3.4 Credential File Locations and Formats

[INFERRED] Credential state is stored in the SQLite state database (`state.vscdb`):
- **Table**: `ItemTable`
- **Key**: `src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser`

Enterprise teams have additional analytics API access.

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

[INFERRED] Application data directories:

| Platform | Path |
|----------|------|
| **macOS** | `~/Library/Application Support/Cursor/` |
| **Linux** | `~/.config/Cursor/` |
| **Windows** | `%APPDATA%\Cursor\` |

#### Key Internal Files

| File | Purpose |
|------|---------|
| `User/globalStorage/state.vscdb` | SQLite database storing IDE state, including command allowlists and security settings |
| `User/settings.json` | User-level IDE settings |
| `extensions/` | Installed VS Code extensions |

#### SQLite State Database (`state.vscdb`)

The command allowlist and YOLO mode settings are stored in:
- **Table**: `ItemTable`
- **Key**: `src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser`
- **JSON path**: `$.composerState.yoloCommandAllowlist`

Related security settings in the same store:
- `useYoloMode` - Whether auto-run is enabled
- `yoloCommandDenylist` - Commands explicitly blocked
- `yoloPrompt` - Custom prompt for YOLO mode
- `yoloDotFilesDisabled` - Whether dotfile access is blocked
- `yoloOutsideWorkspaceDisabled` - Whether out-of-workspace commands are blocked
- `playwrightProtection` - Browser automation protection
- `mcpAllowedTools` - Allowed MCP tools

### 4.2 Project-Level Config Paths

[INFERRED]

| Path | Purpose |
|------|---------|
| `.cursor/` | Project-level Cursor configuration directory |
| `.cursor/rules/` | Project rules (markdown files like `base.mdc`, `security.mdc`) |
| `.cursor/rules.md` | AI persona configuration |
| `.cursor/mcp/` | MCP (Model Context Protocol) server configurations |
| `.cursor/mcp.json` | MCP server connection settings |
| `.cursor/environment.json` | Background agent environment configuration |
| `.cursorrules` | Legacy project rules file (auto-detected) |

#### Background Agent Environment Configuration (`.cursor/environment.json`)

```json
{
  "snapshot": "<cached-disk-image-ref>",
  "install": "npm install",
  "start": "npm run dev",
  "terminals": [
    { "name": "server", "command": "npm run dev" }
  ],
  "env": {
    "NODE_ENV": "development"
  }
}
```

Fields:
- **snapshot**: Reference to a cached disk image for faster boot
- **install**: Idempotent dependency installation script (cached after first run)
- **start**: Command to run when environment starts
- **terminals**: Background processes that run alongside the agent
- **env**: Environment variables for the remote environment

### 4.3 System/Enterprise Config Paths

Not explicitly documented.

### 4.4 Data & State Directories

[INFERRED]:
- Cursor inherits VS Code's data storage patterns
- Background agents use cloud VMs with disposable filesystems
- Local agent operates within the user's standard temp directories

### 4.5 Workspace Files Read

[INFERRED]:
- `.cursor/rules/` (project rules)
- `.cursor/rules.md` (AI persona)
- `.cursorrules` (legacy rules)
- `.cursor/mcp.json` (MCP configuration)
- `.cursor/environment.json` (background agent config)

### 4.6 Temp Directory Usage

[INFERRED]:
- Cursor inherits VS Code's temp file patterns
- Background agents use cloud VMs with disposable filesystems
- Local agent operates within the user's standard temp directories

## 5. Tools Available to the LLM

[INFERRED - from leaked/published system prompts and public documentation]

The Cursor Agent system prompt (powered by Claude) provides the following tools:

| Tool | Description | Parameters |
|------|-------------|------------|
| `codebase_search` | Semantic code search across the codebase | `query`, scope options |
| `read_file` | Read file contents (max ~250 lines per call) | `target_file`, `start_line`, `end_line`, `explanation` |
| `edit_file` | Modify file contents using diff-like markers | `target_file`, `instructions`, `code_edit` |
| `run_terminal_cmd` | Execute a shell command (requires approval) | `command`, `explanation` |
| `grep_search` | Regex-based text search (max 50 results) | `query`, `case_sensitive`, `include_pattern`, `exclude_pattern` |
| `file_search` | Fuzzy filename search (max 10 results) | `query` |
| `list_dir` | List directory contents | `relative_workspace_path`, `explanation` |
| `web_search` | Real-time web search | `query` |
| `delete_file` | Delete a file | `target_file`, `explanation` |

### Tool Usage Rules (from system prompt)
- Tools are only called when necessary
- The agent never outputs code to the user unless requested; it uses edit tools instead
- The agent must never call tools not explicitly provided
- Tool names must not be referenced when communicating with users
- All file paths are relative to the workspace

## 6. Host System Interactions

### 6.1 Subprocess Execution

[INFERRED] Terminal command execution via `run_terminal_cmd` tool:
- Default: Requires user approval for each terminal command
- **YOLO / Auto-Run Mode**: Executes commands without approval
- **Allowlist Mode**: Only pre-approved commands run automatically
- **Denylist Mode**: Specific commands are blocked; others auto-approved

### 6.2 Network Requests

[INFERRED - from public sources and reverse engineering reports]

#### Primary Domains

| Domain | Purpose |
|--------|---------|
| `api2.cursor.sh` | Primary API endpoint (AI completions, chat, agent commands). Uses HTTP/2 with ConnectRPC and binary protobuf |
| `api3.cursor.sh` | Telemetry endpoint |
| `api.cursor.sh` | General API / CLI updates |
| `cursor.com` | Website, authentication, downloads |
| `marketplace.cursorapi.com` | VS Code marketplace interactions |
| `cursor-user-debugging-data.s3.us-east-1.amazonaws.com` | User debugging data uploads (pre-signed S3 URLs) |

#### Telemetry

Cursor inherits VS Code's Microsoft telemetry data collection endpoint and adds its own telemetry via `api3.cursor.sh`. The telemetry collects:
- Development environment information
- Git repository usage analytics
- Standard user actions and interactions
- Error/crash reports

#### Debugging Data Upload

An endpoint generates pre-signed AWS S3 URLs for uploading user debugging data:
- **Bucket**: `cursor-user-debugging-data.s3.us-east-1.amazonaws.com`
- **Path pattern**: `/github|<user_ID>/<timestamp>-debugging-data.zip`

### 6.3 Port Binding

Not explicitly documented. Cursor likely uses Electron's built-in IPC mechanisms rather than TCP ports for internal communication.

### 6.4 Browser Launching

[INFERRED] Deep link authentication flow (visible in historical branch `closeErrorsOnDeepLink`). Cursor likely launches browsers for authentication and documentation links.

### 6.5 Clipboard Access

[INFERRED] Inherited from VS Code -- full clipboard read/write via Electron/Chromium APIs.

### 6.6 File System Watchers

[INFERRED] Inherited from VS Code -- VS Code uses file system watchers extensively for workspace monitoring.

### 6.7 Other

[INFERRED]
- **Codebase indexing**: `cursor-retrieval` extension indexes the codebase for semantic search
- **Tokenization**: `cursor-tokenize` extension handles text tokenization for LLM context
- **VS Code telemetry**: Inherited from VS Code (Microsoft telemetry)
- **Electron vulnerabilities**: Inherits Chromium security surface

## 7. Extension Points

### 7.1 Hook/Lifecycle System

None identified.

### 7.2 Plugin/Extension Architecture

[INFERRED] Cursor inherits VS Code's extension system. Cursor-specific AI extensions run in the extension host process:
- `cursor-retrieval`
- `cursor-shadow-workspace`
- `cursor-tokenize`
- `cursor-deeplink`

### 7.3 MCP Integration

[INFERRED] Cursor supports MCP (Model Context Protocol):
- Configuration via `.cursor/mcp.json` or `.cursor/mcp/` directory
- Allows the agent to interact with external systems (databases, APIs) through configured server connections
- `mcpAllowedTools` setting controls which MCP tools are permitted

### 7.4 Custom Commands/Skills/Agents

[INFERRED]
- `.cursor/rules/` directory for project rules (markdown files)
- `.cursor/rules.md` for AI persona configuration
- `.cursorrules` legacy rules file
- Background agent environment configuration via `.cursor/environment.json`

### 7.5 SDK/API Surface

[INFERRED] The Background Agents API supports:
- Launching agents on GitHub repositories
- Managing agent lifecycles
- Retrieving conversation histories
- Configuring PR automation
- Monitoring agent status

Enterprise teams additionally have access to:
- Analytics APIs (commit tracking, code changes)
- Usage metrics endpoints

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

#### What the Repository Documents

The repository's `SECURITY.md` documents only the vulnerability disclosure process:
- Report vulnerabilities to `security-reports@cursor.com`
- Do not use public GitHub issues for security reports
- Full security info at https://cursor.com/security

#### Local Agent Security [INFERRED]

1. **Filesystem Access**:
   - **Read**: Full filesystem access (can read any file the user can read)
   - **Write**: Scoped to current workspace directory
   - **Delete**: Protected even in auto-run mode

2. **Command Execution**:
   - Default: Requires user approval for each terminal command
   - **YOLO / Auto-Run Mode**: Executes commands without approval
   - **Allowlist Mode**: Only pre-approved commands run automatically
   - **Denylist Mode**: Specific commands are blocked; others auto-approved

#### Background Agent Security [INFERRED]

1. **Isolation**: Each agent runs in its own Docker container on an Ubuntu VM in AWS
2. **Filesystem**: Clean filesystem per container; no cross-contamination
3. **Resource Limits**: Controlled resource allocation per container
4. **Tool Allowlist**: Agents run against a specific set of allowed tools
5. **Repository Scope**: Agent operates on a clone of the repository, not the user's local files

### 8.2 Permission System

[INFERRED]

#### Local Agent Permissions

| Permission | Default | YOLO Mode |
|------------|---------|-----------|
| Read any file | Yes | Yes |
| Write files in workspace | Yes (with diff preview) | Yes |
| Write files outside workspace | Requires approval | Configurable (`yoloOutsideWorkspaceDisabled`) |
| Execute terminal commands | Requires approval | Auto-approved (filtered by allowlist/denylist) |
| Access dotfiles | Yes | Configurable (`yoloDotFilesDisabled`) |
| Delete files | Requires approval | Requires approval (protected) |
| MCP tool invocation | Requires approval | Configurable (`mcpAllowedTools`) |
| Web search | Yes | Yes |
| Network access (via terminal) | Via terminal commands | Via terminal commands |

#### Background Agent Permissions

| Permission | Status |
|------------|--------|
| Repository access | Full (cloned into VM) |
| Terminal commands | Allowed within VM |
| Network access | Scoped (allow-listed) |
| Filesystem | Isolated to container |
| Git operations | Can create branches and PRs |
| External service access | Via configured environment |

### 8.3 Safety Mechanisms

[INFERRED]
- Sensitive file protection (e.g., `.cursor/mcp.json` protected against modification)
- YOLO mode command allowlist/denylist
- Delete file protection in auto-run mode
- Playwright protection setting

### 8.4 Known Vulnerabilities

Several security vulnerabilities have been publicly disclosed:

#### CVE-2026-22708 - Terminal Tool Allowlist Bypass via Environment Variables

- **Severity**: High
- **Affected**: Cursor < 2.3
- **Issue**: Shell built-in commands (`export`, `typeset`) could be executed without appearing in the allowlist and without user approval, even when the allowlist was empty
- **Attack Vector**: Indirect prompt injection could poison the shell environment by manipulating environment variables that influence trusted commands
- **Impact**: Sandbox bypass and remote code execution in both zero-click and one-click scenarios
- **Fix**: Cursor 2.3 now requires explicit user approval for commands the server-side parser cannot classify

#### CVE-2025-59944 - Sensitive File Overwrite Bypass (Case Sensitivity)

- **Severity**: High (CVSS ~8.0)
- **Affected**: Cursor <= 1.6.23
- **Issue**: Cursor checked sensitive file paths (e.g., `.cursor/mcp.json`) using case-sensitive comparison, but macOS and Windows use case-insensitive filesystems
- **Attack Vector**: Prompt injection could write to `.Cursor/MCP.json` (different case) and the OS would treat it as the same file
- **Impact**: Remote code execution via modified MCP configuration
- **Fix**: Cursor 1.7

#### CVE-2025-4609 - Chromium Sandbox Escape (Inherited from VS Code/Electron)

- **Severity**: Critical (CVSS 9.6)
- **Issue**: Chromium IPC mechanism flaw allowing renderer process to reuse browser process handles, escaping the sandbox
- **Impact**: Since Cursor is Electron-based, it inherits Chromium vulnerabilities. Downstream applications like Cursor may lag behind Chromium patches
- **Note**: This is an upstream Chromium vulnerability, not Cursor-specific

#### Sandboxing Credential Leaks (November 2025)

- Cursor's transition from allow-lists to filesystem access created new security risks
- The agent's full filesystem read access combined with aggressive auto-approval could leak credentials from the home directory
- Sensitive files (`.env`, SSH keys, cloud credentials) could be read by the agent and potentially exfiltrated through prompt injection

### 8.5 Enterprise/Managed Security Controls

[INFERRED]
- Enterprise teams have additional analytics API access
- Background agents provide inherent isolation via containerization

## 9. Key Dependencies

[INFERRED] As a VS Code fork, Cursor inherits the full VS Code / Electron dependency tree:

| Dependency | Impact |
|-----------|--------|
| Electron | Desktop application framework (Chromium + Node.js) |
| Chromium | Rendering engine, inherits browser vulnerabilities |
| Node.js | Extension host, main process |
| VS Code Extension API | Extension system, marketplace |
| ConnectRPC (gRPC-Web) | AI service communication protocol |
| Protocol Buffers | Binary serialization for API calls |

## 10. Environment Variables

[INFERRED] Based on background agent configuration and VS Code inheritance:

| Variable | Purpose |
|----------|---------|
| (via `.cursor/environment.json` `env` field) | Background agent environment configuration |
| Standard VS Code env vars | Inherited from VS Code |
| `NODE_ENV` | Example from environment.json documentation |

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `~/Library/Application Support/Cursor/` (macOS) | Read/Write | Application data [INFERRED] | Yes |
| `~/.config/Cursor/` (Linux) | Read/Write | Application data [INFERRED] | Yes |
| `%APPDATA%\Cursor\` (Windows) | Read/Write | Application data [INFERRED] | Yes |
| `User/globalStorage/state.vscdb` | Read/Write | IDE state, command allowlists [INFERRED] | Yes |
| `User/settings.json` | Read/Write | User settings [INFERRED] | Yes |
| `extensions/` | Read/Write | VS Code extensions [INFERRED] | Yes |
| `.cursor/` | Read/Write | Project-level config [INFERRED] | No |
| `.cursor/rules/` | Read | Project rules [INFERRED] | No |
| `.cursor/rules.md` | Read | AI persona config [INFERRED] | No |
| `.cursor/mcp.json` | Read | MCP server config [INFERRED] | No |
| `.cursor/mcp/` | Read | MCP server configs [INFERRED] | No |
| `.cursor/environment.json` | Read | Background agent config [INFERRED] | No |
| `.cursorrules` | Read | Legacy project rules [INFERRED] | No |
| Entire filesystem | Read | Agent can read any user-accessible file [INFERRED] | No |
| Workspace directory | Write | Agent writes within workspace [INFERRED] | Yes |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| `api2.cursor.sh` | Primary AI API (ConnectRPC/protobuf) [INFERRED] | AI completions, chat, agent commands |
| `api3.cursor.sh` | Telemetry [INFERRED] | Periodically |
| `api.cursor.sh` | General API / CLI updates [INFERRED] | Updates, general API |
| `cursor.com` | Authentication, downloads [INFERRED] | Login, updates |
| `marketplace.cursorapi.com` | VS Code marketplace [INFERRED] | Extension install/update |
| `cursor-user-debugging-data.s3.us-east-1.amazonaws.com` | Debug data uploads [INFERRED] | On debug data submission |
| Microsoft telemetry endpoints | VS Code telemetry [INFERRED] | Periodically (inherited) |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Terminal command execution | Shell subprocess [INFERRED] | Via `run_terminal_cmd` tool, approval-gated |
| File read | Internal tool [INFERRED] | Full filesystem read access |
| File write/edit | Internal tool [INFERRED] | Scoped to workspace |
| File delete | Internal tool [INFERRED] | Protected even in YOLO mode |
| Codebase search | `cursor-retrieval` extension [INFERRED] | Semantic search via indexing |
| Web search | `web_search` tool [INFERRED] | Real-time web queries |
| Clipboard | Electron/Chromium APIs [INFERRED] | Read/write inherited from VS Code |
| MCP subprocess | Child process [INFERRED] | MCP server connections |
| Browser launch | Electron shell [INFERRED] | Authentication, deep links |
| Telemetry | HTTP [INFERRED] | Cursor + VS Code telemetry |
| Debug data upload | HTTPS (pre-signed S3) [INFERRED] | On user-initiated debug submission |
| Background agent VM | AWS Docker container [INFERRED] | Cloud-based agent execution |

## 12. Sandboxing Recommendations

### Local Agent Sandboxing

1. **Filesystem Isolation**:
   - Cursor agent has read access to the entire filesystem by default
   - Sandbox should restrict reads to the project workspace and explicitly allowed paths
   - Block access to `~/.ssh/`, `~/.aws/`, `~/.config/`, `~/.gnupg/`, `.env` files
   - Monitor and restrict access to the SQLite state database (`state.vscdb`)

2. **Network Isolation**:
   - Cursor communicates with `*.cursor.sh` domains (API, telemetry)
   - Terminal commands can make arbitrary network requests
   - Sandbox should allowlist only necessary Cursor API domains and block arbitrary outbound connections from agent-spawned processes

3. **Command Execution**:
   - Never use YOLO/auto-run mode in sandboxed environments
   - Maintain strict command allowlists
   - Be aware that shell built-ins may bypass allowlists (CVE-2026-22708)
   - Monitor for environment variable manipulation

4. **MCP Protection**:
   - Protect `.cursor/mcp.json` from modification (including case variants)
   - Restrict MCP tool access to only necessary integrations

### Background Agent Sandboxing

5. **Already Containerized**: Background agents run in Docker containers on AWS VMs, providing inherent isolation from the user's local environment

6. **Secret Management**: Never embed secrets in `environment.json` or `setup.sh`. Use Cursor's environment variable configuration with proper secret management

7. **Repository Scope**: Background agents operate on repository clones; ensure no sensitive data exists in the repository that shouldn't be accessible

### Process-Level Considerations

8. **Electron Vulnerabilities**: As an Electron app, Cursor inherits Chromium vulnerabilities. Keep Cursor updated to receive upstream security patches

9. **Extension Isolation**: Cursor's AI extensions run in the extension host process; VS Code's extension sandboxing model applies

10. **Telemetry**: Cursor sends telemetry to Microsoft (inherited from VS Code) and its own servers. In privacy-sensitive environments, evaluate telemetry settings

### Sources

#### From This Repository (Documented Facts)

- `README.md` at commit `53a1e5adf5b0db7a08bbe47cf8be207c3740bce5`
- `SECURITY.md` at commit `53a1e5adf5b0db7a08bbe47cf8be207c3740bce5`
- `.github/ISSUE_TEMPLATE/new-issue.md`
- Git history (93 commits across 10 branches)
- Historical `package.json` at commit `099eec4`

#### External Sources (Inferred Information)

- [Cursor Agent System Prompt (March 2025)](https://gist.github.com/sshh12/25ad2e40529b269a88b80e7cf1c38084)
- [Cursor Agent Tools - DeepWiki](https://deepwiki.com/x1xhlol/system-prompts-and-models-of-ai-tools/4.1-cursor-agent-tools)
- [The Agent Security Paradox: When Trusted Commands in Cursor Become Attack Vectors](https://www.pillar.security/blog/the-agent-security-paradox-when-trusted-commands-in-cursor-become-attack-vectors)
- [The State of Cursor, November 2025: When Sandboxing Leaks Your Secrets](https://luca-becker.me/blog/cursor-sandboxing-leaks-secrets/)
- [Cursor Security: Key Risks, Protections & Best Practices](https://www.reco.ai/learn/cursor-security)
- [CVE-2026-22708 - Terminal Tool Allowlist Bypass](https://v2.cvefeed.io/vuln/detail/CVE-2026-22708)
- [CVE-2025-59944 - Sensitive File Overwrite Bypass](https://www.lakera.ai/blog/cursor-vulnerability-cve-2025-59944)
- [CVE-2025-4609 - Chromium Sandbox Escape](https://www.ox.security/blog/the-aftermath-of-cve-2025-4609-critical-sandbox-escape-leaves-1-5m-developers-vulnerable/)
- [How Cursor Stores Its Command Allowlist in SQLite](https://tarq.net/posts/cursor-sqlite-command-allowlist/)
- [Peeking Under the Hood of Cursor's API Calls](https://speedscale.com/blog/peeking-under-the-hood-of-cursor/)
- [Configuring Cursor Environments with environment.json](https://stevekinney.com/courses/ai-development/cursor-environment-configuration)
- [Background Agents in Cursor: Cloud-Powered Coding at Scale](https://decoupledlogic.com/2025/05/29/background-agents-in-cursor-cloud-powered-coding-at-scale/)
- [Cursor IDE Security Best Practices](https://www.backslash.security/blog/cursor-ide-security-best-practices)
- [Mastering Cursor Configuration Guide](https://www.hubermann.com/en/blog/mastering-cursor-configuration-a-comprehensive-guide-to-project-rules-and-settings)
- [Security in Cursor 2.0: Sandbox Environment & Data Privacy](https://skywork.ai/blog/vibecoding/cursor-2-0-security-privacy/)
- [Hijacking Cursor's Agent: How We Took Over an EC2 Instance](https://www.reco.ai/blog/hijacking-cursors-agent-how-we-took-over-an-ec2-instance)
- [Cursor YOLO Mode Safeguards Bypassed - The Register](https://www.theregister.com/2025/07/21/cursor_ai_safeguards_easily_bypassed/)
