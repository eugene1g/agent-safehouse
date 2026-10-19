#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] codex boots and completes roundtrip" {
  sft_require_cmd_or_skip "codex"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/codex-home"
  local config_dir="${AGENT_TUI_WORKDIR}/codex-config"
  local auth_log_path="${AGENT_TUI_ROOT}/codex-login.log"
  local model="gpt-5.6-luna"
  # Wait for the loaded model, not just the banner or composer: early Enter
  # presses can be discarded. Older releases show a model: header; 0.162's
  # standalone TUI shows the display name and selected effort in its footer.
  # That footer first reads `GPT-5.6-Luna default` while the session is still
  # loading, then `GPT-5.6-Luna medium` once it is ready, so don't match `default`.
  AGENT_TUI_READY_PATTERN="model: +${model}|GPT-5[.]6-Luna medium"
  # A fresh CODEX_HOME may offer a newer model; keep this test's pinned model.
  sft_agent_tui_add_gate --once 'Use existing model' Down Enter
  sft_agent_tui_add_gate 'Do you trust the contents of this directory' Enter

  prepare_agent_state "${agent_home}" "${config_dir}" "${model}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  # Keep the app server in this sandbox. Codex's shared daemon startup invokes
  # macOS's setuid /bin/ps, which cannot execute inside a Seatbelt sandbox.
  sft_tmux_start \
    safehouse -- \
    "CODEX_HOME=${agent_home}" \
    codex --no-daemon --model="${model}" --dangerously-bypass-approvals-and-sandbox
  sft_agent_tui_handle_startup_gates
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"
  local model="$3"

  mkdir -p "${agent_home}" "${config_dir}"

  cat >"${agent_home}/config.toml" <<EOF
model = "${model}"
model_reasoning_effort = "medium"
check_for_update_on_startup = false

[projects."${AGENT_TUI_WORKDIR}"]
trust_level = "trusted"
EOF
}

login_agent() {
  local _config_dir="$1"
  local auth_log_path="$2"
  local _model="$3"
  local codex_command_path=""

  sft_agent_tui_command_path_or_skip codex_command_path "codex"
  if ! printenv OPENAI_API_KEY | CODEX_HOME="${agent_home}" "${codex_command_path}" login --with-api-key >"${auth_log_path}" 2>&1; then
    cat "${auth_log_path}" >&2
    return 1
  fi
}

configure_agent_tui() {
  # Codex paints its header with `model: loading` and only fills in the model
  # name -- what AGENT_TUI_READY_PATTERN waits for -- once the model catalog
  # comes back over the network. Under the suite's parallelism that has been
  # observed taking longer than the 10s default, and has also overrun CI's 20s
  # floor by ~2s, so allow 150% of that floor (30s).
  if ((AGENT_TUI_STARTUP_WAIT_SECS < 30)); then
    AGENT_TUI_STARTUP_WAIT_SECS=30
  fi

  return 0
}
