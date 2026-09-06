#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "SBPL escaping writes into the caller variable and keeps shell characters literal" {
  run /bin/bash -eu -c '
    source "$1/bin/lib/support/collections.sh"
    source "$1/bin/lib/support/sb.sh"
    safehouse_fail() { printf "%s\n" "$1" >&2; return 1; }
    check_escape() {
      local value=unchanged
      safehouse_escape_for_sb_into value "$1"
      [[ "$value" == "$2" ]]
      [[ "$(safehouse_escape_for_sb "$1")" == "$2" ]]
    }
    check_escape "$2" "$3"
    check_escape "" ""
  ' _ "$SAFEHOUSE_REPO_ROOT" '/quote"/back\slash/$HOME/`id`' '/quote\"/back\\slash/$HOME/`id`'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SBPL escaping rejects control characters before writing an output variable" {
  run /bin/bash -eu -c '
    source "$1/bin/lib/support/collections.sh"
    source "$1/bin/lib/support/sb.sh"
    safehouse_fail() { printf "%s\n" "$1" >&2; return 1; }
    value=unchanged
    for code in 001 011 012 015 177; do
      printf -v bad "path\\$code"
      if safehouse_escape_for_sb_into value "$bad"; then exit 1; fi
      [[ "$value" == unchanged ]]
      if safehouse_escape_for_sb "$bad"; then exit 1; fi
    done
    if safehouse_escape_for_sb_into "value[0]" valid; then exit 1; fi
    [[ "$value" == unchanged ]]
  ' _ "$SAFEHOUSE_REPO_ROOT"

  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "contains control characters"
  sft_assert_contains "$output" "Invalid collection variable name"
}
