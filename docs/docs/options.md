# Options

## Core Flags

| Flag | Description |
|------|-------------|
| `--add-dirs=PATHS` | Colon-separated paths to grant read/write |
| `--add-dirs-ro=PATHS` | Colon-separated paths to grant read-only |
| `--workdir=DIR` | Main directory to grant read/write (`--workdir=` disables automatic workdir grants) |
| `--trust-workdir-config` | Trust and load `<workdir>/.safehouse` (`--trust-workdir-config=BOOL` also supported) |
| `--append-profile=PATH` | Append sandbox profile file after generated rules (repeatable) |
| `--enable=FEATURES` | Enable optional features (see list below) |
| `--env` | Pass full inherited env to wrapped command (incompatible with `--env-pass`) |
| `--env=FILE` | Start from sanitized env and source extra values from `FILE` |
| `--env-pass=NAMES` | Pass selected host env names on top of sanitized/env-file baseline |
| `--output=PATH` | Write policy to a file instead of temp path |
| `--stdout` | Print generated policy to stdout |
| `--explain` | Print effective workdir/grants/profile-selection summary to stderr |

## Optional `--enable` Features

- `clipboard`
- `docker`
- `kubectl`
- `macos-gui`
- `electron` (implies `macos-gui`)
- `ssh`
- `spotlight`
- `cleanshot`
- `1password`
- `cloud-credentials`
- `browser-native-messaging`
- `shell-init`
- `all-agents`
- `all-apps`
- `wide-read`

## Parsing and Separator Behavior

- Path/feature flags accept both `--flag=value` and `--flag value`.
- Runtime env flags support `--env`, `--env=FILE`, and `--env-pass=NAME1,NAME2`.
- Flags are parsed before the first standalone `--`; args after `--` are passed through unchanged.

## Execution Behavior

- No command args: generate policy and print policy file path.
- Command args provided: generate policy, then execute command under `sandbox-exec`.

## Workdir Selection

When `--workdir` is omitted, Safehouse chooses:

1. Git root above invocation directory (if present)
2. Otherwise invocation directory

Path grant merge order:

1. Trusted `<workdir>/.safehouse` (when trust is enabled)
2. `SAFEHOUSE_ADD_DIRS_RO` / `SAFEHOUSE_ADD_DIRS`
3. CLI `--add-dirs-ro` / `--add-dirs`

## Environment Variables

- `SAFEHOUSE_ADD_DIRS_RO`: colon-separated read-only path grants
- `SAFEHOUSE_ADD_DIRS`: colon-separated read/write path grants
- `SAFEHOUSE_WORKDIR`: workdir override (`SAFEHOUSE_WORKDIR=` disables automatic grants)
- `SAFEHOUSE_TRUST_WORKDIR_CONFIG`: trust/load `<workdir>/.safehouse`
- `SAFEHOUSE_ENV_PASS`: comma-separated env names to pass through
- `SAFEHOUSE_CLAUDE_POLICY_URL`: launcher policy URL override for `Claude.app.sandboxed.command`
- `SAFEHOUSE_CLAUDE_POLICY_SHA256`: expected checksum for downloaded launcher policy

## Optional Workdir Config

Path: `<workdir>/.safehouse`

Supported keys:

- `add-dirs-ro=PATHS`
- `add-dirs=PATHS`

By default this file is ignored. It is loaded only with `--trust-workdir-config` (or `SAFEHOUSE_TRUST_WORKDIR_CONFIG`).

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
