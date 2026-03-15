# Usage

## Common Patterns

```bash
# Run Claude in current repo (git root auto-selected as workdir)
safehouse claude --dangerously-skip-permissions

# Grant extra writable directories
safehouse --add-dirs=/tmp/scratch:/data/shared -- claude --dangerously-skip-permissions

# Grant read-only reference directories
safehouse --add-dirs-ro=/repos/shared-lib -- aider

# Grant a single read-only file (for example a global gitignore)
safehouse --add-dirs-ro=~/.gitignore -- claude --dangerously-skip-permissions

# Append custom policy rules (loaded last)
safehouse --append-profile=/path/to/local-overrides.sb -- claude --dangerously-skip-permissions

# Trust and load <workdir>/.safehouse
safehouse --trust-workdir-config aider

# Override workdir
safehouse --workdir=/tmp/scratch -- claude --dangerously-skip-permissions

# Disable automatic workdir grants; use only explicit grants
safehouse --workdir= --add-dirs-ro=/repos/shared-lib --add-dirs=/tmp/scratch -- aider

# Pre-grant a stable worktree root for future cross-worktree read context without restarting
safehouse --add-dirs-ro=~/worktrees -- claude --dangerously-skip-permissions
```

## Config via Environment Variables

```bash
# Equivalent to --add-dirs-ro and --add-dirs flags
SAFEHOUSE_ADD_DIRS_RO=/repos/shared-lib SAFEHOUSE_ADD_DIRS=/tmp/scratch safehouse aider

# Workdir override via env
SAFEHOUSE_WORKDIR=/tmp/scratch safehouse claude --dangerously-skip-permissions
```

## Trusted Workdir Config Example

```bash
cat > .safehouse <<'EOF'
add-dirs-ro=/repos/shared-lib
add-dirs=/tmp/scratch
EOF
safehouse --trust-workdir-config aider
```

## Optional Integrations

```bash
# Docker socket access
safehouse --enable=docker -- docker ps

# kubectl config/cache + krew paths
safehouse --enable=kubectl -- kubectl get pods -A

# Shell startup file reads
safehouse --enable=shell-init -- claude --dangerously-skip-permissions

# Browser native messaging manifests + extension detection (not browsing data)
safehouse --enable=browser-native-messaging -- codex

# Host process enumeration/signalling for local debugging
safehouse --enable=process-control -- claude --dangerously-skip-permissions

# LLDB/debugger allowances for agent-driven native debugging
safehouse --enable=lldb -- claude --dangerously-skip-permissions

# Full Xcode developer roots plus DerivedData / CoreSimulator state
safehouse --enable=xcode -- xcodebuild -scheme MyApp build

# Broad read-only visibility across /
safehouse --enable=wide-read -- claude --dangerously-skip-permissions

```

Common Apple shimmed tools such as `/usr/bin/git`, `/usr/bin/make`, and `/usr/bin/clang` are covered by the default `apple-toolchain-core` toolchain profile.

`--enable=lldb` opens the sandbox side for LLDB/debugger workflows, but macOS can still deny attach to protected or non-debuggable targets.

`--enable=xcode` is for Xcode builds, simulator/device tooling, and per-user Xcode state. It does not grant debugger task-port access; keep `--enable=lldb` separate for real debugger sessions.

## Git Worktrees

When the selected workdir resolves to a Git worktree root, Safehouse automatically grants read/write access to the shared Git common dir when that metadata lives outside the selected workdir.

Safehouse also snapshots the current worktree set and grants read-only access to the other existing worktree paths for that repo.

This is decided when Safehouse starts the wrapped process. If you create new worktrees later, the already-running sandbox does not gain access to those new paths automatically.

If your worktrees are always created under a stable folder such as `~/worktrees/project-name`, grant that parent up front. Use `--add-dirs-ro` for the same cross-worktree read behavior without restarting, or `--add-dirs` if you intentionally want write access too:

```bash
safehouse --add-dirs-ro=~/worktrees/project-name -- codex --dangerously-bypass-approvals-and-sandbox
```

## Environment Modes

```bash
# Full inherited environment pass-through
safehouse --env -- codex --dangerously-bypass-approvals-and-sandbox

# Named env pass-through
safehouse --env-pass=OPENAI_API_KEY,ANTHROPIC_API_KEY -- codex --dangerously-bypass-approvals-and-sandbox

# Source env values from file on top of sanitized defaults
safehouse --env=./agent.env -- codex --dangerously-bypass-approvals-and-sandbox

# Combine file + named pass-through (named vars win)
safehouse --env=./agent.env --env-pass=OPENAI_API_KEY -- codex --dangerously-bypass-approvals-and-sandbox

# Inject a one-off child env value without inheriting the full host env
safehouse -- MYVAR=123 printenv MYVAR
```

## Electron Apps

Known app bundles are auto-detected from the command path. In practice, Claude
Desktop and Visual Studio Code usually do not need `--enable=electron`.
Claude Desktop also picks up its shared `claude-code` profile transitively.
Launch with `--no-sandbox`:

```bash
safehouse -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox
safehouse -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox
```

For VS Code as a multi-agent host:

```bash
safehouse --workdir=~/server --enable=all-agents,wide-read -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox
```

Troubleshooting: `forbidden-sandbox-reinit` or `sandbox initialization failed: Operation not permitted` usually means nested sandbox re-init was attempted; launch with `--no-sandbox`.

Use `--enable=electron` explicitly only for unknown/custom Electron apps or when
you need Electron allowances without launching a concrete app binary.

## Chromium / Playwright

Use `--enable=chromium-full` when a launcher needs the system Google Chrome
bundle or Chrome for Testing bundle under Safehouse.

Use `--enable=playwright-chrome` when Playwright is launching Chrome-family
channels and Safehouse should inject `PLAYWRIGHT_MCP_SANDBOX=false` alongside
the full Chrome policy allowances.

If browser logs still show `sandbox initialization failed: Operation not
permitted`, Chrome is trying to re-initialize its own inner Seatbelt sandbox.
That is not fixable with extra Safehouse allow rules; pass `--no-sandbox` to
the browser launch layer (or configure your Playwright launcher to add
`--no-sandbox` for Chrome channels).

## Inspect Policy Output

```bash
# Print policy content
safehouse --stdout

# Explain effective workdir/grants/profile selection
safehouse --explain --stdout
```
