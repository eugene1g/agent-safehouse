# Agent Safehouse Technical Reference

This file provides technical documentation for developers working with the Agent Safehouse codebase.

## Project Overview

Agent Safehouse is a macOS sandbox toolkit that confines LLM coding agents (Claude, Cursor, Aider, Gemini, etc.) using `sandbox-exec` with composable policy profiles. It starts from **deny-all** and selectively opens access. This is a pure Bash project with no build system or package manager — all code is shell scripts and `.sb` (Sandbox Profile Language) policy files.

## Commands

**Run tests:**
```bash
./tests/run.sh
```
Tests require macOS with `sandbox-exec` available and **cannot run inside an existing sandbox** (e.g. from a sandboxed agent session). The runner detects this at startup and exits early. No arguments accepted.

**Regenerate all committed dist artifacts (after profile/runtime changes):**
```bash
./scripts/generate-dist.sh
```
This produces three deterministic dist files:
- `dist/safehouse.sh` (single-file executable)
- `dist/safehouse.generated.sb` (default policy)
- `dist/safehouse-for-apps.generated.sb` (includes `macos-gui` and `electron` integrations)
CI auto-regenerates and commits these files when profiles or runtime scripts change.

**Important:** After modifying any `.sb` profile or Safehouse policy assembly logic (`bin/safehouse.sh` or `bin/lib/*.sh`), always run:
- `./scripts/generate-dist.sh`

**Generate a policy for the current directory:**
```bash
./bin/safehouse.sh [--add-dirs-ro=...] [--add-dirs=...] [--enable=docker] [--append-profile=PATH] [--output=PATH]
```
Outputs the path to the generated temp policy file when no command is provided.

**Run a command inside the sandbox:**
```bash
./bin/safehouse.sh [policy options] -- <command> [args...]
./bin/safehouse.sh --stdout
```

## Architecture

### Policy Assembly Pipeline

`bin/safehouse.sh` is the primary entry point. Policy generation and CLI behavior are split into `bin/lib/*.sh`, and policy assembly concatenates profile modules in a fixed order into a single `.sb` policy file:

1. `profiles/00-base.sb` — `(version 1)`, `(deny default)`, explicit HOME_DIR replacement token resolution, helper macros (`home-subpath`, `home-literal`, `home-prefix`, `data-home-subpath`, `data-home-literal`)
2. `profiles/10-system-runtime.sb` — system binaries, temp dirs, IPC/mach services
3. `profiles/20-network.sb` — network policy (fully open by default)
4. `profiles/30-toolchains/*.sb` — all toolchain profiles (Node, Python, Go, Rust, etc.)
5. `profiles/40-agents/*.sb` — all agent profiles (Claude, Cursor, Aider, etc.) including `__common.sb` for shared agent paths
6. `profiles/50-integrations/*.sb` — always-on integrations (git, SSH, keychain, 1password, browser-nm, etc.) + opt-in `docker`, `macos-gui`, and `electron` integrations controlled by `--enable` (`electron` also enables `macos-gui`)
7. Dynamic CLI path grants (`--add-dirs-ro`, then `--add-dirs`)
8. Selected workdir grant (read/write; omitted when `--workdir` is explicitly empty)
9. Optional appended profile(s) from CLI `--append-profile` (loaded last so they win)

**Order matters**: later rules override earlier ones. Selected workdir grants come after extra path grants. Appended profiles are loaded last so their deny rules take precedence.

### HOME_DIR Resolution

`00-base.sb` defines `HOME_DIR` with an explicit placeholder string (`__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__`). Safehouse policy assembly logic (`bin/lib/policy.sh`) replaces that token with the resolved `$HOME` value using awk at assembly time. All profile modules use helper macros like `(home-subpath "/.claude")` which expand using this resolved value.

### Ancestor Directory Literals

A key pattern: agents (especially Claude Code) need `file-read*` with `literal` (not `subpath`) on every ancestor directory of CWD up to `/`. This allows `readdir()` for directory listing without granting recursive content access. `emit_path_ancestor_literals()` in `bin/lib/policy.sh` generates these.

### Test Framework

Tests live in `tests/` with this structure:
- `tests/run.sh` — entry point, sources everything then runs sections
- `tests/lib/common.sh` — assertion functions (`assert_allowed`, `assert_denied`, `assert_allowed_strict`, `assert_denied_strict`, `assert_allowed_if_exists`, `assert_policy_contains`, `assert_policy_order_literal`, etc.), section registration, pass/fail/skip counters
- `tests/lib/setup.sh` — creates temp dirs, generates multiple policy variants (`POLICY_DEFAULT`, `POLICY_EXTRA`, `POLICY_DOCKER`, `POLICY_BROWSER_NM`, `POLICY_MERGE`), cleanup on EXIT trap
- `tests/sections/*.sh` — numbered test sections, each defines a `run_section_*` function and calls `register_section`

To add a test: create a function in the appropriate section file, use `section_begin "Name"` and assertion helpers, then call `register_section run_section_yourname`.

### Profile Conventions

Each `.sb` file follows a standard header format:
```
;; ---------------------------------------------------------------------------
;; Category: Name
;; Description
;; Source: path/to/file.sb
;; ---------------------------------------------------------------------------
```

Some profiles use `#safehouse-test-id:tag#` markers in comments — tests grep for these to verify policy structure and ordering.

### CI

- **tests-macos.yml** — runs `./tests/run.sh` on `macos-latest` on push/PR when bin/, profiles/, scripts/, tests/, `dist/safehouse.generated.sb`, `dist/safehouse-for-apps.generated.sb`, or `dist/safehouse.sh` change
- **regenerate-dist.yml** — auto-regenerates and commits `dist/safehouse.sh`, `dist/safehouse.generated.sb`, and `dist/safehouse-for-apps.generated.sb` when profiles/runtime/scripts change

## Key Design Decisions

- Use `--append-profile` to apply local/team-specific allow/deny overlays as the final policy layer
- Docker, macOS GUI, and Electron are opt-in via `--enable`; all other integrations (keychain, git, SSH, 1password, spotlight, cloud-credentials, scm-clis, and browser native messaging) are always-on
- The `data-home-*` macros exist because macOS maps `$HOME` to `/System/Volumes/Data$HOME` in some contexts — profiles must allow both paths
- Sandbox Profile Language (`.sb` files) uses S-expression syntax with `allow`/`deny` rules and path matchers: `literal` (exact path), `subpath` (recursive), `prefix` (starts-with), `regex`
