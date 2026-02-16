# Agent Safehouse

[![Tests (macOS)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml/badge.svg)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml)
[![E2E (TUI Agent via tmux)](https://github.com/eugene1g/agent-safehouse/actions/workflows/e2e-agent-tui-macos.yml/badge.svg)](https://github.com/eugene1g/agent-safehouse/actions/workflows/e2e-agent-tui-macos.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Sandbox your LLM coding agents on macOS so they can only touch the files they need.

Uses macOS `sandbox-exec` with composable policy profiles to confine agents like Claude Code, Codex, Gemini CLI, Goose, Cursor, Aider, Kilo Code, and others. Starts from **deny-all** and selectively opens access to toolchains, agent configs, integrations, and the directories you specify.

## Why

LLM coding agents run shell commands with broad filesystem access. A prompt injection, confused deputy, or hallucinated `rm -rf` can reach your SSH keys, AWS credentials, other repos, or anything else your user account can touch. This kit shrinks the blast radius to the project directory and the toolchains the agent actually needs  - without breaking normal development workflows.

## Guiding Philosophy

**Agent productivity > paranoid lockdown.** The sandbox makes accidental damage hard and targeted attacks more constrained, but it is not a security boundary against a determined adversary with code execution. Every rule follows one question: *does the agent need this to do its job?*

### What we allow (and why)

- **Filesystem reads for system paths**  - `/usr`, `/bin`, `/opt`, `/System`, `/Library/Frameworks`, etc. Agents spawn shells, compilers, and package managers that link against system libraries. Denying these breaks everything.
- **Full process exec/fork**  - agents orchestrate deep subprocess trees (shell > git > ssh > credential-helper). Restricting process creation is impractical.
- **Toolchain and app/agent config directories**  - each toolchain (`~/.cargo`, `~/.npm`, `~/.cache/uv`, etc.) gets scoped access, and app/agent-specific profile grants are loaded only for the wrapped command by default (for example `codex` loads `~/.codex`, `claude` loads `~/.claude`, and `Visual Studio Code.app` loads `vscode-app`). Use `--enable=all-agents` to load every `60-agents` profile, `--enable=all-apps` to load every `65-apps` profile, or both for legacy all-profile behavior.
- **Keychain and Security framework** (auto-injected for keychain-dependent profiles)  - profiles can declare `$$require=55-integrations-optional/keychain.sb$$`, and Safehouse injects shared keychain/security rules automatically for those agents/apps. This avoids duplicating keychain rules across many profile files while keeping non-keychain agents on a tighter baseline.
- **SCM credential stores** (always-on)  - `gh` and `glab` integrations are always enabled via core profile: `~/.config/gh`, `~/.cache/gh`, `~/.local/share/gh`, and `~/.config/glab-cli` paths are writable so git and issue workflows keep working. This intentionally allows agent and tool access to repo auth state.
- **Clipboard access** (opt-in)  - `pbcopy`/`pbpaste` and other pb* workflows remain denied unless you explicitly add `--enable=clipboard` to your invocation. This is deliberate because clipboard contents can include secrets.
- **Cloud credential stores** (opt-in)  - integrations for common cloud CLIs (`~/.aws`, `~/.config/gcloud`, `~/.azure`, etc.) are available via `--enable=cloud-credentials` and are disabled by default because they expose sensitive credentials. This grant is read/write so tools can refresh tokens and SSO/session caches in place.
- **Kubernetes CLI state** (opt-in)  - `--enable=kubectl` opens canonical kubectl defaults (`~/.kube/config`, `~/.kube/cache`, `~/.kube/kuberc`) and krew plugin state under `~/.krew`.
- **Shell startup files**  - `~/.zshenv`, `~/.zprofile`, `/etc/zshrc`, etc. Without these, agents get a broken PATH and misconfigured environment.
- **SSH config (not `~/.ssh` keys)**  - available when `--enable=ssh` is set: `~/.ssh/config`, `~/.ssh/known_hosts`, `/etc/ssh/ssh_config`, `/etc/ssh/ssh_config.d/`, `/etc/ssh/crypto/`. The SSH profile denies `~/.ssh` first, then re-allows only these non-sensitive files.
- **Runtime mach services**  - notification center, logd, diagnosticd, CoreServices, DiskArbitration, DNS-SD, opendirectory, FSEvents, trustd, etc. These are framework-level dependencies that many CLI tools probe during init.
- **Clipboard access (opt-in)**  - pbcopy/pbpaste are blocked by default and available with `--enable=clipboard`, which grants the macOS pasteboard service only.
- **Network (fully open)**  - agents need package registries, APIs, MCP servers, and git remotes. Restricting network is possible but breaks most workflows.
- **Temp directories**  - `/tmp`, `/var/folders`. Transient files, IPC sockets, build artifacts.

### What we specifically deny (and why)

- **`~/.ssh` private keys**  - blocked by default. With `--enable=ssh`, the SSH integration still denies `~/.ssh` broadly and only re-allows non-sensitive config paths like `config` and `known_hosts`.
- **Browser profile directories (default)**  - browser profile data (cookies/session/password/history) is denied by default to protect sensitive data. Browser native messaging access is opt-in via `--enable=browser-native-messaging`, scoped to `NativeMessagingHosts` (read/write) and `Default/Extensions` (read-only).
- **Clipboard content**  - clipboard interaction (`pbcopy`/`pbpaste`) is opt-in via `--enable=clipboard` and should be treated like any other potential secret exfiltration path.
- **`/dev` raw device access**  - this policy allows `/dev` traversal/metadata plus specific safe device nodes (`/dev/null`, `/dev/urandom`, `/dev/tty*`, `/dev/ptmx`, `/dev/autofs_nowait`). It does not grant broad read/write access to raw device files.
- **`forbidden-exec-sugid`**  - execution of setuid/setgid binaries (`sudo`, `passwd`, etc.) is denied. Agents should never escalate privileges. If a specific setuid binary is needed, allow it by name rather than blanket-allowing privilege escalation.
- **`osascript` execution** (optional)  - if you want to hard-block AppleScript entrypoints, add a deny in a custom appended profile file (`--append-profile`). This can reduce GUI/session automation surface but may break agent notification UX.
- **Raw disk/kernel devices**  - `/dev/disk*`, `/dev/bpf*`, `/dev/pf`, `/dev/audit*`, `/dev/dtrace`, `/dev/fsevents`. No coding agent needs raw disk access or packet capture.

### What we do NOT protect against

- **Network exfiltration / C2**  - network is fully open. If an agent can read a file and has network access, it can send the contents anywhere. See `profiles/20-network.sb` for restrictive alternatives.
- **Sandbox escapes**  - `sandbox-exec` is a userspace mechanism, not a hypervisor. Apple has deprecated the public API, though the kernel enforcement still works.
- **Credential theft via IPC**  - Mach services like SecurityServer and 1Password are allowed for keychain/auth workflows, which means an agent could theoretically interact with them. Clipboard IPC (`com.apple.pasteboard.1`) is not enabled by default; use `--enable=clipboard` when needed.
- **Data exfiltration via allowed paths**  - the sandbox limits *which* files are visible, not what happens with their contents once read.

## Setup

```bash
# Download safehouse (single self-contained script)
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/safehouse.sh \
  -o ~/.local/bin/safehouse
chmod +x ~/.local/bin/safehouse
```

First, create an optional local appended profile (example: allow Git to read `~/.gitignore_global`):

```bash
mkdir -p ~/.config/agent-safehouse
cat > ~/.config/agent-safehouse/local-overrides.sb <<'EOF'
;; Local user overrides
(allow file-read*
  (home-literal "/.gitignore_global")
)
EOF
```

Then add shell functions so agent wrappers preserve argument boundaries and forward `"$@"` safely:

```bash
# ~/.bashrc or ~/.zshrc
# Ensure ~/.local/bin is on your PATH
SAFEHOUSE_APPEND_PROFILE="$HOME/.config/agent-safehouse/local-overrides.sb"

safe() { safehouse --add-dirs-ro=~/mywork --append-profile="$SAFEHOUSE_APPEND_PROFILE" "$@"; }
claude()   { safe claude --dangerously-skip-permissions "$@"; }
codex()    { safe codex --dangerously-bypass-approvals-and-sandbox "$@"; }
amp()      { safe amp --dangerously-allow-all "$@"; }
opencode() { OPENCODE_PERMISSION='{"*":"allow"}' safe opencode "$@"; }
gemini()   { NO_BROWSER=true safe gemini --yolo "$@"; }
goose()    { safe goose "$@"; }
kilo()     { safe kilo "$@"; }
pi()       { safe pi "$@"; }
```

How this works:
- `safe <agent> ...` keeps Safehouse's default workdir behavior: read/write access to the selected workdir (`git` root above CWD, otherwise CWD).
- `--add-dirs-ro=~/mywork` adds read-only visibility across your shared workspace so agents can inspect nearby repos/reference files.
- `--append-profile="$SAFEHOUSE_APPEND_PROFILE"` applies your local overrides (like the `~/.gitignore_global` allow rule) after generated defaults.
- Running from inside a repo under `~/mywork` gives that repo read/write plus read-only access to sibling paths under `~/mywork`.

Run the real unsandboxed binary with `command claude` (or `command codex`, etc.) when needed.

### One-File Claude Desktop Launcher (No CLI Install)

For non-technical users, Safehouse ships two self-contained launchers:
- `Claude.app.sandboxed.command` (downloads latest apps policy at runtime)
- `Claude.app.sandboxed-offline.command` (embedded policy, no runtime policy download)

```bash
# Online launcher (tracks latest policy)
curl -fsSL https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/Claude.app.sandboxed.command \
  -o ~/Downloads/Claude.app.sandboxed.command
chmod +x ~/Downloads/Claude.app.sandboxed.command

# Offline policy launcher (embedded policy; no runtime download)
curl -fsSL https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/Claude.app.sandboxed-offline.command \
  -o ~/Downloads/Claude.app.sandboxed-offline.command
chmod +x ~/Downloads/Claude.app.sandboxed-offline.command
```

Drop either launcher into any folder and run it (double-click in Finder or run from Terminal). It launches Claude Desktop sandboxed to that folder.
Both launchers invoke `sandbox-exec` directly (no Safehouse CLI install required). The online launcher fetches and validates the latest apps policy from GitHub; if you need to pin or override the policy source, set `SAFEHOUSE_CLAUDE_POLICY_URL` before launching. You can additionally pin a SHA-256 checksum with `SAFEHOUSE_CLAUDE_POLICY_SHA256` for integrity verification.

Equivalent launch behavior:

```bash
safehouse --workdir="<folder-containing-Claude.app.sandboxed.command>" --enable=electron -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox
```

### Why This Works With "Allow bypass permissions mode"

When Claude Desktop is set to "Allow bypass permissions mode", the app can run tools without normal in-app approval prompts. Launching Claude through `Claude.app.sandboxed.command` keeps those tool runs inside Safehouse's outer macOS sandbox, so you still get filesystem and IPC boundaries from the generated policy.

This gives a practical "outside-in" setup:
- fast in-app execution flow
- confinement from an external sandbox policy

Reference discussion: [Lydia Hallie on X](https://x.com/lydiahallie/status/2021012075712266471)

## Usage

```bash
# Generate a policy for the current repo and print the policy file path
safehouse

# Run Claude in the current repo (default workdir auto-selects git root, else CWD)
cd ~/projects/my-app
safehouse claude --dangerously-skip-permissions
safe claude --dangerously-skip-permissions

# Run Gemini (requires NO_BROWSER=true to avoid opening auth pages)
NO_BROWSER=true safehouse gemini

# Grant extra writable directories
safehouse --add-dirs=/tmp/scratch:/data/shared -- claude --dangerously-skip-permissions

# Grant read-only access to reference code
safehouse --add-dirs-ro=/repos/shared-lib -- aider

# Append custom policy rules (loaded last)
safehouse --append-profile=/path/to/local-overrides.sb -- claude --dangerously-skip-permissions

# Use env vars instead of CLI flags
SAFEHOUSE_ADD_DIRS_RO=/repos/shared-lib SAFEHOUSE_ADD_DIRS=/tmp/scratch safehouse aider

# Override the default workdir selection
safehouse --workdir=/tmp/scratch -- claude --dangerously-skip-permissions

# Or set workdir via env
SAFEHOUSE_WORKDIR=/tmp/scratch safehouse claude --dangerously-skip-permissions

# Disable automatic workdir grants (use only explicit --add-dirs/--add-dirs-ro)
safehouse --workdir= --add-dirs-ro=/repos/shared-lib --add-dirs=/tmp/scratch -- aider

# Load add-dirs/add-dirs-ro from trusted <workdir>/.safehouse
cat > .safehouse <<'EOF'
add-dirs-ro=/repos/shared-lib
add-dirs=/tmp/scratch
EOF
safehouse --trust-workdir-config aider

# Enable Docker socket access (off by default)
safehouse --enable=docker -- docker ps

# Enable kubectl config/cache + krew plugin paths (off by default)
safehouse --enable=kubectl -- kubectl get pods -A

# Restore legacy behavior and include all scoped app/agent profiles
safehouse --enable=all-agents,all-apps codex

# Big-hammer mode: read-only visibility across / (use cautiously)
safehouse --enable=wide-read -- claude --dangerously-skip-permissions

# Enable browser native messaging integration (off by default)
safehouse --enable=browser-native-messaging -- codex

# Enable macOS GUI integration (off by default)
safehouse --enable=macos-gui -- /Applications/TextEdit.app/Contents/MacOS/TextEdit

# Enable Electron integration (off by default; also enables macOS GUI integration)
safehouse --enable=electron -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox

# Run Visual Studio Code sandboxed (loads the 65-apps/vscode-app profile)
safehouse --enable=electron -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox

# If VS Code may launch multiple agent CLIs from extensions, include all agent profiles
safehouse --enable=electron,all-agents -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox

# VS Code as a contained "agent host": broad read visibility + scoped writes
safehouse --workdir=~/server --enable=electron,all-agents,wide-read -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox

# Inspect the generated policy without running anything
safehouse
safehouse --stdout

# Explain effective workdir/config/grants/profile selection
safehouse --explain --stdout
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

To run VS Code as a contained host for multiple AI extensions/agents, prefer:

```bash
safehouse --workdir=~/server --enable=electron,all-agents,wide-read -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox
```

This gives VS Code broad read visibility (to reduce extension breakage) while keeping writes scoped to the selected workdir plus explicit write grants.

Troubleshooting: if logs show `forbidden-sandbox-reinit` or `sandbox initialization failed: Operation not permitted`, this indicates nested sandbox re-init was attempted; run the Electron app with `--no-sandbox`.

## Static Baseline Policy File

If you want static policy files without using the wrapper scripts, use:
- `dist/profiles/safehouse.generated.sb` (default policy)
- `dist/profiles/safehouse-for-apps.generated.sb` (includes `macos-gui` and `electron` integrations)

Committed static policies are generated as:
- `safehouse.generated.sb`: `--enable=all-agents` (all `60-agents` profiles)
- `safehouse-for-apps.generated.sb`: `--enable=macos-gui,electron,all-agents,all-apps` (all `60-agents` + `65-apps` profiles)

Regenerate them after profile or runtime changes:

```bash
./scripts/generate-dist.sh
```

The static generator emits fixed placeholder paths for `HOME` and invocation workdir (`/__SAFEHOUSE_TEMPLATE_HOME__`, `/__SAFEHOUSE_TEMPLATE_WORKDIR__`) so committed artifacts do not depend on a specific developer machine path. Before using the policy directly, replace the `HOME_DIR` definition and the final workdir grant block with paths for your environment.

## Single-File Distribution

To build the standalone executable and regenerate all committed `dist/` artifacts:

```bash
./scripts/generate-dist.sh
```

This writes these files by default:
- `dist/safehouse.sh`
- `dist/Claude.app.sandboxed.command`
- `dist/Claude.app.sandboxed-offline.command`
- `dist/profiles/safehouse.generated.sb`
- `dist/profiles/safehouse-for-apps.generated.sb`

You can distribute `dist/safehouse.sh` directly and run it with exact CLI parity to `bin/safehouse.sh`:

```bash
./dist/safehouse.sh claude --dangerously-skip-permissions
./dist/safehouse.sh --stdout
```

The dist binary is self-contained: it embeds policy modules as plain text and does not unpack helper scripts at runtime.
`dist/safehouse.sh`, `dist/Claude.app.sandboxed.command`, and `dist/Claude.app.sandboxed-offline.command` are committed in the repo and auto-regenerated by CI when profiles/runtime logic change.

## How It Works

`safehouse` composes a sandbox policy from modular profiles, then runs your command under `sandbox-exec`. The policy is assembled in this order:

| Layer | What it covers |
|-------|---------------|
| `00-base.sb` | Default deny, helper functions, explicit HOME replacement token |
| `10-system-runtime.sb` | macOS system binaries, temp dirs, IPC |
| `20-network.sb` | Network policy (fully open) |
| `30-toolchains/*.sb` | Node, Python, Go, Rust, Bun, Java, PHP, Perl, Ruby |
| `40-shared/*.sb` | Shared cross-agent policy modules |
| `50-integrations-core/*.sb` | Always-on core integrations: `container-runtime-default-deny`, `git`, and `scm-clis` |
| `55-integrations-optional/*.sb` | Opt-in integrations enabled via `--enable`: `clipboard`, `docker`, `kubectl`, `macos-gui`, `electron`, `ssh`, `spotlight`, `cleanshot`, `1password`, `cloud-credentials`, `browser-native-messaging` (`electron` also enables `macos-gui`; keychain is auto-injected for profiles that declare `$$require=55-integrations-optional/keychain.sb$$`) |
| `60-agents/*.sb` | Product-specific per-agent config/state paths selected by wrapped command basename |
| `65-apps/*.sb` | Desktop app bundle profiles selected by known app bundles (`Claude.app`, `Visual Studio Code.app`) (`--enable=all-apps` loads all `65-apps` profiles) |
| Config/env/CLI path grants | Trusted `<workdir>/.safehouse` (`add-dirs-ro`, `add-dirs`; loaded only with `--trust-workdir-config` or `SAFEHOUSE_TRUST_WORKDIR_CONFIG`), then `SAFEHOUSE_ADD_DIRS_RO`/`SAFEHOUSE_ADD_DIRS`, then CLI flags, then selected workdir (unless disabled) |
| Appended profile(s) | Optional extra profile files appended last via `--append-profile=PATH` (repeatable) |

SBPL rule interactions are matcher-dependent. Safehouse tests currently verify that broad late grants (for example `--add-dirs` and `--enable=wide-read`) can reopen earlier read-denies, while some deny+allow literal/subpath combinations still remain denied. Put must-not-read paths in appended profiles (`--append-profile`) if you want them to remain blocked. Cloud credential stores are opt-in via `--enable=cloud-credentials`.

## Options

| Flag | Description |
|------|-------------|
| `--add-dirs=PATHS` | Colon-separated paths to grant read/write |
| `--add-dirs-ro=PATHS` | Colon-separated paths to grant read-only |
| `--workdir=DIR` | Main directory to grant read/write (`--workdir=` disables automatic workdir grants) |
| `--trust-workdir-config` | Trust and load `<workdir>/.safehouse` (`--trust-workdir-config=BOOL` also supported) |
| `--append-profile=PATH` | Append a sandbox profile file after generated rules (repeatable) |
| `--enable=FEATURES` | Enable optional features: `clipboard`, `docker`, `kubectl`, `macos-gui`, `electron`, `ssh`, `spotlight`, `cleanshot`, `1password`, `cloud-credentials`, `browser-native-messaging`, `all-agents`, `all-apps`, `wide-read` (`electron` also enables `macos-gui`; `all-agents` loads all `60-agents` profiles; `all-apps` loads all `65-apps` profiles; combine both for legacy all-profile behavior; `wide-read` adds broad read-only `/` visibility; keychain access is auto-injected from selected profile `$$require` metadata) |
| `--output=PATH` | Write policy to a file instead of a temp path |
| `--stdout` | Print the generated policy contents to stdout (does not execute command) |
| `--explain` | Print effective workdir, grant, and profile-selection summary to stderr |

All flags accept both `--flag=value` and `--flag value` forms. For path-based flags/config values, `~` and `~/...` are supported.

Execution behavior:
- No command args: generate a policy and print the policy file path.
- Command args provided: generate a policy, then execute the command under `sandbox-exec`.
- `--` separator is optional (needed when safehouse flags precede the command, e.g. `safehouse --enable=docker -- docker ps`).

Environment variables:
- `SAFEHOUSE_ADD_DIRS_RO`  - Colon-separated paths to grant read-only
- `SAFEHOUSE_ADD_DIRS`  - Colon-separated paths to grant read/write
- `SAFEHOUSE_WORKDIR`  - Workdir override (`SAFEHOUSE_WORKDIR=` disables automatic workdir grants)
- `SAFEHOUSE_TRUST_WORKDIR_CONFIG`  - Trust and load `<workdir>/.safehouse` (`1/0`, `true/false`, `yes/no`, `on/off`)
- `SAFEHOUSE_CLAUDE_POLICY_SHA256`  - (Claude launcher only) Expected SHA-256 for the downloaded online apps policy. If set, launch fails if the checksum does not match.

Optional workdir config file:
- `<workdir>/.safehouse`
- Supported keys: `add-dirs-ro=PATHS`, `add-dirs=PATHS`
- Ignored by default; load it only with `--trust-workdir-config` or `SAFEHOUSE_TRUST_WORKDIR_CONFIG=1`.
- Treat `<workdir>/.safehouse` as trusted input when enabling it.

Path grant merge order is:
1. Trusted `<workdir>/.safehouse` (only when trust is enabled)
2. `SAFEHOUSE_ADD_DIRS_RO` / `SAFEHOUSE_ADD_DIRS`
3. CLI `--add-dirs-ro` / `--add-dirs`

When `--workdir` is omitted, safehouse selects the workdir automatically:
1. git root above the invocation directory (if present)
2. otherwise the invocation directory

## Customization

- **Add credential denials:** create a custom profile file and pass it via `--append-profile` (repeatable for multiple files)
- **Adjust network policy:** edit `profiles/20-network.sb` (commented examples for outbound-only and localhost modes)
- **Adjust shared cross-agent rules:** edit `profiles/40-shared/`
- **Add a new desktop app profile:** create a file in `profiles/65-apps/` following the existing pattern
- **Add a new agent profile:** create a file in `profiles/60-agents/` following the existing pattern
- **Add a new toolchain:** create a file in `profiles/30-toolchains/`

## Testing

Run the full sandbox test suite:

```bash
./tests/run.sh
```

The runner accepts no arguments and executes modular test sections under `tests/sections/` using shared helpers in `tests/lib/`.

Run the tmux-driven TUI E2E simulation:

```bash
./tests/e2e/run.sh
```

This test iterates across every configured profile in `profiles/60-agents/`, launches a command-matched fake TUI agent under safehouse in a detached `tmux` session, selects menu items via keystrokes, captures pane output, and asserts:
- the expected agent profile was selected in the generated policy for that command basename
- in-workdir write succeeds
- out-of-workdir write is denied
- out-of-workdir read is denied
- the session exits cleanly after interaction

This suite supports parallel execution (one tmux session per profile):

```bash
SAFEHOUSE_E2E_TUI_JOBS=4 ./tests/e2e/run.sh
```

Run live LLM checks (installed/authenticated agents with adapters) with verbose transcripts:

```bash
./tests/e2e/live/run.sh
```

To install agent CLIs repo-locally (so tests don't depend on global installs), run:

```bash
./tests/e2e/agents/install.sh
```

This installs:
- Node-based agent CLIs via pnpm (`tests/e2e/agents/pnpm/`)
- `aider` via a local Python venv (`tests/e2e/agents/python/`)
- `goose` via GitHub release download (`tests/e2e/agents/bin/goose`)
- `cursor-agent` via the official cursor.com installer (with `HOME` overridden into `tests/e2e/agents/cursor-agent/home/`)

By default this suite is strict for installed agents:
- each installed configured profile must run its adapter and complete both checks (positive response token + forbidden-file denial token)
- adapter-reported auth/setup prerequisites fail the run by default

To allow prerequisite skips (for example, on a machine where some agents are not authenticated yet):

```bash
SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP=1 ./tests/e2e/live/run.sh
```

Parallel live execution is also supported (be mindful of rate limits):

```bash
SAFEHOUSE_E2E_LIVE_JOBS=3 SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP=1 ./tests/e2e/live/run.sh
```

Timeout tuning:

```bash
# tmux simulation waits
SAFEHOUSE_E2E_TUI_TIMEOUT_SECS=30 SAFEHOUSE_E2E_TUI_SESSION_TIMEOUT_SECS=30 ./tests/e2e/run.sh

# live agent command timeout (per prompt)
SAFEHOUSE_E2E_LIVE_COMMAND_TIMEOUT_SECS=240 ./tests/e2e/live/run.sh
```

Or run both simulations and live checks in one command:

```bash
SAFEHOUSE_E2E_LIVE=1 ./tests/e2e/run.sh
```

## Debugging Sandbox Denials

Use `/usr/bin/log` (not `log`  - some shells shadow it with a builtin).

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

- **[anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)**  - Official Anthropic reference implementation. TypeScript/Node, cross-platform, includes a network proxy for allowlisting API endpoints. ([macos-sandbox-utils.ts](https://github.com/anthropic-experimental/sandbox-runtime/blob/4fad8fa35db3f09958db1df401b30bd00402b611/src/sandbox/macos-sandbox-utils.ts), [sandbox-utils.ts](https://github.com/anthropic-experimental/sandbox-runtime/blob/4fad8fa35db3f09958db1df401b30bd00402b611/src/sandbox/sandbox-utils.ts))

- **[neko-kai/claude-code-sandbox](https://github.com/neko-kai/claude-code-sandbox)**  - Restrictive reads via `noread.sb` + wrapper script for ancestor dir listing. Key insight: Claude Code needs `(allow file-read* (literal "/each/parent/dir"))` for every ancestor of the CWD, or it sets `PATH=""` and disables colored output. Only needs `literal` (dir listing), not `subpath` (recursive content).

- **[n8henrie/trace.sh](https://gist.github.com/n8henrie/eaaa1a25753fadbd7715e85a38b99831)**  - Gist with `trace.sh` (automated deny-to-allow loop) and `shrink.sh` (remove unnecessary allow rules by testing each one). Invaluable for building and minimizing profiles from scratch.

- **[luiscardoso.dev  - Sandboxes for AI](https://www.luiscardoso.dev/blog/sandboxes-for-ai)**  - Overview of sandboxing approaches for AI agents.
