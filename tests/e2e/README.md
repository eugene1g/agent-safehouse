# E2E Tests (tmux + Live Agents)

This directory contains two end-to-end test layers for Agent Safehouse:

1. **TUI simulation (tmux)**: A deterministic fake TUI agent is run under Safehouse and driven via `tmux` keystrokes. This validates sandbox policy basics across *every* configured agent profile without calling any real LLMs.
2. **Live LLM checks (real agent CLIs)**: Real agent CLIs are executed under Safehouse in non-interactive mode to ensure they can actually talk to a provider (OpenAI/Anthropic/etc) and that Safehouse blocks forbidden disk reads.

Both runners enumerate agent profiles from `profiles/60-agents/*.sb`.

## TUI Simulation (Always-On)

Run for all agent profiles:

```bash
./tests/e2e/run.sh
```

Run a single profile:

```bash
./tests/e2e/run.sh --profile kilo-code
```

Run in parallel:

```bash
SAFEHOUSE_E2E_TUI_JOBS=4 ./tests/e2e/run.sh
```

## Live LLM E2E (Real Agents)

The live runner is:

```bash
./tests/e2e/live/run.sh
```

You can also run it after the TUI suite:

```bash
SAFEHOUSE_E2E_LIVE=1 ./tests/e2e/run.sh
```

### What It Verifies

For each agent profile with an installed binary and an adapter:

1. **Positive prompt**: Ask the agent to reply with a unique token (example: `SAFEHOUSERESP...`) and verify the token appears in output.
2. **Negative prompt**: Create a forbidden file outside the sandbox (under `~/.safehouse-live-forbidden.<agent>.<rand>/secret.txt`) containing a unique secret token, ask the agent to read it, and assert:
   - the secret token does **not** appear in output
   - a denial token (example: `SAFEHOUSEDENIED...`) or other denial evidence appears

Each prompt execution is wrapped in a hard timeout (`SAFEHOUSE_E2E_LIVE_COMMAND_TIMEOUT_SECS`, default `180`) and the whole process tree is killed if the timeout hits.

### Requirements

- macOS (uses `sandbox-exec`)
- Installed agent CLIs (prefer repo-local installs, see below)
- Provider credentials in env (at least one):
  - `OPENAI_API_KEY`
  - `ANTHROPIC_API_KEY`

### Installing Agent CLIs (Repo-Local)

Install repo-local agent binaries (Node via pnpm, plus other installers):

```bash
./tests/e2e/agents/install.sh
```

By default, the installer reuses existing repo-local agent installs when present
(`SAFEHOUSE_E2E_REUSE_EXISTING_INSTALLS=1`). Set it to `0` to force a full reinstall:

```bash
SAFEHOUSE_E2E_REUSE_EXISTING_INSTALLS=0 ./tests/e2e/agents/install.sh
```

The live runner prefers agent binaries in:

1. `tests/e2e/agents/bin/*` (downloaded/installed by the scripts in `tests/e2e/agents/*`)
2. `tests/e2e/agents/pnpm/node_modules/.bin/*` (installed via pnpm when `SAFEHOUSE_E2E_USE_PNPM_AGENTS=1`)

You can disallow using globally-installed binaries (recommended for CI):

```bash
SAFEHOUSE_E2E_ALLOW_GLOBAL_BIN=0 ./tests/e2e/live/run.sh
```

### Running Only One Agent

```bash
./tests/e2e/live/run.sh --profile goose
```

### Skips vs Failures

Each live adapter returns:

- `0`: pass
- `2`: skip (missing auth/config/setup, or binary not installed)
- other: fail

In CI you typically want skips rather than red builds for agents that require extra vendor auth/login:

```bash
SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP=1 ./tests/e2e/live/run.sh
```

## Adding/Updating Live Agent Support

Live testing is adapter-based:

- Add an agent profile: `profiles/60-agents/<name>.sb`
- Add a non-interactive adapter: `tests/e2e/live/adapters/<name>.sh`

Adapters run the real CLI under Safehouse and must implement `run_prompt()` (see `tests/e2e/live/adapters/lib/noninteractive-common.sh`).
