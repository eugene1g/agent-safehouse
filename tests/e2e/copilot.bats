#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] copilot boots and completes roundtrip" {
  sft_require_cmd_or_skip "copilot"
  sft_require_env_or_skip "OPENAI_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/copilot-home"
  local config_dir="${AGENT_TUI_WORKDIR}/copilot-config"
  local auth_log_path="${AGENT_TUI_ROOT}/copilot-login.log"
  local model="gpt-5.6-luna"

  AGENT_TUI_READY_PATTERN='Please use /login|/ commands'
  sft_agent_tui_add_gate 'Confirm folder trust|Do you trust the files in this folder\?' Enter
  # Printed if the `copilot` on PATH is the VS Code Copilot Chat launcher shim
  # rather than the standalone GitHub Copilot CLI. Nothing to answer: the agent
  # under test is not installed at all.
  sft_agent_tui_add_skip_gate 'Cannot find GitHub Copilot CLI' \
    'GitHub Copilot CLI not installed, although VS Code Copilot Chat launcher is present'

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  # Copilot CLI's BYOK (bring-your-own-key) mode <https://docs.github.com/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models>
  # skips GitHub authentication entirely once COPILOT_PROVIDER_BASE_URL is set, so
  # the OpenAI key the E2E suite already has can drive the roundtrip directly.
  # The var name doesn't match COPILOT_PROVIDER_API_KEY, so it's re-exported under
  # that name before --env-pass hands it to the sandboxed session (never on the
  # command line -- see sft_agent_tui_apply_env_pass_names).
  COPILOT_PROVIDER_API_KEY="${OPENAI_API_KEY}" \
    sft_tmux_start \
      safehouse --env-pass=COPILOT_PROVIDER_API_KEY -- \
      "HOME=${agent_home}" \
      "COPILOT_PROVIDER_BASE_URL=https://api.openai.com/v1" \
      "COPILOT_PROVIDER_WIRE_API=responses" \
      "COPILOT_MODEL=${model}" \
      copilot --no-auto-update
  sft_agent_tui_handle_startup_gates
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"

  mkdir -p "${agent_home}/Library/Caches" "${config_dir}"
}

login_agent() {
  local _config_dir="$1"
  local _auth_log_path="$2"
  local _model="$3"

  return 0
}

configure_agent_tui() {
  # Each test run gets a fresh HOME, so the packaged Node SEA launcher has to
  # unpack its bundled package into ~/Library/Caches/copilot/pkg on every run;
  # that alone has been observed taking ~26s inside the sandbox, on top of the
  # BYOK provider/model-catalog validation and the trust-gate render.
  if (( AGENT_TUI_STARTUP_WAIT_SECS < 60 )); then
    AGENT_TUI_STARTUP_WAIT_SECS=60
  fi

  return 0
}

