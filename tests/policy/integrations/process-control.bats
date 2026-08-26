#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash
load ../procargs_utils.bash

# Overrides the shared teardown (test_helper.bash) to also reap background processes,
# which the in-test cleanup misses when a test aborts on a failed assertion.
teardown() {
  local pid

  for pid in "${target_pid:-}" "${process_debug_pid:-}"; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done

  sft_teardown_test_env
}

@test "[POLICY-ONLY] enable=process-control includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=process-control)"

  sft_assert_includes_source "$profile" "55-integrations-optional/process-control.sb"
}

@test "[EXECUTION] host process signalling stays denied by default and is allowed with enable=process-control" {
  local process_debug_dir process_debug_bin  # process_debug_pid stays global for teardown

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
}

@test "[POLICY-ONLY] enable=process-control restores argv/env (pidinfo) reads after the base deny" {
  local profile
  profile="$(safehouse_profile --enable=process-control)"

  sft_assert_contains "$profile" "#safehouse-test-id:process-control-procargs-allow#"
  sft_assert_contains "$profile" '(allow process-info-pidinfo)'
  sft_assert_order "$profile" "#safehouse-test-id:cross-process-procargs-deny#" "#safehouse-test-id:process-control-procargs-allow#"
}

@test "[EXECUTION] reading a host process's argv/env is denied by default, allowed with --enable=process-control" {
  sft_require_cmd_or_skip python3

  local reader
  reader="$(sft_procargs_reader_py)"

  TARGET_ENV_CANARY="target-env-canary"
  TARGET_ARGV_CANARY="target-argv-canary"
  ENV_CANARY="$TARGET_ENV_CANARY" python3 -c 'import time; time.sleep(300)' "$TARGET_ARGV_CANARY" </dev/null >/dev/null 2>&1 &
  target_pid=$!

  local selector
  for selector in $KERN_PROCARGS $KERN_PROCARGS2; do
    /bin/kill -0 "$target_pid"

    safehouse_run -- python3 -c "$reader" "$selector" "$target_pid"
    [ "$status" -ne 0 ]
    sft_assert_not_contains "$output" "$TARGET_ARGV_CANARY"
    sft_assert_not_contains "$output" "$TARGET_ENV_CANARY"

    safehouse_run --enable=process-control -- python3 -c "$reader" "$selector" "$target_pid"
    [ "$status" -eq 0 ]
    sft_assert_contains "$output" "$TARGET_ARGV_CANARY"
    sft_assert_contains "$output" "$TARGET_ENV_CANARY"
  done
}
