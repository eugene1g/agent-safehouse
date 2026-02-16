# Testing

## Prerequisites

- macOS host with `sandbox-exec`
- run tests outside any existing sandboxed session

## Core Test Suite

```bash
./tests/run.sh
```

- Runs section-based tests under `tests/sections/`
- Uses shared helpers in `tests/lib/`
- Designed for macOS with `sandbox-exec`

## TUI E2E Simulation

```bash
./tests/e2e/run.sh
```

This runs a fake TUI agent under Safehouse via `tmux` across configured profiles and validates:

- expected profile selection
- in-workdir write succeeds
- out-of-workdir write is denied
- out-of-workdir read is denied
- clean session exit

Parallel execution:

```bash
SAFEHOUSE_E2E_TUI_JOBS=4 ./tests/e2e/run.sh
```

Timeout tuning:

```bash
SAFEHOUSE_E2E_TUI_TIMEOUT_SECS=30 SAFEHOUSE_E2E_TUI_SESSION_TIMEOUT_SECS=30 ./tests/e2e/run.sh
```

## Live Agent Checks

```bash
./tests/e2e/live/run.sh
```

For repo-local agent CLI installs:

```bash
./tests/e2e/agents/install.sh
```

Allow setup/auth prerequisite skips:

```bash
SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP=1 ./tests/e2e/live/run.sh
```

Parallel live execution:

```bash
SAFEHOUSE_E2E_LIVE_JOBS=3 SAFEHOUSE_E2E_LIVE_ALLOW_PREREQ_SKIP=1 ./tests/e2e/live/run.sh
```

Live timeout tuning:

```bash
SAFEHOUSE_E2E_LIVE_COMMAND_TIMEOUT_SECS=240 ./tests/e2e/live/run.sh
```

Run both simulation and live checks:

```bash
SAFEHOUSE_E2E_LIVE=1 ./tests/e2e/run.sh
```
