#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Xcode integration checks.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] enable=xcode includes its optional profile source" { # https://github.com/eugene1g/agent-safehouse/issues/26
  local profile
  profile="$(safehouse_profile --enable=xcode)"

  sft_assert_includes_source "$profile" "55-integrations-optional/xcode.sb"
}

@test "[POLICY-ONLY] enable=xcode keeps debugger-grade access out unless explicitly requested" {
  local profile
  profile="$(safehouse_profile --enable=xcode)"

  sft_assert_omits_source "$profile" "55-integrations-optional/lldb.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/process-control.sb"
}
