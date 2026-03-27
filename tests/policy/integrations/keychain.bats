#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] default policy omits keychain integration while codex injects it and aider does not" {
  local default_profile codex_profile aider_profile

  default_profile="$(safehouse_profile)"
  codex_profile="$(safehouse_profile -- codex --version)"
  aider_profile="$(safehouse_profile -- aider --version)"

  sft_assert_omits_source "$default_profile" "55-integrations-optional/keychain.sb"
  sft_assert_includes_source "$codex_profile" "55-integrations-optional/keychain.sb"
  sft_assert_omits_source "$aider_profile" "55-integrations-optional/keychain.sb"
}

@test "[POLICY-ONLY] --enable=keychain explicitly includes keychain integration for opencode" {
  local fake_home fake_opencode profile

  fake_home="$(sft_fake_home)" || return 1
  fake_opencode="${fake_home}/.local/bin/opencode"
  sft_make_fake_command "$fake_opencode"

  profile="$(HOME="$fake_home" safehouse_profile --enable=keychain -- "$fake_opencode")"

  sft_assert_includes_source "$profile" "60-agents/opencode.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/keychain.sb"
}

@test "[EXECUTION] security tool is denied by default but allowed for a keychain-enabled agent profile" {
  local keychain_policy non_keychain_policy

  sft_require_cmd_or_skip security

  HOME="$SAFEHOUSE_HOST_HOME" /usr/bin/security find-certificate -a >/dev/null 2>&1 || skip "security find-certificate precheck failed outside sandbox"

  keychain_policy="$(sft_workspace_path "policy-keychain-codex.sb")"
  non_keychain_policy="$(sft_workspace_path "policy-keychain-aider.sb")"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok --stdout --output "$keychain_policy" -- codex --version >/dev/null
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok --stdout --output "$non_keychain_policy" -- aider --version >/dev/null

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied -- /usr/bin/security find-certificate -a

  run /bin/sh -c 'HOME="$2" sandbox-exec -f "$1" -- /usr/bin/security find-certificate -a >/dev/null 2>&1' _ "$non_keychain_policy" "$SAFEHOUSE_HOST_HOME"
  [ "$status" -ne 0 ]

  run /bin/sh -c 'HOME="$2" sandbox-exec -f "$1" -- /usr/bin/security find-certificate -a >/dev/null 2>&1' _ "$keychain_policy" "$SAFEHOUSE_HOST_HOME"
  [ "$status" -eq 0 ]
}
