# Agent Safehouse

[![Tests (macOS)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml/badge.svg)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Sandbox your LLM coding agents on macOS so they can only touch the files they need.

Uses macOS `sandbox-exec` with composable policy profiles to confine agents like Claude Code, Codex, Gemini CLI, Cursor, Aider, and others. Starts from **deny-all** and selectively opens access to toolchains, agent configs, integrations, and the directories you specify.

## Why

LLM coding agents run shell commands with broad filesystem access. A prompt injection, confused deputy, or hallucinated `rm -rf` can reach your SSH keys, AWS credentials, other repos, or anything else your user account can touch. This kit shrinks the blast radius to the project directory and the toolchains the agent actually needs — without breaking normal development workflows.

## Guiding Philosophy

**Agent productivity > paranoid lockdown.** The sandbox makes accidental damage hard and targeted attacks more constrained, but it is not a security boundary against a determined adversary with code execution. Every rule follows one question: *does the agent need this to do its job?*

### What we allow (and why)

- **Filesystem reads for system paths** — `/usr`, `/bin`, `/opt`, `/System`, `/Library/Frameworks`, etc. Agents spawn shells, compilers, and package managers that link against system libraries. Denying these breaks everything.
- **Full process exec/fork** — agents orchestrate deep subprocess trees (shell > git > ssh > credential-helper). Restricting process creation is impractical.
- **Toolchain and agent config directories** — each toolchain (`~/.cargo`, `~/.npm`, `~/.cache/uv`, etc.) and agent (`~/.claude`, `~/.codex`, etc.) gets scoped read+write to its own paths. No broader access.
- **Keychain and Security framework** (always-on) — most agents (Claude Code, Amp, etc.) store login tokens in macOS Keychain and cannot authenticate without it. Read+write access to Keychain files and Security mach services is required for credential storage, retrieval, and TLS certificate validation. This is not a feature toggle because agents fail to start without it.
- **Shell startup files** — `~/.zshenv`, `~/.zprofile`, `/etc/zshrc`, etc. Without these, agents get a broken PATH and misconfigured environment.
- **SSH config (not `~/.ssh` keys)** — `~/.ssh/config`, `~/.ssh/known_hosts`, `/etc/ssh/ssh_config`, `/etc/ssh/ssh_config.d/`, `/etc/ssh/crypto/`. The SSH profile denies `~/.ssh` first, then re-allows only these non-sensitive files.
- **Runtime mach services** — notification center, logd, diagnosticd, CoreServices, DiskArbitration, DNS-SD, opendirectory, FSEvents, trustd, etc. These are framework-level dependencies that many CLI tools probe during init.
- **Network (fully open)** — agents need package registries, APIs, MCP servers, and git remotes. Restricting network is possible but breaks most workflows.
- **Temp directories** — `/tmp`, `/var/folders`. Transient files, IPC sockets, build artifacts.

### What we specifically deny (and why)

- **`~/.ssh` private keys (default policy)** — blocked by default via the SSH integration profile; only `config` and `known_hosts` are re-allowed. If you explicitly grant `~/.ssh` later via CLI path grants, you can override this.
- **`~/.aws` credentials** (optional) — can be blocked via a custom appended profile file (`--append-profile`) for defense-in-depth.
- **Browser profile directories (default)** — browser profile data (cookies/session/password/history) is denied by default to protect sensitive data. Browser native messaging support is always-on, but narrowly scoped to `NativeMessagingHosts` (read/write) and `Default/Extensions` (read-only) paths.
- **`/dev` raw device access** — this policy allows `/dev` traversal/metadata plus specific safe device nodes (`/dev/null`, `/dev/urandom`, `/dev/tty*`, `/dev/ptmx`, `/dev/autofs_nowait`). It does not grant broad read/write access to raw device files.
- **`forbidden-exec-sugid`** — execution of setuid/setgid binaries (`sudo`, `passwd`, etc.) is denied. Agents should never escalate privileges. If a specific setuid binary is needed, allow it by name rather than blanket-allowing privilege escalation.
- **`osascript` execution** (optional) — if you want to hard-block AppleScript entrypoints, add a deny in a custom appended profile file (`--append-profile`). This can reduce GUI/session automation surface but may break agent notification UX.
- **Raw disk/kernel devices** — `/dev/disk*`, `/dev/bpf*`, `/dev/pf`, `/dev/audit*`, `/dev/dtrace`, `/dev/fsevents`. No coding agent needs raw disk access or packet capture.

### What we do NOT protect against

- **Network exfiltration / C2** — network is fully open. If an agent can read a file and has network access, it can send the contents anywhere. See `profiles/20-network.sb` for restrictive alternatives.
- **Sandbox escapes** — `sandbox-exec` is a userspace mechanism, not a hypervisor. Apple has deprecated the public API, though the kernel enforcement still works.
- **Credential theft via IPC** — Mach services like SecurityServer and 1Password are allowed for keychain/auth workflows, which means an agent could theoretically interact with them.
- **Data exfiltration via allowed paths** — the sandbox limits *which* files are visible, not what happens with their contents once read.

## Setup

Add shell functions so agent wrappers preserve argument boundaries and forward `"$@"` safely:

```bash
# ~/.bashrc or ~/.zshrc
# Point this to your clone location
safehouse() {
  "$HOME/.local/share/agent-safehouse/bin/safehouse.sh" "$@"
}

safe() { safehouse --add-dirs-ro="$HOME/mywork" "$@"; }
claude()   { safe claude --dangerously-skip-permissions "$@"; }
codex()    { safe codex --dangerously-bypass-approvals-and-sandbox "$@"; }
amp()      { safe amp --dangerously-allow-all "$@"; }
opencode() { OPENCODE_PERMISSION='{"*":"allow"}' safe opencode "$@"; }
gemini()   { NO_BROWSER=true safe gemini --yolo "$@"; }
pi()       { safe pi "$@"; }
```

How this works:
- `safe <agent> ...` keeps Safehouse's default workdir behavior: read/write access to the selected workdir (`git` root above CWD, otherwise CWD).
- `--add-dirs-ro="$HOME/mywork"` adds read-only visibility across your shared workspace so agents can inspect nearby repos/reference files.
- Running from inside a repo under `~/mywork` gives that repo read/write plus read-only access to sibling paths under `~/mywork`.

Run the real unsandboxed binary with `command claude` (or `command codex`, etc.) when needed.

## Usage

```bash
# Generate a policy for the current repo and print the policy file path
safehouse

# Run Claude in the current repo (default workdir auto-selects git root, else CWD)
cd ~/projects/my-app
safehouse -- claude --dangerously-skip-permissions
safehouse claude --dangerously-skip-permissions
safe claude --dangerously-skip-permissions

# Run Gemini (requires NO_BROWSER=true to avoid opening auth pages)
NO_BROWSER=true safehouse -- gemini

# Grant extra writable directories
safehouse --add-dirs=/tmp/scratch:/data/shared -- claude --dangerously-skip-permissions

# Grant read-only access to reference code
safehouse --add-dirs-ro=/repos/shared-lib -- aider

# Append custom policy rules (loaded last)
safehouse --append-profile=/path/to/local-overrides.sb -- claude --dangerously-skip-permissions

# Use env vars instead of CLI flags
SAFEHOUSE_ADD_DIRS_RO=/repos/shared-lib SAFEHOUSE_ADD_DIRS=/tmp/scratch safehouse -- aider

# Override the default workdir selection
safehouse --workdir=/tmp/scratch -- claude --dangerously-skip-permissions

# Or set workdir via env
SAFEHOUSE_WORKDIR=/tmp/scratch safehouse -- claude --dangerously-skip-permissions

# Disable automatic workdir grants (use only explicit --add-dirs/--add-dirs-ro)
safehouse --workdir= --add-dirs-ro=/repos/shared-lib --add-dirs=/tmp/scratch -- aider

# Load add-dirs/add-dirs-ro from <workdir>/.safehouse
cat > .safehouse <<'EOF'
add-dirs-ro=/repos/shared-lib
add-dirs=/tmp/scratch
EOF
safehouse -- aider

# Enable Docker socket access (off by default)
safehouse --enable=docker -- docker ps

# Browser native messaging integration is always on (not toggleable)

# Enable macOS GUI integration (off by default)
safehouse --enable=macos-gui -- /Applications/TextEdit.app/Contents/MacOS/TextEdit

# Enable Electron integration (off by default; also enables macOS GUI integration)
safehouse --enable=electron -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox

# Inspect the generated policy without running anything
safehouse
safehouse --stdout
```

### Electron apps under Safehouse

Electron/Chromium helper processes try to initialize their own sandbox. Under Safehouse, the process tree is already inside macOS Seatbelt, so nested sandbox initialization is OS-blocked and cannot be solved by adding more `.sb` allow rules.

Electron integration is opt-in. Enable it with `--enable=electron` (this also enables the `macos-gui` integration), then use `--no-sandbox` as the primary launch mode:

```bash
safehouse --enable=electron -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox
```

Compatibility fallback (if needed):

```bash
ELECTRON_DISABLE_SANDBOX=1 safehouse --enable=electron -- /Applications/Claude.app/Contents/MacOS/Claude
```

Security note: disabling Chromium/Electron's internal sandbox removes its process-level isolation, but Safehouse's outer `sandbox-exec` policy still confines filesystem and IPC access for the full process tree.

Troubleshooting: if logs show `forbidden-sandbox-reinit` or `sandbox initialization failed: Operation not permitted`, this indicates nested sandbox re-init was attempted; run the Electron app with `--no-sandbox`.

## Static Baseline Policy File

If you want static policy files without using the wrapper scripts, use:
- `dist/safehouse.generated.sb` (default policy)
- `dist/safehouse-for-apps.generated.sb` (includes `macos-gui` and `electron` integrations)

Regenerate them after profile changes:

```bash
./scripts/generate-static-policy.sh
```

The static generator uses deterministic template paths under `/private/tmp/agent-safehouse-static-template` for `HOME` and invocation workdir so commits do not depend on a specific developer machine path. Before using the policy directly, update the `HOME_DIR` definition (or the `__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__` placeholder in `profiles/00-base.sb`) and the final workdir grant block for your environment.

## Single-File Distribution

To build a standalone executable that bundles all sandbox logic and policy modules into one file:

```bash
./scripts/generate-dist.sh
```

This writes `dist/safehouse.sh` by default. You can distribute that file directly and run it with exact CLI parity to `bin/safehouse.sh`:

```bash
./dist/safehouse.sh -- claude --dangerously-skip-permissions
./dist/safehouse.sh --stdout
```

The dist binary is self-contained: it embeds policy modules as plain text and does not unpack helper scripts at runtime.
`dist/safehouse.sh` is committed in the repo and auto-regenerated by CI when profiles/runtime logic change.

## How It Works

`safehouse` composes a sandbox policy from modular profiles, then runs your command under `sandbox-exec`. The policy is assembled in this order:

| Layer | What it covers |
|-------|---------------|
| `00-base.sb` | Default deny, helper functions, explicit HOME replacement token |
| `10-system-runtime.sb` | macOS system binaries, temp dirs, IPC |
| `20-network.sb` | Network policy (fully open) |
| `30-toolchains/*.sb` | Node, Python, Go, Rust, Bun, Java, PHP, Ruby |
| `40-agents/*.sb` | Per-agent config/state paths |
| `50-integrations/*.sb` | Git, SSH, Keychain, Spotlight, AWS, GCloud, GitHub/GitLab CLI, 1Password, Browser NM (always-on); Docker, macOS GUI, Electron (opt-in via `--enable`) |
| Config/env/CLI path grants | `<workdir>/.safehouse` (`add-dirs-ro`, `add-dirs`), then `SAFEHOUSE_ADD_DIRS_RO`/`SAFEHOUSE_ADD_DIRS`, then CLI flags, then selected workdir (unless disabled) |
| Appended profile(s) | Optional extra profile files appended last via `--append-profile=PATH` (repeatable) |

Later rules override earlier ones. CLI path grants are emitted late, so broad `--add-dirs` can reopen paths denied earlier. Put must-not-read paths in appended profiles (`--append-profile`) if you want them to remain blocked.

## Options

| Flag | Description |
|------|-------------|
| `--add-dirs=PATHS` | Colon-separated paths to grant read/write |
| `--add-dirs-ro=PATHS` | Colon-separated paths to grant read-only |
| `--workdir=DIR` | Main directory to grant read/write (`--workdir=` disables automatic workdir grants) |
| `--append-profile=PATH` | Append a sandbox profile file after generated rules (repeatable) |
| `--enable=FEATURES` | Enable optional features: `docker`, `macos-gui`, `electron` (`electron` also enables `macos-gui`) |
| `--output=PATH` | Write policy to a file instead of a temp path |
| `--stdout` | Print the generated policy contents to stdout (does not execute command) |

All flags accept both `--flag=value` and `--flag value` forms.

Execution behavior:
- No command args: generate a policy and print the policy file path.
- Command args provided: generate a policy, then execute the command under `sandbox-exec`.
- `--` separator is optional (recommended when the wrapped command starts with `-`).

Environment variables:
- `SAFEHOUSE_ADD_DIRS_RO` — Colon-separated paths to grant read-only
- `SAFEHOUSE_ADD_DIRS` — Colon-separated paths to grant read/write
- `SAFEHOUSE_WORKDIR` — Workdir override (`SAFEHOUSE_WORKDIR=` disables automatic workdir grants)

Optional workdir config file:
- `<workdir>/.safehouse`
- Supported keys: `add-dirs-ro=PATHS`, `add-dirs=PATHS`

Path grant merge order is:
1. `<workdir>/.safehouse`
2. `SAFEHOUSE_ADD_DIRS_RO` / `SAFEHOUSE_ADD_DIRS`
3. CLI `--add-dirs-ro` / `--add-dirs`

When `--workdir` is omitted, safehouse selects the workdir automatically:
1. git root above the invocation directory (if present)
2. otherwise the invocation directory

## Customization

- **Add credential denials:** create a custom profile file and pass it via `--append-profile` (repeatable for multiple files)
- **Adjust network policy:** edit `profiles/20-network.sb` (commented examples for outbound-only and localhost modes)
- **Add a new agent:** create a file in `profiles/40-agents/` following the existing pattern
- **Add a new toolchain:** create a file in `profiles/30-toolchains/`

## Testing

Run the full sandbox test suite:

```bash
./tests/run.sh
```

The runner accepts no arguments and executes modular test sections under `tests/sections/` using shared helpers in `tests/lib/`.

## Debugging Sandbox Denials

Use `/usr/bin/log` (not `log` — some shells shadow it with a builtin).

**Live stream all denials:**
```bash
/usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "Sandbox:" AND eventMessage CONTAINS "deny("'
```

**Filter by a specific agent version or PID:**
```bash
/usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "Sandbox: 2.1.34(" AND eventMessage CONTAINS "deny("'
```

**Kernel-level denials** (includes PID, captures more events):
```bash
/usr/bin/log stream --style compact --info --debug --predicate '(processID == 0) AND (senderImagePath CONTAINS "/Sandbox")'
```

**Recent history** (not live):
```bash
/usr/bin/log show --last 2m --style compact --predicate 'process == "sandboxd"'
```

**Filter common noise** (dtracehelper, shm, diagnosticd, analyticsd):
```bash
/usr/bin/log stream --style compact \
  --predicate 'eventMessage CONTAINS "Sandbox:" AND eventMessage CONTAINS "deny(" AND NOT eventMessage CONTAINS "duplicate report" AND NOT eventMessage CONTAINS "/dev/dtracehelper" AND NOT eventMessage CONTAINS "apple.shm.notification_center" AND NOT eventMessage CONTAINS "com.apple.diagnosticd" AND NOT eventMessage CONTAINS "com.apple.analyticsd"'
```

Or suppress dtracehelper noise at the source: `DYLD_USE_DTRACE=0 sandbox-exec ...`

**Correlate with filesystem activity for a single PID:**
```bash
sudo fs_usage -w -f filesystem <pid> | grep -iE "open|create|write|rename"
```

### Converting deny logs to allow rules

Each deny log line has the form: `deny(<pid>) <operation> <path-or-name>`

| Deny type | Allow rule pattern |
|-----------|--------------------|
| file ops | `(allow <operation> (literal "<path>"))` |
| sysctl | `(allow sysctl-read (sysctl-name "<name>"))` |
| mach | `(allow mach-lookup (global-name "<name>"))` |
| network | `(allow network-<op> (local ip "localhost:*"))` |

### Building a profile from scratch

1. Start with just `(version 1)` `(deny default)`
2. Run with the kernel-level log stream in another terminal
3. Each `deny(…)` line maps to an allow rule per the table above
4. Add the rule, re-run, repeat until startup succeeds

Sandbox profiles apply to the process and all children (fork+exec inherits). Exercise all the tools you use (git, npm, cargo, etc.) to get full coverage. Usually actionable deny ops: `file-read-data`, `file-write-create`, `process-exec`, `mach-lookup`.

## Reference & Prior Art

- **[anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)** — Official Anthropic reference implementation. TypeScript/Node, cross-platform, includes a network proxy for allowlisting API endpoints. ([macos-sandbox-utils.ts](https://github.com/anthropic-experimental/sandbox-runtime/blob/4fad8fa35db3f09958db1df401b30bd00402b611/src/sandbox/macos-sandbox-utils.ts), [sandbox-utils.ts](https://github.com/anthropic-experimental/sandbox-runtime/blob/4fad8fa35db3f09958db1df401b30bd00402b611/src/sandbox/sandbox-utils.ts))

- **[neko-kai/claude-code-sandbox](https://github.com/neko-kai/claude-code-sandbox)** — Restrictive reads via `noread.sb` + wrapper script for ancestor dir listing. Key insight: Claude Code needs `(allow file-read* (literal "/each/parent/dir"))` for every ancestor of the CWD, or it sets `PATH=""` and disables colored output. Only needs `literal` (dir listing), not `subpath` (recursive content).

- **[n8henrie/trace.sh](https://gist.github.com/n8henrie/eaaa1a25753fadbd7715e85a38b99831)** — Gist with `trace.sh` (automated deny-to-allow loop) and `shrink.sh` (remove unnecessary allow rules by testing each one). Invaluable for building and minimizing profiles from scratch.

- **[luiscardoso.dev — Sandboxes for AI](https://www.luiscardoso.dev/blog/sandboxes-for-ai)** — Overview of sandboxing approaches for AI agents.
