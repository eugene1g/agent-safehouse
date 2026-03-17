#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] default dist policy keeps a project-local command inside its current workspace" {
  local allowed_file blocked_file

  allowed_file="$(sft_workspace_path "notes.txt")" || return 1
  blocked_file="$(sft_external_path "default-workdir-denied" "blocked.txt")" || return 1

  safehouse_ok -- /bin/sh -c "printf '%s' sandboxed > '$allowed_file'"
  sft_assert_file_content "$allowed_file" "sandboxed"

  safehouse_denied -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}

@test "[EXECUTION] ancestor .git directories without repo metadata do not change the default workdir" { # https://github.com/eugene1g/agent-safehouse/issues/52
  local fake_parent nested_dir allowed_file blocked_file

  fake_parent="$(sft_external_dir "non-repo-dotgit-parent")" || return 1
  nested_dir="${fake_parent}/projects/current"
  allowed_file="${nested_dir}/nested-ok.txt"
  blocked_file="${fake_parent}/parent-blocked.txt"

  mkdir -p "${fake_parent}/.git/hooks" "$nested_dir" || return 1

  safehouse_ok_in_dir "$nested_dir" -- /bin/sh -c "printf '%s' ok > '$allowed_file'"
  sft_assert_file_content "$allowed_file" "ok"

  safehouse_denied_in_dir "$nested_dir" -- /bin/sh -c "printf '%s' blocked > '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}
