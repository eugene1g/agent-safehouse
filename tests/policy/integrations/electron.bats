#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=electron adds electron-specific grants and implies macOS GUI plus clipboard" {
  local profile
  profile="$(safehouse_profile --enable=electron)"

  sft_assert_includes_source "$profile" "55-integrations-optional/electron.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/macos-gui.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/clipboard.sb"
}
