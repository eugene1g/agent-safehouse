#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Node/npm toolchain profile (profiles/30-toolchains/node.sb).
# Verifies real npm operations behave as intended under the default sandbox:
# using already-installed global packages works, but installing a NEW global
# package does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

NODE_FIXTURE_PKG="cowsay"

setup() {
  sft_setup_test_env

  command -v npm >/dev/null 2>&1 || skip "npm is not installed"

  if ! npm ls -g "$NODE_FIXTURE_PKG" --depth=0 >/dev/null 2>&1; then
    npm install -g --no-fund --no-audit "$NODE_FIXTURE_PKG" >/dev/null 2>&1 \
      || skip "could not install ${NODE_FIXTURE_PKG} fixture globally (offline?)"
  fi
}

@test "[EXECUTION] npm --version succeeds under the default sandbox" {
  safehouse_ok -- npm --version
}

@test "[EXECUTION] npm ls -g lists already-installed global packages" {
  run safehouse_ok -- npm ls -g --depth=0
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$NODE_FIXTURE_PKG"
}

@test "[EXECUTION] npm view reads package metadata from the registry" {
  safehouse_ok -- npm view "$NODE_FIXTURE_PKG" version
}

@test "[EXECUTION] npm install -g of a new package is denied" {
  safehouse_denied -- npm install -g --no-fund --no-audit is-thirteen
}

@test "[EXECUTION] an already-installed global package runs" {
  run safehouse_ok -- cowsay "safehouse"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "safehouse"
}
