#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=clipboard includes only the clipboard integration layer" {
  local profile

  profile="$(safehouse_profile --enable=clipboard)"

  sft_assert_includes_source "$profile" "55-integrations-optional/clipboard.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/macos-gui.sb"
}
