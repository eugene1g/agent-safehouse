# Options

## Core Flags

| Flag | Description |
|------|-------------|
| `--add-dirs=PATHS` | Colon-separated file/directory paths to grant read/write |
| `--add-dirs-ro=PATHS` | Colon-separated file/directory paths to grant read-only |
| `--workdir=DIR` | Main directory to grant read/write (`--workdir=` disables automatic workdir grants) |
| `--trust-workdir-config` | Trust and load `<workdir>/.safehouse` (`--trust-workdir-config=BOOL` also supported) |
| `--append-profile=PATH` | Append sandbox profile file after generated rules (repeatable) |
| `--enable=FEATURES` | Enable optional features (see list below) |
| `--env` | Pass the full inherited host env to the wrapped command, including secrets (incompatible with `--env-pass`) |
| `--env=FILE` | Start from sanitized env and source extra values from `FILE` |
| `--env-pass=NAMES` | Pass selected host env names on top of sanitized/env-file baseline |
| `--output=PATH` | Write policy to `PATH`; still executes the wrapped command when one is provided |
| `--stdout` | Print generated policy to stdout |
| `--explain` | Print effective workdir/grants/profile-selection summary to stderr |

## Optional `--enable` Features

- `agent-browser`
- `clipboard`
- `docker`
- `kubectl`
- `macos-gui`
- `electron` (implies `macos-gui`)
- `chromium-headless`
- `chromium-full` (implies `chromium-headless`)
- `playwright-chrome` (implies `chromium-full`, `chromium-headless`)
- `ssh`
- `spotlight`
- `cleanshot`
- `1password`
- `cloud-credentials`
- `browser-native-messaging`
- `shell-init`
- `process-control`
- `lldb`
- `xcode`
- `all-agents`
- `all-apps`
- `wide-read`

Common Apple shimmed developer tools such as `/usr/bin/git`, `/usr/bin/make`, and `/usr/bin/clang` are available by default via `profiles/30-toolchains/apple-toolchain-core.sb`; this is not an optional `--enable` feature.

## Parsing and Separator Behavior

- Path/feature flags accept both `--flag=value` and `--flag value`.
- Runtime env flags support `--env`, `--env=FILE`, and `--env-pass=NAME1,NAME2`.
- Flags are parsed before the first standalone `--`; args after `--` are passed through unchanged.
- Leading `NAME=VALUE` tokens after `--` are handled by the `/usr/bin/env -i` launcher and become child env assignments for the wrapped command.

## Execution Behavior

- No command args: generate policy and print policy file path.
- Command args provided: generate policy, then execute command under `sandbox-exec`.
- `--stdout`: print the policy text and do not execute the wrapped command.
- `--output=PATH`: write the generated policy to `PATH`; if a wrapped command is present, Safehouse still executes it.

## Workdir Selection

Safehouse resolves the effective workdir in this order:

1. `--workdir=DIR` (`--workdir=` disables the automatic workdir grant)
2. `SAFEHOUSE_WORKDIR` (`SAFEHOUSE_WORKDIR=` also disables the automatic workdir grant)
3. Git root above the invocation directory (if present)
4. Otherwise the invocation directory

When the effective workdir is a Git worktree root:

- If the current worktree uses a shared Git common dir outside the selected workdir, that common dir gets automatic read/write access.
- Safehouse snapshots the current worktree set at launch time and grants read-only access to the other existing linked worktree paths.
- That worktree snapshot is fixed for the lifetime of the running sandboxed process. New worktrees created after launch are not added automatically.
- If your worktrees live under a stable parent directory and you want future worktrees available without restarting the agent, grant that parent explicitly with `--add-dirs-ro=/path/to/worktrees-root` for the same read behavior, or `--add-dirs=/path/to/worktrees-root` if you intentionally want write access too.

Path grant merge order:

1. Trusted `<workdir>/.safehouse` (when trust is enabled)
2. `SAFEHOUSE_ADD_DIRS_RO` / `SAFEHOUSE_ADD_DIRS`
3. CLI `--add-dirs-ro` / `--add-dirs`

## Environment Variables

Prefer sanitized mode plus `--env-pass` or `SAFEHOUSE_ENV_PASS` when only a few host variables are needed. For one-off child env values, put `NAME=VALUE` immediately after `--`, for example `safehouse -- MYVAR=123 printenv MYVAR`. `--env` disables that boundary and forwards the entire inherited host environment, including cloud credentials, API keys, and other secrets.

`SSH_AUTH_SOCK` is not part of the default sanitized allowlist. Use `--enable=ssh` to auto-pass the current caller value, re-enable `/usr/bin/ssh`, and reopen outbound TCP 22 for SSH workflows. Use explicit env controls only when you need to inspect the variable without granting socket access.

- `SAFEHOUSE_ADD_DIRS_RO`: colon-separated read-only path grants
- `SAFEHOUSE_ADD_DIRS`: colon-separated read/write path grants
- `SAFEHOUSE_WORKDIR`: workdir override (`SAFEHOUSE_WORKDIR=` disables automatic grants)
- `SAFEHOUSE_TRUST_WORKDIR_CONFIG`: trust/load `<workdir>/.safehouse`
- `SAFEHOUSE_ENV_PASS`: comma-separated env names to pass through

## Optional Workdir Config

Path: `<workdir>/.safehouse`

Supported keys:

- `add-dirs-ro=PATHS`
- `add-dirs=PATHS`

By default this file is ignored. It is loaded only with `--trust-workdir-config` (or `SAFEHOUSE_TRUST_WORKDIR_CONFIG`).
Trusted config parsing fails fast on malformed lines and unknown keys.

## `--env=FILE` Format

`FILE` is sourced by `/bin/bash` with `set -a`, so treat it as trusted shell input.

Typical shape:

```bash
OPENAI_API_KEY="sk-..."
ANTHROPIC_API_KEY="..."
export NO_BROWSER=true
PATH="/custom/bin:${PATH}"
```

Supports `export`, quoted values, blank lines, and comments.
