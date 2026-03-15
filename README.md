# Agent Safehouse

[![Tests (macOS)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml/badge.svg)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml)
[![E2E TUI Tests (macOS)](https://github.com/eugene1g/agent-safehouse/actions/workflows/e2e-agent-tui-macos.yml/badge.svg)](https://github.com/eugene1g/agent-safehouse/actions/workflows/e2e-agent-tui-macos.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Sandbox your LLM coding agents on macOS so they can only access the files and integrations they actually need.

Agent Safehouse uses `sandbox-exec` with composable policy profiles and a deny-first model. It includes profiles for major coding agents and app-hosted agent workflows while keeping normal development usage practical.

## Install

Homebrew:

```bash
brew install eugene1g/safehouse/agent-safehouse
```

Standalone script:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://github.com/eugene1g/agent-safehouse/releases/latest/download/safehouse.sh \
  -o ~/.local/bin/safehouse
chmod +x ~/.local/bin/safehouse
```

## Philosophy

Agent Safehouse is designed around practical least privilege:

- Start from deny-all.
- Allow only what the agent needs to do useful work.
- Keep developer workflows productive.
- Make risk reduction easy by default.

It is a hardening layer, not a perfect security boundary against a determined attacker.

## Documentation

- Website: [agent-safehouse.dev](https://agent-safehouse.dev)
- Docs: [agent-safehouse.dev/docs](https://agent-safehouse.dev/docs/)
- Policy Builder: [agent-safehouse.dev/policy-builder](https://agent-safehouse.dev/policy-builder)

## Machine-Specific Defaults

If you keep shared repos, caches, or team folders in machine-specific locations, keep those settings out of project config and put them in a shell wrapper plus a local appended profile.

This lets you define your own sane defaults once and reuse them from `claude`, `codex`, `amp`, or app launchers:

POSIX shells (`zsh` / `bash`):

```bash
# ~/.zshrc or ~/.bashrc
export SAFEHOUSE_APPEND_PROFILE="$HOME/.config/agent-safehouse/local-overrides.sb"

safe() {
  safehouse \
    --add-dirs-ro="$HOME/server" \
    --append-profile="$SAFEHOUSE_APPEND_PROFILE" \
    "$@"
}

safe-claude() { safe claude --dangerously-skip-permissions "$@" }
```

`fish`:

```fish
# ~/.config/fish/config.fish
set -gx SAFEHOUSE_APPEND_PROFILE "$HOME/.config/agent-safehouse/local-overrides.sb"

function safe
    safehouse \
      --add-dirs-ro="$HOME/server" \
      --append-profile="$SAFEHOUSE_APPEND_PROFILE" \
      $argv
end

function safe-claude
    safe claude --dangerously-skip-permissions $argv
end
```

Example machine-local policy file:

```scheme
;; ~/.config/agent-safehouse/local-overrides.sb
;; Host-specific exceptions that should not live in shared repo config.
(allow file-read*
  (home-literal "/.gitignore_global")
  (home-subpath "/Library/Application Support/CleanShot/media")
  (subpath "/Volumes/Shared/Engineering")
)
```

Use `--add-dirs-ro` or `--add-dirs` for normal shared-folder access, and keep `--append-profile` for machine-local policy exceptions or final deny/allow overrides. That pattern is useful when the repo is shared but each developer machine has different local mount points.

All detailed documentation (setup, usage, options, architecture, testing, debugging, and investigations) lives in the VitePress docs site.
