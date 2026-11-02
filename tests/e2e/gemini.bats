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
  local settings_path="${agent_home}/.gemini/settings.json"

  AGENT_TUI_READY_PATTERN='Type your message|@path/to/file|YOLO ctrl\+y'
  sft_agent_tui_add_gate 'Do you trust the files in this folder' Enter
  sft_agent_tui_add_gate 'Get started|How would you like to authenticate for this project\?|Existing API key detected|Use Gemini API Key|Use Enter to select' Enter
  sft_agent_tui_add_gate 'Gemini CLI is restarting to apply the trust changes'

  prepare_agent_state "${agent_home}" "${config_dir}" "${trusted_folders_path}" "${settings_path}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  GEMINI_API_KEY="${GEMINI_API_KEY}" \
  HOME="${agent_home}" \
  GEMINI_CLI_TRUSTED_FOLDERS_PATH="${trusted_folders_path}" \
    sft_tmux_start \
      safehouse --env-pass=GEMINI_API_KEY,GEMINI_CLI_TRUSTED_FOLDERS_PATH -- \
      gemini --yolo
  sft_agent_tui_handle_startup_gates
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"
  local trusted_folders_path="$3"
  local settings_path="$4"
  local workdir_real=""

  mkdir -p "${agent_home}" "${config_dir}" "$(dirname "${settings_path}")"
  workdir_real="$(cd "${AGENT_TUI_WORKDIR}" && pwd -P)"

  cat >"${trusted_folders_path}" <<EOF
{
  "${AGENT_TUI_WORKDIR}": "TRUST_FOLDER",
  "${workdir_real}": "TRUST_FOLDER"
}
EOF

  # With selectedType set, Gemini skips the auth dialog and reads the key
  # from GEMINI_API_KEY.
  cat >"${settings_path}" <<'EOF'
{
  "security": {
    "auth": {
      "selectedType": "gemini-api-key"
    }
  },
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
  if (( AGENT_TUI_RESPONSE_TIMEOUT_SECS < 60 )); then
    AGENT_TUI_RESPONSE_TIMEOUT_SECS=60
  fi
  # Gemini's Ink UI can keep the placeholder visible in tmux captures until
  # submit even when the input buffer is ready, so rely on the roundtrip token
  # instead of a pre-submit prompt echo.
  AGENT_TUI_PROMPT_VISIBLE_MODE="none"
  # The ready screen can appear before Gemini consistently accepts injected
  # input on busy CI runners, so wait briefly and type more conservatively.
  AGENT_TUI_PRE_PROMPT_DELAY_SECS=1
  AGENT_TUI_PROMPT_SEND_MODE="slow"
  AGENT_TUI_PROMPT_CHAR_DELAY_SECS=0.05
  # Give Gemini's hidden input buffer extra time to absorb the injected text
  # before Enter on busy CI runners.
  AGENT_TUI_SUBMIT_DELAY_SECS=1
}
