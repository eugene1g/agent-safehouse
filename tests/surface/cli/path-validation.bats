#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "nonexistent paths are rejected for path-taking flags" {
  local missing_path
  missing_path="$(sft_workspace_path "missing-path")"

  safehouse_denied --add-dirs "$missing_path"

  safehouse_denied --add-dirs-ro "$missing_path"

  safehouse_denied --workdir "$missing_path"
}

@test "newline and control characters are rejected in CLI and env path inputs" {
  local bad_path
  bad_path="$(printf 'first\nsecond')"

  safehouse_denied --add-dirs "$bad_path"

  safehouse_denied --add-dirs-ro "$bad_path"

  safehouse_denied --workdir "$bad_path"

  safehouse_denied_env SAFEHOUSE_ADD_DIRS="$bad_path" --

  safehouse_denied_env SAFEHOUSE_WORKDIR="$bad_path" --
}

@test "HOME must be set to a directory and placeholder replacement handles ampersands" {
  local home_not_dir ampersand_home policy resolved_ampersand_home

  safehouse_denied_env -u HOME --

  home_not_dir="$(sft_workspace_path "home-not-dir.txt")"
  printf '%s\n' "not-a-directory" > "$home_not_dir"

  HOME="$home_not_dir" safehouse_denied --

  ampersand_home="$(sft_workspace_path "home-with-&-char")"
  mkdir -p "$ampersand_home"
  resolved_ampersand_home="$(cd "$ampersand_home" && pwd -P)"

  policy="$(HOME="$ampersand_home" safehouse_profile --workdir="")"

  sft_assert_contains "$policy" "(define HOME_DIR \"${resolved_ampersand_home}\")"
  sft_assert_not_contains "$policy" "__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
}

@test "paths with quotes and backslashes are escaped correctly in generated SBPL and runtime grants" {
  local weird_dir weird_file policy escaped_weird_dir

  weird_dir="${SAFEHOUSE_EXTERNAL_ROOT}/path-with-\"quote\"-and-\\-backslash"
  weird_file="${weird_dir}/fixture.txt"

  mkdir -p "$weird_dir"
  printf '%s\n' "weird-path-ok" > "$weird_file"

  policy="$(safehouse_profile --add-dirs-ro "$weird_dir")"
  escaped_weird_dir="$(cd "$weird_dir" && pwd -P)"
  escaped_weird_dir="${escaped_weird_dir//\\/\\\\}"
  escaped_weird_dir="${escaped_weird_dir//\"/\\\"}"
  sft_assert_contains "$policy" "$escaped_weird_dir"

  safehouse_denied -- /bin/cat "$weird_file"

  run safehouse_ok --add-dirs-ro "$weird_dir" -- /bin/cat "$weird_file"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "weird-path-ok"
}

@test "file symlink grants normalize to the resolved target path" {
  local target_dir symlink_dir target_file symlink_file policy

  target_dir="$(sft_external_dir "symlink-target")" || return 1
  symlink_dir="$(sft_external_dir "symlink-source")" || return 1
  target_file="${target_dir}/real.txt"
  symlink_file="${symlink_dir}/link.txt"

  printf '%s\n' "via-symlink" > "$target_file"
  /bin/ln -sf "$target_file" "$symlink_file"

  policy="$(safehouse_profile --add-dirs-ro "$symlink_file")"

  sft_assert_contains "$policy" "(literal \"${target_file}\")"
  sft_assert_not_contains "$policy" "(literal \"${symlink_file}\")"

  run safehouse_ok --add-dirs-ro "$symlink_file" -- /bin/cat "$target_file"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "via-symlink"
}
