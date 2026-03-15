#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] aider boots and completes roundtrip" {
  sft_require_cmd_or_skip "aider"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/aider-home"
  local config_dir="${AGENT_TUI_WORKDIR}/aider-config"
  local auth_log_path="${AGENT_TUI_ROOT}/aider-login.log"
  local input_history_path="${config_dir}/.aider.input.history"
  local chat_history_path="${config_dir}/.aider.chat.history.md"
  local input_ready_pattern='ask>'
  local trust_gate_pattern=""
  local permission_gate_pattern=""
  local restart_gate_pattern=""
  local model="gpt-5-mini"

  prepare_agent_state "${agent_home}" "${config_dir}" "${input_history_path}" "${chat_history_path}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  OPENAI_API_KEY="${OPENAI_API_KEY}" \
    sft_tmux_start \
      safehouse --env-pass=OPENAI_API_KEY -- \
      "HOME=${agent_home}" \
      aider \
      --model="${model}" \
      --yes-always \
      --chat-mode ask \
      --no-git \
      --no-pretty \
      --no-check-update \
      --no-show-release-notes \
      --no-analytics \
      --no-browser \
      --input-history-file "${input_history_path}" \
      --chat-history-file "${chat_history_path}"
  handle_startup_gates 1
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"
  local input_history_path="$3"
  local chat_history_path="$4"

  mkdir -p "${agent_home}" "${config_dir}"
  : >"${input_history_path}"
  : >"${chat_history_path}"
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
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
