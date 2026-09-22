#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

prepare_opencode_v2() {
  local version
  OPENCODE_V2_BIN="${SAFEHOUSE_OPENCODE_V2_BIN:-opencode}"
  if [[ -n "${SAFEHOUSE_OPENCODE_V2_BIN:-}" ]]; then
    # An explicitly configured CI installation must fail rather than silently skip.
    [ -x "$OPENCODE_V2_BIN" ] || return 1
  else
    sft_require_cmd_or_skip "$OPENCODE_V2_BIN"
  fi
  OPENCODE_V2_BIN="$(sft_agent_tui_resolve_command_path "$OPENCODE_V2_BIN")"

  # Keep HOME and ancestor configs outside /tmp and the workdir grant: otherwise
  # broad temporary-directory access masks the config discovery regression (#198).
  OPENCODE_V2_HOME="$(sft_fake_home)"
  export HOME="$OPENCODE_V2_HOME"
  export XDG_CONFIG_HOME="${HOME}/.config"
  export XDG_CACHE_HOME="${HOME}/.cache"
  export XDG_DATA_HOME="${HOME}/.local/share"
  export XDG_STATE_HOME="${HOME}/.local/state"
  AGENT_TUI_WORKDIR="${HOME}/projects/repo"
  mkdir -p "$AGENT_TUI_WORKDIR" "${HOME}/.claude" "${XDG_CONFIG_HOME}/opencode"
  printf '{}\n' >"${HOME}/projects/opencode.json"
  printf '{"model":"anthropic/claude-sonnet-5"}\n' >"${XDG_CONFIG_HOME}/opencode/opencode.json"

  version="$("$OPENCODE_V2_BIN" --version)" || return 1
  if [[ "$version" != 'opencode v2.'* ]]; then
    [[ -z "${SAFEHOUSE_OPENCODE_V2_BIN:-}" ]] || return 1
    skip "OpenCode v2 is not installed (set SAFEHOUSE_OPENCODE_V2_BIN)"
  fi
  AGENT_TUI_READY_PATTERN='ctrl.p commands'
  AGENT_TUI_STARTUP_WAIT_SECS=60
}

start_opencode_v2() {
  # A private server is essential: a pre-existing unsandboxed daemon would make
  # both startup and the model roundtrip a false-positive sandbox test.
  sft_tmux_start safehouse --env-pass=ANTHROPIC_API_KEY -- \
    "HOME=${OPENCODE_V2_HOME}" \
    "XDG_CONFIG_HOME=${XDG_CONFIG_HOME}" \
    "XDG_CACHE_HOME=${XDG_CACHE_HOME}" \
    "XDG_DATA_HOME=${XDG_DATA_HOME}" \
    "XDG_STATE_HOME=${XDG_STATE_HOME}" \
    "OPENCODE_TEST_HOME=${OPENCODE_V2_HOME}" \
    "$OPENCODE_V2_BIN" --standalone
  sft_agent_tui_handle_startup_gates
}

@test "[E2E-TUI] opencode v2 boots with existing home and ancestor config paths" {
  prepare_opencode_v2
  start_opencode_v2
}

@test "[E2E-TUI] opencode v2 boots and completes roundtrip with a sandboxed private server" {
  sft_require_env_or_skip "ANTHROPIC_API_KEY"
  prepare_opencode_v2
  start_opencode_v2
  sft_tmux_assert_roundtrip
}
