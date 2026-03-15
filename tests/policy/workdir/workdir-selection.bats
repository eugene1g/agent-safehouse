#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] explicit workdir allows writes there and still blocks unrelated paths" {
  local explicit_dir allowed_file blocked_file

  explicit_dir="$(sft_external_dir "explicit-workdir")" || return 1
  allowed_file="${explicit_dir}/explicit-workdir-ok.txt"
  blocked_file="$(sft_external_path "explicit-workdir-blocked" "blocked.txt")" || return 1

  safehouse_ok --workdir "$explicit_dir" -- /bin/sh -c "printf '%s' ok > '$allowed_file'"
  sft_assert_file_content "$allowed_file" "ok"

  safehouse_denied --workdir "$explicit_dir" -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}

@test "[EXECUTION] git root is auto-detected when invoked from a nested repo path" {
  sft_require_cmd_or_skip git

  local repo_root nested_dir repo_file nested_file blocked_file
  repo_root="$(sft_workspace_path "repo")" || return 1
  nested_dir="${repo_root}/nested/work"
  repo_file="${repo_root}/git-root-ok.txt"
  nested_file="${nested_dir}/git-subdir-ok.txt"
  blocked_file="$(sft_external_path "git-root-blocked" "blocked.txt")" || return 1

  mkdir -p "$nested_dir"
  /bin/sh -c "cd '$repo_root' && git init -q" || return 1

  safehouse_ok_in_dir "$nested_dir" -- /bin/sh -c "touch '$repo_file' '$nested_file'"
  sft_assert_file_exists "$repo_file"
  sft_assert_file_exists "$nested_file"

  safehouse_denied_in_dir "$nested_dir" -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}
