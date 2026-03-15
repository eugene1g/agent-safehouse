#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=lldb adds lldb grants and implicit process-control" {
  local profile
  profile="$(safehouse_profile --enable=lldb)"

  sft_assert_includes_source "$profile" "55-integrations-optional/lldb.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/process-control.sb"
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
