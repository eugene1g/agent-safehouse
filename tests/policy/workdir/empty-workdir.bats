#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] empty workdir mode can lock a release task to a single explicit export directory" {
  local export_dir exported_file blocked_file

  export_dir="$(sft_external_dir "export")" || return 1
  exported_file="${export_dir}/release.txt"
  blocked_file="$(sft_external_path "denied" "blocked.txt")" || return 1
  cd "$export_dir" || return 1

  safehouse_ok \
    --workdir '' \
    --add-dirs "$export_dir" \
    -- /bin/sh -c "printf '%s' shipped > '$exported_file'"
  sft_assert_file_content "$exported_file" "shipped"

  safehouse_denied \
    --workdir '' \
    --add-dirs "$export_dir" \
    -- /bin/sh -c "printf '%s' blocked > '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}
