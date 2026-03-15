#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] SAFEHOUSE_ADD_DIRS_RO and SAFEHOUSE_ADD_DIRS grant paths from env" {
  local readonly_dir writable_dir input_file output_file blocked_file

  readonly_dir="$(sft_external_dir "env-readonly")" || return 1
  writable_dir="$(sft_external_dir "env-writable")" || return 1
  input_file="${readonly_dir}/input.txt"
  output_file="${writable_dir}/output.txt"
  blocked_file="${readonly_dir}/blocked.txt"

  printf '%s\n' "fixture-data" > "$input_file"

  safehouse_ok_env \
    SAFEHOUSE_ADD_DIRS_RO="$readonly_dir" \
    SAFEHOUSE_ADD_DIRS="$writable_dir" \
    -- \
    -- /bin/sh -c "cat '$input_file' > '$output_file'"
  sft_assert_file_content "$output_file" "fixture-data"

  safehouse_denied_env \
    SAFEHOUSE_ADD_DIRS_RO="$readonly_dir" \
    -- \
    -- /bin/sh -c "printf '%s' blocked > '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}

@test "[EXECUTION] SAFEHOUSE_WORKDIR overrides auto-selected workdir from env" {
  local env_workdir allowed_file blocked_file

  env_workdir="$(sft_external_dir "env-workdir")" || return 1
  allowed_file="${env_workdir}/env-workdir-ok.txt"
  blocked_file="$(sft_external_path "env-workdir-blocked" "blocked.txt")" || return 1

  safehouse_ok_env \
    SAFEHOUSE_WORKDIR="$env_workdir" \
    -- \
    -- /bin/sh -c "printf '%s' ok > '$allowed_file'"
  sft_assert_file_content "$allowed_file" "ok"

  safehouse_denied_env \
    SAFEHOUSE_WORKDIR="$env_workdir" \
    -- \
    -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}
