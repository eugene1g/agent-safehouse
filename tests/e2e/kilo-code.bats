#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] kilo-code boots and completes roundtrip" {
  sft_require_cmd_or_skip "kilo"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/kilo-code-home"
  local config_dir="${agent_home}/.config"
  local auth_log_path="${AGENT_TUI_ROOT}/kilo-code-login.log"
  local input_ready_pattern='Ask anything|ctrl\+p commands|tab agents|Code[[:space:]]+'
  local trust_gate_pattern=""
  local permission_gate_pattern=""
  local restart_gate_pattern='Performing one time database migration|Database migration complete'
  local model="openai/gpt-5-mini"

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  OPENAI_API_KEY="${OPENAI_API_KEY}" \
    sft_tmux_start \
      safehouse --env-pass=OPENAI_API_KEY -- \
      "HOME=${agent_home}" \
      "XDG_CONFIG_HOME=${agent_home}/.config" \
      "XDG_CACHE_HOME=${agent_home}/.cache" \
      "XDG_STATE_HOME=${agent_home}/.local/state" \
      "XDG_DATA_HOME=${agent_home}/.local/share" \
      kilo --model="${model}"
  handle_startup_gates 1
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"

  mkdir -p \
    "${agent_home}/.kilocode" \
    "${config_dir}" \
    "${agent_home}/.cache" \
    "${agent_home}/.local/state" \
    "${agent_home}/.local/share"
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
  AGENT_TUI_STARTUP_WAIT_SECS=60
  AGENT_TUI_RESPONSE_TIMEOUT_SECS=120
  AGENT_TUI_PROMPT_VISIBLE_TIMEOUT_SECS=8
  # Kilo keeps the placeholder visible in tmux captures instead of echoing the
  # full typed prompt before submit, so the response token is the stable signal.
  AGENT_TUI_PROMPT_VISIBLE_MODE="none"
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
    sft_tmux_wait_until_regex \
      "${input_ready_pattern}" \
      "${AGENT_TUI_STARTUP_WAIT_SECS}" \
      "${AGENT_TUI_POLL_INTERVAL_SECS}" || {
        AGENT_TUI_FAILED=1
        sft_agent_tui_write_screen_capture >&2 || true
        return 1
      }
    return 0
  fi

  AGENT_TUI_FAILED=1
  printf 'unhandled startup gate\n' >&2
  sft_agent_tui_write_screen_capture >&2 || true
  return 1
}
