#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Ruby toolchain profile (profiles/30-toolchains/ruby.sb).
# Verifies real gem/bundler operations behave as intended under the default
# sandbox: using an already-installed global gem works, but installing a new
# one does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

setup() {
  sft_setup_test_env

  command -v gem >/dev/null 2>&1 || skip "gem is not installed"
}

@test "[EXECUTION] gem --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- gem --version
}

@test "[EXECUTION] gem list shows the bundled default gems" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- gem list bundler
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "bundler"
}

@test "[EXECUTION] gem info describes an installed gem" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- gem info bundler
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "bundler"
}

@test "[EXECUTION] gem install of a new gem is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- gem install colorize
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed global gem binary runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- bundle --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Bundler version"
}
