#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=electron adds electron-specific grants and implies macOS GUI plus clipboard" {
  local coredrag_lookup profile
  profile="$(safehouse_profile --enable=electron)"

  sft_assert_includes_source "$profile" "55-integrations-optional/electron.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/macos-gui.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/clipboard.sb"

  coredrag_lookup="$(awk '
    $0 == "(allow mach-lookup" { capture=1; block=$0 "\n"; next }
    capture { block=block $0 "\n" }
    capture && $0 == ")" && index(block, "(local-name \"com.apple.coredrag\")") {
      printf "%s", block
      exit
    }
    capture && $0 == ")" { capture=0; block="" }
  ' <<<"$profile")"
  sft_assert_contains "$coredrag_lookup" '(local-name "com.apple.coredrag")'
}
