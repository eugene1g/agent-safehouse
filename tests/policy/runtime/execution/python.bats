#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Python/uv toolchain profile (profiles/30-toolchains/python.sb).
# Verifies real uv operations behave as intended under the default sandbox:
# using an already-installed global tool works, but installing a new one
# does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
# Note: `uv tool install` also drops a PATH shim into ~/.local/bin (e.g.
# ~/.local/bin/ruff), which this profile deliberately does NOT grant (see the
# "Do not grant blanket writes to ~/.local/bin" comment in python.sb) -- that
# directory also hosts per-agent entrypoints handled elsewhere. So the
# already-installed tool is run here by its real path under the read-only
# ~/.local/share/uv/tools tree, not via the (denied) bare-name PATH shim.
#
load ../../../test_helper.bash

PYTHON_FIXTURE_TOOL="ruff"

setup() {
  sft_setup_test_env

  command -v uv >/dev/null 2>&1 || skip "uv is not installed"

  PYTHON_FIXTURE_BIN="${SAFEHOUSE_HOST_HOME}/.local/share/uv/tools/${PYTHON_FIXTURE_TOOL}/bin/${PYTHON_FIXTURE_TOOL}"
  if [ ! -x "$PYTHON_FIXTURE_BIN" ]; then
    HOME="$SAFEHOUSE_HOST_HOME" uv tool install "$PYTHON_FIXTURE_TOOL" --quiet \
      || skip "could not install ${PYTHON_FIXTURE_TOOL} fixture globally"
  fi
}

@test "[EXECUTION] uv --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- uv --version
}

@test "[EXECUTION] uv tool list shows already-installed tools" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- uv tool list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$PYTHON_FIXTURE_TOOL"
}

@test "[EXECUTION] uv tool list --show-paths describes installed tool locations" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- uv tool list --show-paths
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$PYTHON_FIXTURE_TOOL"
}

@test "[EXECUTION] uv tool install of a new tool is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- uv tool install is2-cli --quiet
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed global tool runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- "$PYTHON_FIXTURE_BIN" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$PYTHON_FIXTURE_TOOL"
}
