#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] claude-code boots and completes roundtrip" {
  sft_require_cmd_or_skip "claude"
  sft_require_env_or_skip "ANTHROPIC_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/claude-code-home"
  local config_dir="${AGENT_TUI_WORKDIR}/claude-code-config"
  local auth_log_path="${AGENT_TUI_ROOT}/claude-code-login.log"
  local input_ready_pattern='Try \".+\"|/effort|Welcome back!|❯'
  local trust_gate_pattern=""
  local permission_gate_pattern=""
  local restart_gate_pattern=""
  local model="claude-haiku-4-5"
  local api_key="${ANTHROPIC_API_KEY}"

  prepare_agent_state "${agent_home}" "${config_dir}"
  login_agent "${config_dir}" "${auth_log_path}" "${model}"
  configure_agent_tui

  SAFEHOUSE_ANTHROPIC_API_KEY="${api_key}" \
    sft_tmux_start \
      safehouse --env-pass=SAFEHOUSE_ANTHROPIC_API_KEY -- \
      "HOME=${agent_home}" \
      "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" \
      claude --model="${model}" --effort low --dangerously-skip-permissions
  handle_startup_gates 1
  sft_tmux_assert_roundtrip
}

prepare_agent_state() {
  local agent_home="$1"
  local config_dir="$2"
  local api_key_helper="${agent_home}/.claude/print-api-key.sh"
  local workdir_json="\"${AGENT_TUI_WORKDIR}\""

  mkdir -p "${agent_home}/.claude" "${config_dir}"

  cat >"${agent_home}/.claude/settings.json" <<EOF
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "theme": "dark",
  "skipDangerousModePermissionPrompt": true,
  "apiKeyHelper": "/bin/sh \"${api_key_helper}\""
}
EOF

  cat >"${api_key_helper}" <<'EOF'
#!/bin/sh
printf '%s' "${SAFEHOUSE_ANTHROPIC_API_KEY:-}"
EOF
  chmod 700 "${api_key_helper}"

  cat >"${agent_home}/.claude.json" <<EOF
{
  "hasCompletedOnboarding": true,
  "projects": {
    ${workdir_json}: {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true,
      "projectOnboardingSeenCount": 1
    }
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
  AGENT_TUI_NAME="claude"
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
