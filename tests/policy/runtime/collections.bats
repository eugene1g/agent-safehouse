#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "collection helpers reject invalid variable names before hitting eval" {
  run /bin/bash -lc '
    safehouse_fail() {
      printf "%s\n" "$1"
      return 1
    }

    source "'"${SAFEHOUSE_REPO_ROOT}/bin/lib/support/collections.sh"'"
    safehouse_array_append "not-valid-name" "value"
  '
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "Invalid collection variable name: not-valid-name"
}
