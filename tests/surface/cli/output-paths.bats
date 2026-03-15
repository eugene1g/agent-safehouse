#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "--output supports spaces and nested directories" {
  local output_space output_nested

  output_space="$(sft_workspace_path "output dir/policy with spaces.sb")"
  output_nested="$(sft_workspace_path "nested/output/path/policy.sb")"

  safehouse_ok --output "$output_space" >/dev/null
  safehouse_ok --output "$output_nested" >/dev/null

  sft_assert_file_exists "$output_space"
  sft_assert_file_contains "$output_space" "(version 1)"
  sft_assert_file_exists "$output_nested"
}

@test "--output overwrites existing files" {
  local output_path
  output_path="$(sft_workspace_path "overwrite/policy.sb")"

  mkdir -p "$(dirname "$output_path")"
  printf '%s\n' "sentinel-old" > "$output_path"

  safehouse_ok --output "$output_path" >/dev/null

  sft_assert_file_not_contains "$output_path" "sentinel-old"
  sft_assert_file_contains "$output_path" "(version 1)"
}

@test "--stdout with --output writes the file and still prints the policy text" {
  local output_path

  output_path="$(sft_workspace_path "stdout-output/policy.sb")"

  safehouse_run --stdout --output "$output_path"
  [ "$status" -eq 0 ]

  sft_assert_contains "$output" "(version 1)"
  sft_assert_file_exists "$output_path"
  sft_assert_file_contains "$output_path" "(version 1)"
}
