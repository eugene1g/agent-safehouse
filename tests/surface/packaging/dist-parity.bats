#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "[POLICY-ONLY] bin and dist default policy output match byte-for-byte" {
  local bin_policy dist_policy

  bin_policy="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout)"
  dist_policy="$(safehouse_profile)"

  [ "$bin_policy" = "$dist_policy" ]
}

@test "[POLICY-ONLY] bin and dist command-scoped policies match for alias-driven and app-hosted commands" {
  local fake_copilot_bin fake_claude_app_bin fake_codex_app_bin
  local bin_copilot dist_copilot bin_claude_app dist_claude_app bin_codex_app dist_codex_app

  fake_copilot_bin="$(sft_workspace_path "copilot")"
  fake_claude_app_bin="$(sft_workspace_path "Claude.app/Contents/MacOS/Claude")"
  fake_codex_app_bin="$(sft_workspace_path "Codex.app/Contents/MacOS/codex")"
  sft_make_fake_command "$fake_copilot_bin"
  sft_make_fake_command "$fake_claude_app_bin"
  sft_make_fake_command "$fake_codex_app_bin"

  bin_copilot="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout -- "$fake_copilot_bin")"
  dist_copilot="$(safehouse_profile -- "$fake_copilot_bin")"
  [ "$bin_copilot" = "$dist_copilot" ]
  sft_assert_includes_source "$dist_copilot" "60-agents/copilot-cli.sb"
  sft_assert_includes_source "$dist_copilot" "55-integrations-optional/keychain.sb"

  bin_claude_app="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout -- "$fake_claude_app_bin")"
  dist_claude_app="$(safehouse_profile -- "$fake_claude_app_bin")"
  [ "$bin_claude_app" = "$dist_claude_app" ]
  sft_assert_includes_source "$dist_claude_app" "65-apps/claude-app.sb"
  sft_assert_includes_source "$dist_claude_app" "60-agents/claude-code.sb"

  bin_codex_app="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout -- "$fake_codex_app_bin")"
  dist_codex_app="$(safehouse_profile -- "$fake_codex_app_bin")"
  [ "$bin_codex_app" = "$dist_codex_app" ]
  sft_assert_includes_source "$dist_codex_app" "65-apps/codex-app.sb"
  sft_assert_includes_source "$dist_codex_app" "55-integrations-optional/electron.sb"
  sft_assert_includes_source "$dist_codex_app" "55-integrations-optional/keychain.sb"
  sft_assert_omits_source "$dist_codex_app" "60-agents/codex.sb"
}

@test "[EXECUTION] bin and dist apply playwright-chrome exec env defaults identically" {
  local bin_value dist_value

  bin_value="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --enable=playwright-chrome -- /bin/sh -c 'printf "%s" "${PLAYWRIGHT_MCP_SANDBOX:-}"')"
  dist_value="$(safehouse_ok --enable=playwright-chrome -- /bin/sh -c 'printf "%s" "${PLAYWRIGHT_MCP_SANDBOX:-}"')"

  [ "$bin_value" = "$dist_value" ]
  [ "$dist_value" = "false" ]
}
