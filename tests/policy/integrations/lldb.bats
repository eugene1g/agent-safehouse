#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash
load ../procargs_utils.bash

# Overrides the shared teardown (test_helper.bash) to also reap the background target,
# which the in-test cleanup misses when a test aborts on a failed assertion.
teardown() {
  if [ -n "${target_pid:-}" ]; then
    kill "$target_pid" 2>/dev/null || true
    wait "$target_pid" 2>/dev/null || true
  fi

  sft_teardown_test_env
}

@test "[POLICY-ONLY] enable=lldb adds lldb grants and implicit process-control" {
  local profile
  profile="$(safehouse_profile --enable=lldb)"

  sft_assert_includes_source "$profile" "55-integrations-optional/lldb.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/process-control.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/xcode.sb"
  sft_assert_contains "$profile" '(subpath "/Library/Developer/PrivateFrameworks")'
  sft_assert_contains "$profile" '(regex #"^/Applications/Xcode[^/]*\.app(/.*)?$")'
  sft_assert_contains "$profile" '(regex #"^/System/Volumes/Data/Applications/Xcode[^/]*\.app(/.*)?$")'
  sft_assert_not_contains "$profile" '(home-subpath "/Library/Developer/Xcode")'
}

@test "[EXECUTION] lldb stays denied by default and with process-control alone, then becomes allowed with enable=lldb" {
  sft_require_cmd_or_skip lldb
  sft_require_cmd_or_skip xcrun

  /usr/bin/lldb --version >/dev/null 2>&1 || skip "lldb precheck failed outside sandbox"
  /usr/bin/xcrun -f lldb >/dev/null 2>&1 || skip "xcrun lldb precheck failed outside sandbox"

  safehouse_denied -- /usr/bin/lldb --version

  safehouse_denied --enable=process-control -- /usr/bin/lldb --version

  safehouse_ok --enable=lldb -- /usr/bin/lldb --version >/dev/null
  safehouse_ok --enable=lldb -- /usr/bin/xcrun -f lldb >/dev/null
}

@test "[POLICY-ONLY] enable=lldb restores argv/env (pidinfo) reads after the base deny" {
  local profile
  profile="$(safehouse_profile --enable=lldb)"

  sft_assert_contains "$profile" "#safehouse-test-id:lldb-procargs-allow#"
  sft_assert_contains "$profile" '(allow process-info-pidinfo)'
  sft_assert_order "$profile" "#safehouse-test-id:cross-process-procargs-deny#" "#safehouse-test-id:lldb-procargs-allow#"
}

@test "[EXECUTION] reading a host process's argv/env is denied by default, allowed with --enable=lldb" {
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

    safehouse_run --enable=lldb -- python3 -c "$reader" "$selector" "$target_pid"
    [ "$status" -eq 0 ]
    sft_assert_contains "$output" "$TARGET_ARGV_CANARY"
    sft_assert_contains "$output" "$TARGET_ENV_CANARY"
  done
}
