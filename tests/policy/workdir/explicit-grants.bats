#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] explicit ro and rw grants let a report job read fixtures and publish output without widening access" {
  local readonly_dir writable_dir input_file output_file blocked_file

  readonly_dir="$(sft_external_dir "readonly")" || return 1
  writable_dir="$(sft_external_dir "writable")" || return 1
  input_file="${readonly_dir}/input.txt"
  output_file="${writable_dir}/output.txt"
  blocked_file="${readonly_dir}/blocked.txt"

  printf '%s\n' "fixture-data" > "$input_file"

  safehouse_ok \
    --add-dirs-ro "$readonly_dir" \
    --add-dirs "$writable_dir" \
    -- /bin/sh -c "cat '$input_file' > '$output_file'"
  sft_assert_file_content "$output_file" "fixture-data"

  safehouse_denied \
    --add-dirs-ro "$readonly_dir" \
    -- /bin/sh -c "printf '%s' blocked > '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}
