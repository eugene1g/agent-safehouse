#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] muse command selects the muse agent profile" {
  local profile

  profile="$(safehouse_profile -- muse)"

  sft_assert_includes_source "$profile" "60-agents/muse.sb"
  sft_assert_omits_source "$profile" "60-agents/opencode.sb"
}

@test "[POLICY-ONLY] muse grants launcher, sidecars, config, and state roots" {
  local profile muse_section

  profile="$(safehouse_profile -- muse)"
  muse_section="$(sft_profile_source_section "$profile" "60-agents/muse.sb")"

  sft_assert_contains "$muse_section" '(home-prefix "/.local/bin/muse")'
  sft_assert_contains "$muse_section" '(home-prefix "/.local/bin/.muse")'
  sft_assert_contains "$muse_section" '(home-subpath "/.config/muse")'
  sft_assert_contains "$muse_section" '(home-subpath "/.local/share/muse")'
}
