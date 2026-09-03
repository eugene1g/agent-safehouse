#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Elixir toolchain profile (profiles/30-toolchains/elixir.sb).
# Verifies real Mix/Hex operations behave as intended under the default
# sandbox: listing/describing/running already-installed Mix archives works,
# but `mix archive.install`ing a new archive into ~/.mix/archives does not.
# https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

# Bootstrapping `mix hex.info` installs the `hex` archive itself into
# ~/.mix/archives the first time it's needed -- this is our already-installed
# fixture, so no separate fixture package is required.
ELIXIR_FIXTURE_ARCHIVE="hex"

setup() {
  sft_setup_test_env

  command -v mix >/dev/null 2>&1 || skip "elixir/mix is not installed"

  if ! HOME="$SAFEHOUSE_HOST_HOME" mix archive 2>/dev/null | grep -q "^\* ${ELIXIR_FIXTURE_ARCHIVE}-"; then
    HOME="$SAFEHOUSE_HOST_HOME" mix hex.info hex_core >/dev/null 2>&1 \
      || skip "could not bootstrap the hex archive fixture"
  fi
}

@test "[EXECUTION] mix --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- mix --version
}

@test "[EXECUTION] mix archive lists already-installed archives" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- mix archive
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$ELIXIR_FIXTURE_ARCHIVE"
}

@test "[EXECUTION] mix hex.info describes a package using the installed hex archive" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- mix hex.info hex_core
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "hex_core"
}

@test "[EXECUTION] mix archive.install of a new archive is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- /bin/sh -c 'yes | mix archive.install hex phx_new'
  [ "$status" -ne 0 ]
  [ ! -e "${SAFEHOUSE_HOST_HOME}/.mix/archives/phx_new-1.8.13" ]
}

@test "[EXECUTION] an already-installed Mix archive (hex) runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- mix hex.info
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Hex"
}
