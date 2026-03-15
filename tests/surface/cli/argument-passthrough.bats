#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "[EXECUTION] wrapped command arguments preserve exact boundaries" {
  local args_file
  args_file="$(sft_workspace_path "args.txt")"

  safehouse_ok -- /bin/sh -c 'printf "[%s]|[%s]|[%s]|[%s]\n" "$1" "$2" "$3" "$4" > "$5"' \
    sh "two words" 'quote"double' "single'quote" '$dollar value' "$args_file"

  sft_assert_file_content "$args_file" "[two words]|[quote\"double]|[single'quote]|[\$dollar value]"
}
