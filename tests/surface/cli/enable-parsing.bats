#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "[POLICY-ONLY] separate-form --enable parses representative optional integrations" {
  local docker_profile shell_init_profile xcode_profile

  docker_profile="$(safehouse_profile --enable docker)"
  shell_init_profile="$(safehouse_profile --enable shell-init)"
  xcode_profile="$(safehouse_profile --enable xcode)"

  sft_assert_includes_source "$docker_profile" "55-integrations-optional/docker.sb"
  sft_assert_includes_source "$shell_init_profile" "55-integrations-optional/shell-init.sb"
  sft_assert_includes_source "$xcode_profile" "55-integrations-optional/xcode.sb"
  sft_assert_omits_source "$xcode_profile" "55-integrations-optional/lldb.sb"
}

@test "[POLICY-ONLY] csv --enable parsing supports dependencies and synthetic feature catalogs" {
  local csv_profile all_agents_profile all_apps_profile wide_read_profile

  csv_profile="$(safehouse_profile "--enable=docker, electron, kubectl, xcode")"
  all_agents_profile="$(safehouse_profile --enable=all-agents)"
  all_apps_profile="$(safehouse_profile --enable=all-apps)"
  wide_read_profile="$(safehouse_profile --enable=wide-read)"

  sft_assert_includes_source "$csv_profile" "55-integrations-optional/docker.sb"
  sft_assert_includes_source "$csv_profile" "55-integrations-optional/electron.sb"
  sft_assert_includes_source "$csv_profile" "55-integrations-optional/kubectl.sb"
  sft_assert_includes_source "$csv_profile" "55-integrations-optional/xcode.sb"
  sft_assert_includes_source "$csv_profile" "55-integrations-optional/macos-gui.sb"
  sft_assert_includes_source "$csv_profile" "55-integrations-optional/clipboard.sb"

  sft_assert_includes_source "$all_agents_profile" "60-agents/codex.sb"
  sft_assert_includes_source "$all_agents_profile" "60-agents/claude-code.sb"
  sft_assert_omits_source "$all_agents_profile" "65-apps/claude-app.sb"

  sft_assert_includes_source "$all_apps_profile" "65-apps/claude-app.sb"
  sft_assert_includes_source "$all_apps_profile" "65-apps/vscode-app.sb"
  sft_assert_omits_source "$all_apps_profile" "60-agents/codex.sb"

  sft_assert_contains "$wide_read_profile" "#safehouse-test-id:wide-read#"
}

@test "unknown and renamed --enable features fail fast" {
  safehouse_denied --enable=bogus

  safehouse_denied --enable env

  safehouse_denied --enable shell-startup

  safehouse_denied --enable apple-build-tools
}
