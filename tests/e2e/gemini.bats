#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] gemini boots and completes roundtrip" {
  sft_require_cmd_or_skip "gemini"
  sft_require_env_or_skip "GEMINI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/gemini-home"
  local config_dir="${AGENT_TUI_WORKDIR}/gemini-config"
  local auth_log_path="${AGENT_TUI_ROOT}/gemini-login.log"
  local trusted_folders_path="${config_dir}/trustedFolders.json"
  local system_settings_path="${config_dir}/system-settings.json"
  
  prepare_agent_state "${agent_home}" "${config_dir}" "${trusted_folders_path}" "${system_settings_path}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  GEMINI_API_KEY="${GEMINI_API_KEY}" \
  HOME="${agent_home}" \
  GEMINI_CLI_TRUSTED_FOLDERS_PATH="${trusted_folders_path}" \
  GEMINI_CLI_SYSTEM_SETTINGS_PATH="${system_settings_path}" \
    sft_tmux_start \
      safehouse --env-pass=GEMINI_API_KEY,GEMINI_CLI_TRUSTED_FOLDERS_PATH,GEMINI_CLI_SYSTEM_SETTINGS_PATH -- \
      gemini --yolo
  handle_startup_gates 1
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"
  local trusted_folders_path="$3"
  local system_settings_path="$4"
  local workdir_real=""

  mkdir -p "${agent_home}" "${config_dir}"
  workdir_real="$(cd "${AGENT_TUI_WORKDIR}" && pwd -P)"

  cat >"${trusted_folders_path}" <<EOF
{
  "${AGENT_TUI_WORKDIR}": "TRUST_FOLDER",
  "${workdir_real}": "TRUST_FOLDER"
}
EOF

  cat >"${system_settings_path}" <<'EOF'
{
  "general": {
    "enableAutoUpdate": false,
    "enableAutoUpdateNotification": false
  },
  "hooksConfig": {
    "enabled": false,
    "notifications": false
  }
}
EOF
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
  AGENT_TUI_STARTUP_WAIT_SECS=30
  if (( AGENT_TUI_PROMPT_VISIBLE_TIMEOUT_SECS < 12 )); then
    AGENT_TUI_PROMPT_VISIBLE_TIMEOUT_SECS=12
  fi
  if (( AGENT_TUI_RESPONSE_TIMEOUT_SECS < 30 )); then
    AGENT_TUI_RESPONSE_TIMEOUT_SECS=30
  fi
  # Gemini's Ink UI can keep the placeholder visible in tmux captures until
  # submit even when the input buffer is ready, so rely on the roundtrip token
  # instead of a pre-submit prompt echo.
  AGENT_TUI_PROMPT_VISIBLE_MODE="none"
}

handle_startup_gates() {
  local pass="${1:-1}"
  local input_ready_pattern='Type your message|@path/to/file|YOLO ctrl\+y'
  local trust_gate_pattern='Do you trust the files in this folder'
  local permission_gate_pattern='Get started|How would you like to authenticate for this project\?|Existing API key detected|Use Gemini API Key|Use Enter to select'
  local restart_gate_pattern='Gemini CLI is restarting to apply the trust changes'
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

  # Once the combined wait above has seen either the ready screen or a known
  # gate, Gemini can repaint between captures. If no known gate is still
  # visible, treat the session as ready and let the roundtrip assertion own any
  # later failure.
  return 0
}
