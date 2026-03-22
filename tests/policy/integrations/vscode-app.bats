#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=all-apps keeps VS Code launchable from the system Applications root" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_omits_source "$profile" "55-integrations-optional/vscode.sb"
  sft_assert_includes_source "$profile" "65-apps/vscode-app.sb"
  sft_assert_contains "$profile" '(literal "/Applications")'
}

@test "[POLICY-ONLY] enable=vscode includes the explicit VS Code integration and app profile" {
  local profile

  profile="$(safehouse_profile --enable=vscode)"

  sft_assert_includes_source "$profile" "55-integrations-optional/vscode.sb"
  sft_assert_includes_source "$profile" "65-apps/vscode-app.sb"
}

@test "[EXECUTION] VS Code CLI can report its version when launched via bash if the CLI is installed" {
  local code_bin

  code_bin="/usr/local/bin/code"
  [ -x "$code_bin" ] || skip "VS Code CLI is not installed at /usr/local/bin/code"

  HOME="$SAFEHOUSE_HOST_HOME" "$code_bin" --version >/dev/null 2>&1 || skip "VS Code CLI precheck failed outside sandbox"

  run safehouse_ok_env HOME="$SAFEHOUSE_HOST_HOME" -- --enable=all-apps -- /bin/bash "$code_bin" --version
  [ "$status" -eq 0 ]
}
