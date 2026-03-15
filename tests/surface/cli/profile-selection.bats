#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "[POLICY-ONLY] agent profile selection follows command basename for direct executables" {
  local codex_bin goose_bin kilo_bin codex_profile goose_profile kilo_profile

  codex_bin="$(sft_workspace_path "codex")"
  goose_bin="$(sft_workspace_path "goose")"
  kilo_bin="$(sft_workspace_path "kilo")"

  sft_make_fake_command "$codex_bin"
  sft_make_fake_command "$goose_bin"
  sft_make_fake_command "$kilo_bin"

  codex_profile="$(safehouse_profile -- "$codex_bin")"
  goose_profile="$(safehouse_profile -- "$goose_bin")"
  kilo_profile="$(safehouse_profile -- "$kilo_bin")"

  sft_assert_includes_source "$codex_profile" "60-agents/codex.sb"
  sft_assert_includes_source "$codex_profile" "55-integrations-optional/keychain.sb"
  sft_assert_omits_source "$codex_profile" "60-agents/claude-code.sb"

  sft_assert_includes_source "$goose_profile" "60-agents/goose.sb"
  sft_assert_omits_source "$goose_profile" "60-agents/codex.sb"

  sft_assert_includes_source "$kilo_profile" "60-agents/kilo-code.sb"
  sft_assert_omits_source "$kilo_profile" "60-agents/codex.sb"
}

@test "[POLICY-ONLY] wrapper launchers map to the wrapped command for profile selection" {
  local npx_bin bunx_bin uvx_bin pipx_bin xcrun_bin cline_bin aider_bin codex_bin
  local npx_profile bunx_profile uvx_profile pipx_profile xcrun_profile

  npx_bin="$(sft_workspace_path "npx")"
  bunx_bin="$(sft_workspace_path "bunx")"
  uvx_bin="$(sft_workspace_path "uvx")"
  pipx_bin="$(sft_workspace_path "pipx")"
  xcrun_bin="$(sft_workspace_path "xcrun")"
  cline_bin="$(sft_workspace_path "cline")"
  aider_bin="$(sft_workspace_path "aider")"
  codex_bin="$(sft_workspace_path "codex")"
  npx_profile="$(sft_workspace_path "npx-policy.sb")"
  bunx_profile="$(sft_workspace_path "bunx-policy.sb")"
  uvx_profile="$(sft_workspace_path "uvx-policy.sb")"
  pipx_profile="$(sft_workspace_path "pipx-policy.sb")"
  xcrun_profile="$(sft_workspace_path "xcrun-policy.sb")"

  sft_make_fake_command "$npx_bin"
  sft_make_fake_command "$bunx_bin"
  sft_make_fake_command "$uvx_bin"
  sft_make_fake_command "$pipx_bin"
  sft_make_fake_command "$xcrun_bin"
  sft_make_fake_command "$cline_bin"
  sft_make_fake_command "$aider_bin"
  sft_make_fake_command "$codex_bin"

  npx_profile="$(safehouse_profile -- "$npx_bin" "$cline_bin")"
  bunx_profile="$(safehouse_profile -- "$bunx_bin" "$codex_bin")"
  uvx_profile="$(safehouse_profile -- "$uvx_bin" "$aider_bin")"
  pipx_profile="$(safehouse_profile -- "$pipx_bin" "$aider_bin")"
  xcrun_profile="$(safehouse_profile -- "$xcrun_bin" "$codex_bin")"

  sft_assert_includes_source "$npx_profile" "60-agents/cline.sb"
  sft_assert_includes_source "$bunx_profile" "60-agents/codex.sb"
  sft_assert_includes_source "$uvx_profile" "60-agents/aider.sb"
  sft_assert_includes_source "$pipx_profile" "60-agents/aider.sb"
  sft_assert_includes_source "$xcrun_profile" "60-agents/codex.sb"
}

@test "[POLICY-ONLY] leading command env assignments still map profile selection to the wrapped command" {
  local codex_bin codex_profile

  codex_bin="$(sft_workspace_path "codex")"

  sft_make_fake_command "$codex_bin"

  codex_profile="$(safehouse_profile -- OPENAI_API_KEY=test-key "$codex_bin")"

  sft_assert_includes_source "$codex_profile" "60-agents/codex.sb"
  sft_assert_includes_source "$codex_profile" "55-integrations-optional/keychain.sb"
}

@test "[POLICY-ONLY] profile selection covers filename-matched agents and metadata aliases" {
  local amp_bin auggie_bin droid_bin cursor_agent_bin cursor_bin generic_agent_bin
  local amp_profile auggie_profile droid_profile cursor_agent_profile cursor_profile generic_agent_profile

  amp_bin="$(sft_workspace_path "amp")"
  auggie_bin="$(sft_workspace_path "auggie")"
  droid_bin="$(sft_workspace_path "droid")"
  cursor_agent_bin="$(sft_workspace_path "cursor-agent")"
  cursor_bin="$(sft_workspace_path "cursor")"
  generic_agent_bin="$(sft_workspace_path "agent")"

  sft_make_fake_command "$amp_bin"
  sft_make_fake_command "$auggie_bin"
  sft_make_fake_command "$droid_bin"
  sft_make_fake_command "$cursor_agent_bin"
  sft_make_fake_command "$cursor_bin"
  sft_make_fake_command "$generic_agent_bin"

  amp_profile="$(safehouse_profile -- "$amp_bin")"
  auggie_profile="$(safehouse_profile -- "$auggie_bin")"
  droid_profile="$(safehouse_profile -- "$droid_bin")"
  cursor_agent_profile="$(safehouse_profile -- "$cursor_agent_bin")"
  cursor_profile="$(safehouse_profile -- "$cursor_bin")"
  generic_agent_profile="$(safehouse_profile -- "$generic_agent_bin")"

  sft_assert_includes_source "$amp_profile" "60-agents/amp.sb"
  sft_assert_includes_source "$amp_profile" "55-integrations-optional/clipboard.sb"
  sft_assert_includes_source "$auggie_profile" "60-agents/auggie.sb"
  sft_assert_includes_source "$droid_profile" "60-agents/droid.sb"
  sft_assert_includes_source "$cursor_agent_profile" "60-agents/cursor-agent.sb"
  sft_assert_includes_source "$cursor_profile" "60-agents/cursor-agent.sb"
  sft_assert_includes_source "$generic_agent_profile" "60-agents/cursor-agent.sb"
}

@test "[POLICY-ONLY] unknown commands skip scoped profile layers by default" {
  local unknown_bin unknown_profile

  unknown_bin="$(sft_workspace_path "not-an-agent")"

  sft_make_fake_command "$unknown_bin"
  unknown_profile="$(safehouse_profile -- "$unknown_bin")"

  sft_assert_omits_source "$unknown_profile" "60-agents/codex.sb"
  sft_assert_omits_source "$unknown_profile" "55-integrations-optional/keychain.sb"
  sft_assert_contains "$unknown_profile" "No command-matched app/agent profile selected; skipping 60-agents and 65-apps modules."
}
