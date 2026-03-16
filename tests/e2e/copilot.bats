#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] copilot boots to startup screen" {
  sft_require_cmd_or_skip "copilot"

  local agent_home="${AGENT_TUI_WORKDIR}/copilot-home"
  local config_dir="${AGENT_TUI_WORKDIR}/copilot-config"
  local auth_log_path="${AGENT_TUI_ROOT}/copilot-login.log"
  local input_ready_pattern='Please use /login|Type @ to mention files|shift\+tab switch mode'
  local trust_gate_pattern='Confirm folder trust|Do you trust the files in this folder\?'
  local permission_gate_pattern=""
  local restart_gate_pattern=""

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}"
  configure_agent_tui

  sft_tmux_start \
    safehouse -- \
    "HOME=${agent_home}" \
    copilot
  handle_startup_gates 1
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"

  mkdir -p "${agent_home}/Library/Caches" "${config_dir}"
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"

  return 0
}

configure_agent_tui() {
  if (( AGENT_TUI_STARTUP_WAIT_SECS < 20 )); then
    AGENT_TUI_STARTUP_WAIT_SECS=20
  fi

  return 0
}

handle_startup_gates() {
  local pass="${1:-1}"
  local combined_pattern="${input_ready_pattern}"
  local gate_pattern=""
  local -a gate_patterns=(
    "${trust_gate_pattern:-}"
    "${permission_gate_pattern:-}"
    "${restart_gate_pattern:-}"
  )

  (( pass <= 5 )) || {
    AGENT_TUI_FAILED=1
    printf 'too many startup gate passes\n' >&2
    sft_agent_tui_write_screen_capture >&2 || true
    return 1
  }

  for gate_pattern in "${gate_patterns[@]}"; do
    [[ -n "${gate_pattern}" ]] || continue
    combined_pattern="${combined_pattern}|${gate_pattern}"
  done

  sft_tmux_wait_until_regex \
    "${combined_pattern}" \
    "${AGENT_TUI_STARTUP_WAIT_SECS}" \
    "${AGENT_TUI_POLL_INTERVAL_SECS}" || {
      AGENT_TUI_FAILED=1
      sft_agent_tui_write_screen_capture >&2 || true
      return 1
    }

  if sft_tmux_matches_regex "${input_ready_pattern}"; then
    return 0
  fi

  if [[ -n "${trust_gate_pattern:-}" ]] && sft_tmux_matches_regex "${trust_gate_pattern}"; then
    sft_tmux_send_keys Enter
    handle_startup_gates "$((pass + 1))"
    return $?
  fi

  if [[ -n "${permission_gate_pattern:-}" ]] && sft_tmux_matches_regex "${permission_gate_pattern}"; then
    sft_tmux_send_keys Enter
    handle_startup_gates "$((pass + 1))"
    return $?
  fi

  if [[ -n "${restart_gate_pattern:-}" ]] && sft_tmux_matches_regex "${restart_gate_pattern}"; then
    handle_startup_gates "$((pass + 1))"
    return $?
  fi

  AGENT_TUI_FAILED=1
  printf 'unhandled startup gate\n' >&2
  sft_agent_tui_write_screen_capture >&2 || true
  return 1
}
