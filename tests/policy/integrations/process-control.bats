#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=process-control includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=process-control)"

  sft_assert_includes_source "$profile" "55-integrations-optional/process-control.sb"
}

@test "[EXECUTION] host process signalling stays denied by default and is allowed with enable=process-control" {
  local process_debug_dir process_debug_bin process_debug_pid

  process_debug_dir="$(mktemp -d "${SAFEHOUSE_WORKSPACE_ROOT}/proc-debug.XXXXXX")"
  process_debug_bin="${process_debug_dir}/safehouse-proc-test"

  /bin/ln -s /bin/sleep "$process_debug_bin"
  "$process_debug_bin" 60 >/dev/null 2>&1 &
  process_debug_pid=$!

  /bin/kill -0 "$process_debug_pid"
  /usr/bin/pkill -0 -f "$process_debug_bin"

  safehouse_denied -- /bin/kill -0 "$process_debug_pid"

  safehouse_denied -- /usr/bin/pkill -0 -f "$process_debug_bin"

  safehouse_ok --enable=process-control -- /bin/kill -0 "$process_debug_pid" >/dev/null
  safehouse_ok --enable=process-control -- /usr/bin/pkill -0 -f "$process_debug_bin" >/dev/null

  /bin/kill "$process_debug_pid" >/dev/null 2>&1 || true
  wait "$process_debug_pid" 2>/dev/null || true
}
