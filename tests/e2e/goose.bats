#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] goose boots and completes roundtrip" {
  sft_require_cmd_or_skip "goose"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/goose-home"
  local config_dir="${agent_home}/.config/goose"
  local auth_log_path="${AGENT_TUI_ROOT}/goose-login.log"
  local model="gpt-5.6-luna"

  # The banner appears before the editor can accept and submit input. Wait for
  # the empty editor's hint, otherwise the prompt can remain unsubmitted in CI.
  AGENT_TUI_READY_PATTERN='> Enter to send'
  # --once: Press the key sequence to dismiss this gate exactly once
  sft_agent_tui_add_gate --once 'Share anonymous usage data' Right Enter

  prepare_agent_state "${agent_home}" "${config_dir}" "${model}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  OPENAI_API_KEY="${OPENAI_API_KEY}" \
    sft_tmux_start \
      safehouse --env-pass=OPENAI_API_KEY -- \
      "HOME=${agent_home}" \
      "XDG_CONFIG_HOME=${agent_home}/.config" \
      "XDG_DATA_HOME=${agent_home}/.local/share" \
      "XDG_STATE_HOME=${agent_home}/.local/state" \
      "GOOSE_DISABLE_KEYRING=1" \
      "GOOSE_TELEMETRY_OFF=1" \
      "GOOSE_PROVIDER=openai" \
      "GOOSE_MODEL=${model}" \
      goose
  sft_agent_tui_handle_startup_gates
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"
  local model="$3"

  mkdir -p \
    "${agent_home}" \
    "${config_dir}" \
    "${agent_home}/.local/share/goose" \
    "${agent_home}/.local/state/goose"

  cat >"${config_dir}/config.yaml" <<EOF
GOOSE_TELEMETRY_ENABLED: false
GOOSE_DISABLE_KEYRING: true
active_provider: openai
providers:
  openai:
    enabled: true
    model: ${model}
    configured: true
extensions:
  developer:
    enabled: true
    type: builtin
    name: developer
    description: default
    display_name: Developer
    timeout: 300
    bundled: true
    available_tools: []
EOF
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
  AGENT_TUI_RESPONSE_TIMEOUT_SECS=40
}
