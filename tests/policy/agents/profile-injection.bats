#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Agent profile injection.
# Verifies that agent commands auto-inject their required integration
# profiles (keychain, browser-native-messaging, microphone) via $$require=$$ metadata.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] claude command auto-injects keychain profile" { # https://github.com/eugene1g/agent-safehouse/issues/5
  local profile
  profile="$(safehouse_profile -- claude)"

  sft_assert_includes_source "$profile" "55-integrations-optional/keychain.sb"
}

@test "[POLICY-ONLY] copilot command auto-injects keychain profile" { # https://github.com/eugene1g/agent-safehouse/issues/5
  local profile
  profile="$(safehouse_profile -- copilot)"

  sft_assert_includes_source "$profile" "55-integrations-optional/keychain.sb"
}

@test "[POLICY-ONLY] copilot command grants bundled package cache roots" {
  local profile
  profile="$(safehouse_profile -- copilot)"

  sft_assert_contains "$profile" '(home-subpath "/Library/Caches/copilot")'
  sft_assert_contains "$profile" '(allow file-read-metadata'
  sft_assert_contains "$profile" '(home-literal "/Library")'
  sft_assert_contains "$profile" '(home-literal "/Library/Caches")'
}

@test "[POLICY-ONLY] claude command auto-injects browser-native-messaging profile" { # https://github.com/eugene1g/agent-safehouse/issues/16
  local profile
  profile="$(safehouse_profile -- claude)"

  sft_assert_includes_source "$profile" "55-integrations-optional/browser-native-messaging.sb"
}

@test "[POLICY-ONLY] claude command auto-injects microphone profile for voice mode" {
  local profile
  profile="$(safehouse_profile -- claude)"

  sft_assert_includes_source "$profile" "55-integrations-optional/microphone.sb"
}

@test "[POLICY-ONLY] kilo command auto-injects keychain profile" {
  local profile
  profile="$(safehouse_profile -- kilo)"

  sft_assert_includes_source "$profile" "55-integrations-optional/keychain.sb"
}

@test "[POLICY-ONLY] selected agent commands include their own scoped agent profile source" {
  local claude_profile copilot_profile

  claude_profile="$(safehouse_profile -- claude)"
  copilot_profile="$(safehouse_profile -- copilot)"

  sft_assert_includes_source "$claude_profile" "60-agents/claude-code.sb"
  sft_assert_includes_source "$copilot_profile" "60-agents/copilot-cli.sb"
}

@test "[POLICY-ONLY] claude command includes narrow VS Code bundle metadata for editor reuse" {
  local claude_profile

  claude_profile="$(safehouse_profile -- claude)"

  sft_assert_contains "$claude_profile" '(allow file-read-metadata'
  sft_assert_contains "$claude_profile" '(literal "/Applications")'
  sft_assert_contains "$claude_profile" '(subpath "/Applications/Visual Studio Code.app")'
  sft_assert_contains "$claude_profile" '(subpath "/Applications/Visual Studio Code - Insiders.app")'
  sft_assert_omits_source "$claude_profile" "55-integrations-optional/vscode.sb"
  sft_assert_omits_source "$claude_profile" "65-apps/vscode-app.sb"
}
