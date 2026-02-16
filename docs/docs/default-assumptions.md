# Default Assumptions (Allow vs Disable)

This page documents the baseline assumptions Safehouse makes so default behavior is predictable.

## Design Assumptions

1. Agents should work with normal developer tooling by default.
2. Sensitive paths and integrations should require explicit opt-in.
3. Least privilege should be practical to maintain.
4. Final-deny overlays should always remain possible (`--append-profile`).

## Allowed by Default

These are baseline allowances intended to keep common workflows functional:

- Selected workdir read/write (git root above CWD, otherwise CWD).
- Core system/runtime paths required by shells, compilers, and package managers.
- Toolchain profile access under `profiles/30-toolchains/`.
- Core integrations in `profiles/50-integrations-core/` (`git`, `scm-clis`).
- Agent-specific profile selection for the wrapped command.
- Network access (open by default).
- Sanitized runtime environment (not full shell env by default).
- SSH metadata read support (`~/.ssh/config`, `~/.ssh/known_hosts`) for git-over-ssh workflows.

## Opt-In (Disabled by Default)

Enable only when required for the current task:

- `clipboard`: clipboard read/write integration.
- `cloud-credentials`: cloud CLI credential stores.
- `docker`: Docker socket and related access.
- `kubectl`: kube config/cache + krew state.
- `shell-init`: shell startup/config file reads.
- `ssh`: extended SSH agent socket and system SSH config integration.
- `browser-native-messaging`: browser host messaging integration.
- `macos-gui`: GUI app-related integration paths.
- `electron`: Electron integration (also enables `macos-gui`).
- `all-agents`: load all agent profiles.
- `all-apps`: load all desktop app profiles.
- `wide-read`: broad read-only visibility across `/` (high-risk convenience mode).

## Not Granted (or Explicitly Denied) by Default

- SSH private keys under `~/.ssh`.
- Browser profile/cookie/session data.
- Shell startup files unless `shell-init` is enabled.
- Clipboard access unless `clipboard` is enabled.
- Broad raw device access under `/dev`.
- Setuid/setgid executable paths (`forbidden-exec-sugid`).

## Operational Defaults for Common Scenarios

- **Daily coding agent use**: no optional integrations; rely on workdir + minimal explicit grants.
- **Cross-repo read context**: add `--add-dirs-ro` for specific sibling paths.
- **Cloud task burst**: enable `cloud-credentials` only for that run/session.
- **Docker/k8s workflow**: enable `docker` and/or `kubectl` only while needed.
- **IDE app-hosted agents**: enable `electron` and add `all-agents` only if extension-hosted CLIs require it.

## Before You Enable Anything

Ask these questions:

1. Is this required for the current task, or just convenient?
2. Can I scope it to a narrower path or single feature?
3. Can I make it read-only instead of read/write?
4. Should this be temporary instead of shell-default?
