#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] pi boots and completes roundtrip" {
  sft_require_cmd_or_skip "pi"
  sft_require_env_or_skip "ANTHROPIC_API_KEY"

  local agent_home="${AGENT_TUI_WORKDIR}/pi-home"

  mkdir -p "${agent_home}"

  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
  PI_CODING_AGENT_DIR="${agent_home}" \
  sft_tmux_start \
    safehouse --env-pass=ANTHROPIC_API_KEY,PI_CODING_AGENT_DIR -- \
    pi --model anthropic/haiku:low
  sft_tmux_wait_until_regex "claude-haiku"
  sft_tmux_assert_roundtrip
}