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

@test "[POLICY-ONLY] enable=xcode grants the full CoreSimulator mach namespace for simulator builds" {
  local profile
  profile="$(safehouse_profile --enable=xcode)"

  # Simulator-targeted xcodebuild / actool / simctl enumerate runtimes via
  # simdiskimaged in addition to CoreSimulatorService. The namespace regex
  # covers both plus future sub-services (SimulatorTrampoline, SimDevice.*).
  sft_assert_contains "$profile" '(global-name-regex #"^com\.apple\.CoreSimulator(\.|$)")'
}
