#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] cline boots and completes roundtrip" {
  sft_require_cmd_or_skip "cline"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/cline-home"
  local config_dir="${AGENT_TUI_WORKDIR}/cline-config"
  local auth_log_path="${AGENT_TUI_ROOT}/cline-login.log"
  local promo_settle_secs="${SAFEHOUSE_AGENT_TUI_CLINE_PROMO_SETTLE_SECS:-1.5}"
  local model="gpt-5.6-luna"

  AGENT_TUI_READY_PATTERN='What can I do for you\?|/ for commands|Plan .* Act'
  # A "Try ClinePass" subscription promo appears over the input line at startup.
  # It closes on any key other than Enter. Use --before-ready to recognize it
  # before the ready pattern because the promo overlay does NOT obscure the
  # input line which the ready pattern matches.
  sft_agent_tui_add_gate --before-ready 'Try ClinePass|any other key to close' Escape

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  sft_tmux_start \
    safehouse -- \
    "HOME=${agent_home}" \
    cline --config "${config_dir}" --model "${model}" -a -y

  # Wait for input ready. Sequence:
  # 1. ${AGENT_TUI_READY_PATTERN} observed. Input IGNORED (if promo coming).
  # 2. About 300-400ms pass.
  #    The promo gate is observed.
  # 3. Press Escape.
  #    ${AGENT_TUI_READY_PATTERN} observed. Input accepted.
  #
  # NOTE: The promo lands *after* the ready screen, so one call is not enough.
  sft_agent_tui_handle_startup_gates  # wait for first ready screen
  sleep "${promo_settle_secs}"        # wait for promo to display (if there is one)
  sft_agent_tui_handle_startup_gates  # dismiss promo (if any); wait for last ready screen

  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"

  mkdir -p "${agent_home}" "${config_dir}"
}

login_agent() {
  local config_dir="$1"
  local auth_log_path="$2"
  local model="$3"

  if ! sft_safehouse_run_capture "${auth_log_path}" cline auth --config "${config_dir}" --provider openai-native --apikey "${OPENAI_API_KEY}" --modelid "${model}"; then
    cat "${auth_log_path}" >&2
    return 1
  fi
}

configure_agent_tui() {
  # cline can leave the terminal blank for well past the 10s default before it
  # paints its splash, so the first handle_startup_gates call has nothing to
  # match. Same floor codex uses, and the one CI already sets globally.
  if (( AGENT_TUI_STARTUP_WAIT_SECS < 20 )); then
    AGENT_TUI_STARTUP_WAIT_SECS=20
  fi

  return 0
}
