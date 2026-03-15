# E2E Agent TUI Tests

This directory contains Bats-native boot-and-roundtrip checks for live agent CLIs.

Run the suite with:

```bash
./tests/run.sh e2e
```

CI installs the required CLIs directly in the dedicated GitHub Actions workflow, using Homebrew for `node`/`aider`/`goose` and global `npm` for the Node-based agent CLIs.

## Layout

- `tmux_utils.bash`: low-level tmux session, capture, send-keys, and polling helpers.
- `agent_tui_harness.bash`: E2E-specific setup/teardown, Safehouse launch shaping, one-shot command capture, and probe submission.
- `../test_helper.bash`: shared per-test Safehouse workspace setup used across the suite.
- `<agent>.bats`: one file per agent profile. Each file owns its path setup, login/bootstrap behavior, input-ready patterns, and startup gate handling.

## Contract

Each agent file should:

1. `load ../test_helper.bash`.
2. `load tmux_utils.bash`.
3. `load agent_tui_harness.bash`.
4. Start the test body with `sft_require_cmd_or_skip` and any `sft_require_env_or_skip`.
5. Declare locals in this order: path variables, pattern variables, then `model`.
6. Implement the same file-local helpers in every test file:
   - `prepare_agent_state`
   - `login_agent`
   - `configure_agent_tui`
   - `handle_startup_gates`
7. Prepare any per-agent home/config state under `AGENT_TUI_ROOT` or `AGENT_TUI_WORKDIR`.
8. Launch the CLI with `sft_tmux_start safehouse [safehouse-args ...] -- [ENV=VALUE ...] <agent> [args...]`.
   Prefer `VAR=value sft_tmux_start safehouse --env-pass=VAR -- ...` for secrets so they stay out of the pane command line.
9. Resolve any startup gates through `handle_startup_gates`, which should recurse until input is ready or fail after 5 passes.
10. Confirm the probe roundtrip with `sft_tmux_assert_roundtrip`.

Use `sft_safehouse_run_capture` inside `login_agent` when an agent needs a one-time Safehouse-wrapped auth/bootstrap step before the interactive launch.

## Canonical Shape

```bash
@test "[E2E-TUI] <agent> boots and completes roundtrip" {
  sft_require_cmd_or_skip "<agent>"
  sft_require_env_or_skip "<API_KEY_VAR>"

  local agent_home="${AGENT_TUI_WORKDIR}/<agent>-home"
  local config_dir="${AGENT_TUI_WORKDIR}/<agent>-config"
  local auth_log_path="${AGENT_TUI_ROOT}/<agent>-login.log"
  local input_ready_pattern='...'
  local trust_gate_pattern='...'
  local permission_gate_pattern='...'
  local restart_gate_pattern='...'
  local model="..."

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  API_KEY="${API_KEY}" \
    sft_tmux_start \
      safehouse --env-pass=API_KEY -- \
      "HOME=${agent_home}" \
      <agent> --model="${model}"

  handle_startup_gates 1
  sft_tmux_assert_roundtrip
}
```

`handle_startup_gates` should:

- build a list of gate-detection regexes
- wait for either a gate or input-ready text
- handle one matched gate
- recurse up to 5 passes
- return as soon as the input-ready pattern is visible

## Naming

- Use the `[E2E-TUI]` prefix for tests that drive a real interactive agent UI.
- Use the title shape `[E2E-TUI] <agent> boots and completes roundtrip`.
- Keep helper names and variable names aligned across files so the only differences are launch args, setup files, and gate actions.

## Debugging And Cleanup

List only tmux sessions created by this suite:

```bash
tmux ls 2>/dev/null | rg '^safehouse-agent-tui-'
```

Inspect pane ids, pane pids, and dead/alive state for suite sessions:

```bash
tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_pid} dead=#{pane_dead}' | rg '^safehouse-agent-tui-'
```

Attach to one lingering session:

```bash
tmux attach-session -t safehouse-agent-tui-<name>
```

Kill all lingering suite sessions:

```bash
tmux ls 2>/dev/null | rg '^safehouse-agent-tui-' | cut -d: -f1 | while read -r session_name; do
  [[ -n "${session_name}" ]] || continue
  tmux kill-session -t "${session_name}"
done
```

If a pane process survives unexpectedly, kill its full process group:

```bash
pane_pid="$(tmux display-message -p -t <session-name> '#{pane_pid}')"
pgid="$(ps -o pgid= -p "${pane_pid}" | tr -d '[:space:]')"
kill -TERM -- "-${pgid}"
sleep 1
kill -KILL -- "-${pgid}"
```
