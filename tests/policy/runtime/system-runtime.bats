#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] default profile includes the system-runtime source and generated HOME ancestor metadata" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "10-system-runtime.sb"
  sft_assert_contains "$profile" "#safehouse-test-id:home-ancestor-metadata#"
}

@test "[POLICY-ONLY] default profile includes always-on network, shared, and core integration sources" {
  local profile

  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "20-network.sb"
  sft_assert_includes_source "$profile" "40-shared/agent-common.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/container-runtime-default-deny.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/git.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/launch-services.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/scm-clis.sb"
  sft_assert_includes_source "$profile" "50-integrations-core/ssh-agent-default-deny.sb"
}

@test "[EXECUTION] default sandbox can read standard runtime paths and devices" {
  safehouse_ok -- /bin/ls /usr/bin
  safehouse_ok -- /bin/cat /dev/null
  safehouse_ok -- /bin/dd if=/dev/urandom bs=1 count=1
}

@test "[EXECUTION] default sandbox can write to tmp" {
  local tmp_canary
  tmp_canary="/tmp/safehouse-bats-tmp-canary.$$"
  rm -f "$tmp_canary"

  safehouse_ok -- /usr/bin/touch "$tmp_canary"
  sft_assert_file_exists "$tmp_canary"
  rm -f "$tmp_canary"
}

@test "[EXECUTION] default sandbox keeps device writes constrained" {
  safehouse_denied -- /bin/sh -c 'printf x > /dev/zero'
}

@test "[EXECUTION] default sandbox keeps shell startup files denied" {
  [ -e /private/etc/zshrc ] || skip "/private/etc/zshrc is not present"

  safehouse_denied -- /bin/cat /private/etc/zshrc
}
