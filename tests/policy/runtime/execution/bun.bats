#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Bun toolchain profile (profiles/30-toolchains/bun.sb).
# Verifies real bun operations behave as intended under the default sandbox:
# using an already-installed global package works, but installing a new one
# does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

BUN_FIXTURE_PKG="cowsay"

setup() {
  sft_setup_test_env

  command -v bun >/dev/null 2>&1 || skip "bun is not installed"

  if [ ! -x "${SAFEHOUSE_HOST_HOME}/.bun/bin/${BUN_FIXTURE_PKG}" ]; then
    HOME="$SAFEHOUSE_HOST_HOME" bun add -g "$BUN_FIXTURE_PKG" --silent \
      || skip "could not install ${BUN_FIXTURE_PKG} fixture globally"
  fi
}

@test "[EXECUTION] bun --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- bun --version
}

@test "[EXECUTION] bun pm ls -g shows already-installed global packages" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- bun pm ls -g
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$BUN_FIXTURE_PKG"
}

@test "[EXECUTION] bun info reads package metadata from the registry" {
  # `bun info` refuses to run without a package.json in cwd, even read-only.
  echo '{}' > "${SAFEHOUSE_WORKSPACE}/package.json"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- bun info "$BUN_FIXTURE_PKG" version
}

@test "[EXECUTION] bun add -g of a new package is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- bun add -g is-thirteen
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed global package runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- "$BUN_FIXTURE_PKG" "safehouse"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "safehouse"
}
