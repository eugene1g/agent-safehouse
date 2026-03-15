# Testing

## Prerequisites

- macOS host with `sandbox-exec`
- run tests outside any existing sandboxed session

## Core Test Suite

```bash
./tests/run.sh
```

- `./tests/run.sh` is the primary entrypoint for the macOS Bats suite.
- By default it runs the `policy` and `surface` suites.
- Tests live under `tests/policy/`, `tests/surface/`, and `tests/e2e/`.
- The suite is designed for macOS with `sandbox-exec`.

Run a specific suite:

```bash
./tests/run.sh policy
./tests/run.sh surface
./tests/run.sh e2e
./tests/run.sh all
```

Single-file ad hoc runs should use Bats directly:

```bash
bats tests/policy/integrations/docker.bats
bats tests/e2e/codex.bats
```

Some standard-suite integration checks also depend on host browser tooling. When
present, CI installs `agent-browser`, Playwright's `chromium-headless-shell`
download, and Google Chrome for those checks. Missing local host dependencies
skip cleanly.

## E2E Checks

These Bats tests drive real agent TUIs through `tmux` under Safehouse.
Their contract is limited to startup/readiness and a basic prompt roundtrip, not full agent capability coverage.
They currently cover:

- `aider`
- `amp`
- `claude-code`
- `cline`
- `codex`
- `gemini`
- `goose`
- `kilo-code`
- `opencode`
- `pi`

CI runs this subset in the dedicated `E2E TUI Tests (macOS)` workflow.

Install the same agent dependencies used by GitHub Actions:

```bash
brew install bats-core parallel tmux node aider block-goose-cli
$(brew --prefix node)/bin/npm install --global \
  @anthropic-ai/claude-code \
  @google/gemini-cli \
  @kilocode/cli \
  @mariozechner/pi-coding-agent \
  @openai/codex \
  @sourcegraph/amp \
  cline \
  opencode-ai
```

CI installs these packages directly in the workflow job.

Depending on the specific test file, you may also need provider keys such as:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`

Without the required binary or API key, the corresponding test skips cleanly.
