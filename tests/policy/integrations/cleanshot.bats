#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=cleanshot includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=cleanshot)"

  sft_assert_includes_source "$profile" "55-integrations-optional/cleanshot.sb"
}

@test "CleanShot media stays denied by default and becomes readable when enabled" {
  local fake_home media_dir screenshot_file

  fake_home="$(sft_fake_home)" || return 1
  media_dir="${fake_home}/Library/Application Support/CleanShot/media"
  screenshot_file="${media_dir}/capture.png"

  mkdir -p "$media_dir"
  printf '%s\n' "fake-image" > "$screenshot_file"

  HOME="$fake_home" safehouse_denied -- /bin/cat "$screenshot_file"

  HOME="$fake_home" safehouse_ok --enable=cleanshot -- /bin/cat "$screenshot_file" >/dev/null
}
