# Overview & Philosophy

Agent Safehouse sandboxes LLM coding agents on macOS so they can only access paths they need.

It uses macOS `sandbox-exec` with composable policy profiles. The default posture is strict: start from deny-all, then allow specific system/runtime/toolchain paths plus explicitly granted project paths.

## Why

LLM coding agents run shell commands with your user privileges. A prompt injection, confused deputy flow, or a bad command can otherwise touch SSH keys, cloud credentials, unrelated repos, and personal files.

Safehouse reduces that blast radius without requiring major workflow changes.

## Guiding Philosophy

Agent productivity is prioritized over paranoid lockdown. The goal is practical damage reduction and stronger defaults, not perfect isolation against a determined attacker.

Each policy rule should answer one question:

> Does the agent need this to do its job?

## What Safehouse Allows

- Filesystem reads for core macOS/system/toolchain paths needed for shells, compilers, and package managers.
- Process execution/forking so normal dev subprocess trees work.
- Agent/app-specific config grants scoped to the wrapped command.
- Keychain/security integration when selected profiles declare keychain dependency metadata.
- Core SCM integrations (`git`, `gh`, `glab`) so repo workflows keep working.
- Sanitized runtime environment by default, with explicit opt-in controls for env pass-through.
- Network access by default for registries, APIs, remotes, and MCP servers.
- Temporary directories and runtime IPC services required by common CLI workflows.

## What Is Denied By Default

- SSH private keys under `~/.ssh`.
- Shell startup files unless `--enable=shell-init` is used.
- Browser profile data unless `--enable=browser-native-messaging` is used.
- Clipboard access unless `--enable=clipboard` is used.
- Broad raw device access under `/dev`.
- Setuid/setgid executable paths (`forbidden-exec-sugid`).

## Important Limitations

Safehouse does **not** fully protect against:

- Data exfiltration over network from files the sandbox is allowed to read.
- Sandbox escapes (it is not a VM/hypervisor boundary).
- Abuse through already-allowed IPC/credential channels.
- Leakage of data from explicitly allowed paths.

For practical hardening guidance, continue with [Getting Started](./getting-started.md) and [Usage](./usage.md).

## Isolation Model Comparison

Safehouse is a host-level macOS policy wrapper, not a VM boundary. It is optimized for day-to-day local agent workflows where low overhead and native compatibility matter.

For a detailed comparison with VMs and containers, see [Isolation Models](./isolation-models.md).

## Default Assumptions

Safehouse defaults prioritize usability plus constrained blast radius:

- keep common coding workflows working
- require explicit opt-in for sensitive integrations
- keep final user overrides possible

For the full allow/disable matrix, see [Default Assumptions](./default-assumptions.md).
