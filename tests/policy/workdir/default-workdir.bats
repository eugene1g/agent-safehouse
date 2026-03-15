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
