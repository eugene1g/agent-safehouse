# Default Assumptions (Allow vs Disable)

This page documents the baseline assumptions Safehouse makes so default behavior is predictable.

## Design Assumptions

1. Agents should work with normal developer tooling by default.
2. Sensitive paths and integrations should require explicit opt-in.
3. Least privilege should be practical to maintain.
4. Final-deny overlays should always remain possible (`--append-profile`).

## Allowed by Default

These are baseline allowances intended to keep common workflows functional:

- Selected invocation directory read/write by default.
- Safehouse does not auto-widen the default workdir to an enclosing Git repo; broader parent-repo access must be granted explicitly.
- Existing linked Git worktrees are granted read-only visibility only when the selected workdir itself is a Git worktree root.
- Shared Git common-dir metadata for linked worktrees is granted read/write only when the selected workdir itself is a linked Git worktree root and that metadata lives outside the selected workdir.
- Metadata-only traversal on `/`, the path to `$HOME`, and `$HOME` itself so runtimes can reach explicitly allowed home-scoped paths without opening broad home reads.
- Directory-root reads for `~/.config` and `~/.cache` so tools can discover XDG locations; contents under those trees still need more specific grants.
- Core system/runtime paths required by shells, compilers, and package managers.
- Toolchain profile access under `profiles/30-toolchains/`.
- Curated Apple Command Line Tools shim targets for common `/usr/bin` developer commands such as `git`, `make`, and `clang`.
- Core integrations in `profiles/50-integrations-core/` (`container-runtime-default-deny`, `git`, `launch-services`, `scm-clis`, `ssh-agent-default-deny`, `worktree-common-dir`, `worktrees`).
- Agent-specific profile selection for the wrapped command.
- Network access (open by default).
- Sanitized runtime environment (not full shell env by default; preserves `SDKROOT`, `EDITOR`, and `VISUAL` when set).
- SSH metadata read support (`~/.ssh/config`, `~/.ssh/known_hosts`) for git-over-ssh workflows.

## Opt-In (Disabled by Default)

Enable only when required for the current task:

- `agent-browser`: local browser automation CLI state plus Chrome-family launch access.
- `clipboard`: clipboard read/write integration.
- `cleanshot`: read access to CleanShot media captures.
- `cloud-credentials`: cloud CLI credential stores.
- `chromium-headless`: headless Chromium / Playwright shell access.
- `chromium-full`: system Google Chrome and related full Chrome allowances.
- `docker`: Docker socket and related access.
- `1password`: 1Password CLI/app integration paths.
- `kubectl`: kube config/cache + krew state.
- `shell-init`: shell startup/config file reads.
- `ssh`: extended SSH agent socket and system SSH config integration.
- `spotlight`: Spotlight metadata queries via `mdfind` / `mdls`.
- `microphone`: microphone capture via TCC/CoreAudio/CMIO without broader GUI grants.
- `browser-native-messaging`: browser host messaging integration.
- `playwright-chrome`: Playwright Chrome-family channels plus injected `PLAYWRIGHT_MCP_SANDBOX=false`.
- `process-control`: host process enumeration/signalling for local supervision tools.
- `lldb`: LLDB/debugger toolchain access plus debugger-grade host process inspection.
- `vscode`: Visual Studio Code desktop/editor integration, including cold-start Claude editor handoff support. Without `--enable=vscode`, Claude can only reuse an already-running VS Code instance for external-editor handoff. If `EDITOR` or `VISUAL` is set, Safehouse does not inject the VS Code-specific Claude fallback.
- `xcode`: full Xcode developer roots plus Xcode/CoreSimulator user state.
- `macos-gui`: GUI app-related integration paths.
- `electron`: Electron integration (also enables `macos-gui`).
- `all-agents`: load all agent profiles.
- `all-apps`: load all desktop app profiles.
- `wide-read`: broad read-only visibility across `/` (high-risk convenience mode).

## Not Granted (or Explicitly Denied) by Default

- Broad recursive reads of `$HOME`, directory listing of `$HOME` itself, and arbitrary file reads under `$HOME` unless a narrower explicit rule grants that path.
- SSH private keys under `~/.ssh`.
- SSH agent sockets (`SSH_AUTH_SOCK`, including launchd listeners and `~/.ssh/agent/*`) unless `ssh` is enabled.
- Browser profile/cookie/session data, even when `browser-native-messaging` is enabled.
- Shell startup files unless `shell-init` is enabled.
- Clipboard access unless `clipboard` is enabled.
- Host process enumeration/control unless `process-control` or `lldb` is enabled.
- LLDB/debugger toolchain and task-port access unless `lldb` is enabled.
- Full Xcode developer roots and Xcode/CoreSimulator state unless `xcode` is enabled.
- Broad raw device access under `/dev`.

`browser-native-messaging` is intentionally narrower: it grants NativeMessagingHosts registration paths and browser extension-manifest reads, not cookies, passwords, history, or bookmarks.

## Operational Defaults for Common Scenarios

- **Daily coding agent use**: no optional integrations; rely on workdir + minimal explicit grants.
- **Nested folder inside a larger repo**: the default workdir stays on the nested folder; add `--add-dirs` or `--add-dirs-ro` if you intentionally want the enclosing repo.
- **Multi-worktree repo use**: existing worktrees are readable by default at launch; add `--add-dirs-ro` for a stable worktree parent if you need future worktrees for read context without restarting, or `--add-dirs` if you intentionally want broader write access.
- **Cross-repo read context**: add `--add-dirs-ro` for specific sibling paths or files.
- **Cloud task burst**: enable `cloud-credentials` only for that run/session.
- **Docker/k8s workflow**: enable `docker` and/or `kubectl` only while needed.
- **Native builds via Apple shims**: common `/usr/bin/git`, `/usr/bin/make`, and `/usr/bin/clang` flows work by default via the Apple toolchain core profile.
- **Full Xcode builds / simulator flows**: add `--enable=xcode`; reserve `--enable=lldb` for debugger sessions.
- **Local process triage**: prefer `process-control`; reserve `lldb` for real debugger sessions.
- **IDE app-hosted agents**: enable `electron` and add `all-agents` only if extension-hosted CLIs require it.

## Before You Enable Anything

Ask these questions:

1. Is this required for the current task, or just convenient?
2. Can I scope it to a narrower path or single feature?
3. Can I make it read-only instead of read/write?
4. Should this be temporary instead of shell-default?
