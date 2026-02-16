# Usage

## Common Patterns

```bash
# Run Claude in current repo (git root auto-selected as workdir)
safehouse claude --dangerously-skip-permissions

# Grant extra writable directories
safehouse --add-dirs=/tmp/scratch:/data/shared -- claude --dangerously-skip-permissions

# Grant read-only reference directories
safehouse --add-dirs-ro=/repos/shared-lib -- aider

# Append custom policy rules (loaded last)
safehouse --append-profile=/path/to/local-overrides.sb -- claude --dangerously-skip-permissions

# Trust and load <workdir>/.safehouse
safehouse --trust-workdir-config aider

# Override workdir
safehouse --workdir=/tmp/scratch -- claude --dangerously-skip-permissions

# Disable automatic workdir grants; use only explicit grants
safehouse --workdir= --add-dirs-ro=/repos/shared-lib --add-dirs=/tmp/scratch -- aider
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

# Browser native messaging integration
safehouse --enable=browser-native-messaging -- codex

# Broad read-only visibility across /
safehouse --enable=wide-read -- claude --dangerously-skip-permissions
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
```

## Electron Apps

Use `--enable=electron` and launch with `--no-sandbox`:

```bash
safehouse --enable=electron -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox
safehouse --enable=electron -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox
```

For VS Code as a multi-agent host:

```bash
safehouse --workdir=~/server --enable=electron,all-agents,wide-read -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox
```

Troubleshooting: `forbidden-sandbox-reinit` or `sandbox initialization failed: Operation not permitted` usually means nested sandbox re-init was attempted; launch with `--no-sandbox`.

## Inspect Policy Output

```bash
# Print policy content
safehouse --stdout

# Explain effective workdir/grants/profile selection
safehouse --explain --stdout
```
