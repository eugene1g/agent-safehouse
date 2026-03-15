#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=macos-gui adds GUI grants, implies clipboard, and does not inject electron" {
  local profile
  profile="$(safehouse_profile --enable=macos-gui)"

  sft_assert_includes_source "$profile" "55-integrations-optional/macos-gui.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/clipboard.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/electron.sb"
}
